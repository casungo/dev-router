curl_json() {
  local method url body_file headers
  method="$1"
  url="$2"
  body_file="${3:-}"
  shift 3

  local tmp_body http_code curl_rc
  require_curl || return $?
  require_jq || return $?
  require_timeout || return $?
  tmp_body="$(make_temp)" || return $?

  if [[ -n "$body_file" ]]; then
    http_code="$(
      run_with_timeout "$CHECK_TIMEOUT_SECONDS" curl -sS -X "$method" "$url" \
        "$@" \
        --data @"$body_file" \
        -o "$tmp_body" \
        -w '%{http_code}' 2>/dev/null
    )"
    curl_rc=$?
  else
    http_code="$(
      run_with_timeout "$CHECK_TIMEOUT_SECONDS" curl -sS -X "$method" "$url" \
        "$@" \
        -o "$tmp_body" \
        -w '%{http_code}' 2>/dev/null
    )"
    curl_rc=$?
  fi

  if [[ "$curl_rc" -ne 0 ]]; then
    printf '{"http_code":0,"body":null,"error":"request failed or timed out"}\n'
    remove_temp "$tmp_body"
    return 0
  fi

  jq -n \
    --argjson body "$(jq -c . "$tmp_body" 2>/dev/null || jq -Rn --rawfile raw "$tmp_body" '$raw')" \
    --argjson http_code "${http_code:-0}" \
    '{http_code:$http_code, body:$body}'
  remove_temp "$tmp_body"
}

codex_window_status_jq='
  def pct_exhausted:
    (.used_percent? // .usedPercent? // .usage_percent? // .usagePercent? // null) as $p
    | if ($p | type) == "number" then $p >= 100 else false end;
  def rem_exhausted:
    (.remaining? // .remaining_units? // .remainingUnits? // null) as $r
    | if ($r | type) == "number" then $r <= 0 else false end;
  def available:
    if type != "object" then false
    elif pct_exhausted or rem_exhausted then false
    elif ((.remaining? // .remaining_units? // .remainingUnits? // null) | type) == "number" then true
    elif ((.used_percent? // .usedPercent? // .usage_percent? // .usagePercent? // null) | type) == "number" then true
    else false end;
  def status:
  {
    available: available,
    used_percent: (.used_percent? // .usedPercent? // .usage_percent? // .usagePercent? // null),
    remaining: (.remaining? // .remaining_units? // .remainingUnits? // null),
    reset: (.reset_at? // .resets_at? // .resetAfter? // .reset_after? // null)
  };
'

check_codex_live() {
  local auth_file access_token account_id response http body five weekly primary secondary
  auth_file="$HOME/.codex/auth.json"

  require_jq || return $?

  if ! command -v codex >/dev/null 2>&1; then
    write_cache codex false "codex CLI not found"
    read_cache codex
    return
  fi

  if [[ ! -f "$auth_file" ]]; then
    write_cache codex false "missing $auth_file"
    read_cache codex
    return
  fi

  access_token="$(jq -r '.tokens.access_token // empty' "$auth_file" 2>/dev/null)"
  account_id="$(jq -r '.tokens.account_id // empty' "$auth_file" 2>/dev/null)"

  if [[ -z "$access_token" || -z "$account_id" ]]; then
    write_cache codex false "missing Codex access token or account id"
    read_cache codex
    return
  fi

  response="$(curl_json GET "https://chatgpt.com/backend-api/wham/usage" "" \
    -H "Authorization: Bearer $access_token" \
    -H "ChatGPT-Account-Id: $account_id" \
    -H "Accept: application/json")"
  http="$(jq -r '.http_code' <<<"$response")"
  body="$(jq -c '.body' <<<"$response")"

  if [[ "$http" -eq 401 || "$http" -eq 403 ]]; then
    write_cache codex false "auth failed checking quota" "$body"
    read_cache codex
    return
  fi

  if [[ "$http" -ne 200 ]]; then
    write_cache codex false "quota check failed (HTTP $http)" "$body"
    read_cache codex
    return
  fi

  five="$(jq -c "$codex_window_status_jq"'(.five_hour // .five_hour_limit // .primary_window // .primaryWindow // .rate_limit.primary_window // .rate_limit.primaryWindow // empty) | status' <<<"$body")"
  weekly="$(jq -c "$codex_window_status_jq"'(.weekly // .weekly_limit // .secondary_window // .secondaryWindow // .rate_limit.secondary_window // .rate_limit.secondaryWindow // empty) | status' <<<"$body")"

  if [[ -z "$five" || -z "$weekly" ]]; then
    write_cache codex false "quota response did not include both Codex windows" "$body"
    read_cache codex
    return
  fi

  if [[ "$(jq -r '.available' <<<"$five")" == "true" && "$(jq -r '.available' <<<"$weekly")" == "true" ]]; then
    write_cache codex true "available" "$(jq -n --argjson five "$five" --argjson weekly "$weekly" '{five_hour:$five, weekly:$weekly}')"
  elif [[ "$(jq -r '.available' <<<"$five")" != "true" ]]; then
    write_cache codex false "five-hour limit exhausted" "$(jq -n --argjson five "$five" --argjson weekly "$weekly" '{five_hour:$five, weekly:$weekly}')"
  else
    write_cache codex false "weekly limit exhausted" "$(jq -n --argjson five "$five" --argjson weekly "$weekly" '{five_hour:$five, weekly:$weekly}')"
  fi
  read_cache codex
}

check_glm_live() {
  local response http body remaining tmp_body test_response test_http test_body code

  require_jq || return $?

  if ! command -v claude >/dev/null 2>&1; then
    write_cache glm false "claude CLI not found"
    read_cache glm
    return
  fi

  if [[ -z "${Z_AI_API_KEY:-}" ]]; then
    write_cache glm false "missing Z_AI_API_KEY"
    read_cache glm
    return
  fi

  response="$(curl_json GET "https://api.z.ai/v4/user/quota" "" \
    -H "Authorization: Bearer $Z_AI_API_KEY" \
    -H "Accept: application/json")"
  http="$(jq -r '.http_code' <<<"$response")"
  body="$(jq -c '.body' <<<"$response")"
  remaining="$(jq -r '.data.remaining_seconds // empty' <<<"$body" 2>/dev/null)"

  if [[ "$http" -eq 200 && "$remaining" =~ ^[0-9]+$ ]]; then
    if [[ "$remaining" -gt 0 ]]; then
      write_cache glm true "available" "$body"
    else
      write_cache glm false "quota exhausted (0 seconds remaining)" "$body"
    fi
    read_cache glm
    return
  fi

  tmp_body="$(make_temp)" || return $?
  jq -n --arg model "$DEV_GLM_FAST_MODEL" '{model:$model, messages:[{role:"user", content:"hi"}], max_tokens:1}' >"$tmp_body"
  test_response="$(curl_json POST "https://api.z.ai/api/coding/paas/v4/chat/completions" "$tmp_body" \
    -H "Authorization: Bearer $Z_AI_API_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept-Language: en-US,en" \
    -H "Accept: application/json")"
  remove_temp "$tmp_body"

  test_http="$(jq -r '.http_code' <<<"$test_response")"
  test_body="$(jq -c '.body' <<<"$test_response")"
  code="$(jq -r '.error.code // .code // empty' <<<"$test_body" 2>/dev/null)"

  if [[ "$test_http" -eq 200 ]]; then
    write_cache glm true "available (test call passed)" "$test_body"
  elif [[ "$test_http" -eq 429 || "$code" =~ ^(1302|1303|1113)$ ]]; then
    write_cache glm false "rate-limited or quota exhausted" "$test_body"
  else
    write_cache glm false "quota check unclear (HTTP $test_http)" "$test_body"
  fi
  read_cache glm
}

check_antigravity_live() {
  local help_text status_output probe_output probe_rc token response http body message tmp_body

  require_jq || return $?
  require_timeout || return $?

  if ! command -v agy >/dev/null 2>&1; then
    write_cache antigravity false "agy CLI not found"
    read_cache antigravity
    return
  fi

  help_text="$(run_with_timeout "$CHECK_TIMEOUT_SECONDS" agy --help 2>&1 || true)"
  if grep -q -- '--status' <<<"$help_text"; then
    status_output="$(run_with_timeout "$CHECK_TIMEOUT_SECONDS" agy --status 2>&1)"
    if [[ "$?" -eq 0 ]]; then
      write_cache antigravity true "available (agy --status passed)" "$status_output"
    elif grep -Eiq 'quota.*exhausted|exhausted.*quota|RESOURCE_EXHAUSTED|HTTP[[:space:]]*429|(^|[^0-9])429([^0-9]|$)' <<<"$status_output"; then
      write_cache antigravity false "quota exhausted" "$status_output"
    else
      write_cache antigravity false "agy --status failed" "$status_output"
    fi
    read_cache antigravity
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    probe_output="$(run_with_timeout "$CHECK_TIMEOUT_SECONDS" python3 - <<'PY' 2>&1
import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import termios
import time

master, slave = pty.openpty()
try:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 220, 0, 0))
except Exception:
    pass

proc = subprocess.Popen(["agy"], stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
out = bytearray()
start = time.time()
sent = False
ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")

def clean_text():
    text = out.decode("utf-8", "ignore")
    text = ansi.sub("", text)
    text = re.sub(r"\x1b\][^\x07]*(?:\x07|\x1b\\)", "", text)
    return text.replace("\r", "\n")

while time.time() - start < 2.8:
    ready, _, _ = select.select([master], [], [], 0.05)
    if ready:
        try:
            chunk = os.read(master, 8192)
        except OSError:
            break
        if not chunk:
            break
        out.extend(chunk)

    text = clean_text()
    if not sent and ("? for shortcuts" in text or "\n>\n" in text):
        os.write(master, b"/usage\r")
        sent = True

    if sent and ("Model Quota" in text or "Quota available" in text or "RESOURCE_EXHAUSTED" in text):
        os.write(master, b"\x1b")
        time.sleep(0.1)
        break

try:
    proc.terminate()
    proc.wait(timeout=0.3)
except Exception:
    try:
        proc.kill()
    except Exception:
        pass

print(clean_text())
PY
)"
    probe_rc=$?

    if [[ "$probe_rc" -eq 0 && "$probe_output" == *"Model Quota"* && "$probe_output" == *"Quota available"* ]]; then
      write_cache antigravity true "available (/usage quota available)" "$probe_output"
      read_cache antigravity
      return
    fi

    if grep -Eiq 'authentication required|log in|authorization code|oauth|not authenticated|not signed in|not logged into Antigravity' <<<"$probe_output"; then
      write_cache antigravity false "authentication required"
      read_cache antigravity
      return
    fi

    if grep -Eiq 'quota.*exhausted|exhausted.*quota|RESOURCE_EXHAUSTED|HTTP[[:space:]]*429|(^|[^0-9])429([^0-9]|$)' <<<"$probe_output"; then
      write_cache antigravity false "quota exhausted" "$probe_output"
      read_cache antigravity
      return
    fi

    if [[ "$probe_rc" -eq 124 ]]; then
      write_cache antigravity false "agy /usage probe timed out" "$probe_output"
      read_cache antigravity
      return
    fi
  else
    probe_output="$(run_with_timeout "$CHECK_TIMEOUT_SECONDS" agy --print "hi" --print-timeout "${CHECK_TIMEOUT_SECONDS}s" 2>&1)"
    probe_rc=$?
    if [[ "$probe_rc" -eq 0 ]]; then
      write_cache antigravity true "available (agy --print probe passed)" "$probe_output"
      read_cache antigravity
      return
    fi
  fi

  token="${ANTIGRAVITY_ACCESS_TOKEN:-}"
  if [[ -z "$token" ]] && command -v gcloud >/dev/null 2>&1; then
    token="$(run_with_timeout "$CHECK_TIMEOUT_SECONDS" gcloud auth print-access-token 2>/dev/null || true)"
  fi

  if [[ -z "$token" ]]; then
    write_cache antigravity false "no agy --status and no Antigravity access token for API probe"
    read_cache antigravity
    return
  fi

  tmp_body="$(make_temp)" || return $?
  jq -n '{prompt:"hi", max_output_tokens:1}' >"$tmp_body"
  response="$(curl_json POST "https://antigravity.googleapis.com/v1/query" "$tmp_body" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json")"
  remove_temp "$tmp_body"

  http="$(jq -r '.http_code' <<<"$response")"
  body="$(jq -c '.body' <<<"$response")"
  message="$(jq -r '(.error.message // .message // .error.status // empty)' <<<"$body" 2>/dev/null)"

  if [[ "$http" -eq 200 ]]; then
    write_cache antigravity true "available (API probe passed)" "$body"
  elif [[ "$http" -eq 429 ]] || grep -Eiq 'quota.*exhausted|exhausted.*quota|RESOURCE_EXHAUSTED' <<<"$message $body"; then
    write_cache antigravity false "quota exhausted" "$body"
  else
    write_cache antigravity false "Antigravity API probe failed (HTTP $http)" "$body"
  fi
  read_cache antigravity
}

check_deepseek_live() {
  require_jq || return $?

  if ! command -v claude >/dev/null 2>&1; then
    write_cache deepseek false "claude CLI not found"
  elif [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    write_cache deepseek false "missing DEEPSEEK_API_KEY"
  else
    write_cache deepseek true "available (pay-per-token fallback)"
  fi
  read_cache deepseek
}

check_provider() {
  local provider use_cache="${2:-yes}"
  provider="$1"

  if [[ "$use_cache" == "yes" ]] && cache_is_fresh "$provider"; then
    read_cache "$provider"
    return
  fi

  case "$provider" in
    codex) check_codex_live ;;
    glm) check_glm_live ;;
    antigravity) check_antigravity_live ;;
    deepseek) check_deepseek_live ;;
    *) write_cache "$provider" false "unknown provider"; read_cache "$provider" ;;
  esac
}
