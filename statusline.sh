#!/bin/bash
# Read JSON input from stdin
input=$(cat)

# Extract values using jq
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name')
PERCENT_USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir')
CURRENT_DIR=$(basename "$CURRENT_DIR")

# CLAUDE_ENV_CONFIG is set by ccenv when launching claude
CONFIG_NAME="${CLAUDE_ENV_CONFIG:-}"

if [[ -n "$CONFIG_NAME" ]]; then
    echo "[$MODEL_DISPLAY] | Context: ${PERCENT_USED}% | Dir: $CURRENT_DIR | Env: $CONFIG_NAME"
else
    echo "[$MODEL_DISPLAY] | Context: ${PERCENT_USED}% | Dir: $CURRENT_DIR"
fi