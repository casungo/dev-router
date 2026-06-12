# dev-router

Opinionated local router for AI coding CLIs.

This is built around my setup and preferences. It hardcodes choices I personally want, including permissive launch flags like `--dangerously-bypass-approvals-and-sandbox` / `--dangerously-skip-permissions`, my default model names, and my fallback order. Treat it as a useful starting point to fork or edit, not as a general-purpose safety wrapper.

Run `dev` from any repo and it checks provider quota before launching the first available coding agent:

1. Codex
2. GLM through Claude Code
3. Antigravity
4. DeepSeek through Claude Code

It caches quota checks for 5 minutes, supports `dev --status`, and lets you directly launch one provider when you already know what you want.
You can also change the routing order interactively.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/install.sh | bash
```

Manual install:

```bash
mkdir -p "$HOME/.local/bin"
curl -fsSL https://raw.githubusercontent.com/casungo/dev-router/main/bin/dev \
  -o "$HOME/.local/bin/dev"
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

The self-updater reads the latest release from `casungo/dev-router` and downloads `bin/dev` from that release tag.

To publish a new version:

1. Update `DEV_ROUTER_VERSION` in `bin/dev`.
2. Commit and push the change.
3. Create a GitHub release whose tag matches the version, for example `v0.1.1`.

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

## Notes

This script launches tools with permission-skipping flags because that is how I use these CLIs locally. Remove those flags in `bin/dev` if you want each agent to ask for approval.

GLM quota checks use the Z.AI Coding Plan endpoint. Antigravity quota checks are based on launching `agy` and reading `/usage`, because the public CLI quota endpoint is not documented.

If Antigravity later exposes a stable status or quota API, replace the `/usage` probe in `bin/dev` with that official endpoint.
