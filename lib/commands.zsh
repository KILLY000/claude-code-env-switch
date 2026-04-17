_ccenv_add() {
    _ensure_env_dir

    echo "Adding a new Claude Code configuration"
    echo

    local token_type=""
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

    local config_name=""
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

    local description=""
    read "description?Enter description (optional, press Enter to skip): "

    local conf_file="$(_config_file_path "$config_name")"
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
    local value=""
    for key in "${CLAUDE_MANAGED_ENV_KEYS[@]}"; do
        value="$(_get_settings_env_value "$key")" || return 1
        [[ -z "$value" ]] && continue
        echo "$key: $(_mask_env_value "$key" "$value")"
    done
}

_ccenv_settings_clear() {
    if [[ ! -f "$CLAUDE_SETTINGS_FILE" ]]; then
        echo "No settings file found at $CLAUDE_SETTINGS_FILE"
        return 0
    fi

    if ! _settings_has_managed_env; then
        echo "No managed auth env found in $CLAUDE_SETTINGS_FILE"
        return 0
    fi

    _clear_settings_managed_env || return 1
    echo "Cleared managed auth env from $CLAUDE_SETTINGS_FILE"
}

_ccenv_settings_set() {
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

    if _settings_has_managed_env; then
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
    type="$(_get_statusline_settings_value "type")" || return 1
    command="$(_get_statusline_settings_value "command")" || return 1
    padding="$(_get_statusline_settings_value "padding")" || return 1

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
        type="$(_get_statusline_settings_value "type")" || return 1
        command="$(_get_statusline_settings_value "command")" || return 1
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

    local conf_file="$(_config_file_path "$config_name")"
    local token_type="$(_get_config_token_type "$config_name")"
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

    if [[ "$token_type" == "auth-token" ]]; then
        CLAUDE_ENV_CONFIG="$config_name" \
        ANTHROPIC_BASE_URL="$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")" \
        ANTHROPIC_AUTH_TOKEN="$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN")" \
        CLAUDE_CODE_ATTRIBUTION_HEADER="$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
        claude "$@"
    elif [[ "$token_type" == "api-key" ]]; then
        CLAUDE_ENV_CONFIG="$config_name" \
        ANTHROPIC_BASE_URL="$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")" \
        ANTHROPIC_API_KEY="$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")" \
        CLAUDE_CODE_ATTRIBUTION_HEADER="$CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT" \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT" \
        claude "$@"
    else
        CLAUDE_ENV_CONFIG="$config_name" \
        CLAUDE_CODE_OAUTH_TOKEN="$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN")" \
        claude "$@"
    fi
}

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

    local conf=""
    for conf in "${configs[@]}"; do
        echo "  - $(_get_config_display_line "$conf")"
    done

    echo
    echo "Use 'ccenv view <name>' for details"
    echo "Use 'ccenv use <name>' to switch"
}

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

    local conf_file="$(_config_file_path "$config_name")"
    local token_type="$(_get_config_token_type "$config_name")"
    local description="$(_get_config_description "$config_name")"

    echo "Configuration: $config_name"
    echo "Type: $token_type"
    if [[ -n "$description" ]]; then
        echo "Description: $description"
    fi
    echo

    if [[ "$token_type" == "auth-token" ]]; then
        echo "ANTHROPIC_BASE_URL:    $(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")"
        echo "ANTHROPIC_AUTH_TOKEN:  $(_mask_token "$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN")")"
        echo "CLAUDE_CODE_ATTRIBUTION_HEADER: $CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT"
        echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT"
    elif [[ "$token_type" == "api-key" ]]; then
        echo "ANTHROPIC_BASE_URL: $(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")"
        echo "ANTHROPIC_API_KEY:  $(_mask_token "$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")")"
        echo "CLAUDE_CODE_ATTRIBUTION_HEADER: $CLAUDE_CODE_ATTRIBUTION_HEADER_DEFAULT"
        echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: $CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC_DEFAULT"
    else
        echo "CLAUDE_CODE_OAUTH_TOKEN: $(_mask_token "$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN")")"
    fi
}

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

    local conf_file="$(_config_file_path "$config_name")"
    local token_type="$(_get_config_token_type "$config_name")"
    local current_description="$(_get_config_description "$config_name")"

    echo "Editing configuration: $config_name ($token_type)"
    echo "Press Enter to keep current value"
    echo

    local new_base_url=""
    local new_auth_token=""
    local new_api_key=""
    local new_oauth_token=""
    local current_base_url="$(_get_config_value "$conf_file" "ANTHROPIC_BASE_URL")"
    local current_auth_token="$(_get_config_value "$conf_file" "ANTHROPIC_AUTH_TOKEN")"
    local current_api_key="$(_get_config_value "$conf_file" "ANTHROPIC_API_KEY")"
    local current_oauth_token="$(_get_config_value "$conf_file" "CLAUDE_CODE_OAUTH_TOKEN")"

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

    local token_type="$(_get_config_token_type "$config_name")"
    local description="$(_get_config_description "$config_name")"

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

    rm -f "$(_config_file_path "$config_name")"
    _remove_from_order "$config_name"
    echo "Configuration '$config_name' deleted successfully!"
}

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

ccenv() {
    local command="$1"
    shift 2>/dev/null || true

    case "$command" in
        add)
            _ccenv_add
            ;;
        use)
            local config_name="$1"
            shift 2>/dev/null || true
            local extra_args=()
            local found_sep=0
            local arg=""
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
