# Claude Code Environment Switch Plugin
# Manage multiple Claude Code authentication configurations

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

typeset -ga _CLAUDE_ENV_SWITCH_MODULES=(
    core
    config-store
    settings
    statusline
    commands
    ui
    completion
)

local _ccenv_module=""
local _ccenv_module_path=""
for _ccenv_module in "${_CLAUDE_ENV_SWITCH_MODULES[@]}"; do
    _ccenv_module_path="$CLAUDE_ENV_SWITCH_PLUGIN_DIR/lib/${_ccenv_module}.zsh"
    if [[ ! -f "$_ccenv_module_path" ]]; then
        echo "error: Missing ccenv module: $_ccenv_module_path" >&2
        return 1
    fi
    source "$_ccenv_module_path"
done
unset _ccenv_module _ccenv_module_path

if (( $+functions[compdef] )); then
    compdef _ccenv_completion ccenv
fi
