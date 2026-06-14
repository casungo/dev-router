run_and_invalidate_on_quota_failure() {
  local provider rc tmp_err
  provider="$1"
  shift

  if [[ -t 0 && -t 2 ]]; then
    "$@"
    return $?
  fi

  tmp_err="$(make_temp)" || return $?

  "$@" 2> >(tee "$tmp_err" >&2)
  rc=$?

  if [[ "$rc" -ne 0 ]] && grep -Eiq '(^|[^0-9])429([^0-9]|$)|rate.?limit|quota|RESOURCE_EXHAUSTED|exhausted' "$tmp_err"; then
    invalidate_cache "$provider"
    printf '[%s] cache invalidated after quota-looking failure\n' "$provider" >&2
  fi

  remove_temp "$tmp_err"
  return "$rc"
}

status_all() {
  local provider result
  while IFS= read -r provider; do
    result="$(check_provider "$provider" yes)"
    print_result_json "$provider" "$result"
  done < <(provider_order)
}

mark_exhausted_for_test() {
  local provider input
  input="${1:-}"
  if ! provider="$(normalize_provider "$input")"; then
    echo "[dev] unknown provider for exhausted test: ${input:-<missing>}" >&2
    echo "[dev] expected one of: codex, glm, antigravity, deepseek" >&2
    return 2
  fi

  write_cache "$provider" false "forced exhausted test ($provider)" "Created by dev --exhausted-test; clear with dev --clear-cache or wait 5 minutes."
  echo "[dev] marked $provider unavailable in cache for $CACHE_TTL_SECONDS seconds"
  echo "[dev] run 'dev --status' or 'dev ...' to test fallback"
}

usage() {
  cat <<EOF
Usage:
  dev [prompt...]                         Auto-route to first available provider
  dev --version                           Show dev-router version
  dev --update                            Update dev-router from the latest GitHub release
  dev --status                            Show quota status for all providers
  dev --order                             Show provider routing order
  dev --order edit                        Reorder providers interactively
  dev --order set <providers...>          Save provider routing order
  dev --order reset                       Reset provider routing order
  dev --use <provider> [args...]          Check then launch one provider directly
  dev --force-use <provider> [args...]    Launch one provider directly without quota check
  dev <provider> [args...]                Launch one provider directly without quota check
  dev --exhausted-test <provider>         Mark provider unavailable in cache for fallback tests
  dev --clear-cache [provider]            Clear quota cache

Providers: codex, glm, agy, antigravity, deepseek
EOF
}

order_command() {
  local subcommand
  subcommand="${1:-show}"

  case "$subcommand" in
    show)
      print_provider_order
      ;;
    edit)
      interactive_order_editor
      ;;
    set)
      shift
      if [[ "$#" -eq 0 ]]; then
        echo "[dev] provide at least one provider for --order set" >&2
        return 2
      fi
      validate_order_args "$@" || return $?
      save_provider_order "${VALIDATED_ORDER[@]}"
      echo "[dev] provider order saved to $ORDER_FILE"
      print_provider_order
      ;;
    reset)
      rm -f "$ORDER_FILE"
      echo "[dev] provider order reset"
      print_provider_order
      ;;
    *)
      echo "[dev] unknown --order command: $subcommand" >&2
      echo "[dev] expected: show, edit, set, reset" >&2
      return 2
      ;;
  esac
}

interactive_order_editor() {
  local line command first second tmp i provider
  local -a order
  local -a parts
  order=()

  if [[ ! -t 0 ]]; then
    echo "[dev] --order edit needs an interactive terminal" >&2
    return 2
  fi

  while IFS= read -r provider; do
    order+=("$provider")
  done < <(provider_order)

  while true; do
    echo
    echo "Provider order:"
    i=1
    for provider in "${order[@]}"; do
      printf '  %d. %s (%s)\n' "$i" "$(provider_label "$provider")" "$provider"
      i=$((i + 1))
    done
    echo
    echo "Commands: move <from> <to>, up <n>, down <n>, save, quit"
    printf '> '
    IFS= read -r line || return 1

    read -r -a parts <<<"$line"
    command="${parts[0]:-}"
    first="${parts[1]:-}"
    second="${parts[2]:-}"

    case "$command" in
      move|m)
        if [[ ! "$first" =~ ^[0-9]+$ || ! "$second" =~ ^[0-9]+$ || "$first" -lt 1 || "$first" -gt "${#order[@]}" || "$second" -lt 1 || "$second" -gt "${#order[@]}" ]]; then
          echo "[dev] usage: move <from> <to>"
          continue
        fi
        first=$((first - 1))
        second=$((second - 1))
        tmp="${order[$first]}"
        unset 'order[first]'
        order=("${order[@]}")
        order=("${order[@]:0:$second}" "$tmp" "${order[@]:$second}")
        ;;
      up|u)
        if [[ ! "$first" =~ ^[0-9]+$ || "$first" -le 1 || "$first" -gt "${#order[@]}" ]]; then
          echo "[dev] usage: up <n>"
          continue
        fi
        first=$((first - 1))
        tmp="${order[$first]}"
        order[$first]="${order[$((first - 1))]}"
        order[$((first - 1))]="$tmp"
        ;;
      down|d)
        if [[ ! "$first" =~ ^[0-9]+$ || "$first" -lt 1 || "$first" -ge "${#order[@]}" ]]; then
          echo "[dev] usage: down <n>"
          continue
        fi
        first=$((first - 1))
        tmp="${order[$first]}"
        order[$first]="${order[$((first + 1))]}"
        order[$((first + 1))]="$tmp"
        ;;
      save|s)
        save_provider_order "${order[@]}"
        echo "[dev] provider order saved to $ORDER_FILE"
        return 0
        ;;
      quit|q)
        echo "[dev] provider order unchanged"
        return 0
        ;;
      "")
        ;;
      *)
        echo "[dev] unknown command: $command"
        ;;
    esac
  done
}

glm_mcp_config_path() {
  # Echo a path to an MCP config file holding the Z.AI servers (vision,
  # web search, web reader, zread) so they load only when GLM is launched.
  # Returns 1 and prints nothing when the feature is off or unavailable.
  # DEV_GLM_MCP=0 disables the auto-generated servers entirely; point
  # DEV_GLM_MCP_CONFIG at a hand-written file to use that instead.
  local tmp key

  if [[ "${DEV_GLM_MCP:-1}" != "1" ]]; then
    return 1
  fi

  if [[ -n "${DEV_GLM_MCP_CONFIG:-}" && -f "${DEV_GLM_MCP_CONFIG}" ]]; then
    printf '%s\n' "$DEV_GLM_MCP_CONFIG"
    return 0
  fi

  key="${Z_AI_API_KEY:-}"
  if [[ -z "$key" ]]; then
    return 1
  fi

  require_jq >/dev/null 2>&1 || return $?
  tmp="$(make_temp)" || return $?
  jq -n --arg key "$key" '{
    mcpServers: {
      "zai-vision": {
        type: "stdio",
        command: "npx",
        args: ["-y", "@z_ai/mcp-server@latest"],
        env: { Z_AI_API_KEY: $key, Z_AI_MODE: "ZAI" }
      },
      "web-search-prime": {
        type: "http",
        url: "https://api.z.ai/api/mcp/web_search_prime/mcp",
        headers: { Authorization: ("Bearer " + $key) }
      },
      "web-reader": {
        type: "http",
        url: "https://api.z.ai/api/mcp/web_reader/mcp",
        headers: { Authorization: ("Bearer " + $key) }
      },
      zread: {
        type: "http",
        url: "https://api.z.ai/api/mcp/zread/mcp",
        headers: { Authorization: ("Bearer " + $key) }
      }
    }
  }' >"$tmp" || { remove_temp "$tmp"; return 1; }

  printf '%s\n' "$tmp"
}

launch_provider() {
  local provider
  provider="$1"
  shift

  case "$provider" in
    codex)
      require_command codex "launching Codex" || return $?
      echo "▶ Launching codex directly ($DEV_CODEX_MODEL)"
      run_and_invalidate_on_quota_failure codex codex \
        --model "$DEV_CODEX_MODEL" \
        --dangerously-bypass-approvals-and-sandbox \
        "$@"
      return $?
      ;;
    glm)
      local mcp_file rc
      local -a claude_args
      require_command claude "launching GLM through Claude Code" || return $?
      if [[ -z "${Z_AI_API_KEY:-}" ]]; then
        echo "[dev] Z_AI_API_KEY is required for GLM" >&2
        return 2
      fi

      mcp_file="$(glm_mcp_config_path)" || mcp_file=""
      claude_args=(claude --model "$DEV_GLM_MODEL" --dangerously-skip-permissions)
      if [[ -n "$mcp_file" ]]; then
        claude_args+=(--mcp-config "$mcp_file")
        echo "▶ Launching claude+GLM directly ($DEV_GLM_MODEL) with Z.AI MCP servers"
      else
        echo "▶ Launching claude+GLM directly ($DEV_GLM_MODEL)"
      fi

      run_and_invalidate_on_quota_failure glm env \
        ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic" \
        ANTHROPIC_AUTH_TOKEN="$Z_AI_API_KEY" \
        ANTHROPIC_MODEL="$DEV_GLM_MODEL" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$DEV_GLM_MODEL" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$DEV_GLM_MODEL" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$DEV_GLM_FAST_MODEL" \
        CLAUDE_CODE_SUBAGENT_MODEL="$DEV_GLM_FAST_MODEL" \
        "${claude_args[@]}" "$@"
      rc=$?
      # Remove only the auto-generated temp config; never a user-supplied file.
      if [[ -n "$mcp_file" && "$mcp_file" != "${DEV_GLM_MCP_CONFIG:-}" ]]; then
        remove_temp "$mcp_file"
      fi
      return "$rc"
      ;;
    antigravity)
      require_command agy "launching Antigravity" || return $?
      echo "▶ Launching agy directly ($DEV_AGY_MODEL)"
      run_and_invalidate_on_quota_failure antigravity agy \
        --model "$DEV_AGY_MODEL" \
        --dangerously-skip-permissions \
        "$@"
      return $?
      ;;
    deepseek)
      require_command claude "launching DeepSeek through Claude Code" || return $?
      if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
        echo "[dev] DEEPSEEK_API_KEY is required for DeepSeek" >&2
        return 2
      fi
      echo "▶ Launching claude+DeepSeek directly ($DEV_DEEPSEEK_MODEL)"
      run_and_invalidate_on_quota_failure deepseek env \
        ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic" \
        ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY" \
        ANTHROPIC_MODEL="$DEV_DEEPSEEK_MODEL" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="$DEV_DEEPSEEK_MODEL" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="$DEV_DEEPSEEK_MODEL" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$DEV_DEEPSEEK_FAST_MODEL" \
        CLAUDE_CODE_SUBAGENT_MODEL="$DEV_DEEPSEEK_FAST_MODEL" \
        CLAUDE_CODE_EFFORT_LEVEL=max \
        claude --model "$DEV_DEEPSEEK_MODEL" --dangerously-skip-permissions "$@"
      return $?
      ;;
  esac

  echo "[dev] unknown provider: $provider" >&2
  return 2
}

direct_launch() {
  local provider input result available force
  force="${1:-no}"
  input="${2:-}"
  if ! provider="$(normalize_provider "$input")"; then
    echo "[dev] unknown provider for direct launch: ${input:-<missing>}" >&2
    echo "[dev] expected one of: codex, glm, agy, antigravity, deepseek" >&2
    return 2
  fi
  shift 2

  if [[ "$force" != "yes" ]]; then
    result="$(check_provider "$provider" yes)"
    print_result_json "$provider" "$result"
    available="$(json_available <<<"$result")"
    if [[ "$available" != "true" ]]; then
      echo "[dev] $provider is unavailable; use --force-use $input to launch anyway" >&2
      return 1
    fi
  fi

  launch_provider "$provider" "$@"
}

choose_and_launch() {
  local provider result available
  auto_update_if_due

  while IFS= read -r provider <&3; do
    result="$(check_provider "$provider" yes)"
    print_result_json "$provider" "$result"
    available="$(json_available <<<"$result")"
    [[ "$available" == "true" ]] || continue

    case "$provider" in
      codex)
        echo "▶ Codex available"
        launch_provider codex "$@"
        return $?
        ;;
      glm)
        echo "▶ GLM available"
        launch_provider glm "$@"
        return $?
        ;;
      antigravity)
        echo "▶ Antigravity available"
        launch_provider antigravity "$@"
        return $?
        ;;
      deepseek)
        echo "▶ DeepSeek available"
        launch_provider deepseek "$@"
        return $?
        ;;
    esac
  done 3< <(provider_order)

  echo "[dev] no provider is currently available" >&2
  return 1
}
