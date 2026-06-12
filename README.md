# dev-router

Friendly local router for AI coding CLIs.

Run `dev` from any repo and it checks provider quota before launching the first available coding agent:

1. Codex
2. GLM through Claude Code
3. Antigravity
4. DeepSeek through Claude Code

It caches quota checks for 5 minutes, supports `dev --status`, and lets you directly launch one provider when you already know what you want.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/dev-router/main/install.sh | bash
```

Manual install:

```bash
mkdir -p "$HOME/.local/bin"
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/dev-router/main/bin/dev \
  -o "$HOME/.local/bin/dev"
chmod +x "$HOME/.local/bin/dev"
```

Make sure `~/.local/bin` is on your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
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
export DEV_GLM_MODEL="GLM-4.7"
export DEV_GLM_FAST_MODEL="GLM-4.5-Air"
export DEV_AGY_MODEL="Claude Sonnet 4.6 (Thinking)"
export DEV_DEEPSEEK_MODEL="deepseek-v4-pro[1m]"
export DEV_DEEPSEEK_FAST_MODEL="deepseek-v4-flash"
```

## Notes

GLM quota checks use the Z.AI Coding Plan endpoint. Antigravity quota checks are based on launching `agy` and reading `/usage`, because the public CLI quota endpoint is not documented.

If Antigravity later exposes a stable status or quota API, replace the `/usage` probe in `bin/dev` with that official endpoint.
