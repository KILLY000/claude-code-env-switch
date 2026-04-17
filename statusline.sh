#!/bin/sh
input=$(cat)
model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cwd=$(basename "$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')")
env_name="${CLAUDE_ENV_CONFIG:-}"
extra_info="${CLAUDE_STATUSLINE_EXTRA:-}"

if [ -n "$used" ]; then
  ctx=$(printf "%.0f%%" "$used")
else
  ctx="--"
fi

printf "\033[36m%s\033[0m  \033[33mCtx: %s\033[0m  \033[32m%s\033[0m" "$model" "$ctx" "$cwd"

if [ -n "$env_name" ]; then
  printf "  \033[35mEnv: %s\033[0m" "$env_name"
fi

if [ -n "$extra_info" ]; then
  printf "  \033[34m%s\033[0m" "$extra_info"
fi

printf "\n"
