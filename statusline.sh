#!/bin/bash
# Read JSON input from stdin
input=$(cat)

# Extract values using jq
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name')

# CLAUDE_ENV_CONFIG is set by ccenv when launching claude
CONFIG_NAME="${CLAUDE_ENV_CONFIG:-}"

if [[ -n "$CONFIG_NAME" ]]; then
    echo "[$MODEL_DISPLAY] ⚙ $CONFIG_NAME"
else
    echo "[$MODEL_DISPLAY]"
fi