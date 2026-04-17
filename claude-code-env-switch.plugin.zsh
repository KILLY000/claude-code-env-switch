# Claude Code Environment Switch Plugin
# Manage multiple Claude Code authentication configurations

# Configuration directory
export CLAUDE_ENV_SWITCH_PLUGIN_DIR="${${(%):-%N}:A:h}"
export CLAUDE_ENVS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-envs"
export CLAUDE_ENVS_ORDER_FILE="$CLAUDE_ENVS_DIR/.order"
export CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.json"
export CLAUDE_STATUSLINE_FILE="$HOME/.claude/statusline-command.sh"

typeset -ga CLAUDE_MANAGED_ENV_KEYS=(
    CLAUDE_ENV_CONFIG
    CLAUDE_CODE_OAUTH_TOKEN
    ANTHROPIC_BASE_URL
    ANTHROPIC_AUTH_TOKEN
    ANTHROPIC_API_KEY
    CLAUDE_CODE_ATTRIBUTION_HEADER
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
)

export CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT="0"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT="1"

# ==============================================================================
# Helper Functions
# ==============================================================================

# Ensure config directory exists
_ensure_env_dir() {
    if [[ ! -d "$CLAUDE_ENVS_DIR" ]]; then
        mkdir -p "$CLAUDE_ENVS_DIR"
        chmod 700 "$CLAUDE_ENVS_DIR"
    fi
}

# Ensure order file exists; seed with existing configs if missing
_ensure_order_file() {
    _ensure_env_dir
    if [[ ! -f "$CLAUDE_ENVS_ORDER_FILE" ]]; then
        local configs=($(find "$CLAUDE_ENVS_DIR" -maxdepth 1 -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
        printf "%s\n" "${configs[@]}" > "$CLAUDE_ENVS_ORDER_FILE" 2>/dev/null
    fi
}

# Rewrite .order to contain exactly the given names, one per line
_write_order_file() {
    local names=("$@")
    printf "%s\n" "${names[@]}" > "$CLAUDE_ENVS_ORDER_FILE"
}

# Remove a single entry from .order
_remove_from_order() {
    local name="$1"
    [[ ! -f "$CLAUDE_ENVS_ORDER_FILE" ]] && return
    local tmp=()
    local line
    while IFS= read -r line; do
        [[ "$line" == "$name" ]] && continue
        [[ -z "$line" ]] && continue
        tmp+=("$line")
    done < "$CLAUDE_ENVS_ORDER_FILE"
    _write_order_file "${tmp[@]}"
}

# Append a name to .order (idempotent -- skips if already present)
_append_to_order() {
    local name="$1"
    _ensure_order_file
    if grep -qxF "$name" "$CLAUDE_ENVS_ORDER_FILE" 2>/dev/null; then
        return
    fi
    echo "$name" >> "$CLAUDE_ENVS_ORDER_FILE"
}

# List all available configs, respecting .order file
_list_configs() {
    _ensure_order_file

    # Collect all actual .conf files on disk
    local -A on_disk=()
    local f
    for f in "$CLAUDE_ENVS_DIR"/*.conf(N); do
        local name="${f:t:r}"
        on_disk[$name]=1
    done

    local result=()

    # Walk the .order file; emit only entries that still exist on disk
    if [[ -s "$CLAUDE_ENVS_ORDER_FILE" ]]; then
        local line
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if (( ${+on_disk[$line]} )); then
                result+=("$line")
                unset "on_disk[$line]"
            fi
        done < "$CLAUDE_ENVS_ORDER_FILE"
    fi

    # Append any configs found on disk but missing from .order
    local orphan
    for orphan in "${(ko)on_disk[@]}"; do
        result+=("$orphan")
        echo "$orphan" >> "$CLAUDE_ENVS_ORDER_FILE"
    done

    echo "${result[@]}"
}

# Check if config exists
_config_exists() {
    local name="$1"
    [[ -f "$CLAUDE_ENVS_DIR/$name.conf" ]]
}

# Validate config name (alphanumeric, dash, underscore)
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

# Mask token for display (show first 6 and last 4 chars)
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

# Get config value by key
_get_config_value() {
    local conf_file="$1"
    local key="$2"
    grep "^${key}=" "$conf_file" 2>/dev/null | cut -d'=' -f2-
}

# Normalize token type (backward compat: api -> auth-token)
_normalize_token_type() {
    local t="$1"
    if [[ "$t" == "api" ]]; then
        echo "auth-token"
    else
        echo "$t"
    fi
}

# Require jq for settings.json operations
_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "error: jq is required for settings and statusline commands" >&2
        return 1
    fi
}

# Ensure ~/.claude exists before writing settings.json
_ensure_claude_settings_dir() {
    local settings_dir="${CLAUDE_SETTINGS_FILE:h}"
    if [[ ! -d "$settings_dir" ]]; then
        mkdir -p "$settings_dir"
        chmod 700 "$settings_dir" 2>/dev/null || true
    fi
}

# Validate settings.json shape before reading or writing
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

_set_statusline_in_settings() {
    _require_jq || return 1
    _validate_settings_file || return 1
    _ensure_claude_settings_dir

    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/ccenv-statusline.XXXXXX") || return 1

    if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
        jq \
            --arg command_path "$CLAUDE_STATUSLINE_FILE" \
            '
            .statusLine = {
                "type": "command",
                "command": $command_path,
                "padding": 0
            }
            ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file" || {
            rm -f "$tmp_file"
            echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
            return 1
        }
    else
        jq -n \
            --arg command_path "$CLAUDE_STATUSLINE_FILE" \
            '{
                statusLine: {
                    type: "command",
                    command: $command_path,
                    padding: 0
                }
            }' > "$tmp_file" || {
            rm -f "$tmp_file"
            echo "error: Failed to create $CLAUDE_SETTINGS_FILE" >&2
            return 1
        }
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

    local tmp_file
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

# List managed auth keys currently present in ~/.claude/settings.json
_list_settings_managed_keys() {
    [[ ! -f "$CLAUDE_SETTINGS_FILE" ]] && return 0

    _validate_settings_file || return 1

    jq -r '
        .env // {}
        | keys[]?
        | select(
            . == "CLAUDE_ENV_CONFIG"
            or . == "CLAUDE_CODE_OAUTH_TOKEN"
            or . == "ANTHROPIC_BASE_URL"
            or . == "ANTHROPIC_AUTH_TOKEN"
            or . == "ANTHROPIC_API_KEY"
            or . == "CLAUDE_CODE_ATTRIBUTION_HEADER"
            or . == "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
        )
    ' "$CLAUDE_SETTINGS_FILE"
}

# Check whether ~/.claude/settings.json already contains managed auth env
_settings_has_managed_env() {
    local keys=""
    keys="$(_list_settings_managed_keys)" || return 1
    [[ -n "$keys" ]]
}

# Get env value from ~/.claude/settings.json
_get_settings_env_value() {
    local key="$1"
    [[ ! -f "$CLAUDE_SETTINGS_FILE" ]] && return 0

    _validate_settings_file || return 1

    jq -r --arg key "$key" '.env[$key] // empty' "$CLAUDE_SETTINGS_FILE"
}

# Mask settings values, except base URL which is not secret
_mask_env_value() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" ]]; then
        echo "(not set)"
    elif [[ "$key" == "CLAUDE_ENV_CONFIG" || "$key" == "ANTHROPIC_BASE_URL" || "$key" == "CLAUDE_CODE_ATTRIBUTION_HEADER" || "$key" == "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" ]]; then
        echo "$value"
    else
        _mask_token "$value"
    fi
}

# Clear managed auth env from ~/.claude/settings.json while preserving other fields
_clear_settings_managed_env() {
    _require_jq || return 1
    _validate_settings_file || return 1

    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
        return 0
    fi

    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/ccenv-settings.XXXXXX") || return 1

    if ! jq '
        del(
            .env.CLAUDE_ENV_CONFIG,
            .env.CLAUDE_CODE_OAUTH_TOKEN,
            .env.ANTHROPIC_BASE_URL,
            .env.ANTHROPIC_AUTH_TOKEN,
            .env.ANTHROPIC_API_KEY,
            .env.CLAUDE_CODE_ATTRIBUTION_HEADER,
            .env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
        )
        | if ((.env // {}) | keys | length) == 0 then del(.env) else . end
    ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file"; then
        rm -f "$tmp_file"
        echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
        return 1
    fi

    mv "$tmp_file" "$CLAUDE_SETTINGS_FILE"
    chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || true
}

# Write one configuration into ~/.claude/settings.json env after clearing managed keys
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

    local conf_file="$CLAUDE_ENVS_DIR/$config_name.conf"
    local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/ccenv-settings.XXXXXX") || return 1

    if [[ "$token_type" == "auth-token" ]]; then
        local base_url=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")
        local auth_token=$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN")
        if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
            jq \
                --arg config_name "$config_name" \
                --arg base_url "$base_url" \
                --arg auth_token "$auth_token" \
                --arg attribution_header "$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
                --arg disable_nonessential_traffic "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
                '
                del(
                    .env.CLAUDE_ENV_CONFIG,
                    .env.CLAUDE_CODE_OAUTH_TOKEN,
                    .env.ANTHROPIC_BASE_URL,
                    .env.ANTHROPIC_AUTH_TOKEN,
                    .env.ANTHROPIC_API_KEY,
                    .env.CLAUDE_CODE_ATTRIBUTION_HEADER,
                    .env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                )
                | .env = ((.env // {}) + {
                    "CLAUDE_ENV_CONFIG": $config_name,
                    "ANTHROPIC_BASE_URL": $base_url,
                    "ANTHROPIC_AUTH_TOKEN": $auth_token,
                    "CLAUDE_CODE_ATTRIBUTION_HEADER": $attribution_header,
                    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": $disable_nonessential_traffic
                })
                ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file" || {
                rm -f "$tmp_file"
                echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
                return 1
            }
        else
            jq -n \
                --arg config_name "$config_name" \
                --arg base_url "$base_url" \
                --arg auth_token "$auth_token" \
                --arg attribution_header "$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
                --arg disable_nonessential_traffic "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
                '{
                    env: {
                        CLAUDE_ENV_CONFIG: $config_name,
                        ANTHROPIC_BASE_URL: $base_url,
                        ANTHROPIC_AUTH_TOKEN: $auth_token,
                        CLAUDE_CODE_ATTRIBUTION_HEADER: $attribution_header,
                        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $disable_nonessential_traffic
                    }
                }' > "$tmp_file" || {
                rm -f "$tmp_file"
                echo "error: Failed to create $CLAUDE_SETTINGS_FILE" >&2
                return 1
            }
        fi
    elif [[ "$token_type" == "api-key" ]]; then
        local base_url=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")
        local api_key=$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")
        if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
            jq \
                --arg config_name "$config_name" \
                --arg base_url "$base_url" \
                --arg api_key "$api_key" \
                --arg attribution_header "$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
                --arg disable_nonessential_traffic "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
                '
                del(
                    .env.CLAUDE_ENV_CONFIG,
                    .env.CLAUDE_CODE_OAUTH_TOKEN,
                    .env.ANTHROPIC_BASE_URL,
                    .env.ANTHROPIC_AUTH_TOKEN,
                    .env.ANTHROPIC_API_KEY,
                    .env.CLAUDE_CODE_ATTRIBUTION_HEADER,
                    .env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                )
                | .env = ((.env // {}) + {
                    "CLAUDE_ENV_CONFIG": $config_name,
                    "ANTHROPIC_BASE_URL": $base_url,
                    "ANTHROPIC_API_KEY": $api_key,
                    "CLAUDE_CODE_ATTRIBUTION_HEADER": $attribution_header,
                    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": $disable_nonessential_traffic
                })
                ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file" || {
                rm -f "$tmp_file"
                echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
                return 1
            }
        else
            jq -n \
                --arg config_name "$config_name" \
                --arg base_url "$base_url" \
                --arg api_key "$api_key" \
                --arg attribution_header "$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
                --arg disable_nonessential_traffic "$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
                '{
                    env: {
                        CLAUDE_ENV_CONFIG: $config_name,
                        ANTHROPIC_BASE_URL: $base_url,
                        ANTHROPIC_API_KEY: $api_key,
                        CLAUDE_CODE_ATTRIBUTION_HEADER: $attribution_header,
                        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $disable_nonessential_traffic
                    }
                }' > "$tmp_file" || {
                rm -f "$tmp_file"
                echo "error: Failed to create $CLAUDE_SETTINGS_FILE" >&2
                return 1
            }
        fi
    else
        local oauth_token=$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN")
        if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
            jq \
                --arg config_name "$config_name" \
                --arg oauth_token "$oauth_token" \
                '
                del(
                    .env.CLAUDE_ENV_CONFIG,
                    .env.CLAUDE_CODE_OAUTH_TOKEN,
                    .env.ANTHROPIC_BASE_URL,
                    .env.ANTHROPIC_AUTH_TOKEN,
                    .env.ANTHROPIC_API_KEY,
                    .env.CLAUDE_CODE_ATTRIBUTION_HEADER,
                    .env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
                )
                | .env = ((.env // {}) + {
                    "CLAUDE_ENV_CONFIG": $config_name,
                    "CLAUDE_CODE_OAUTH_TOKEN": $oauth_token
                })
                ' "$CLAUDE_SETTINGS_FILE" > "$tmp_file" || {
                rm -f "$tmp_file"
                echo "error: Failed to update $CLAUDE_SETTINGS_FILE" >&2
                return 1
            }
        else
            jq -n \
                --arg config_name "$config_name" \
                --arg oauth_token "$oauth_token" \
                '{
                    env: {
                        CLAUDE_ENV_CONFIG: $config_name,
                        CLAUDE_CODE_OAUTH_TOKEN: $oauth_token
                    }
                }' > "$tmp_file" || {
                rm -f "$tmp_file"
                echo "error: Failed to create $CLAUDE_SETTINGS_FILE" >&2
                return 1
            }
        fi
    fi

    mv "$tmp_file" "$CLAUDE_SETTINGS_FILE"
    chmod 600 "$CLAUDE_SETTINGS_FILE" 2>/dev/null || true
}

# ==============================================================================
# Subcommands
# ==============================================================================

# Add a new configuration
_ccenv_add() {
    _ensure_env_dir

    echo "Adding a new Claude Code configuration"
    echo

    # Select token type
    local token_type
    echo "Select token type:"
    echo "  1) Auth Token (ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN)"
    echo "  2) API Key (ANTHROPIC_BASE_URL + ANTHROPIC_API_KEY)"
    echo "  3) OAuth (CLAUDE_CODE_OAUTH_TOKEN, obtain via 'claude setup-token')"
    echo
    read "choice?Choose (1, 2, or 3): "

    case "$choice" in
        1|auth-token)
            token_type="auth-token"
            ;;
        2|api-key)
            token_type="api-key"
            ;;
        3|oauth)
            token_type="oauth"
            ;;
        *)
            echo "error: Invalid choice" >&2
            return 1
            ;;
    esac

    echo

    # Get tokens based on type
    local base_url=""
    local auth_token=""
    local api_key=""
    local oauth_token=""

    if [[ "$token_type" == "auth-token" ]]; then
        read "base_url?Enter ANTHROPIC_BASE_URL: "
        if [[ -z "$base_url" ]]; then
            echo "error: ANTHROPIC_BASE_URL cannot be empty" >&2
            return 1
        fi

        echo -n "Enter ANTHROPIC_AUTH_TOKEN: "
        read -s auth_token
        echo
        if [[ -z "$auth_token" ]]; then
            echo "error: ANTHROPIC_AUTH_TOKEN cannot be empty" >&2
            return 1
        fi
        echo "Token: $(_mask_token "$auth_token")"
    elif [[ "$token_type" == "api-key" ]]; then
        read "base_url?Enter ANTHROPIC_BASE_URL: "
        if [[ -z "$base_url" ]]; then
            echo "error: ANTHROPIC_BASE_URL cannot be empty" >&2
            return 1
        fi

        echo -n "Enter ANTHROPIC_API_KEY: "
        read -s api_key
        echo
        if [[ -z "$api_key" ]]; then
            echo "error: ANTHROPIC_API_KEY cannot be empty" >&2
            return 1
        fi
        echo "Token: $(_mask_token "$api_key")"
    else
        echo -n "Enter CLAUDE_CODE_OAUTH_TOKEN: "
        read -s oauth_token
        echo
        if [[ -z "$oauth_token" ]]; then
            echo "error: CLAUDE_CODE_OAUTH_TOKEN cannot be empty" >&2
            return 1
        fi
        echo "Token: $(_mask_token "$oauth_token")"
    fi

    echo

    # Get config name
    local config_name
    read "config_name?Enter configuration name: "

    if ! _validate_config_name "$config_name"; then
        return 1
    fi

    if _config_exists "$config_name"; then
        read "overwrite?Config '$config_name' already exists. Overwrite? (y/N): "
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo "Aborted"
            return 0
        fi
    fi

    # Get description (optional)
    local description=""
    read "description?Enter description (optional, press Enter to skip): "

    # Save configuration
    local conf_file="$CLAUDE_ENVS_DIR/$config_name.conf"
    {
        echo "TYPE=$token_type"
        echo "DESCRIPTION=$description"
        if [[ "$token_type" == "auth-token" ]]; then
            echo "ANTHROPIC_BASE_URL=$base_url"
            echo "ANTHROPIC_AUTH_TOKEN=$auth_token"
        elif [[ "$token_type" == "api-key" ]]; then
            echo "ANTHROPIC_BASE_URL=$base_url"
            echo "ANTHROPIC_API_KEY=$api_key"
        else
            echo "CLAUDE_CODE_OAUTH_TOKEN=$oauth_token"
        fi
    } > "$conf_file"

    chmod 600 "$conf_file"
    _append_to_order "$config_name"

    echo
    echo "Configuration '$config_name' saved successfully!"
}

# Manage ~/.claude/settings.json env
_ccenv_settings_help() {
    cat <<'EOF'
Manage Claude auth env in ~/.claude/settings.json

USAGE:
    ccenv settings
    ccenv settings view
    ccenv settings clear
    ccenv settings set <name>
    ccenv settings apply <name>

COMMANDS:
    view           Show managed auth env currently stored in settings.json
    clear          Remove managed auth env from settings.json
    set <name>     Clear then write config <name> into settings.json env
    apply <name>   Alias for set
    help           Show this help message
EOF
}

_ccenv_settings_view() {
    echo "Settings file: $CLAUDE_SETTINGS_FILE"

    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
        echo "Status: not found"
        return 0
    fi

    _validate_settings_file || return 1

    local keys=""
    keys="$(_list_settings_managed_keys)" || return 1

    if [[ -z "$keys" ]]; then
        echo "Status: no managed auth env found"
        return 0
    fi

    echo "Status: managed auth env present"
    echo

    local key=""
    for key in "${CLAUDE_MANAGED_ENV_KEYS[@]}"; do
        local value=""
        value=$(_get_settings_env_value "$key") || return 1
        [[ -z "$value" ]] && continue
        echo "$key: $(_mask_env_value "$key" "$value")"
    done
}

_ccenv_settings_clear() {
    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
        echo "No settings file found at $CLAUDE_SETTINGS_FILE"
        return 0
    fi

    local keys=""
    keys="$(_list_settings_managed_keys)" || return 1

    if [[ -z "$keys" ]]; then
        echo "No managed auth env found in $CLAUDE_SETTINGS_FILE"
        return 0
    fi

    _clear_settings_managed_env || return 1
    echo "Cleared managed auth env from $CLAUDE_SETTINGS_FILE"
}

_ccenv_settings_set() {
    local config_name="$1"
    local existing_keys=""

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

    existing_keys="$(_list_settings_managed_keys)" || return 1

    if [[ -n "$existing_keys" ]]; then
        echo "Found existing managed auth env in $CLAUDE_SETTINGS_FILE"
        echo "Clearing existing managed auth env before applying '$config_name'..."
        _clear_settings_managed_env || return 1
    fi

    _set_settings_from_config "$config_name" || return 1

    echo "Applied configuration '$config_name' to $CLAUDE_SETTINGS_FILE"
    echo "Run 'ccenv settings view' to verify"
}

_ccenv_settings() {
    local subcommand="$1"
    shift 2>/dev/null || true

    case "$subcommand" in
        ""|view|show|status)
            _ccenv_settings_view
            ;;
        clear)
            _ccenv_settings_clear
            ;;
        set|apply)
            _ccenv_settings_set "$@"
            ;;
        help|--help|-h)
            _ccenv_settings_help
            ;;
        *)
            echo "error: Unknown settings subcommand '$subcommand'" >&2
            echo "Run 'ccenv settings help' for usage information" >&2
            return 1
            ;;
    esac
}

# Manage Claude Code status line command in ~/.claude
_ccenv_statusline_help() {
    cat <<'EOF'
Manage Claude Code status line command in ~/.claude

USAGE:
    ccenv statusline
    ccenv statusline status
    ccenv statusline install
    ccenv statusline clear
    ccenv statusline uninstall

COMMANDS:
    status        Show current statusline script and settings.json statusLine config
    install       Copy statusline.sh to ~/.claude/statusline-command.sh and configure settings.json
    clear         Remove statusLine from settings.json and delete ~/.claude/statusline-command.sh
    uninstall     Alias for clear
    help          Show this help message
EOF
}

_ccenv_statusline_status() {
    echo "Settings file: $CLAUDE_SETTINGS_FILE"
    echo "Statusline file: $CLAUDE_STATUSLINE_FILE"

    if [[ -f "$CLAUDE_STATUSLINE_FILE" ]]; then
        echo "Script: installed"
    else
        echo "Script: not installed"
    fi

    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
        echo "Settings: not found"
        return 0
    fi

    _validate_settings_file || return 1

    local type=""
    local command=""
    local padding=""
    type=$(_get_statusline_settings_value "type") || return 1
    command=$(_get_statusline_settings_value "command") || return 1
    padding=$(_get_statusline_settings_value "padding") || return 1

    if [[ -z "$type" && -z "$command" && -z "$padding" ]]; then
        echo "Settings: statusLine not configured"
        return 0
    fi

    echo "Settings: statusLine configured"
    [[ -n "$type" ]] && echo "type: $type"
    [[ -n "$command" ]] && echo "command: $command"
    [[ -n "$padding" ]] && echo "padding: $padding"
}

_ccenv_statusline_install() {
    _install_statusline_script || return 1
    _set_statusline_in_settings || return 1

    echo "Installed statusline script to $CLAUDE_STATUSLINE_FILE"
    echo "Configured statusLine in $CLAUDE_SETTINGS_FILE"
}

_ccenv_statusline_clear() {
    local removed_file=0
    local cleared_settings=0

    if [[ -f "$CLAUDE_SETTINGS_FILE" ]]; then
        local type=""
        local command=""
        type=$(_get_statusline_settings_value "type") || return 1
        command=$(_get_statusline_settings_value "command") || return 1
        if [[ -n "$type" || -n "$command" ]]; then
            _clear_statusline_in_settings || return 1
            cleared_settings=1
        fi
    fi

    if [[ -f "$CLAUDE_STATUSLINE_FILE" ]]; then
        rm -f "$CLAUDE_STATUSLINE_FILE" || {
            echo "error: Failed to remove $CLAUDE_STATUSLINE_FILE" >&2
            return 1
        }
        removed_file=1
    fi

    if (( cleared_settings )); then
        echo "Cleared statusLine from $CLAUDE_SETTINGS_FILE"
    else
        echo "No statusLine config found in $CLAUDE_SETTINGS_FILE"
    fi

    if (( removed_file )); then
        echo "Removed $CLAUDE_STATUSLINE_FILE"
    else
        echo "No statusline file found at $CLAUDE_STATUSLINE_FILE"
    fi
}

_ccenv_statusline() {
    local subcommand="$1"
    shift 2>/dev/null || true

    case "$subcommand" in
        ""|status|view|show)
            _ccenv_statusline_status
            ;;
        install|setup)
            _ccenv_statusline_install
            ;;
        clear|remove|rm|uninstall)
            _ccenv_statusline_clear
            ;;
        help|--help|-h)
            _ccenv_statusline_help
            ;;
        *)
            echo "error: Unknown statusline subcommand '$subcommand'" >&2
            echo "Run 'ccenv statusline help' for usage information" >&2
            return 1
            ;;
    esac
}

# Use a configuration (set env vars and start claude)
# Usage: _ccenv_use <config_name> [extra args for claude...]
_ccenv_use() {
    local config_name="$1"
    shift

    if [[ -z "$config_name" ]]; then
        echo "error: Please specify a configuration name" >&2
        echo "Usage: ccenv use <name> [-- <args>]" >&2
        echo "Run 'ccenv list' to see available configurations" >&2
        return 1
    fi

    if ! _config_exists "$config_name"; then
        echo "error: Configuration '$config_name' not found" >&2
        echo "Run 'ccenv list' to see available configurations" >&2
        return 1
    fi

    local conf_file="$CLAUDE_ENVS_DIR/$config_name.conf"
    local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
    local settings_keys=""

    settings_keys="$(_list_settings_managed_keys)" || return 1
    if [[ -n "$settings_keys" ]]; then
        echo "error: Managed Claude auth env already exists in $CLAUDE_SETTINGS_FILE" >&2
        echo "Clear it first with: ccenv settings clear" >&2
        echo "Found keys:" >&2
        local key=""
        while IFS= read -r key; do
            [[ -n "$key" ]] && echo "  - $key" >&2
        done <<< "$settings_keys"
        return 1
    fi

    echo "Using configuration: $config_name ($token_type)"
    if [[ $# -gt 0 ]]; then
        echo "Extra args: $*"
    fi
    echo "Starting Claude..."
    echo

    # Run claude with environment variables (only for this command)
    if [[ "$token_type" == "auth-token" ]]; then
        CLAUDE_ENV_CONFIG="$config_name" \
        ANTHROPIC_BASE_URL=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL") \
        ANTHROPIC_AUTH_TOKEN=$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN") \
        CLAUDE_CODE_ATTRIBUTION_HEADER="$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
        claude "$@"
    elif [[ "$token_type" == "api-key" ]]; then
        CLAUDE_ENV_CONFIG="$config_name" \
        ANTHROPIC_BASE_URL=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL") \
        ANTHROPIC_API_KEY=$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY") \
        CLAUDE_CODE_ATTRIBUTION_HEADER="$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
        claude "$@"
    else
        CLAUDE_ENV_CONFIG="$config_name" \
        CLAUDE_CODE_OAUTH_TOKEN=$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN") \
        claude "$@"
    fi
}

# List all configurations
_ccenv_list() {
    _ensure_env_dir

    local configs=($(_list_configs))

    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No configurations found."
        echo "Run 'ccenv add' to create one."
        return 0
    fi

    echo "Available configurations:"
    echo
    for conf in "${configs[@]}"; do
        local conf_file="$CLAUDE_ENVS_DIR/$conf.conf"
        local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
        local description=$(_get_config_value "$conf_file" "DESCRIPTION")
        local desc_display=""
        if [[ -n "$description" ]]; then
            desc_display=" - $description"
        fi
        echo "  - $conf ($token_type)$desc_display"
    done
    echo
    echo "Use 'ccenv view <name>' for details"
    echo "Use 'ccenv use <name>' to switch"
}

# Show configuration details
_ccenv_view() {
    local config_name="$1"

    if [[ -z "$config_name" ]]; then
        echo "error: Please specify a configuration name" >&2
        echo "Usage: ccenv view <name>" >&2
        return 1
    fi

    if ! _config_exists "$config_name"; then
        echo "error: Configuration '$config_name' not found" >&2
        return 1
    fi

    local conf_file="$CLAUDE_ENVS_DIR/$config_name.conf"
    local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
    local description=$(_get_config_value "$conf_file" "DESCRIPTION")

    echo "Configuration: $config_name"
    echo "Type: $token_type"
    if [[ -n "$description" ]]; then
        echo "Description: $description"
    fi
    echo

    if [[ "$token_type" == "auth-token" ]]; then
        local base_url=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")
        local auth_token=$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN")
        echo "ANTHROPIC_BASE_URL:    $base_url"
        echo "ANTHROPIC_AUTH_TOKEN:  $(_mask_token "$auth_token")"
        echo "CLAUDE_CODE_ATTRIBUTION_HEADER: $CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT"
        echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT"
    elif [[ "$token_type" == "api-key" ]]; then
        local base_url=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")
        local api_key=$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")
        echo "ANTHROPIC_BASE_URL: $base_url"
        echo "ANTHROPIC_API_KEY:  $(_mask_token "$api_key")"
        echo "CLAUDE_CODE_ATTRIBUTION_HEADER: $CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT"
        echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT"
    else
        local oauth_token=$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN")
        echo "CLAUDE_CODE_OAUTH_TOKEN: $(_mask_token "$oauth_token")"
    fi
}

# Edit a configuration
_ccenv_edit() {
    local config_name="$1"

    if [[ -z "$config_name" ]]; then
        echo "error: Please specify a configuration name" >&2
        echo "Usage: ccenv edit <name>" >&2
        return 1
    fi

    if ! _config_exists "$config_name"; then
        echo "error: Configuration '$config_name' not found" >&2
        return 1
    fi

    local conf_file="$CLAUDE_ENVS_DIR/$config_name.conf"
    local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
    local current_description=$(_get_config_value "$conf_file" "DESCRIPTION")

    echo "Editing configuration: $config_name ($token_type)"
    echo "Press Enter to keep current value"
    echo

    local new_base_url=""
    local new_auth_token=""
    local new_api_key=""
    local new_oauth_token=""
    local new_description=""
    local current_base_url=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")
    local current_auth_token=$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN")
    local current_api_key=$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")
    local current_oauth_token=$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN")

    read "new_description?Description [$current_description]: "

    if [[ "$token_type" == "auth-token" ]]; then
        read "new_base_url?ANTHROPIC_BASE_URL [$current_base_url]: "
        echo -n "ANTHROPIC_AUTH_TOKEN [$(_mask_token "$current_auth_token")]: "
        read -s new_auth_token
        echo
        if [[ -n "$new_auth_token" ]]; then
            echo "New token: $(_mask_token "$new_auth_token")"
        fi
    elif [[ "$token_type" == "api-key" ]]; then
        read "new_base_url?ANTHROPIC_BASE_URL [$current_base_url]: "
        echo -n "ANTHROPIC_API_KEY [$(_mask_token "$current_api_key")]: "
        read -s new_api_key
        echo
        if [[ -n "$new_api_key" ]]; then
            echo "New token: $(_mask_token "$new_api_key")"
        fi
    else
        echo -n "CLAUDE_CODE_OAUTH_TOKEN [$(_mask_token "$current_oauth_token")]: "
        read -s new_oauth_token
        echo
        if [[ -n "$new_oauth_token" ]]; then
            echo "New token: $(_mask_token "$new_oauth_token")"
        fi
    fi

    echo
    {
        echo "TYPE=$token_type"
        echo "DESCRIPTION=${new_description:-$current_description}"
        if [[ "$token_type" == "auth-token" ]]; then
            echo "ANTHROPIC_BASE_URL=${new_base_url:-$current_base_url}"
            echo "ANTHROPIC_AUTH_TOKEN=${new_auth_token:-$current_auth_token}"
        elif [[ "$token_type" == "api-key" ]]; then
            echo "ANTHROPIC_BASE_URL=${new_base_url:-$current_base_url}"
            echo "ANTHROPIC_API_KEY=${new_api_key:-$current_api_key}"
        else
            echo "CLAUDE_CODE_OAUTH_TOKEN=${new_oauth_token:-$current_oauth_token}"
        fi
    } > "$conf_file"

    echo "Configuration '$config_name' updated successfully!"
}

# Delete a configuration
_ccenv_delete() {
    local config_name="$1"

    if [[ -z "$config_name" ]]; then
        echo "error: Please specify a configuration name" >&2
        echo "Usage: ccenv delete <name>" >&2
        return 1
    fi

    if ! _config_exists "$config_name"; then
        echo "error: Configuration '$config_name' not found" >&2
        return 1
    fi

    local conf_file="$CLAUDE_ENVS_DIR/$config_name.conf"
    local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
    local description=$(_get_config_value "$conf_file" "DESCRIPTION")

    echo "Configuration: $config_name"
    echo "Type: $token_type"
    if [[ -n "$description" ]]; then
        echo "Description: $description"
    fi
    echo

    read "confirm?Are you sure you want to delete this configuration? (y/N): "
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted"
        return 0
    fi

    rm -f "$conf_file"
    _remove_from_order "$config_name"
    echo "Configuration '$config_name' deleted successfully!"
}

# Show help
_ccenv_help() {
    cat <<'EOF'
Claude Code Environment Switch Plugin

Manage multiple Claude Code authentication configurations.

USAGE:
    ccenv <command> [args]
    ccenv [-- <claude args>]

COMMANDS:
    add              Add a new configuration
    use <name>       Switch to specified configuration and start claude
                     Use -- to pass extra args: ccenv use <name> -- <args>
    list             List all configurations (alias: ls)
    settings         Manage auth env in ~/.claude/settings.json
    statusline       Install/manage Claude Code status line command
    view <name>      Display configuration details (alias: info)
    edit <name>      Edit existing configuration
    delete <name>    Delete a configuration (aliases: del, rm)
    reorder          Reorder configurations interactively (alias: order)
    help             Show this help message

INTERACTIVE MODE:
    ccenv                        # Start interactive selector
    ccenv -- <args>              # Start interactive selector with preset claude args
    In interactive mode, press 's' to set/modify claude startup args.
    Press 'w' to write the selected config into ~/.claude/settings.json.

EXAMPLES:
    ccenv add                    # Create a new configuration
    ccenv settings view          # Show managed auth env in settings.json
    ccenv settings clear         # Clear managed auth env in settings.json
    ccenv settings set work      # Write config 'work' into settings.json env
    ccenv statusline install     # Install ~/.claude/statusline-command.sh and configure settings.json
    ccenv statusline status      # Show current statusline installation state
    ccenv use work               # Use the 'work' configuration
    ccenv use work -- --verbose  # Use 'work' config, pass --verbose to claude
    ccenv list                   # List all configurations
    ccenv view work              # Show details of 'work' config
    ccenv edit work              # Edit the 'work' configuration
    ccenv delete work            # Delete the 'work' configuration
    ccenv reorder                # Reorder configurations with arrow keys
    ccenv -- --model opus        # Interactive mode with preset args

CONFIGURATION LOCATION:
    ~/.config/claude-envs/

EOF
}

# Interactive configuration selector (arrow keys)
# Usage: _ccenv_select [extra args for claude...]
_ccenv_select() {
    _ensure_env_dir

    local selected=1
    local claude_args=("$@")

    while true; do
        clear  # Clean interface after each action

        # Reload configs each iteration (handles add/edit/delete)
        local configs=($(_list_configs))

        # Handle empty state - minimal UI
        if [[ ${#configs[@]} -eq 0 ]]; then
            echo "No configurations found."
            echo "(a: add, q: quit)"
            echo
            local key
            while true; do
                read -rsk1 key
                case "$key" in
                    "a"|"A")
                        _ccenv_add
                        break  # Re-enter outer loop to show new config
                        ;;
                    "q"|"Q")
                        return 0
                        ;;
                esac
            done
            continue
        fi

        # Build display lines
        local display_lines=()
        for conf in "${configs[@]}"; do
            local conf_file="$CLAUDE_ENVS_DIR/$conf.conf"
            local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
            local description=$(_get_config_value "$conf_file" "DESCRIPTION")
            local desc_display=""
            [[ -n "$description" ]] && desc_display=" - $description"
            display_lines+=("$conf ($token_type)$desc_display")
        done

        # Clamp selected index if config was deleted
        local total=${#configs[@]}
        ((selected > total)) && selected=$total
        ((selected < 1)) && selected=1

        # Calculate list start row (dynamic based on terminal width and args)
        # Row 0: "Claude Code Environment Switch"
        # Row 1: "Manage multiple authentication configurations"
        # Row 2: (blank)
        # Row 3: "Configurations:"
        # Row 4+: "(shortcuts...)" - may wrap to multiple lines if terminal is narrow
        # Next: "Args: ..." (only if claude_args is non-empty)
        # Next: (blank)
        # Next: first config item
        local has_args=0
        [[ ${#claude_args[@]} -gt 0 ]] && has_args=1

        local shortcuts_line="(↑/↓:move  Enter:start  a:add  e:edit  d:delete  v:view  o:reorder  w:settings  s:args  q:quit)"
        local term_width=$(tput cols)
        local shortcuts_len=${#shortcuts_line}
        local shortcuts_rows=$(( (shortcuts_len + term_width - 1) / term_width ))
        local list_start_row=$((5 + shortcuts_rows + has_args))

        # Terminal setup
        _ccenv_restore() {
            tput cnorm 2>/dev/null
            stty echo 2>/dev/null
        }
        trap '_ccenv_restore; return 130' INT
        stty -echo
        tput civis

        # Render function
        _ccenv_render() {
            if [[ "$1" == "1" ]]; then
                echo "Claude Code Environment Switch"
                echo "Manage multiple authentication configurations"
                echo
                echo "Configurations:"
                echo "$shortcuts_line"
                if [[ $has_args -eq 1 ]]; then
                    echo "Args: ${claude_args[*]}"
                fi
                echo
            else
                tput cup $list_start_row 0
            fi
            for i in $(seq 1 $total); do
                if [[ $i -eq $selected ]]; then
                    printf "\e[2K  \e[7m %s \e[0m\n" "${display_lines[$i]}"
                else
                    printf "\e[2K   %s\n" "${display_lines[$i]}"
                fi
            done
        }

        _ccenv_render 1

        local action=""
        local key=""
        while true; do
            read -rsk1 key
            case "$key" in
                $'\x1b')
                    read -rsk2 key
                    case "$key" in
                        "[A") ((selected > 1)) && ((selected--)) || selected=$total ;;
                        "[B") ((selected < total)) && ((selected++)) || selected=1 ;;
                    esac
                    ;;
                $'\n')
                    action="use"
                    break
                    ;;
                "a"|"A")
                    action="add"
                    break
                    ;;
                "e"|"E")
                    action="edit"
                    break
                    ;;
                "d"|"D")
                    action="delete"
                    break
                    ;;
                "v"|"V")
                    action="view"
                    break
                    ;;
                "o"|"O")
                    action="reorder"
                    break
                    ;;
                "w"|"W")
                    action="settings"
                    break
                    ;;
                "s"|"S")
                    action="args"
                    break
                    ;;
                "q"|"Q")
                    action="quit"
                    break
                    ;;
            esac
            _ccenv_render 0
        done

        # Restore terminal before running action
        _ccenv_restore
        trap - INT

        # Execute action
        case "$action" in
            "use")
                clear
                _ccenv_use "${configs[$selected]}" "${claude_args[@]}"
                return $?
                ;;
            "add")
                clear
                _ccenv_add
                ;;
            "edit")
                clear
                _ccenv_edit "${configs[$selected]}"
                ;;
            "delete")
                clear
                _ccenv_delete "${configs[$selected]}"
                ;;
            "view")
                clear
                _ccenv_view "${configs[$selected]}"
                echo
                echo "(Press any key to return)"
                read -rsk1
                # 清空输入缓冲区（处理方向键等多字符序列）
                read -rsk -t 0.01 2>/dev/null || true
                ;;
            "reorder")
                clear
                _ccenv_reorder
                ;;
            "settings")
                clear
                local settings_status=0
                _ccenv_settings_set "${configs[$selected]}"
                settings_status=$?
                echo
                echo "(Press any key to exit)"
                read -rsk1
                read -rsk -t 0.01 2>/dev/null || true
                return $settings_status
                ;;
            "args")
                clear
                echo "Current args: ${claude_args[*]:-(none)}"
                echo
                echo "Enter new args for claude (space-separated, empty to clear):"
                local new_args_str
                read "new_args_str?"
                if [[ -z "$new_args_str" ]]; then
                    claude_args=()
                else
                    claude_args=(${=new_args_str})
                fi
                ;;
            "quit")
                return 0
                ;;
        esac
    done
}

# Interactive reorder: arrow-key UI to rearrange config order
_ccenv_reorder() {
    _ensure_order_file

    local configs=($(_list_configs))

    if [[ ${#configs[@]} -le 1 ]]; then
        echo "Need at least 2 configurations to reorder."
        return 0
    fi

    # Build display lines
    local -a display_lines
    local conf
    for conf in "${configs[@]}"; do
        local conf_file="$CLAUDE_ENVS_DIR/$conf.conf"
        local token_type=$(_normalize_token_type "$(_get_config_value "$conf_file" "TYPE")")
        local description=$(_get_config_value "$conf_file" "DESCRIPTION")
        local desc_display=""
        if [[ -n "$description" ]]; then
            desc_display=" - $description"
        fi
        display_lines+=("$conf ($token_type)$desc_display")
    done

    local selected=1
    local total=${#configs[@]}
    local changed=0

    # Restore terminal on exit
    _ccenv_restore() {
        tput cnorm 2>/dev/null
        stty echo 2>/dev/null
    }
    trap '_ccenv_restore; return 130' INT

    stty -echo
    tput civis

    # Render the menu
    _ccenv_reorder_render() {
        if [[ "$1" == "1" ]]; then
            echo "Reorder configurations:"
            echo "(↑/↓ move cursor, u/d move item up/down, Enter save, q cancel)"
            echo
        else
            # 使用绝对定位移动到第 4 行（配置列表起始位置）
            tput cup 3 0
        fi
        local i
        for i in $(seq 1 $total); do
            if [[ $i -eq $selected ]]; then
                printf "\e[2K  \e[7m %d. %s \e[0m\n" "$i" "${display_lines[$i]}"
            else
                printf "\e[2K   %d. %s\n" "$i" "${display_lines[$i]}"
            fi
        done
    }

    _ccenv_reorder_render 1

    local key=""
    while true; do
        read -rsk1 key
        case "$key" in
            $'\x1b')
                read -rsk2 key
                case "$key" in
                    "[A")   # Up arrow -- move cursor
                        ((selected > 1)) && ((selected--)) || selected=$total
                        ;;
                    "[B")   # Down arrow -- move cursor
                        ((selected < total)) && ((selected++)) || selected=1
                        ;;
                esac
                ;;
            "u"|"U"|"k"|"K")   # Move item UP
                if ((selected > 1)); then
                    local prev=$((selected - 1))
                    # Swap in configs array
                    local tmp="${configs[$selected]}"
                    configs[$selected]="${configs[$prev]}"
                    configs[$prev]="$tmp"
                    # Swap in display_lines array
                    tmp="${display_lines[$selected]}"
                    display_lines[$selected]="${display_lines[$prev]}"
                    display_lines[$prev]="$tmp"
                    ((selected--))
                    changed=1
                fi
                ;;
            "d"|"D"|"j"|"J")   # Move item DOWN
                if ((selected < total)); then
                    local next=$((selected + 1))
                    # Swap in configs array
                    local tmp="${configs[$selected]}"
                    configs[$selected]="${configs[$next]}"
                    configs[$next]="$tmp"
                    # Swap in display_lines array
                    tmp="${display_lines[$selected]}"
                    display_lines[$selected]="${display_lines[$next]}"
                    display_lines[$next]="$tmp"
                    ((selected++))
                    changed=1
                fi
                ;;
            $'\n')   # Enter -- save and exit
                break
                ;;
            "q"|"Q")   # Cancel
                _ccenv_restore
                trap - INT
                echo
                echo "Cancelled, order unchanged."
                return 0
                ;;
        esac
        _ccenv_reorder_render 0
    done

    _ccenv_restore
    trap - INT
    echo

    if ((changed)); then
        _write_order_file "${configs[@]}"
        echo "Order saved successfully!"
    else
        echo "No changes made."
    fi
}

# ==============================================================================
# Main Function
# ==============================================================================

ccenv() {
    local command="$1"
    shift 2>/dev/null || true

    case "$command" in
        add)
            _ccenv_add
            ;;
        use)
            # Parse: ccenv use <name> [-- <extra args>]
            local config_name="$1"
            shift 2>/dev/null || true
            local extra_args=()
            local found_sep=0
            for arg in "$@"; do
                if [[ "$found_sep" -eq 1 ]]; then
                    extra_args+=("$arg")
                elif [[ "$arg" == "--" ]]; then
                    found_sep=1
                fi
            done
            _ccenv_use "$config_name" "${extra_args[@]}"
            ;;
        list|ls)
            _ccenv_list
            ;;
        settings)
            _ccenv_settings "$@"
            ;;
        statusline)
            _ccenv_statusline "$@"
            ;;
        view|info)
            _ccenv_view "$@"
            ;;
        edit)
            _ccenv_edit "$@"
            ;;
        delete|del|rm)
            _ccenv_delete "$@"
            ;;
        reorder|order)
            _ccenv_reorder
            ;;
        help|--help|-h)
            _ccenv_help
            ;;
        --)
            # ccenv -- <extra args> → interactive mode with preset args
            _ccenv_select "$@"
            ;;
        "")
            _ccenv_select
            ;;
        *)
            echo "error: Unknown command '$command'" >&2
            echo "Run 'ccenv help' for usage information" >&2
            return 1
            ;;
    esac
}

# Tab completion for ccenv
_ccenv_completion() {
    local -a subcommands
    subcommands=(
        'add:Add a new configuration'
        'use:Switch to specified configuration and start claude'
        'list:List all configurations'
        'ls:List all configurations'
        'settings:Manage auth env in ~/.claude/settings.json'
        'statusline:Install/manage Claude Code status line command'
        'view:Display configuration details'
        'info:Display configuration details'
        'edit:Edit existing configuration'
        'delete:Delete a configuration'
        'del:Delete a configuration'
        'rm:Delete a configuration'
        'reorder:Reorder configurations interactively'
        'order:Reorder configurations interactively'
        'help:Show help message'
    )

    if (( CURRENT == 2 )); then
        _describe 'command' subcommands
    elif (( CURRENT == 3 )); then
        case "${words[2]}" in
            settings)
                local -a settings_subcommands
                settings_subcommands=(
                    'view:Show managed auth env in settings.json'
                    'show:Show managed auth env in settings.json'
                    'status:Show managed auth env in settings.json'
                    'clear:Clear managed auth env from settings.json'
                    'set:Write one config into settings.json env'
                    'apply:Write one config into settings.json env'
                    'help:Show settings help'
                )
                _describe 'settings-command' settings_subcommands
                ;;
            statusline)
                local -a statusline_subcommands
                statusline_subcommands=(
                    'status:Show current statusline installation state'
                    'view:Show current statusline installation state'
                    'show:Show current statusline installation state'
                    'install:Install statusline script and configure settings.json'
                    'setup:Install statusline script and configure settings.json'
                    'clear:Remove statusline config and installed script'
                    'remove:Remove statusline config and installed script'
                    'rm:Remove statusline config and installed script'
                    'uninstall:Remove statusline config and installed script'
                    'help:Show statusline help'
                )
                _describe 'statusline-command' statusline_subcommands
                ;;
            use|view|info|edit|delete|del|rm)
                local configs=($(_list_configs))
                _describe 'config' configs
                ;;
        esac
    elif (( CURRENT == 4 )); then
        case "${words[2]}:${words[3]}" in
            settings:set|settings:apply)
                local configs=($(_list_configs))
                _describe 'config' configs
                ;;
        esac
    fi
}

compdef _ccenv_completion ccenv
