#!/bin/bash

# Apply ThinkPad optimizations after initial setup
# Run this after tune-thinkpad.sh

set -e

echo "🚀 Applying ThinkPad Optimizations"
echo "==================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Get the actual user's home directory (works even when run with sudo)
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi

# 1. Apply TLP configuration
echo "📝 Applying TLP configuration..."
TLP_SOURCE=""

# Try to find the TLP config file in common locations
for path in "$USER_HOME/Projects/tlp-thinkpad-t480s.conf" \
            "/home/$SUDO_USER/Projects/tlp-thinkpad-t480s.conf" \
            "$HOME/Projects/tlp-thinkpad-t480s.conf" \
            "/home/dfinn/Projects/tlp-thinkpad-t480s.conf"; do
    if [ -f "$path" ]; then
        TLP_SOURCE="$path"
        break
    fi
done

if [ -n "$TLP_SOURCE" ] && [ -f "$TLP_SOURCE" ]; then
    if [ ! -f /etc/tlp.d/99-thinkpad-t480s.conf ]; then
        cp "$TLP_SOURCE" /etc/tlp.d/99-thinkpad-t480s.conf
        echo -e "${GREEN}✅ TLP configuration applied from $TLP_SOURCE${NC}"
    else
        echo -e "${YELLOW}⚠️  TLP config already exists at /etc/tlp.d/99-thinkpad-t480s.conf${NC}"
        echo "   Review and merge manually if needed"
        echo "   Source file found at: $TLP_SOURCE"
    fi
else
    echo -e "${YELLOW}⚠️  TLP config file not found${NC}"
    echo "   Searched in:"
    echo "     - $USER_HOME/Projects/tlp-thinkpad-t480s.conf"
    [ -n "$SUDO_USER" ] && echo "     - /home/$SUDO_USER/Projects/tlp-thinkpad-t480s.conf"
    echo "     - $HOME/Projects/tlp-thinkpad-t480s.conf"
    echo "   You can manually copy it: sudo cp ~/Projects/tlp-thinkpad-t480s.conf /etc/tlp.d/99-thinkpad-t480s.conf"
fi

# 2. Reload WiFi module
echo ""
echo "📡 Reloading WiFi module..."
set +e  # Temporarily disable exit on error for this section
if lsmod | grep -q iwlwifi; then
    # Find WiFi interface
    WIFI_IFACE=$(ip link show 2>/dev/null | grep -E "^[0-9]+: wl" | head -1 | cut -d: -f2 | tr -d ' ' || echo "")
    
    if [ -n "$WIFI_IFACE" ]; then
        echo "   Disconnecting WiFi interface $WIFI_IFACE..."
        # Disconnect the interface first
        nmcli device disconnect "$WIFI_IFACE" 2>/dev/null
        ip link set "$WIFI_IFACE" down 2>/dev/null
        sleep 2
    fi
    
    # Try to unload the module
    if modprobe -r iwlwifi 2>/dev/null; then
        sleep 1
        modprobe iwlwifi 2>/dev/null
        echo -e "${GREEN}✅ WiFi module reloaded${NC}"
        
        # Bring interface back up
        if [ -n "$WIFI_IFACE" ]; then
            sleep 2
            ip link set "$WIFI_IFACE" up 2>/dev/null
            nmcli device connect "$WIFI_IFACE" 2>/dev/null
        fi
    else
        echo -e "${YELLOW}⚠️  Could not unload iwlwifi (still in use)${NC}"
        echo "   This is normal if WiFi is connected. Module parameters will apply on next reboot."
        echo "   To apply now: Disconnect WiFi, then run: sudo modprobe -r iwlwifi && sudo modprobe iwlwifi"
    fi
else
    echo -e "${YELLOW}⚠️  iwlwifi module not loaded${NC}"
fi
set -e  # Re-enable exit on error

# 3. Restart NetworkManager
echo ""
echo "🔄 Restarting NetworkManager..."
systemctl restart NetworkManager
sleep 2
echo -e "${GREEN}✅ NetworkManager restarted${NC}"

# 4. Restart TLP
echo ""
echo "🔋 Restarting TLP..."
tlp start
echo -e "${GREEN}✅ TLP restarted${NC}"

# 5. Apply sysctl settings
echo ""
echo "⚙️  Applying kernel parameters..."
if [ -f /etc/sysctl.d/99-thinkpad-t480s.conf ]; then
    sysctl -p /etc/sysctl.d/99-thinkpad-t480s.conf >/dev/null 2>&1
    echo -e "${GREEN}✅ Kernel parameters applied${NC}"
else
    echo -e "${YELLOW}⚠️  Kernel config not found${NC}"
fi

echo ""
echo "================================"
echo "✨ Optimizations Applied!"
echo "================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Check WiFi status:"
echo "   iw dev"
echo "   iw dev wlan0 link"
echo ""
echo "2. Check TLP status:"
echo "   sudo tlp-stat -s"
echo ""
echo "3. Test WiFi connection and speed"
echo ""
echo "4. (Optional) Enable battery charge thresholds in TLP:"
echo "   sudo nano /etc/tlp.d/99-thinkpad-t480s.conf"
echo "   Uncomment START_CHARGE_THRESH_BAT0 and STOP_CHARGE_THRESH_BAT0"
echo "   sudo tlp start"
echo ""
