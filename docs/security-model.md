# AgentOS Security Model

AgentOS is built around the principle of **least privilege for autonomous agents**: the agent process has exactly the access it needs to do its job and nothing more.

## User isolation

| Account | UID | Purpose |
|---------|-----|---------|
| `user` | 1000 | Human operator — sudo access, desktop login |
| `agentos` | 1100 | Agent service account — no sudo, no shell login |

The agent process (`claude`) runs as `agentos`. It cannot escalate privileges, read other users' files, or modify system configuration.

## AppArmor confinement

The agent binary (`/usr/bin/claude`) runs under the `agentos-claude` AppArmor profile (`/etc/apparmor.d/agentos-claude`).

**Allowed:**
- Read/write to `/home/agentos/` and `/home/agentos/workspace/`
- Read from `/opt/agentos/skills/`
- Write to `/var/log/agentos/`
- Full network access (needed to call LLM APIs)
- Docker socket (for sandboxed skill execution)
- Unix socket to the credential broker

**Denied:**
- `/etc/agentos/vault/` — API keys (agent uses the broker instead)
- `/etc/shadow`, `/etc/sudoers` — system credential files
- `/root/`, `/boot/` — system directories
- `/usr/sbin/` executables — privileged system tools

## Credential vault

API keys are stored in `/etc/agentos/vault/` (owned `root:root`, mode `700`). The agent process cannot read this directory directly (AppArmor denies it).

Instead, the **credential broker** (`agentos-broker` service) runs as root and exposes a Unix socket at `/run/agentos/credentials.sock` (mode `660`, group `agentos`). The agent sends `GET <key_name>` requests and receives the secret value without ever seeing the vault files.

```
agent process (uid 1100)
    │
    ▼  GET ANTHROPIC_API_KEY
/run/agentos/credentials.sock
    │
    ▼
credential-broker (uid 0) → reads /etc/agentos/vault/ANTHROPIC_API_KEY
    │
    ▼  sk-ant-...
agent process
```

## Audit logging

The `auditd` service logs all actions by the `agentos` user (UID 1100):

- Every `execve` syscall (commands run by the agent)
- Every write to `/etc/agentos/` and `/home/agentos/.claude/`
- Every outbound network connection

Logs are written to `/var/log/agentos/audit.log` and also available via `journalctl -u agentos-gateway`.

## Docker sandboxing

Skills that require shell access run inside ephemeral Docker containers with no persistent state. The agent has access to the Docker socket, but AppArmor prevents it from modifying the Docker daemon configuration or host filesystem mounts.

## SSH hardening (Server edition)

The Server edition additionally:
- Disables password authentication (key-only SSH)
- Sets `MaxAuthTries 3` and `LoginGraceTime 30`
- Enables UFW with default-deny inbound policy
- Exposes only port 22 externally; dashboard (18789) is localhost-only
