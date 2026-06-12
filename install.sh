#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DEV_ROUTER_REPO_URL:-https://raw.githubusercontent.com/casungo/dev-router/main}"
INSTALL_DIR="${DEV_ROUTER_INSTALL_DIR:-${HOME}/.local/bin}"
TARGET="${INSTALL_DIR}/dev"

mkdir -p "$INSTALL_DIR"

curl -fsSL "${REPO_URL}/bin/dev" -o "$TARGET"
chmod +x "$TARGET"

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
echo "Configure provider keys with:"
echo "export Z_AI_API_KEY=\"...\""
echo "export DEEPSEEK_API_KEY=\"...\""
