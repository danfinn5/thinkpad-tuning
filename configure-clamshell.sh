#!/usr/bin/env bash
set -euo pipefail

# configure-clamshell.sh — Set up clamshell mode toggle for ThinkPad T480s
#
# Installs clamshell-toggle script and binds F12 to toggle lid behavior.
# The toggle controls KDE PowerDevil's LidAction (0=nothing, 1=suspend).
#
# Run with: sudo bash configure-clamshell.sh

GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    echo "  sudo bash \"$0\""
    exit 1
fi

SUDO_USER="${SUDO_USER:-}"
if [ -z "$SUDO_USER" ]; then
    echo "Run with sudo (not as root directly) so user config can be set"
    exit 1
fi

SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Clamshell Mode Setup"
echo "===================="
echo ""

# =============================================================================
# 1. Clean up old config that conflicts with the toggle
# =============================================================================
echo "--- Cleanup ---"

# Remove old logind drop-in if present (not needed — PowerDevil handles lid)
if [ -f /etc/systemd/logind.conf.d/clamshell.conf ]; then
    rm -f /etc/systemd/logind.conf.d/clamshell.conf
    systemctl kill -s HUP systemd-logind 2>/dev/null || true
    info "Removed old logind drop-in (PowerDevil handles lid events)"
else
    info "No old logind drop-in to clean up"
fi

# Remove InhibitLidActionWhenExternalMonitorPresent if set
# (the toggle manages this itself)
sudo -u "$SUDO_USER" kwriteconfig6 --file powerdevilrc \
    --group "AC" --group "SuspendAndShutdown" \
    --key "InhibitLidActionWhenExternalMonitorPresent" --delete 2>/dev/null || true
info "Cleared InhibitLidActionWhenExternalMonitorPresent (toggle manages this)"

# =============================================================================
# 2. Install clamshell-toggle script
# =============================================================================
echo ""
echo "--- Toggle script ---"

TOGGLE_DEST="$SUDO_USER_HOME/.local/bin/clamshell-toggle"
mkdir -p "$(dirname "$TOGGLE_DEST")"
cp "$SCRIPT_DIR/clamshell-toggle" "$TOGGLE_DEST"
chmod +x "$TOGGLE_DEST"
chown "$SUDO_USER":"$SUDO_USER" "$TOGGLE_DEST"
info "Installed $TOGGLE_DEST"

# =============================================================================
# 3. KDE shortcut: bind F12 to clamshell-toggle
# =============================================================================
echo ""
echo "--- F12 shortcut ---"

DESKTOP_DIR="$SUDO_USER_HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/clamshell-toggle.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Toggle Clamshell Mode
Comment=Toggle lid-close behavior (suspend vs ignore)
Exec=$TOGGLE_DEST
Icon=video-display
Terminal=false
Categories=System;
NoDisplay=true
X-KDE-Shortcuts=F12
EOF
chown "$SUDO_USER":"$SUDO_USER" "$DESKTOP_DIR/clamshell-toggle.desktop"
sudo -u "$SUDO_USER" update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
info "Created clamshell-toggle.desktop (with X-KDE-Shortcuts=F12)"

# Register F12 shortcut in kglobalshortcutsrc
sudo -u "$SUDO_USER" kwriteconfig6 --file kglobalshortcutsrc \
    --group "services" --group "clamshell-toggle.desktop" \
    --key "_k_friendly_name" "Toggle Clamshell Mode"

sudo -u "$SUDO_USER" kwriteconfig6 --file kglobalshortcutsrc \
    --group "services" --group "clamshell-toggle.desktop" \
    --key "_launch" "F12,F12,Toggle Clamshell Mode"

info "Bound F12 to clamshell-toggle in kglobalshortcutsrc"

# Reload kwin
if sudo -u "$SUDO_USER" qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure 2>/dev/null; then
    info "Reloaded kwin config — F12 shortcut should be active now"
else
    info "F12 shortcut may require logout/login to take effect"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "===================="
echo "Setup complete"
echo ""
echo "Press F12 to toggle between:"
echo "  ON  — lid close does nothing (clamshell mode)"
echo "  OFF — lid close suspends (normal behavior)"
echo ""
echo "CLI usage:"
echo "  clamshell-toggle          # toggle on/off"
echo "  clamshell-toggle status   # check current state"
echo ""
echo "A logout/login may be needed for the F12 shortcut to activate."
