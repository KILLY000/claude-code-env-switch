# Claude Code Environment Switch Plugin
# Manage multiple Claude Code authentication configurations

# Configuration directory
export CLAUDE_ENVS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-envs"

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

# List all available configs
_list_configs() {
    _ensure_env_dir
    local configs=($(find "$CLAUDE_ENVS_DIR" -maxdepth 1 -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    echo "${configs[@]}"
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

    echo
    echo "Configuration '$config_name' saved successfully!"
}

# Use a configuration (set env vars and start claude)
_ccenv_use() {
    local config_name="$1"

    if [[ -z "$config_name" ]]; then
        echo "error: Please specify a configuration name" >&2
        echo "Usage: ccenv use <name>" >&2
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

    echo "Using configuration: $config_name ($token_type)"
    echo "Starting Claude..."
    echo

    # Run claude with environment variables (only for this command)
    if [[ "$token_type" == "auth-token" ]]; then
        ANTHROPIC_BASE_URL=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL") \
        ANTHROPIC_AUTH_TOKEN=$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN") \
        claude
    elif [[ "$token_type" == "api-key" ]]; then
        ANTHROPIC_BASE_URL=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL") \
        ANTHROPIC_API_KEY=$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY") \
        claude
    else
        CLAUDE_CODE_OAUTH_TOKEN=$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN") \
        claude
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
    echo "Use 'ccenv info <name>' for details"
    echo "Use 'ccenv use <name>' to switch"
}

# Show configuration details
_ccenv_info() {
    local config_name="$1"

    if [[ -z "$config_name" ]]; then
        echo "error: Please specify a configuration name" >&2
        echo "Usage: ccenv info <name>" >&2
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
    elif [[ "$token_type" == "api-key" ]]; then
        local base_url=$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")
        local api_key=$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")
        echo "ANTHROPIC_BASE_URL: $base_url"
        echo "ANTHROPIC_API_KEY:  $(_mask_token "$api_key")"
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
    echo "Configuration '$config_name' deleted successfully!"
}

# Show help
_ccenv_help() {
    cat <<'EOF'
Claude Code Environment Switch Plugin

Manage multiple Claude Code authentication configurations.

USAGE:
    ccenv <command> [args]

COMMANDS:
    add              Add a new configuration
    use <name>       Switch to specified configuration and start claude
    list             List all configurations (alias: ls)
    info <name>      Display configuration details
    edit <name>      Edit existing configuration
    delete <name>    Delete a configuration (aliases: del, rm)
    help             Show this help message

EXAMPLES:
    ccenv add                    # Create a new configuration
    ccenv use work               # Use the 'work' configuration
    ccenv list                   # List all configurations
    ccenv info work              # Show details of 'work' config
    ccenv edit work              # Edit the 'work' configuration
    ccenv delete work            # Delete the 'work' configuration

CONFIGURATION LOCATION:
    ~/.config/claude-envs/

EOF
}

# Interactive configuration selector (arrow keys)
_ccenv_select() {
    _ensure_env_dir

    local configs=($(_list_configs))

    if [[ ${#configs[@]} -eq 0 ]]; then
        echo "No configurations found."
        echo "Run 'ccenv add' to create one, or 'ccenv help' for more commands."
        return 0
    fi

    # Build display lines
    local display_lines=()
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

    # Restore terminal on exit
    _ccenv_restore() {
        tput cnorm 2>/dev/null
        stty echo 2>/dev/null
    }
    trap '_ccenv_restore; return 130' INT

    stty -echo
    tput civis

    # Render the menu
    _ccenv_render() {
        if [[ "$1" == "1" ]]; then
            echo "Select a configuration to start Claude:"
            echo "(↑/↓ move, Enter select, q cancel)"
            echo
        else
            tput cuu $total
        fi
        local i
        for i in $(seq 1 $total); do
            if [[ $i -eq $selected ]]; then
                printf "\e[2K  \e[7m %s \e[0m\n" "${display_lines[$i]}"
            else
                printf "\e[2K   %s\n" "${display_lines[$i]}"
            fi
        done
    }

    _ccenv_render 1

    local key
    while true; do
        read -rsk1 key
        case "$key" in
            $'\x1b')
                read -rsk2 key
                case "$key" in
                    "[A")
                        ((selected > 1)) && ((selected--)) || selected=$total
                        ;;
                    "[B")
                        ((selected < total)) && ((selected++)) || selected=1
                        ;;
                esac
                ;;
            $'\n')
                break
                ;;
            "q"|"Q")
                _ccenv_restore
                trap - INT
                echo
                echo "Cancelled"
                return 0
                ;;
        esac
        _ccenv_render 0
    done

    _ccenv_restore
    trap - INT
    echo

    _ccenv_use "${configs[$selected]}"
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
            _ccenv_use "$@"
            ;;
        list|ls)
            _ccenv_list
            ;;
        info)
            _ccenv_info "$@"
            ;;
        edit)
            _ccenv_edit "$@"
            ;;
        delete|del|rm)
            _ccenv_delete "$@"
            ;;
        help|--help|-h)
            _ccenv_help
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
