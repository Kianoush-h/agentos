# Configuration Reference

## Reconfiguring the agent after first boot

Run the setup wizard again at any time:

```bash
sudo /opt/agentos/bin/setup-wizard.sh
```

Or edit the config files directly (see below).

## Agent config — `/home/agentos/.claude/agent.json`

```json
{
    "name": "Atlas",
    "models": {
        "primary": {
            "provider": "anthropic",
            "model": "claude-sonnet-4-6"
        }
    }
}
```

**Supported providers:** `anthropic`, `openai`, `openrouter`, `ollama`

## Environment file — `/etc/agentos/env`

Owned by `root`, readable by the `agentos-gateway` service via `EnvironmentFile=`.

```bash
# API keys (written by the wizard)
ANTHROPIC_API_KEY=sk-ant-...

# Dashboard
DASHBOARD_PORT=18789

# Claude Code
CLAUDE_CODE_HOME=/home/agentos/.claude
CLAUDE_WORKSPACE=/home/agentos/workspace
```

## Vault — `/etc/agentos/vault/`

One file per secret, named by the environment variable:

```
/etc/agentos/vault/
├── ANTHROPIC_API_KEY
├── OPENAI_API_KEY        (if configured)
└── DISCORD_TOKEN         (if configured)
```

To add or rotate a key:

```bash
# As root
echo "sk-ant-new-key" | sudo tee /etc/agentos/vault/ANTHROPIC_API_KEY
sudo chmod 600 /etc/agentos/vault/ANTHROPIC_API_KEY
sudo systemctl restart agentos-broker agentos-gateway
```

## Ollama — local model

If you selected Ollama during setup, it runs as a system service on `http://localhost:11434`.

```bash
# Check status
systemctl status ollama

# Pull a different model
ollama pull llama3

# List available models
ollama list
```

Update `agent.json` to switch models:

```json
{
    "models": {
        "primary": {
            "provider": "ollama",
            "model": "llama3"
        }
    }
}
```

Then restart the gateway: `sudo systemctl restart agentos-gateway`

## Service management

| Service | Description |
|---------|-------------|
| `agentos-gateway` | Claude Code agent process |
| `agentos-broker` | Credential vault broker |
| `agentos-dashboard` | Web UI on port 18789 |
| `ollama` | Local model runtime |

```bash
# View live logs
journalctl -u agentos-gateway -f

# Restart all agent services
sudo systemctl restart agentos-broker agentos-gateway agentos-dashboard
```
