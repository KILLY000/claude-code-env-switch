# Claude Code Environment Switch Plugin

An Oh My Zsh plugin for managing multiple Claude Code authentication configurations.

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

### Add a Configuration

Create a new configuration with either API tokens or OAuth token:

```bash
ccenv add
```

You'll be prompted to:
1. Choose token type (API or OAuth)
2. Enter your tokens
3. Name your configuration
4. Enter an optional description

### Use a Configuration

Switch to a configuration and automatically start Claude:

```bash
ccenv use <name>
```

Example:
```bash
ccenv use work
```

### List All Configurations

Show all saved configurations:

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
# Output:
# Configuration: work
# Type: api
# Description: Work account
#
# ANTHROPIC_BASE_URL:    https://api.anthropic.com
# ANTHROPIC_AUTH_TOKEN: xxx...xxxx
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

### Help

Display help information:

```bash
ccenv help
```

## Configuration Storage

Configurations are stored in `~/.config/claude-envs/` (respects `XDG_CONFIG_HOME`).

Each configuration is stored as a separate `.conf` file with simple key=value pairs.

## Configuration Types

### API
Requires two environment variables:
- `ANTHROPIC_BASE_URL` - Your Anthropic base URL
- `ANTHROPIC_AUTH_TOKEN` - Your Anthropic auth token

### OAuth Token
Requires one environment variable:
- `CLAUDE_CODE_OAUTH_TOKEN` - Your Claude Code OAuth token (obtain via `claude setup-token`)

## Example Workflow

```bash
# Add your work account
ccenv add
# Select: API
# Enter ANTHROPIC_BASE_URL: https://api.anthropic.com
# Enter ANTHROPIC_AUTH_TOKEN: ...
# Enter configuration name: work
# Enter description: Work account

# Add your personal account
ccenv add
# Select: OAuth
# Enter CLAUDE_CODE_OAUTH_TOKEN: ...
# Enter configuration name: personal
# Enter description: Personal account

# List all configs
ccenv list
# Available configurations:
#   - work (api) - Work account
#   - personal (oauth) - Personal account

# Switch to work account
ccenv use work

# Later, switch to personal account
ccenv use personal
```

## Security

- Configuration files are created with `chmod 600` (read/write for owner only)
- Token input is hidden during entry (only masked version displayed after input)
- Tokens are masked when displaying configuration info
- Configuration directory respects `XDG_CONFIG_HOME`
