#!/bin/bash

# ThinkPad T480s System Optimization Script
# Fedora 43 KDE Plasma — i7-8650U, 40GB RAM, Intel AX210
#
# Fixes: WiFi band priority, TLP/tuned conflict, VM parameters,
#        unnecessary services, OOM protection, KDE animation speed
#
# Run with: sudo bash optimize-system.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[SKIP]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC} $1"; }
section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# --- Root check (most sections need it) ---
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    echo "  sudo bash \"$0\""
    exit 1
fi

SUDO_USER="${SUDO_USER:-}"

echo "ThinkPad T480s System Optimization"
echo "==================================="

# =============================================================================
# 1. WiFi Band Priority
# =============================================================================
section "WiFi Band Priority"

if command -v nmcli &>/dev/null; then
    # Check if the connections exist before modifying
    if nmcli -t -f NAME connection show | grep -qx "TP-Link_D84E_5G"; then
        nmcli connection modify "TP-Link_D84E_5G" connection.autoconnect-priority 30
        nmcli connection modify "TP-Link_D84E_6G" connection.autoconnect-priority 20
        nmcli connection modify "TP-Link_D84E"    connection.autoconnect-priority 10
        info "Set WiFi priorities: 5GHz(30) > 6GHz(20) > 2.4GHz(10)"

        # Don't disconnect — WiFi passwords are in user keyring (KDE Wallet)
        # and aren't accessible from sudo context. NM will prefer the
        # higher-priority SSID on next reconnect automatically.
        WIFI_DEV=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
        if [ -n "$WIFI_DEV" ]; then
            FREQ=$(iw dev "$WIFI_DEV" link 2>/dev/null | awk '/freq:/{print $2}')
            if [ -n "$FREQ" ]; then
                info "Currently connected at ${FREQ} MHz — priorities take effect on next reconnect"
            fi
        fi
    else
        warn "TP-Link SSIDs not found — skipping WiFi priority"
    fi
else
    warn "nmcli not found — skipping WiFi priority"
fi

# =============================================================================
# 2. Resolve TLP vs tuned Conflict
# =============================================================================
section "Power Management (TLP -> tuned)"

# Disable TLP if present
if systemctl list-unit-files tlp.service &>/dev/null; then
    systemctl disable --now tlp 2>/dev/null || true
    systemctl mask tlp 2>/dev/null || true
    info "Disabled and masked TLP"
else
    info "TLP not installed — nothing to disable"
fi

# Ensure tuned (via tuned-ppd) is active
if systemctl is-active --quiet tuned 2>/dev/null || systemctl is-active --quiet tuned-ppd 2>/dev/null; then
    info "tuned/tuned-ppd is active (powers KDE battery profile widget)"
else
    systemctl enable --now tuned 2>/dev/null || warn "Could not start tuned"
fi

# Create custom tuned profiles (AC and battery variants)
# Shared sysctl block used by both profiles
SYSCTL_BLOCK='[sysctl]
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_writeback_centisecs=1500
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_slow_start_after_idle=0'

# Clean up profiles from wrong path (if any from earlier runs)
rm -rf /etc/tuned/thinkpad-t480s /etc/tuned/thinkpad-t480s-battery 2>/dev/null || true

# AC profile — inherits from balanced
mkdir -p /etc/tuned/profiles/thinkpad-t480s
cat > /etc/tuned/profiles/thinkpad-t480s/tuned.conf << EOF
[main]
summary=ThinkPad T480s balanced profile (AC)
include=balanced

[cpu]
energy_perf_bias=balance_performance
energy_performance_preference=balance_performance

$SYSCTL_BLOCK
EOF

# Battery profile — inherits from balanced-battery
mkdir -p /etc/tuned/profiles/thinkpad-t480s-battery
cat > /etc/tuned/profiles/thinkpad-t480s-battery/tuned.conf << EOF
[main]
summary=ThinkPad T480s balanced profile (battery)
include=balanced-battery

$SYSCTL_BLOCK
EOF

# Update tuned-ppd mapping to use our profiles
PPD_CONF="/etc/tuned/ppd.conf"
if [ -f "$PPD_CONF" ]; then
    cp "$PPD_CONF" "${PPD_CONF}.bak"
    cat > "$PPD_CONF" << 'PPDEOF'
[main]
default=balanced
battery_detection=true
sysfs_acpi_monitor=true

[profiles]
power-saver=powersave
balanced=thinkpad-t480s
performance=throughput-performance

[battery]
balanced=thinkpad-t480s-battery
PPDEOF
    info "Updated ppd.conf to use custom profiles"
fi

# Restart tuned-ppd to pick up new profiles and mapping
systemctl restart tuned-ppd 2>/dev/null || systemctl restart tuned 2>/dev/null
sleep 1

ACTIVE_PROFILE=$(tuned-adm active 2>/dev/null | awk -F': ' '{print $2}')
if [[ "$ACTIVE_PROFILE" == thinkpad-t480s* ]]; then
    info "Active tuned profile: $ACTIVE_PROFILE"
else
    err "Expected thinkpad-t480s profile, got: $ACTIVE_PROFILE"
fi

# =============================================================================
# 3. Kernel VM Parameters (immediate apply)
# =============================================================================
section "Kernel VM Parameters"

SYSCTL_CONFIG="/etc/sysctl.d/99-thinkpad-t480s.conf"
cat > "$SYSCTL_CONFIG" << 'EOF'
# ThinkPad T480s optimizations

# Network buffer optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# WiFi optimizations
net.ipv4.tcp_slow_start_after_idle = 0

# VM tuning for 40GB RAM
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_writeback_centisecs = 1500
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

sysctl -p "$SYSCTL_CONFIG" >/dev/null 2>&1
info "Applied sysctl: swappiness=10, vfs_cache_pressure=50, dirty_writeback=1500"

# =============================================================================
# 4. Disable Unnecessary Services
# =============================================================================
section "Service Cleanup"

SERVICES_TO_DISABLE=(
    vboxservice          # VirtualBox guest agent
    vgauthd              # VMware guest auth
    vmtoolsd             # VMware Tools
    qemu-guest-agent     # QEMU guest agent
    livesys              # Live media remnant
    livesys-late         # Live media remnant
    iscsi-onboot         # No iSCSI storage
    iscsid               # No iSCSI storage
    iscsi                # No iSCSI storage
    mdmonitor            # No software RAID
    NetworkManager-wait-online  # Blocks boot unnecessarily
    mcelog               # Deprecated (rasdaemon replaces it)
    atd                  # at job scheduler (cron suffices)
)

disabled_count=0
for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl list-unit-files "${svc}.service" &>/dev/null 2>&1; then
        # Check if it's actually enabled or active
        if systemctl is-enabled --quiet "$svc" 2>/dev/null || \
           systemctl is-active --quiet "$svc" 2>/dev/null; then
            systemctl disable --now "$svc" 2>/dev/null || true
            info "Disabled: $svc"
            disabled_count=$((disabled_count + 1))
        fi
    fi
done

if [ "$disabled_count" -eq 0 ]; then
    info "No unnecessary services were active"
else
    info "Disabled $disabled_count unnecessary services"
fi

# =============================================================================
# 5. Enable systemd-oomd
# =============================================================================
section "OOM Protection"

if systemctl list-unit-files systemd-oomd.service &>/dev/null; then
    if systemctl is-active --quiet systemd-oomd; then
        info "systemd-oomd already active"
    else
        systemctl enable --now systemd-oomd 2>/dev/null && \
            info "Enabled systemd-oomd" || \
            err "Failed to enable systemd-oomd"
    fi
else
    warn "systemd-oomd not available"
fi

# =============================================================================
# 6. KDE Animation Speed (runs as the invoking user)
# =============================================================================
section "KDE Animation Speed"

if [ -n "$SUDO_USER" ]; then
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    KDE_GLOBALS="$SUDO_USER_HOME/.config/kdeglobals"

    if [ -f "$KDE_GLOBALS" ]; then
        if grep -q "AnimationDurationFactor" "$KDE_GLOBALS"; then
            # Update existing value
            sed -i 's/^AnimationDurationFactor=.*/AnimationDurationFactor=0.5/' "$KDE_GLOBALS"
        else
            # Add under [KDE] section, or create it
            if grep -q '^\[KDE\]' "$KDE_GLOBALS"; then
                sed -i '/^\[KDE\]/a AnimationDurationFactor=0.5' "$KDE_GLOBALS"
            else
                echo -e "\n[KDE]\nAnimationDurationFactor=0.5" >> "$KDE_GLOBALS"
            fi
        fi
    else
        mkdir -p "$(dirname "$KDE_GLOBALS")"
        cat > "$KDE_GLOBALS" << 'EOF'
[KDE]
AnimationDurationFactor=0.5
EOF
    fi
    chown "$SUDO_USER":"$SUDO_USER" "$KDE_GLOBALS"
    info "Set KDE AnimationDurationFactor=0.5 (halved animation duration)"
else
    warn "No SUDO_USER detected — set AnimationDurationFactor=0.5 in ~/.config/kdeglobals manually"
fi

# =============================================================================
# 7. Summary
# =============================================================================
section "Summary"

echo ""
echo "Optimizations applied:"
echo "  - WiFi band priority: 5GHz > 6GHz > 2.4GHz"
echo "  - Power: TLP disabled+masked, tuned profile 'thinkpad-t480s' active"
echo "  - Kernel: swappiness=10, vfs_cache_pressure=50, dirty_writeback=1500"
echo "  - Services: VM guest agents, iSCSI, RAID monitor, mcelog, atd disabled"
echo "  - OOM: systemd-oomd enabled"
echo "  - KDE: animation speed halved (0.5x)"
echo ""
echo -e "${YELLOW}Pending: ~730 dnf package updates${NC}"
echo "  Review and run when ready:"
echo "    sudo dnf upgrade --refresh"
echo ""
echo "Verify with:"
echo "  iw dev wlp61s0 link                    # WiFi band"
echo "  tuned-adm active                       # tuned profile"
echo "  cat /proc/sys/vm/swappiness            # should be 10"
echo "  systemctl is-active systemd-oomd       # should be active"
echo "  systemctl is-active tlp                # should be inactive"
echo ""
echo "A reboot is recommended to confirm all changes persist."
echo "  Check boot time after reboot: systemd-analyze"
