#!/bin/bash
# optimize-extras.sh — Additional system optimizations for ThinkPad T480s
# Run after optimize-system.sh for further improvements
# Usage: sudo bash optimize-extras.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
skip() { echo -e "  ${YELLOW}[SKIP]${NC} $1"; }
err()  { echo -e "  ${RED}[ERR]${NC} $1"; }
section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: Run with sudo${NC}"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"

echo -e "${BLUE}ThinkPad T480s — Extra Optimizations${NC}"
echo "============================================"

# ─────────────────────────────────────────────
section "1. Silence TLP log spam"
# ─────────────────────────────────────────────
# TLP is disabled (replaced by tuned) but still triggers on power events.
# Masking prevents it from running entirely.

if systemctl is-active tlp &>/dev/null; then
    skip "TLP is active — not masking (you may still be using it)"
elif systemctl is-enabled tlp &>/dev/null && [[ "$(systemctl is-enabled tlp 2>/dev/null)" != "masked" ]]; then
    systemctl stop tlp 2>/dev/null || true
    systemctl disable tlp 2>/dev/null || true
    systemctl mask tlp 2>/dev/null || true
    systemctl mask tlp-sleep 2>/dev/null || true
    ok "Masked tlp and tlp-sleep — no more journal spam"
elif [[ "$(systemctl is-enabled tlp 2>/dev/null)" == "masked" ]]; then
    skip "TLP already masked"
else
    # TLP might be disabled but not masked — mask it anyway
    systemctl mask tlp 2>/dev/null || true
    systemctl mask tlp-sleep 2>/dev/null || true
    ok "Masked tlp and tlp-sleep"
fi

# ─────────────────────────────────────────────
section "2. Faster DNS (Cloudflare 1.1.1.1)"
# ─────────────────────────────────────────────
# Switch from router DNS to Cloudflare for faster, more private resolution.
# Falls back to Quad9 as secondary.

WIFI_CONN=$(nmcli -t -f NAME,TYPE connection show --active | grep -i 'wireless\|wifi' | head -1 | cut -d: -f1 || true)

if [[ -n "$WIFI_CONN" ]]; then
    CURRENT_DNS=$(nmcli -t -f ipv4.dns connection show "$WIFI_CONN" 2>/dev/null | cut -d: -f2)
    if [[ "$CURRENT_DNS" == *"1.1.1.1"* ]]; then
        skip "DNS already set to Cloudflare on '$WIFI_CONN'"
    else
        nmcli connection modify "$WIFI_CONN" ipv4.dns "1.1.1.1 1.0.0.1 9.9.9.9"
        nmcli connection modify "$WIFI_CONN" ipv4.ignore-auto-dns yes
        nmcli connection modify "$WIFI_CONN" ipv6.dns "2606:4700:4700::1111 2606:4700:4700::1001"
        nmcli connection modify "$WIFI_CONN" ipv6.ignore-auto-dns yes
        # Reapply connection without full disconnect to avoid dropping the script
        nmcli connection up "$WIFI_CONN" &>/dev/null || true
        sleep 2
        ok "Set DNS to Cloudflare (1.1.1.1) + Quad9 (9.9.9.9) fallback on '$WIFI_CONN'"
    fi
else
    err "No active WiFi connection found — set DNS manually after connecting"
fi

# ─────────────────────────────────────────────
section "3. Set hostname"
# ─────────────────────────────────────────────

CURRENT_STATIC=$(hostnamectl --static 2>/dev/null)
if [[ -z "$CURRENT_STATIC" || "$CURRENT_STATIC" == "fedora" ]]; then
    hostnamectl set-hostname "t480s"
    ok "Hostname set to 't480s'"
else
    skip "Hostname already set to '$CURRENT_STATIC'"
fi

# ─────────────────────────────────────────────
section "4. Defer dnf5-automatic off boot path"
# ─────────────────────────────────────────────
# dnf5-automatic takes ~20s and blocks boot. Add a random delay so it
# runs after the desktop is up.

TIMER_OVERRIDE="/etc/systemd/system/dnf5-automatic.timer.d"
if [[ -f "$TIMER_OVERRIDE/override.conf" ]]; then
    skip "dnf5-automatic timer override already exists"
else
    mkdir -p "$TIMER_OVERRIDE"
    cat > "$TIMER_OVERRIDE/override.conf" << 'EOF'
[Timer]
# Delay auto-updates to 15 min after boot so they don't slow startup
OnBootSec=15min
RandomizedDelaySec=10min
EOF
    systemctl daemon-reload
    ok "dnf5-automatic deferred to 15min after boot (was blocking startup for ~20s)"
fi

# ─────────────────────────────────────────────
section "5. Disable unused services"
# ─────────────────────────────────────────────

disable_if_active() {
    local svc="$1"
    local desc="$2"
    if systemctl is-active "$svc" &>/dev/null || systemctl is-enabled "$svc" &>/dev/null; then
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        ok "Disabled $svc ($desc)"
    else
        skip "$svc already disabled"
    fi
}

# Smart card daemon — only needed for smart card / PIV authentication
disable_if_active "pcscd.service" "smart card daemon — not using smart cards"
disable_if_active "pcscd.socket" "smart card socket"

# Kerberos GSSAPI proxy — only needed on enterprise/AD domains
disable_if_active "gssproxy.service" "Kerberos GSSAPI proxy — not on enterprise domain"

# ─────────────────────────────────────────────
section "6. Fix NetworkManager config warning"
# ─────────────────────────────────────────────
# 99-wifi-performance.conf has 'dhcp-timeout' in [main] which is invalid.
# The correct setting is 'ipv4.dhcp-timeout' per-connection, not global.

NM_PERF_CONF="/etc/NetworkManager/conf.d/99-wifi-performance.conf"
if [[ -f "$NM_PERF_CONF" ]] && grep -q 'dhcp-timeout' "$NM_PERF_CONF"; then
    cat > "$NM_PERF_CONF" << 'EOF'
# Disable WiFi power saving via NetworkManager
# This prevents the card from throttling when idle
[connection]
wifi.powersave = 2

[device]
wifi.scan-rand-mac-address = no
EOF
    nmcli general reload conf 2>/dev/null || true
    ok "Removed invalid dhcp-timeout from NM config (was causing warnings)"
else
    skip "NM config already clean"
fi

# ─────────────────────────────────────────────
section "7. Kernel watchdog optimization"
# ─────────────────────────────────────────────
# Disable NMI watchdog at runtime — saves CPU cycles on a laptop
# (not needed unless debugging kernel hangs)

CURRENT_NMI=$(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null)
if [[ "$CURRENT_NMI" == "0" ]]; then
    skip "NMI watchdog already disabled"
else
    echo 0 > /proc/sys/kernel/nmi_watchdog
    ok "Disabled NMI watchdog (runtime)"
fi

# Make persistent via sysctl
SYSCTL_CONF="/etc/sysctl.d/99-thinkpad-t480s.conf"
if [[ -f "$SYSCTL_CONF" ]] && grep -q 'nmi_watchdog' "$SYSCTL_CONF"; then
    skip "nmi_watchdog already in sysctl config"
else
    echo "" >> "$SYSCTL_CONF"
    echo "# Disable NMI watchdog — saves CPU on laptop (not debugging kernels)" >> "$SYSCTL_CONF"
    echo "kernel.nmi_watchdog = 0" >> "$SYSCTL_CONF"
    ok "Added nmi_watchdog=0 to $SYSCTL_CONF"
fi

# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}All done!${NC}"
echo ""
echo "Summary of changes:"
echo "  1. TLP fully masked — no more journal spam"
echo "  2. DNS → Cloudflare 1.1.1.1 (+ Quad9 fallback)"
echo "  3. Hostname → t480s"
echo "  4. dnf5-automatic deferred to 15min post-boot"
echo "  5. Disabled pcscd + gssproxy"
echo "  6. Fixed NM config warning"
echo "  7. Disabled NMI watchdog"
echo ""
echo "Verify with:"
echo "  resolvectl status | grep 'DNS Server'    # Should show 1.1.1.1"
echo "  hostnamectl                               # Should show t480s"
echo "  journalctl -b --priority=3 --no-pager     # Should be clean of TLP errors"
echo "  systemd-analyze blame | head -5           # dnf5-automatic gone from top"
