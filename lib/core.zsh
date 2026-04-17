_ensure_env_dir() {
    if [[ ! -d "$CLAUDE_ENVS_DIR" ]]; then
        mkdir -p "$CLAUDE_ENVS_DIR"
        chmod 700 "$CLAUDE_ENVS_DIR"
    fi
}

_config_file_path() {
    local name="$1"
    echo "$CLAUDE_ENVS_DIR/$name.conf"
}

_config_exists() {
    local name="$1"
    [[ -f "$(_config_file_path "$name")" ]]
}

_validate_config_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "error: Config name cannot be empty" >&2
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "error: Config name must contain only letters, numbers, dashes, and underscores" >&2
        return 1
    fi
    return 0
}

_mask_token() {
    local token="$1"
    local len=${#token}
    if (( len < 10 )); then
        echo "***"
    else
        local show_first=6
        local show_last=4
        echo "${token[1,$show_first]}...${token[-$show_last,$len]}"
    fi
}

_get_config_value() {
    local conf_file="$1"
    local key="$2"
    grep "^${key}=" "$conf_file" 2>/dev/null | cut -d'=' -f2-
}

_normalize_token_type() {
    local token_type="$1"
    if [[ "$token_type" == "api" ]]; then
        echo "auth-token"
    else
        echo "$token_type"
    fi
}

_get_config_token_type() {
    local config_name="$1"
    local conf_file="$(_config_file_path "$config_name")"
    _normalize_token_type "$(_get_config_value "$conf_file" "TYPE")"
}

_get_config_description() {
    local config_name="$1"
    local conf_file="$(_config_file_path "$config_name")"
    _get_config_value "$conf_file" "DESCRIPTION"
}

_get_config_display_line() {
    local config_name="$1"
    local token_type="$(_get_config_token_type "$config_name")"
    local description="$(_get_config_description "$config_name")"
    local desc_display=""
    [[ -n "$description" ]] && desc_display=" - $description"
    echo "$config_name ($token_type)$desc_display"
}

_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "error: jq is required for settings and statusline commands" >&2
        return 1
    fi
}

_ensure_claude_settings_dir() {
    local settings_dir="${CLAUDE_SETTINGS_FILE:h}"
    if [[ ! -d "$settings_dir" ]]; then
        mkdir -p "$settings_dir"
        chmod 700 "$settings_dir" 2>/dev/null || true
    fi
}
