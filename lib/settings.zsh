_managed_env_keys_json() {
    printf "%s\n" "${CLAUDE_MANAGED_ENV_KEYS[@]}" | jq -R . | jq -s .
}

_validate_settings_file() {
    [[ ! -f "$CLAUDE_SETTINGS_FILE" ]] && return 0

    _require_jq || return 1

    if ! jq -e '
        (.env == null or (.env | type == "object"))
        and (.statusLine == null or (.statusLine | type == "object"))
    ' "$CLAUDE_SETTINGS_FILE" >/dev/null 2>&1; then
        echo "error: $CLAUDE_SETTINGS_FILE is not valid JSON or .env/.statusLine are not objects" >&2
        return 1
    fi
}

_get_statusline_settings_value() {
    local key="$1"
    [[ ! -f "$CLAUDE_SETTINGS_FILE" ]] && return 0

    _validate_settings_file || return 1
    jq -r --arg key "$key" '.statusLine[$key] // empty' "$CLAUDE_SETTINGS_FILE"
}

_list_settings_managed_keys() {
    [[ ! -f "$CLAUDE_SETTINGS_FILE" ]] && return 0

    _validate_settings_file || return 1

    local managed_keys_json=""
    managed_keys_json="$(_managed_env_keys_json)" || return 1

    jq -r --argjson managed_keys "$managed_keys_json" '
        .env // {}
        | keys[]?
        | select(. as $key | $managed_keys | index($key))
    ' "$CLAUDE_SETTINGS_FILE"
}

_settings_has_managed_env() {
    local keys=""
    keys="$(_list_settings_managed_keys)" || return 1
    [[ -n "$keys" ]]
}

_get_settings_env_value() {
    local key="$1"
    [[ ! -f "$CLAUDE_SETTINGS_FILE" ]] && return 0

    _validate_settings_file || return 1
    jq -r --arg key "$key" '.env[$key] // empty' "$CLAUDE_SETTINGS_FILE"
}

_mask_env_value() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "(not set)"
    elif [[ "$key" == "CLAUDE_ENV_CONFIG" || "$key" == "ANTHROPIC_BASE_URL" || "$key" == "DISABLE_TELEMETRY" || "$key" == "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" ]]; then
        echo "$value"
    else
        _mask_token "$value"
    fi
}

_build_config_env_json() {
    local config_name="$1"
    local conf_file="$(_config_file_path "$config_name")"
    local token_type="$(_get_config_token_type "$config_name")"

    case "$token_type" in
        auth-token)
            jq -n \
                --arg config_name "$config_name" \
                --arg base_url "$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")" \
                --arg auth_token "$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN")" \
                --arg disable_telemetry "$DISABLE_TELEMETRY_DEFAULT" \
                --arg disable_nonessential_traffic "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
                '{
                    CLAUDE_ENV_CONFIG: $config_name,
                    ANTHROPIC_BASE_URL: $base_url,
                    ANTHROPIC_AUTH_TOKEN: $auth_token,
                    DISABLE_TELEMETRY: $disable_telemetry,
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $disable_nonessential_traffic
                }'
            ;;
        api-key)
            jq -n \
                --arg config_name "$config_name" \
                --arg base_url "$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")" \
                --arg api_key "$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")" \
                --arg disable_telemetry "$DISABLE_TELEMETRY_DEFAULT" \
                --arg disable_nonessential_traffic "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
                '{
                    CLAUDE_ENV_CONFIG: $config_name,
                    ANTHROPIC_BASE_URL: $base_url,
                    ANTHROPIC_API_KEY: $api_key,
                    DISABLE_TELEMETRY: $disable_telemetry,
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $disable_nonessential_traffic
                }'
            ;;
        oauth)
            jq -n \
                --arg config_name "$config_name" \
                --arg oauth_token "$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN")" \
                --arg disable_telemetry "$DISABLE_TELEMETRY_DEFAULT" \
                --arg disable_nonessential_traffic "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
                '{
                    CLAUDE_ENV_CONFIG: $config_name,
                    CLAUDE_CODE_OAUTH_TOKEN: $oauth_token,
                    DISABLE_TELEMETRY: $disable_telemetry,
                    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $disable_nonessential_traffic
                }'
            ;;
        *)
            echo "error: Unsupported token type '$token_type' in configuration '$config_name'" >&2
            return 1
            ;;
    esac
}

_clear_settings_managed_env() {
    _require_jq || return 1
    _validate_settings_file || return 1

    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
        return 0
    fi

    local managed_keys_json=""
    managed_keys_json="$(_managed_env_keys_json)" || return 1

    local tmp_file=""
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/ccenv-settings.XXXXXX") || return 1

    if ! jq --argjson managed_keys "$managed_keys_json" '
        reduce $managed_keys[] as $key (. ; del(.env[$key]))
        | if ((.env // {}) | keys | length) == 0 then del(.env) else . end
    ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file"; then
        rm -f "$tmp_file"
        echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
        return 1
    fi

    mv "$tmp_file" "$CLAUDE_SETTINGS_FILE"
    chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || true
}

_set_settings_from_config() {
    local config_name="$1"

    if [[ -z "$config_name" ]]; then
        echo "error: Please specify a configuration name" >&2
        echo "Usage: ccenv settings set <name>" >&2
        return 1
    fi

    if ! _config_exists "$config_name"; then
        echo "error: Configuration '$config_name' not found" >&2
        echo "Run 'ccenv list' to see available configurations" >&2
        return 1
    fi

    _require_jq || return 1
    _validate_settings_file || return 1
    _ensure_claude_settings_dir

    local managed_keys_json=""
    managed_keys_json="$(_managed_env_keys_json)" || return 1

    local env_json=""
    env_json="$(_build_config_env_json "$config_name")" || return 1

    local tmp_file=""
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/ccenv-settings.XXXXXX") || return 1

    if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
        if ! jq \
            --argjson managed_keys "$managed_keys_json" \
            --argjson env "$env_json" \
            '
            reduce $managed_keys[] as $key (. ; del(.env[$key]))
            | .env = ((.env // {}) + $env)
            ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file"; then
            rm -f "$tmp_file"
            echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
            return 1
        fi
    else
        if ! jq -n --argjson env "$env_json" '{ env: $env }' > "$tmp_file"; then
            rm -f "$tmp_file"
            echo "error: Failed to create $CLAUDE_SETTINGS_FILE" >&2
            return 1
        fi
    fi

    mv "$tmp_file" "$CLAUDE_SETTINGS_FILE"
    chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || true
}
