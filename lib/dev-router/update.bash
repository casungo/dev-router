latest_release_tag() {
  local url tmp http_code curl_rc tag
  require_update_curl || return $?
  require_jq || return $?
  require_timeout "updates" || return $?

  url="https://api.github.com/repos/${DEV_ROUTER_GITHUB_REPO}/releases/latest"
  tmp="$(make_temp)" || return $?
  http_code="$(
    run_with_timeout "$CHECK_TIMEOUT_SECONDS" curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      "$url" \
      -o "$tmp" \
      -w '%{http_code}' 2>/dev/null
  )"
  curl_rc=$?

  if [[ "$curl_rc" -ne 0 || "${http_code:-0}" -ne 200 ]]; then
    remove_temp "$tmp"
    return 1
  fi

  tag="$(jq -r '.tag_name // empty' "$tmp" 2>/dev/null)"
  remove_temp "$tmp"
  [[ -n "$tag" ]] || return 1
  printf '%s\n' "$tag"
}

download_update_file() {
  local tag path target url
  tag="$1"
  path="$2"
  target="$3"
  require_update_curl || return $?
  require_timeout "updates" || return $?

  mkdir -p "$(dirname "$target")"
  url="https://raw.githubusercontent.com/${DEV_ROUTER_GITHUB_REPO}/${tag}/${path}"
  run_with_timeout "$CHECK_TIMEOUT_SECONDS" curl -fsSL "$url" -o "$target"
}

download_update_tree() {
  local tag target_dir path
  tag="$1"
  target_dir="$2"

  for path in "${DEV_ROUTER_FILES[@]}"; do
    download_update_file "$tag" "$path" "$target_dir/$path" || return $?
  done
}

validate_downloaded_update() {
  local tree file
  tree="$1"

  if ! head -n 1 "$tree/bin/dev" | grep -q '^#!/usr/bin/env bash'; then
    echo "[dev] downloaded update does not look like a bash script" >&2
    return 1
  fi

  if ! grep -q '^DEV_ROUTER_VERSION=' "$tree/bin/dev"; then
    echo "[dev] downloaded update does not look like dev-router" >&2
    return 1
  fi

  for file in "${DEV_ROUTER_FILES[@]}"; do
    if [[ ! -s "$tree/$file" ]]; then
      echo "[dev] downloaded update is missing $file" >&2
      return 1
    fi
  done
}

install_downloaded_update() {
  local tree target target_bin_dir install_root path source dest tmp_dest
  tree="$1"
  target="$(self_path)"
  target_bin_dir="$(dirname "$target")"
  install_root="$(cd "$target_bin_dir/.." 2>/dev/null && pwd)"

  if [[ ! -f "$target" || ! -w "$target" ]]; then
    echo "[dev] cannot update $target; file is not writable" >&2
    return 1
  fi

  validate_downloaded_update "$tree" || return $?

  for path in "${DEV_ROUTER_FILES[@]}"; do
    source="$tree/$path"
    if [[ "$path" == "bin/dev" ]]; then
      dest="$target"
    else
      dest="$install_root/$path"
    fi

    mkdir -p "$(dirname "$dest")" || return $?
    tmp_dest="$(make_temp_in_dir "$(dirname "$dest")" "$(basename "$dest").update")" || return $?
    cp "$source" "$tmp_dest" || return $?
    if [[ "$path" == "bin/dev" ]]; then
      chmod +x "$tmp_dest" || return $?
    fi
    mv "$tmp_dest" "$dest" || return $?
  done
}

update_dev_router() {
  local latest tmp_dir
  latest="$(latest_release_tag)" || {
    echo "[dev] could not find latest release for ${DEV_ROUTER_GITHUB_REPO}" >&2
    return 1
  }

  if ! version_is_newer "$latest" "$DEV_ROUTER_VERSION"; then
    echo "[dev] dev-router is already up to date ($DEV_ROUTER_VERSION)"
    return 0
  fi

  tmp_dir="$(make_temp_dir)" || return $?
  if ! download_update_tree "$latest" "$tmp_dir"; then
    remove_temp "$tmp_dir"
    echo "[dev] failed to download dev-router $latest" >&2
    return 1
  fi

  if install_downloaded_update "$tmp_dir"; then
    remove_temp "$tmp_dir"
    mkdir -p "$CACHE_DIR"
    date +%s >"$UPDATE_CACHE_FILE"
    echo "[dev] updated dev-router $DEV_ROUTER_VERSION -> $latest"
    return 0
  fi

  remove_temp "$tmp_dir"
  return 1
}

auto_update_is_due() {
  local now mtime age
  [[ "$DEV_ROUTER_AUTO_UPDATE" == "1" ]] || return 1
  [[ "$DEV_ROUTER_VERSION" != "0.0.0-dev" ]] || return 1

  now="$(date +%s)"
  if [[ -f "$UPDATE_CACHE_FILE" ]]; then
    mtime="$(cat "$UPDATE_CACHE_FILE" 2>/dev/null || echo 0)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    age=$((now - mtime))
    [[ "$age" -ge "$AUTO_UPDATE_TTL_SECONDS" ]] || return 1
  fi

  return 0
}

auto_update_if_due() {
  local latest tmp_dir
  auto_update_is_due || return 0

  mkdir -p "$CACHE_DIR"
  date +%s >"$UPDATE_CACHE_FILE"

  latest="$(latest_release_tag 2>/dev/null)" || return 0
  version_is_newer "$latest" "$DEV_ROUTER_VERSION" || return 0

  tmp_dir="$(make_temp_dir)" || return 0
  download_update_tree "$latest" "$tmp_dir" 2>/dev/null || {
    remove_temp "$tmp_dir"
    return 0
  }

  if install_downloaded_update "$tmp_dir" 2>/dev/null; then
    echo "[dev] updated dev-router $DEV_ROUTER_VERSION -> $latest"
  fi
  remove_temp "$tmp_dir"
}
