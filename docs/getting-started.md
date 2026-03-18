# Getting Started with AgentOS

## Requirements

- A hypervisor: VirtualBox 7+, VMware Fusion/Workstation, QEMU/KVM, or Hyper-V
- 4GB RAM allocated to the VM (8GB recommended)
- 20GB disk space

## Option 1 — Import the OVA (easiest)

Download the latest OVA from the [Releases](https://github.com/Kianoush-h/agentos/releases) page.

**VirtualBox:**
```bash
VBoxManage import agentos-lite.ova
VBoxManage startvm agentos-lite
```

**VMware:**
Open VMware → File → Open → select `agentos-lite.ova`

**QEMU/KVM (QCOW2):**
```bash
qemu-system-x86_64 \
  -hda agentos-lite.qcow2 \
  -m 4096 \
  -enable-kvm \
  -cpu host \
  -smp 2 \
  -net nic -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::18789-:18789
```

## Option 2 — Build from source

Requires Ubuntu 24.04 as the host (or WSL2 on Windows).

```bash
git clone https://github.com/Kianoush-h/agentos.git
cd agentos
make validate   # check everything before building
make build      # builds the Lite edition (~45 min)
```

The output OVA and QCOW2 are written to `/tmp/agentos-build/output/`.

## First boot

1. The VM boots and auto-logs in as `user`
2. The setup wizard launches automatically
3. Follow the 4 steps: choose AI provider → name your agent → connect a channel → confirm
4. Open `http://localhost:18789` for the web dashboard

## Default credentials

| Account | Password |
|---------|----------|
| `user` (human login) | `agentos` (forced to change on first login) |
| `agentos` (service account) | no shell login |

## Accessing the dashboard from your host machine

The dashboard binds to `127.0.0.1:18789` inside the VM. To access it from your host:

```bash
# SSH tunnel
ssh -L 18789:localhost:18789 user@<vm-ip>
# Then open http://localhost:18789 in your browser
```
