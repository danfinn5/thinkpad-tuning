#!/bin/bash

# Bluetooth Optimization Script for ThinkPad T480s
# Improves Bluetooth connection speed and reduces delay

set -e

echo "🔵 Bluetooth Optimization for ThinkPad T480s"
echo "============================================="
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Bluetooth service optimization
echo "📡 Optimizing Bluetooth service..."
BLUETOOTH_CONF="/etc/bluetooth/main.conf"

if [ -f "$BLUETOOTH_CONF" ]; then
    # Backup original
    cp "$BLUETOOTH_CONF" "$BLUETOOTH_CONF.backup"
    
    # Optimize for faster connections
    sed -i 's/#AutoEnable=false/AutoEnable=true/' "$BLUETOOTH_CONF" 2>/dev/null || true
    sed -i 's/#FastConnectable=false/FastConnectable=true/' "$BLUETOOTH_CONF" 2>/dev/null || true
    
    # Add optimizations if not present
    if ! grep -q "^FastConnectable" "$BLUETOOTH_CONF"; then
        echo "" >> "$BLUETOOTH_CONF"
        echo "# Fast connection optimization" >> "$BLUETOOTH_CONF"
        echo "FastConnectable=true" >> "$BLUETOOTH_CONF"
    fi
    
    if ! grep -q "^AutoEnable" "$BLUETOOTH_CONF"; then
        echo "AutoEnable=true" >> "$BLUETOOTH_CONF"
    fi
    
    echo -e "${GREEN}✅ Bluetooth service configuration updated${NC}"
else
    echo -e "${YELLOW}⚠️  Bluetooth config not found at $BLUETOOTH_CONF${NC}"
fi

# 2. Kernel Bluetooth parameters
echo ""
echo "⚙️  Setting kernel Bluetooth parameters..."

# Create modprobe config for Bluetooth
BLUETOOTH_MODPROBE="/etc/modprobe.d/bluetooth-optimize.conf"
cat > "$BLUETOOTH_MODPROBE" << 'EOF'
# Bluetooth optimization for faster connections
# Disable power save for better responsiveness
options btusb enable_autosuspend=0
EOF

echo -e "${GREEN}✅ Created $BLUETOOTH_MODPROBE${NC}"

# 3. Update TLP Bluetooth settings for better performance
echo ""
echo "🔋 Updating TLP Bluetooth settings..."
TLP_BT_CONFIG="/etc/tlp.d/99-bluetooth-optimize.conf"

cat > "$TLP_BT_CONFIG" << 'EOF'
# Bluetooth optimization for faster connections
# Keep Bluetooth always on when on AC power for faster reconnection
BLUETOOTH_ON_AC=on
BLUETOOTH_ON_BAT=on

# Disable USB autosuspend for Bluetooth devices
USB_BLACKLIST_BTUSB=1
EOF

echo -e "${GREEN}✅ Created $TLP_BT_CONFIG${NC}"

# 4. Systemd service optimization
echo ""
echo "🔄 Optimizing Bluetooth service settings..."
SYSTEMD_OVERRIDE="/etc/systemd/system/bluetooth.service.d/override.conf"
mkdir -p "$(dirname "$SYSTEMD_OVERRIDE")"

cat > "$SYSTEMD_OVERRIDE" << 'EOF'
[Service]
# Reduce service startup time
TimeoutStartSec=10
# Keep service running for faster reconnection
Restart=on-failure
RestartSec=2
EOF

systemctl daemon-reload
echo -e "${GREEN}✅ Systemd service optimized${NC}"

# 5. Apply changes
echo ""
echo "🔄 Applying changes..."
systemctl restart bluetooth
sleep 2

# Reload TLP if it's running
if systemctl is-active --quiet tlp; then
    tlp start
    echo -e "${GREEN}✅ TLP restarted with new settings${NC}"
fi

# Reload Bluetooth module if possible
if lsmod | grep -q btusb; then
    echo "   Note: Bluetooth module parameters will apply on next reboot"
    echo "   Or manually reload: sudo modprobe -r btusb && sudo modprobe btusb"
fi

echo ""
echo "================================"
echo "✨ Bluetooth Optimization Complete!"
echo "================================"
echo ""
echo "Changes applied:"
echo "  ✅ FastConnectable enabled for quicker pairing"
echo "  ✅ AutoEnable enabled for automatic startup"
echo "  ✅ USB autosuspend disabled for Bluetooth"
echo "  ✅ TLP configured to keep Bluetooth on"
echo ""
echo "Next steps:"
echo ""
echo "1. Reboot or reload Bluetooth module:"
echo "   sudo modprobe -r btusb && sudo modprobe btusb"
echo ""
echo "2. Test your mouse connection speed"
echo ""
echo "3. If still slow, try:"
echo "   # Remove and re-pair your mouse"
echo "   bluetoothctl"
echo "   # Then: remove <device-mac>, scan on, pair <device-mac>"
echo ""
echo "4. Check Bluetooth status:"
echo "   systemctl status bluetooth"
echo "   bluetoothctl show"
echo ""
