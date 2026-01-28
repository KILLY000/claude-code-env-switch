# Claude Code Environment Switch Plugin

An Oh My Zsh plugin for managing multiple Claude Code authentication configurations. Easily switch between different accounts or API credentials with interactive selection and full command-line control.

## Installation

1. Clone this plugin into your Oh My Zsh custom plugins directory:

```bash
git clone https://github.com/KILLY000/claude-code-env-switch.git ~/.oh-my-zsh/custom/plugins/claude-code-env-switch
```

2. Enable the plugin in your `~/.zshrc`:

```bash
plugins=(... claude-code-env-switch)
```

3. Reload your shell:

```bash
source ~/.zshrc
```

## Usage

### Interactive Configuration Selector

Run `ccenv` without arguments to launch an interactive arrow-key selector:

```bash
ccenv
```

Use **↑/↓** to navigate, **Enter** to select and start Claude, **q** to cancel.

### Add a Configuration

Create a new configuration interactively:

```bash
ccenv add
```

You'll be prompted to:
1. Choose token type (`auth-token`, `api-key`, or `oauth`)
2. Enter your credentials based on the selected type
3. Name your configuration (alphanumeric, dash, underscore)
4. Enter an optional description

### Use a Configuration

Activate a configuration and start Claude:

```bash
ccenv use <name>
```

Example:
```bash
ccenv use work
```

### List All Configurations

Show all saved configurations in their custom order:

```bash
ccenv list
```

Alias: `ccenv ls`

### View Configuration Details

Display configuration details (tokens are masked for security):

```bash
ccenv info <name>
```

Example:
```bash
ccenv info work
# Configuration: work
# Type: auth-token
# Description: Work account
#
# ANTHROPIC_BASE_URL:    https://api.anthropic.com
# ANTHROPIC_AUTH_TOKEN:  abc123...xyz789
```

### Edit a Configuration

Update an existing configuration interactively:

```bash
ccenv edit <name>
```

Press Enter to keep the current value, or enter a new value.

### Delete a Configuration

Remove a configuration:

```bash
ccenv delete <name>
```

Aliases: `ccenv del <name>`, `ccenv rm <name>`

### Reorder Configurations

Rearrange the display order of configurations with an interactive UI:

```bash
ccenv reorder
```

Alias: `ccenv order`

Controls:
- **↑/↓** — Move cursor
- **u/k** — Move selected item up
- **d/j** — Move selected item down
- **Enter** — Save new order
- **q** — Cancel without saving

### Help

Display help information:

```bash
ccenv help
```

## Configuration Types

The plugin supports three authentication methods:

### auth-token

Uses two environment variables:
- `ANTHROPIC_BASE_URL` — Your Anthropic base URL
- `ANTHROPIC_AUTH_TOKEN` — Your authentication token

### api-key

Uses two environment variables:
- `ANTHROPIC_BASE_URL` — Your Anthropic base URL
- `ANTHROPIC_API_KEY` — Your API key

### oauth

Uses one environment variable:
- `CLAUDE_CODE_OAUTH_TOKEN` — Your OAuth token (obtain via `claude setup-token`)

## Configuration Storage

Configurations are stored in `~/.config/claude-envs/` (respects `XDG_CONFIG_HOME`).

Each configuration is a `.conf` file with simple key=value pairs. A `.order` file in the same directory maintains the custom display order of configurations.

## Tab Completion

The plugin provides zsh tab completion for all subcommands and configuration names. Type `ccenv` and press Tab to see available commands, or `ccenv use` and press Tab to see available configurations.

## Security

- Configuration directory is created with `chmod 700` (owner only)
- Configuration files are created with `chmod 600` (read/write for owner only)
- Token input is hidden during entry (`read -s`)
- Tokens are masked when displayed (showing first 6 and last 4 characters)
- Deletion requires explicit confirmation

## Example Workflow

```bash
# Add your work account (auth-token type)
ccenv add
# Select: 1 (auth-token)
# Enter ANTHROPIC_BASE_URL: https://api.anthropic.com
# Enter ANTHROPIC_AUTH_TOKEN: ...
# Enter configuration name: work
# Enter description: Work account

# Add your personal account (oauth type)
ccenv add
# Select: 3 (oauth)
# Enter CLAUDE_CODE_OAUTH_TOKEN: ...
# Enter configuration name: personal
# Enter description: Personal account

# List all configs
ccenv list
# Available configurations:
#   - work (auth-token) - Work account
#   - personal (oauth) - Personal account

# Reorder configurations
ccenv reorder

# Use interactive selector to pick a config and start Claude
ccenv

# Or directly use a specific config
ccenv use work
```
