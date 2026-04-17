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
