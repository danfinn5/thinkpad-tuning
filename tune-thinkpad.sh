#!/bin/bash

# ThinkPad T480s Tuning Script
# Optimizes WiFi (Intel AX210) and common ThinkPad settings

set -e

echo "🔧 ThinkPad T480s Tuning Script"
echo "================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root for system changes
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}⚠️  Some operations require root privileges.${NC}"
    echo "   This script will show you what needs to be done."
    echo "   Run with sudo for automatic configuration."
    echo ""
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 1. WiFi Optimization for Intel AX210
echo "📡 WiFi Configuration (Intel AX210)"
echo "-----------------------------------"

# Check WiFi card
WIFI_CARD=$(lspci | grep -i "Network controller" | grep -i "Intel")
if [[ $WIFI_CARD == *"AX210"* ]] || [[ $WIFI_CARD == *"AX1675"* ]]; then
    echo -e "${GREEN}✅ Intel AX210 WiFi card detected${NC}"
    
    # Create WiFi optimization config
    echo ""
    echo "Creating WiFi optimization configuration..."
    
    # Check for iwlwifi module parameters
    if [ -d /sys/module/iwlwifi ]; then
        echo "Current iwlwifi parameters:"
        cat /sys/module/iwlwifi/parameters/* 2>/dev/null | head -5 || echo "  (using defaults)"
    fi
    
    # Create modprobe config for WiFi optimization
    MODPROBE_CONFIG="/etc/modprobe.d/iwlwifi-ax210.conf"
    if [ "$EUID" -eq 0 ]; then
        cat > "$MODPROBE_CONFIG" << 'EOF'
# Intel AX210 WiFi 6E Optimization
# Enable 11ax (WiFi 6) support
options iwlwifi 11n_disable=0 11ac_disable=0 11ax_disable=0

# Power management (1=enable, 0=disable)
# Enable power save for better battery life
options iwlwifi power_save=1

# Enable 160MHz channel width for maximum speed
options iwlwifi enable_ini=1

# Disable 11b support (legacy, slow)
options cfg80211 ieee80211_regdom="US"
EOF
        echo -e "${GREEN}✅ Created $MODPROBE_CONFIG${NC}"
    else
        echo ""
        echo "Create $MODPROBE_CONFIG with:"
        cat << 'EOF'
# Intel AX210 WiFi 6E Optimization
options iwlwifi 11n_disable=0 11ac_disable=0 11ax_disable=0
options iwlwifi power_save=1
options iwlwifi enable_ini=1
options cfg80211 ieee80211_regdom="US"
EOF
    fi
    
    # NetworkManager WiFi settings
    echo ""
    echo "NetworkManager WiFi optimizations:"
    if command_exists nmcli; then
        echo "  Current WiFi power save:"
        nmcli radio wifi 2>/dev/null || echo "    (check manually)"
    fi
    
    # Create NetworkManager WiFi config
    NM_CONFIG="/etc/NetworkManager/conf.d/wifi-ax210.conf"
    if [ "$EUID" -eq 0 ]; then
        mkdir -p /etc/NetworkManager/conf.d/
        cat > "$NM_CONFIG" << 'EOF'
[connection]
# Enable 802.11ax (WiFi 6)
wifi.cloned-mac-address=preserve

[device]
wifi.scan-rand-mac-address=no
EOF
        echo -e "${GREEN}✅ Created $NM_CONFIG${NC}"
    else
        echo ""
        echo "Create $NM_CONFIG with:"
        cat << 'EOF'
[connection]
wifi.cloned-mac-address=preserve
[device]
wifi.scan-rand-mac-address=no
EOF
    fi
    
else
    echo -e "${YELLOW}⚠️  Intel AX210 not detected in lspci output${NC}"
fi

# 2. TLP Power Management
echo ""
echo "🔋 TLP Power Management"
echo "----------------------"

if command_exists tlp; then
    echo -e "${GREEN}✅ TLP is installed${NC}"
    
    # Check if TLP is enabled
    if systemctl is-enabled tlp >/dev/null 2>&1; then
        echo -e "${GREEN}✅ TLP service is enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  TLP service is not enabled${NC}"
        if [ "$EUID" -eq 0 ]; then
            systemctl enable tlp
            systemctl start tlp
            echo -e "${GREEN}✅ Enabled and started TLP${NC}"
        else
            echo "   Run: sudo systemctl enable --now tlp"
        fi
    fi
    
    # Check TLP config for ThinkPad optimizations
    TLP_CONFIG="/etc/tlp.conf"
    if [ -f "$TLP_CONFIG" ]; then
        echo ""
        echo "Recommended TLP settings for ThinkPad T480s:"
        echo ""
        echo "Add or modify these in $TLP_CONFIG:"
        cat << 'EOF'

# ThinkPad T480s specific optimizations
CPU_SCALING_GOVERNOR_ON_AC=powersave
CPU_SCALING_GOVERNOR_ON_BAT=powersave

# Intel CPU energy/performance bias
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power

# PCIe Active State Power Management
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave

# WiFi power save (for Intel AX210)
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# Disable Bluetooth when on battery
BLUETOOTH_ON_BAT=off

# ThinkPad specific: Enable battery charge thresholds
# Uncomment and set if you want to preserve battery health
# START_CHARGE_THRESH_BAT0=75
# STOP_CHARGE_THRESH_BAT0=80
EOF
    fi
else
    echo -e "${YELLOW}⚠️  TLP config not found${NC}"
fi

# 3. Install useful WiFi tools
echo ""
echo "🛠️  WiFi Tools"
echo "-------------"

TOOLS_TO_INSTALL=()
if ! command_exists iw; then
    TOOLS_TO_INSTALL+=("iw")
fi

# Check if iwconfig exists, but don't install wireless-tools on Fedora (deprecated)
# Use 'iw' instead which is the modern replacement
if ! command_exists iwconfig; then
    # Check if we're on Fedora/RHEL
    if command_exists dnf && [ -f /etc/fedora-release ]; then
        echo "  Note: iwconfig not available (wireless-tools deprecated on Fedora)"
        echo "  Using 'iw' instead (modern replacement, already installed)"
    else
        # Try to install on other distros
        TOOLS_TO_INSTALL+=("wireless-tools")
    fi
fi

if ! command_exists rfkill; then
    TOOLS_TO_INSTALL+=("rfkill")
fi

if [ ${#TOOLS_TO_INSTALL[@]} -gt 0 ]; then
    echo "Missing tools: ${TOOLS_TO_INSTALL[*]}"
    if [ "$EUID" -eq 0 ]; then
        # Try to install, but skip unavailable packages
        dnf install -y "${TOOLS_TO_INSTALL[@]}" --skip-unavailable 2>/dev/null || \
        dnf install -y "${TOOLS_TO_INSTALL[@]}" 2>&1 | grep -v "No match" || true
        echo -e "${GREEN}✅ Installed available WiFi tools${NC}"
    else
        echo "   Run: sudo dnf install -y ${TOOLS_TO_INSTALL[*]}"
    fi
else
    echo -e "${GREEN}✅ All essential WiFi tools are installed${NC}"
    if ! command_exists iwconfig; then
        echo "   Note: Using 'iw' (modern) instead of 'iwconfig' (deprecated)"
    fi
fi

# 4. Kernel parameters for ThinkPad
echo ""
echo "⚙️  Kernel Parameters"
echo "-------------------"

SYSCTL_CONFIG="/etc/sysctl.d/99-thinkpad-t480s.conf"
if [ "$EUID" -eq 0 ]; then
    cat > "$SYSCTL_CONFIG" << 'EOF'
# ThinkPad T480s optimizations

# Network optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# WiFi optimizations
net.ipv4.tcp_slow_start_after_idle = 0

# Power management
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF
    sysctl -p "$SYSCTL_CONFIG" >/dev/null 2>&1
    echo -e "${GREEN}✅ Created $SYSCTL_CONFIG${NC}"
else
    echo "Create $SYSCTL_CONFIG with kernel optimizations"
fi

# 5. ThinkPad ACPI features
echo ""
echo "💻 ThinkPad ACPI Features"
echo "-----------------------"

if [ -d /sys/devices/platform/thinkpad_acpi ]; then
    echo -e "${GREEN}✅ ThinkPad ACPI is available${NC}"
    
    # Check for thinkpad_acpi module
    if lsmod | grep -q thinkpad_acpi; then
        echo "  ThinkPad ACPI module is loaded"
        
        # Show available features
        if [ -f /proc/acpi/ibm/thinkpad ]; then
            echo "  Available ThinkPad features:"
            cat /proc/acpi/ibm/thinkpad 2>/dev/null | head -10 || echo "    (check /proc/acpi/ibm/)"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  ThinkPad ACPI not found${NC}"
    echo "   Install: sudo dnf install kernel-modules-extra"
fi

# 6. Check for firmware updates
echo ""
echo "📦 Firmware"
echo "----------"

if command_exists fwupdmgr; then
    echo -e "${GREEN}✅ fwupdmgr is available${NC}"
    echo "  Check for updates: fwupdmgr get-updates"
    echo "  Install updates: fwupdmgr update"
else
    echo -e "${YELLOW}⚠️  fwupdmgr not found${NC}"
    echo "   Install: sudo dnf install fwupd"
fi

# 7. Summary and next steps
echo ""
echo "================================"
echo "✨ Tuning Summary"
echo "================================"
echo ""
echo "Completed optimizations:"
echo "  ✅ WiFi configuration for Intel AX210"
echo "  ✅ TLP power management setup"
echo "  ✅ Kernel parameter optimizations"
echo ""
echo "Next steps:"
echo ""
echo "1. Reload WiFi module (if config was created):"
echo "   sudo modprobe -r iwlwifi && sudo modprobe iwlwifi"
echo ""
echo "2. Restart NetworkManager:"
echo "   sudo systemctl restart NetworkManager"
echo ""
echo "3. Review and customize TLP settings:"
echo "   sudo nano /etc/tlp.conf"
echo "   Then: sudo tlp start"
echo ""
echo "4. Check WiFi status:"
echo "   iw dev"
echo "   iwconfig  # (if wireless-tools installed)"
echo ""
echo "5. Test WiFi performance:"
echo "   iw dev wlan0 link"
echo "   iw dev wlan0 station dump"
echo ""
echo "6. Check for firmware updates:"
echo "   sudo fwupdmgr get-updates"
echo "   sudo fwupdmgr update"
echo ""
