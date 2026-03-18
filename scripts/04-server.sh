#!/usr/bin/env bash
#
# Phase 04 (Server edition): Headless server hardening
# Applied instead of 04-desktop.sh when --server is passed.
# Makes the image minimal, SSH-only, and firewall-protected.
#
set -euo pipefail

log "Applying server edition hardening..."

# ── Set default systemd target to multi-user (no GUI) ─────────────
log "Setting default target to multi-user.target..."
chroot "${ROOTFS}" systemctl set-default multi-user.target

# ── Remove any display-manager packages if present ────────────────
log "Ensuring no display manager is installed..."
chroot "${ROOTFS}" bash -c '
    apt-get remove -y --purge gdm3 lightdm xdm nodm 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
'

# ── Install and configure UFW firewall ────────────────────────────
log "Installing UFW firewall..."
chroot "${ROOTFS}" apt-get install -y ufw

chroot "${ROOTFS}" bash -c '
    # Default policy: deny all inbound, allow all outbound
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH
    ufw allow 22/tcp comment "SSH"

    # Allow AgentOS dashboard (localhost only — not exposed externally)
    # External access should be via SSH tunnel: ssh -L 18789:localhost:18789 user@host
    ufw allow from 127.0.0.1 to any port 18789 comment "AgentOS dashboard (local only)"

    # Enable UFW non-interactively
    ufw --force enable

    # Enable at boot
    systemctl enable ufw
'
ok "UFW firewall configured"

# ── Harden SSH for server use ─────────────────────────────────────
log "Hardening SSH configuration..."
cat >> "${ROOTFS}/etc/ssh/sshd_config" <<'SSHD'

# AgentOS Server hardening
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
X11Forwarding no
AllowTcpForwarding yes
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
SSHD

ok "SSH hardened (password auth disabled, key-only)"

# ── Disable unused services ────────────────────────────────────────
log "Disabling unused services..."
chroot "${ROOTFS}" bash -c '
    systemctl disable bluetooth 2>/dev/null || true
    systemctl disable cups     2>/dev/null || true
    systemctl disable avahi-daemon 2>/dev/null || true
'

# ── Create SSH key instructions file ─────────────────────────────
cat > "${ROOTFS}/home/user/FIRST-LOGIN.txt" <<'README'
AgentOS Server — First Login Instructions
==========================================

SSH is configured for key-based authentication only.
Password login is disabled.

To add your SSH public key:
  1. Boot the VM and connect a console (VirtualBox/VMware serial console)
  2. Log in as 'user' with the default password 'agentos'
  3. Run: mkdir -p ~/.ssh && echo "YOUR_PUBLIC_KEY" >> ~/.ssh/authorized_keys
  4. Then reconnect via SSH: ssh user@<vm-ip>

Agent dashboard (via SSH tunnel):
  ssh -L 18789:localhost:18789 user@<vm-ip>
  Then open: http://localhost:18789

Agent logs:
  journalctl -u agentos-gateway -f
README

chroot "${ROOTFS}" chown user:user /home/user/FIRST-LOGIN.txt

ok "Server edition hardening complete"
