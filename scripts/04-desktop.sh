#!/usr/bin/env bash
#
# Phase 04: Desktop environment (Lite edition only)
# Installs GNOME and configures a clean desktop with AgentOS branding
#
set -euo pipefail

log "Installing desktop environment..."

# ── Install GNOME minimal ─────────────────────────────────────────
log "Installing GNOME (this takes 5-10 minutes)..."
chroot "${ROOTFS}" bash -c '
    apt-get update
    apt-get install -y --no-install-recommends \
        ubuntu-desktop-minimal \
        gnome-terminal \
        nautilus \
        firefox \
        gdm3 \
        gnome-tweaks \
        dconf-cli

    # Enable display manager
    systemctl enable gdm3
'
ok "GNOME desktop installed"

# ── Configure auto-login for first boot ────────────────────────────
log "Configuring GDM for first-boot experience..."
mkdir -p "${ROOTFS}/etc/gdm3"
cat > "${ROOTFS}/etc/gdm3/custom.conf" <<'EOF'
[daemon]
# Auto-login on first boot; the setup wizard will disable this after
AutomaticLoginEnable=true
AutomaticLogin=user
WaylandEnable=true

[security]

[xdmcp]

[chooser]

[debug]
EOF

# ── Desktop branding ──────────────────────────────────────────────
log "Applying AgentOS branding..."

# Set GNOME settings via dconf defaults
mkdir -p "${ROOTFS}/etc/dconf/profile"
cat > "${ROOTFS}/etc/dconf/profile/user" <<'EOF'
user-db:user
system-db:agentos
EOF

mkdir -p "${ROOTFS}/etc/dconf/db/agentos.d"
cat > "${ROOTFS}/etc/dconf/db/agentos.d/00-agentos" <<'EOF'
[org/gnome/desktop/interface]
gtk-theme='Adwaita-dark'
color-scheme='prefer-dark'

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/agentos-wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/agentos-wallpaper-dark.png'
picture-options='zoom'
primary-color='#1a1a2e'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/agentos-wallpaper-dark.png'

[org/gnome/shell]
favorite-apps=['org.gnome.Terminal.desktop', 'firefox.desktop', 'org.gnome.Nautilus.desktop', 'agentos-dashboard.desktop']

[org/gnome/terminal/legacy/profiles:/:b1dcc9dd-5262-4d8d-a863-c897e6d979b9]
background-color='#1a1a2e'
foreground-color='#e0e0e0'
use-theme-colors=false
EOF

# Compile dconf database
chroot "${ROOTFS}" dconf update || true

# ── Install branding assets ────────────────────────────────────────
log "Installing branding assets..."
mkdir -p "${ROOTFS}/usr/share/backgrounds"
mkdir -p "${ROOTFS}/usr/share/plymouth/themes/agentos"
mkdir -p "${ROOTFS}/boot/grub/themes/agentos"

# Wallpaper — install SVG from branding/ and convert to PNG
cp "${PROJECT_ROOT}/branding/wallpaper.svg" \
   "${ROOTFS}/usr/share/backgrounds/agentos-wallpaper.svg"

chroot "${ROOTFS}" bash -c '
    apt-get install -y --no-install-recommends librsvg2-bin || true
    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert -w 1920 -h 1080 \
            /usr/share/backgrounds/agentos-wallpaper.svg \
            -o /usr/share/backgrounds/agentos-wallpaper.png
        cp /usr/share/backgrounds/agentos-wallpaper.png \
           /usr/share/backgrounds/agentos-wallpaper-dark.png
    fi
'

# Plymouth theme
cp "${PROJECT_ROOT}/branding/plymouth/agentos/agentos.plymouth" \
   "${ROOTFS}/usr/share/plymouth/themes/agentos/agentos.plymouth"
cp "${PROJECT_ROOT}/branding/plymouth/agentos/agentos.script" \
   "${ROOTFS}/usr/share/plymouth/themes/agentos/agentos.script"

chroot "${ROOTFS}" bash -c '
    apt-get install -y --no-install-recommends plymouth plymouth-themes || true
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
        default.plymouth /usr/share/plymouth/themes/agentos/agentos.plymouth 100 || true
    update-initramfs -u || true
'

# GRUB theme
cp "${PROJECT_ROOT}/branding/grub/theme.txt" \
   "${ROOTFS}/boot/grub/themes/agentos/theme.txt"
# Copy wallpaper as GRUB background (will be used if PNG conversion succeeded)
cp "${ROOTFS}/usr/share/backgrounds/agentos-wallpaper.png" \
   "${ROOTFS}/boot/grub/themes/agentos/background.png" 2>/dev/null || true

# ── Desktop entry for AgentOS Dashboard ────────────────────────────
log "Creating AgentOS dashboard launcher..."
cat > "${ROOTFS}/usr/share/applications/agentos-dashboard.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=AgentOS Dashboard
Comment=Manage your AI agent
Icon=utilities-system-monitor
Exec=xdg-open http://localhost:18789
Categories=System;
Terminal=false
StartupNotify=true
DESKTOP

# ── Autostart the setup wizard on first login ──────────────────────
log "Configuring first-run setup wizard autostart..."
mkdir -p "${ROOTFS}/etc/xdg/autostart"
cat > "${ROOTFS}/etc/xdg/autostart/agentos-wizard.desktop" <<'WIZARD'
[Desktop Entry]
Type=Application
Name=AgentOS Setup
Comment=Configure your AI agent
Exec=/opt/agentos/bin/setup-wizard.sh
Terminal=true
X-GNOME-Autostart-enabled=true
OnlyShowIn=GNOME;
WIZARD

ok "Desktop environment configured"
