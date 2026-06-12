# AGENTS.md

Guidance for coding agents working in this repository.

## Project Shape

`dev-router` is a small Bash CLI. The main executable is `bin/dev`; `install.sh` downloads that file into the user's local bin directory.

Keep changes simple and portable. The script should work on Linux and macOS with Bash, `curl`, `jq`, and either `timeout` or `gtimeout`.

## Common Commands

```bash
bash -n bin/dev install.sh
./bin/dev --help
./bin/dev --version
```

Avoid running provider launch commands in automated checks unless the user explicitly asks, because they can start interactive CLIs.

## Release And Update Flow

The updater uses GitHub Releases:

1. Update `DEV_ROUTER_VERSION` in `bin/dev`.
2. Commit and push.
3. Publish a GitHub release with a matching tag, such as `v0.1.1`.

Installed copies update from:

```text
https://raw.githubusercontent.com/casungo/dev-router/<tag>/bin/dev
```

`dev --update` checks immediately. Normal `dev` runs auto-check at most once per day unless `DEV_ROUTER_AUTO_UPDATE=0`.

## Style Notes

- Prefer Bash built-ins and small functions over adding new runtime dependencies.
- Preserve user-facing output style: short `[dev]` diagnostics and concise status lines.
- Keep network checks timeout-bound.
- Do not store secrets or provider tokens in the repo.
- Do not change the intentionally permissive launch flags unless the user asks.
