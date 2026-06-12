require_command() {
  local command_name purpose
  command_name="$1"
  purpose="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "[dev] $command_name is required for $purpose" >&2
    return 127
  fi
}

require_jq() {
  require_command jq "quota parsing"
}

require_curl() {
  require_command curl "quota checks"
}

require_update_curl() {
  require_command curl "updates"
}

DEV_ROUTER_TMP_FILES=()

dev_router_cleanup_tmp() {
  local tmp
  for tmp in "${DEV_ROUTER_TMP_FILES[@]:-}"; do
    [[ -n "$tmp" ]] && rm -rf "$tmp"
  done
}

dev_router_signal_cleanup() {
  local signal
  signal="$1"
  dev_router_cleanup_tmp
  trap - "$signal"
  kill "-$signal" "$$"
}

trap dev_router_cleanup_tmp EXIT
trap 'dev_router_signal_cleanup HUP' HUP
trap 'dev_router_signal_cleanup INT' INT
trap 'dev_router_signal_cleanup TERM' TERM

make_temp() {
  local tmp
  tmp="$(mktemp)" || return $?
  DEV_ROUTER_TMP_FILES+=("$tmp")
  printf '%s\n' "$tmp"
}

make_temp_dir() {
  local tmp
  tmp="$(mktemp -d)" || return $?
  DEV_ROUTER_TMP_FILES+=("$tmp")
  printf '%s\n' "$tmp"
}

make_temp_in_dir() {
  local dir prefix tmp
  dir="$1"
  prefix="$2"
  tmp="$(mktemp "$dir/$prefix.XXXXXX")" || return $?
  DEV_ROUTER_TMP_FILES+=("$tmp")
  printf '%s\n' "$tmp"
}

remove_temp() {
  local tmp
  for tmp in "$@"; do
    [[ -n "$tmp" ]] && rm -rf "$tmp"
  done
}

self_path() {
  local source
  source="${BASH_SOURCE[0]:-$0}"
  if [[ "$source" == */* ]]; then
    (cd "$(dirname "$source")" 2>/dev/null && printf '%s/%s\n' "$PWD" "$(basename "$source")")
  elif command -v "$source" >/dev/null 2>&1; then
    command -v "$source"
  else
    printf '%s\n' "$source"
  fi
}

timeout_bin() {
  if command -v timeout >/dev/null 2>&1; then
    printf 'timeout\n'
  elif command -v gtimeout >/dev/null 2>&1; then
    printf 'gtimeout\n'
  else
    return 1
  fi
}

require_timeout() {
  local purpose="${1:-${CHECK_TIMEOUT_SECONDS}-second quota checks}"
  if ! timeout_bin >/dev/null; then
    echo "[dev] timeout or gtimeout is required for $purpose" >&2
    echo "[dev] on macOS, install GNU coreutils to get gtimeout" >&2
    return 127
  fi
}

run_with_timeout() {
  local seconds bin
  seconds="$1"
  shift

  bin="$(timeout_bin)" || {
    require_timeout
    return 127
  }

  "$bin" "$seconds" "$@"
}

version_normalize() {
  printf '%s\n' "${1#v}" | sed 's/[^0-9.].*$//'
}

version_is_newer() {
  local latest current latest_part current_part i
  IFS=. read -r -a latest_part <<<"$(version_normalize "$1")"
  IFS=. read -r -a current_part <<<"$(version_normalize "$2")"

  for i in 0 1 2; do
    latest_part[$i]="${latest_part[$i]:-0}"
    current_part[$i]="${current_part[$i]:-0}"
    [[ "${latest_part[$i]}" =~ ^[0-9]+$ ]] || latest_part[$i]=0
    [[ "${current_part[$i]}" =~ ^[0-9]+$ ]] || current_part[$i]=0

    if ((10#${latest_part[$i]} > 10#${current_part[$i]})); then
      return 0
    fi
    if ((10#${latest_part[$i]} < 10#${current_part[$i]})); then
      return 1
    fi
  done

  return 1
}
