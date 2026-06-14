# dev-router

[![Release](https://img.shields.io/github/v/release/casungo/dev-router)](https://github.com/casungo/dev-router/releases)
[![License](https://img.shields.io/github/license/casungo/dev-router)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25)](bin/dev)

Opinionated Bash router for AI coding CLIs with quota-aware fallback, configurable provider order, and self-updates from GitHub Releases.

This is built around my setup and preferences. It hardcodes choices I personally want, including permissive launch flags like `--dangerously-bypass-approvals-and-sandbox` / `--dangerously-skip-permissions`, my default model names, and my fallback order. Treat it as a useful starting point to fork or edit, not as a general-purpose safety wrapper.

Run `dev` from any repo and it checks provider quota before launching the first available coding agent:

1. Codex
2. GLM through Claude Code
3. Antigravity
4. DeepSeek through Claude Code

It caches quota checks for 5 minutes, supports `dev --status`, and lets you directly launch one provider when you already know what you want.
You can also change the routing order interactively.

## Features

- Quota-aware routing across Codex, GLM, Antigravity, and DeepSeek
- 5-minute quota cache to avoid repeated network checks
- Interactive or file-based provider order
- Direct provider launches when you want to skip routing
- Self-update command and once-per-day automatic update checks

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/install.sh | bash
```

Manual install:

```bash
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/lib/dev-router"
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/bin/dev \
  -o "$HOME/.local/bin/dev"
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/lib/dev-router/core.bash \
  -o "$HOME/.local/lib/dev-router/core.bash"
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/lib/dev-router/update.bash \
  -o "$HOME/.local/lib/dev-router/update.bash"
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/lib/dev-router/cache-order.bash \
  -o "$HOME/.local/lib/dev-router/cache-order.bash"
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/lib/dev-router/providers.bash \
  -o "$HOME/.local/lib/dev-router/providers.bash"
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/lib/dev-router/commands.bash \
  -o "$HOME/.local/lib/dev-router/commands.bash"
chmod +x "$HOME/.local/bin/dev"
```

Make sure `~/.local/bin` is on your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To install somewhere else:

```bash
DEV_ROUTER_INSTALL_DIR="$HOME/bin" bash install.sh
```

## Configuration

Add your provider keys somewhere private, for example `~/.config/shell/secrets.zsh`:

```bash
export Z_AI_API_KEY="your-z-ai-key"
export DEEPSEEK_API_KEY="your-deepseek-key"
```

Then source it from `~/.zshrc`:

```bash
source "$HOME/.config/shell/secrets.zsh"
export PATH="$HOME/.local/bin:$PATH"
```

Codex auth is read from `~/.codex/auth.json`. Antigravity auth is handled by `agy`.

## Requirements

Quota checks need `jq`, `curl`, and `timeout` or `gtimeout`. On macOS, `gtimeout` is provided by GNU coreutils:

```bash
brew install coreutils jq
```

## Usage

Auto-route to the first available provider:

```bash
dev
dev "fix the failing tests"
```

Show all quota states:

```bash
dev --status
```

Show the installed version or update from the latest GitHub release:

```bash
dev --version
dev --update
```

`dev` also checks for a newer GitHub release at most once per day and updates itself automatically when a newer release is available. Disable that with:

```bash
export DEV_ROUTER_AUTO_UPDATE=0
```

Show or modify the provider routing order:

```bash
dev --order
dev --order edit
dev --order set glm codex agy deepseek
dev --order reset
```

The order is saved in `~/.config/dev-router/order`, or in `$DEV_ROUTER_ORDER_FILE` if you set it.

## Publishing Updates

The self-updater reads the latest release from `casungo/dev-router` and downloads the matching `bin/dev` plus `lib/dev-router/*.bash` files from that release tag.

To publish a new version:

```bash
pnpm release patch
```

You can also pass `minor`, `major`, or an explicit version such as `0.1.3`.
The release helper updates `DEV_ROUTER_VERSION` in `bin/dev`, runs the safe checks, commits and pushes the bump, creates a matching tag, and publishes the GitHub release.

Existing installs update on the next `dev` run after their daily update check is due, or immediately when running `dev --update`.

Launch one provider directly and skip routing:

```bash
dev codex
dev glm
dev agy
dev deepseek
```

Check one provider before launching it:

```bash
dev --use glm
```

Launch one provider without a quota check:

```bash
dev --force-use agy
```

Test fallback behavior by marking a provider exhausted in cache:

```bash
dev --exhausted-test glm
dev --clear-cache glm
```

## Model Defaults

The script reads model defaults from environment variables, so you can override them without editing the script:

```bash
export DEV_CODEX_MODEL="gpt-5.5"
export DEV_GLM_MODEL="GLM-5.1"
export DEV_GLM_FAST_MODEL="GLM-4.5-Air"
export DEV_AGY_MODEL="Claude Sonnet 4.6 (Thinking)"
export DEV_DEEPSEEK_MODEL="deepseek-v4-pro[1m]"
export DEV_DEEPSEEK_FAST_MODEL="deepseek-v4-flash"
```

## GLM MCP Servers

When GLM is launched through Claude Code, dev-router injects the Z.AI MCP servers (Vision, Web Search, Web Reader, and Zread) via `claude --mcp-config`, so they are available only on the GLM path — not when routed to Codex, Antigravity, or DeepSeek. The config is generated into a temp file at launch time using your `Z_AI_API_KEY` and removed afterward.

```bash
# Turn the auto-generated Z.AI MCP servers off (default: 1 / on)
export DEV_GLM_MCP=0

# Or point at your own MCP config file instead of the generated one
export DEV_GLM_MCP_CONFIG="$HOME/.config/dev-router/glm.mcp.json"
```

If you previously added any of these servers globally (for example with `claude mcp add -s user ...`), remove them first — otherwise they load on every provider regardless of routing:

```bash
claude mcp list
claude mcp remove web-search-prime
claude mcp remove web-reader
claude mcp remove zread
claude mcp remove zai-mcp-server
```

The Vision server (`@z_ai/mcp-server`) spawns via `npx` and needs Node.js >= 22; if it is missing, that one server fails to start while the HTTP servers still work.

## Notes

This script launches tools with permission-skipping flags because that is how I use these CLIs locally. Remove those flags in `lib/dev-router/commands.bash` if you want each agent to ask for approval.

GLM quota checks use the Z.AI Coding Plan endpoint. Antigravity quota checks are based on launching `agy` and reading `/usage`, because the public CLI quota endpoint is not documented.

If Antigravity later exposes a stable status or quota API, replace the `/usage` probe in `lib/dev-router/providers.bash` with that official endpoint.
