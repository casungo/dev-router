#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DEV_ROUTER_REPO_URL:-https://raw.githubusercontent.com/casungo/dev-router/main}"
INSTALL_DIR="${DEV_ROUTER_INSTALL_DIR:-${HOME}/.local/bin}"
PREFIX_DIR="${DEV_ROUTER_PREFIX_DIR:-$(dirname "$INSTALL_DIR")}"
LIB_DIR="${DEV_ROUTER_LIB_DIR:-${PREFIX_DIR}/lib/dev-router}"
TARGET="${INSTALL_DIR}/dev"
FILES=(
  bin/dev
  lib/dev-router/core.bash
  lib/dev-router/update.bash
  lib/dev-router/cache-order.bash
  lib/dev-router/providers.bash
  lib/dev-router/commands.bash
)

suggest_shell_config() {
  case "$(basename "${SHELL:-}")" in
    zsh)
      echo "\$HOME/.zshrc"
      ;;
    bash)
      if [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]]; then
        echo "\$HOME/.bash_profile"
      else
        echo "\$HOME/.bashrc"
      fi
      ;;
    *)
      echo "your shell startup file"
      ;;
  esac
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}

signal_cleanup() {
  local signal
  signal="$1"
  cleanup
  trap - "$signal"
  kill "-$signal" "$$"
}

trap cleanup EXIT
trap 'signal_cleanup HUP' HUP
trap 'signal_cleanup INT' INT
trap 'signal_cleanup TERM' TERM

mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_DIR"

for file in "${FILES[@]}"; do
  mkdir -p "$TMP_DIR/$(dirname "$file")"
  curl -fsSL "${REPO_URL}/${file}" -o "$TMP_DIR/$file"
done

if ! head -n 1 "$TMP_DIR/bin/dev" | grep -q '^#!/usr/bin/env bash'; then
  echo "Downloaded bin/dev does not look like a bash script" >&2
  exit 1
fi

if ! grep -q '^DEV_ROUTER_VERSION=' "$TMP_DIR/bin/dev"; then
  echo "Downloaded files do not look like dev-router" >&2
  exit 1
fi

install -m 755 "$TMP_DIR/bin/dev" "$TARGET"
install -m 644 "$TMP_DIR/lib/dev-router/"*.bash "$LIB_DIR/"

echo "Installed dev-router to ${TARGET}"

case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    echo
    echo "Add this to your shell config:"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

echo
SHELL_CONFIG="$(suggest_shell_config)"
echo "Configure provider keys by adding these to ${SHELL_CONFIG}:"
echo "export Z_AI_API_KEY=\"...\""
echo "export DEEPSEEK_API_KEY=\"...\""
echo
echo "Then restart your shell, or run: source ${SHELL_CONFIG}"
