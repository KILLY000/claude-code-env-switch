_set_statusline_in_settings() {
    _require_jq || return 1
    _validate_settings_file || return 1
    _ensure_claude_settings_dir

    local tmp_file=""
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/ccenv-statusline.XXXXXX") || return 1

    if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
        if ! jq \
            --arg command_path "$CLAUDE_STATUSLINE_FILE" \
            '
            .statusLine = {
                "type": "command",
                "command": $command_path,
                "padding": 0
            }
            ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file"; then
            rm -f "$tmp_file"
            echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
            return 1
        fi
    else
        if ! jq -n \
            --arg command_path "$CLAUDE_STATUSLINE_FILE" \
            '{
                statusLine: {
                    type: "command",
                    command: $command_path,
                    padding: 0
                }
            }' > "$tmp_file"; then
            rm -f "$tmp_file"
            echo "error: Failed to create $CLAUDE_SETTINGS_FILE" >&2
            return 1
        fi
    fi

    mv "$tmp_file" "$CLAUDE_SETTINGS_FILE"
    chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || true
}

_clear_statusline_in_settings() {
    _require_jq || return 1
    _validate_settings_file || return 1

    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
        return 0
    fi

    local tmp_file=""
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/ccenv-statusline.XXXXXX") || return 1

    if ! jq 'del(.statusLine)' "$CLAUDE_SETTINGS_FILE" > "$tmp_file"; then
        rm -f "$tmp_file"
        echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
        return 1
    fi

    mv "$tmp_file" "$CLAUDE_SETTINGS_FILE"
    chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || true
}

_install_statusline_script() {
    local source_script="$CLAUDE_ENV_SWITCH_PLUGIN_DIR/statusline.sh"

    if [[ ! -f "$source_script" ]]; then
        echo "error: Statusline source script not found at $source_script" >&2
        return 1
    fi

    _ensure_claude_settings_dir

    cp "$source_script" "$CLAUDE_STATUSLINE_FILE" || {
        echo "error: Failed to copy statusline script to $CLAUDE_STATUSLINE_FILE" >&2
        return 1
    }

    chmod 755 "$CLAUDE_STATUSLINE_FILE" 2>/dev/null || true
}
