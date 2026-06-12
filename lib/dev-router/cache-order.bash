cache_file() {
  printf '%s/%s.json\n' "$CACHE_DIR" "$1"
}

cache_is_fresh() {
  local file now mtime age
  file="$(cache_file "$1")"
  [[ -f "$file" ]] || return 1

  now="$(date +%s)"
  if stat -c %Y "$file" >/dev/null 2>&1; then
    mtime="$(stat -c %Y "$file")"
  else
    mtime="$(stat -f %m "$file" 2>/dev/null || echo 0)"
  fi
  age=$((now - mtime))
  [[ "$age" -ge 0 && "$age" -lt "$CACHE_TTL_SECONDS" ]]
}

write_cache() {
  local provider available reason detail file tmp
  provider="$1"
  available="$2"
  reason="$3"
  detail="${4:-}"
  file="$(cache_file "$provider")"
  tmp="${file}.$$"

  require_jq || return $?
  mkdir -p "$CACHE_DIR"
  jq -n \
    --arg provider "$provider" \
    --argjson available "$available" \
    --arg reason "$reason" \
    --arg detail "$detail" \
    --arg checked_at "$(date -u +%FT%TZ)" \
    '{provider:$provider, available:$available, reason:$reason, detail:$detail, checked_at:$checked_at}' \
    >"$tmp" && mv "$tmp" "$file"
}

read_cache() {
  cat "$(cache_file "$1")"
}

invalidate_cache() {
  rm -f "$(cache_file "$1")"
}

clear_all_cache() {
  if [[ -d "$CACHE_DIR" ]]; then
    rm -f "$CACHE_DIR"/*.json
  fi
  echo "[dev] cache cleared: $CACHE_DIR"
}

normalize_provider() {
  local provider
  provider="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$provider" in
    codex|openai) printf 'codex\n' ;;
    glm|zai|z.ai|z-ai) printf 'glm\n' ;;
    agy|antigravity|google) printf 'antigravity\n' ;;
    deepseek|ds) printf 'deepseek\n' ;;
    *) return 1 ;;
  esac
}

provider_label() {
  case "$1" in
    codex) printf 'Codex\n' ;;
    glm) printf 'GLM\n' ;;
    antigravity) printf 'Antigravity\n' ;;
    deepseek) printf 'DeepSeek\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

provider_order() {
  local raw provider default seen
  local -a order
  order=()

  if [[ -f "$ORDER_FILE" ]]; then
    while IFS= read -r raw || [[ -n "$raw" ]]; do
      raw="${raw%%#*}"
      raw="${raw#"${raw%%[![:space:]]*}"}"
      raw="${raw%"${raw##*[![:space:]]}"}"
      [[ -n "$raw" ]] || continue
      if ! provider="$(normalize_provider "$raw")"; then
        continue
      fi
      seen=" ${order[*]} "
      [[ "$seen" == *" $provider "* ]] || order+=("$provider")
    done <"$ORDER_FILE"
  fi

  for default in "${DEFAULT_PROVIDER_ORDER[@]}"; do
    seen=" ${order[*]} "
    [[ "$seen" == *" $default "* ]] || order+=("$default")
  done

  printf '%s\n' "${order[@]}"
}

save_provider_order() {
  local provider
  mkdir -p "$CONFIG_DIR"
  {
    printf '# dev-router provider order\n'
    for provider in "$@"; do
      printf '%s\n' "$provider"
    done
  } >"$ORDER_FILE"
}

print_provider_order() {
  local provider n=1
  while IFS= read -r provider; do
    printf '%d. %s (%s)\n' "$n" "$(provider_label "$provider")" "$provider"
    n=$((n + 1))
  done < <(provider_order)
}

validate_order_args() {
  local input provider seen
  VALIDATED_ORDER=()
  for input in "$@"; do
    if ! provider="$(normalize_provider "$input")"; then
      echo "[dev] unknown provider in order: $input" >&2
      echo "[dev] expected one of: codex, glm, agy, antigravity, deepseek" >&2
      return 2
    fi
    seen=" ${VALIDATED_ORDER[*]} "
    if [[ "$seen" == *" $provider "* ]]; then
      echo "[dev] duplicate provider in order: $input" >&2
      return 2
    fi
    VALIDATED_ORDER+=("$provider")
  done
}

json_available() {
  jq -r '.available // false' 2>/dev/null
}

json_reason() {
  jq -r '.reason // "unknown"' 2>/dev/null
}

print_result_json() {
  local provider padded available reason
  provider="$1"
  padded="$(printf '[%-8s]' "$provider")"

  require_jq || return $?
  available="$(json_available <<<"$2")"
  reason="$(json_reason <<<"$2")"

  if [[ "$available" == "true" ]]; then
    printf '%s ✓ %s\n' "$padded" "$reason"
  else
    printf '%s ✗ %s\n' "$padded" "$reason"
  fi
}
