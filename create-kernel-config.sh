#!/bin/bash

# Create the missing kernel configuration file

if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root (use sudo)"
    exit 1
fi

SYSCTL_CONFIG="/etc/sysctl.d/99-thinkpad-t480s.conf"

cat > "$SYSCTL_CONFIG" << 'EOF'
# ThinkPad T480s optimizations

# Network optimizations
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
echo "✅ Created and applied $SYSCTL_CONFIG"
