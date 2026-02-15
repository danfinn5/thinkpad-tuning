# ThinkPad T480s Tuning Guide

## Overview
This guide helps optimize your ThinkPad T480s running Fedora 43 KDE Plasma with an Intel AX210 WiFi 6E card.

## Quick Start

1. **Run the system optimization script:**
   ```bash
   sudo bash ~/Projects/"thinkpad tuning"/optimize-system.sh
   ```
   This handles WiFi band priority, power management (tuned), kernel parameters, service cleanup, OOM protection, and KDE animation speed in one pass.

2. **Run the extras script** (DNS, hostname, boot speed, service cleanup):
   ```bash
   sudo bash ~/Projects/"thinkpad tuning"/optimize-extras.sh
   ```

3. **Optionally run the original tuning script** (WiFi module config, NM settings, tools):
   ```bash
   sudo bash ~/Projects/"thinkpad tuning"/tune-thinkpad.sh
   ```

4. **Reboot and verify:**
   ```bash
   systemd-analyze                        # Boot time
   iw dev wlp61s0 link                    # WiFi band
   tuned-adm active                       # Power profile
   cat /proc/sys/vm/swappiness            # Should be 10
   systemctl is-active systemd-oomd       # Should be active
   ```

## WiFi Optimization (Intel AX210)

### Band Priority

The system has three saved SSIDs for the same router. `optimize-system.sh` sets autoconnect priorities so NetworkManager prefers the fastest available band:

| Connection | Band | Priority | Rationale |
|------------|------|----------|-----------|
| TP-Link_D84E_5G | 5 GHz | 30 (highest) | Best speed/range balance |
| TP-Link_D84E_6G | 6 GHz | 20 | Fastest but shorter range |
| TP-Link_D84E | 2.4 GHz | 10 (fallback) | Widest range, slowest |

Manual adjustment:
```bash
nmcli connection modify "TP-Link_D84E_5G" connection.autoconnect-priority 30
nmcli connection modify "TP-Link_D84E_6G" connection.autoconnect-priority 20
nmcli connection modify "TP-Link_D84E" connection.autoconnect-priority 10
```

### Module Parameters
The `tune-thinkpad.sh` script creates `/etc/modprobe.d/iwlwifi-ax210.conf` with:
- WiFi 6 (802.11ax) enabled
- Power save enabled for battery life
- 160MHz channel width support

### NetworkManager Settings
Created `/etc/NetworkManager/conf.d/wifi-ax210.conf` for optimal WiFi behavior.

### Useful Commands

```bash
iw dev wlp61s0 link                         # Connection status (band, signal, bitrate)
iw dev wlp61s0 link | grep -E "freq|signal|bitrate"
iw dev wlp61s0 scan | grep -E "SSID|freq|signal"  # Scan for networks
iw dev wlp61s0 get power_save               # Check WiFi power save
```

## Power Management (tuned)

### TLP to tuned Migration

The T480s ships with both TLP and tuned-ppd installed, which conflict. `optimize-system.sh` resolves this:

- **TLP**: Disabled, stopped, and masked (prevents accidental re-enable)
- **tuned-ppd**: Kept active — it powers KDE Plasma's battery profile widget

**Why tuned over TLP:** Fedora 43 uses `tuned-ppd` to bridge `tuned` with KDE's power profile UI. Running TLP alongside it causes conflicts where neither tool fully controls power policy.

### Custom tuned Profiles

The script creates two profiles and updates `/etc/tuned/ppd.conf` so `tuned-ppd` uses them automatically:

| Profile | Inherits from | Used when |
|---------|--------------|-----------|
| `thinkpad-t480s` | `balanced` | AC power, Balanced mode |
| `thinkpad-t480s-battery` | `balanced-battery` | Battery, Balanced mode |

Both profiles add the sysctl optimizations (see Kernel Parameters below). The AC profile also sets `energy_perf_bias=balance_performance`.

The ppd.conf mapping ensures `tuned-ppd` switches between our custom profiles instead of the stock ones when KDE's power profile widget changes modes.

Verify:
```bash
tuned-adm active                    # Should show thinkpad-t480s or thinkpad-t480s-battery
```

Revert to stock profiles:
```bash
sudo cp /etc/tuned/ppd.conf.bak /etc/tuned/ppd.conf
sudo systemctl restart tuned-ppd
```

### KDE Power Profile Widget
The KDE battery widget continues to work because `tuned-ppd` translates between KDE's power profile UI (Performance/Balanced/Power Saver) and tuned profiles. The custom profiles slot in transparently — no UI changes needed.

## Kernel Parameters

The script creates `/etc/sysctl.d/99-thinkpad-t480s.conf` with:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `vm.swappiness` | 10 | Strongly prefer RAM over zram (40GB available) |
| `vm.vfs_cache_pressure` | 50 | Keep dentry/inode caches longer for snappier file operations |
| `vm.dirty_writeback_centisecs` | 1500 | Less aggressive background writeback (15s vs default 5s) |
| `vm.dirty_ratio` | 15 | Max dirty memory before forced writeback |
| `vm.dirty_background_ratio` | 5 | Background writeback threshold |
| `net.core.rmem_max` | 16MB | Larger receive buffer |
| `net.core.wmem_max` | 16MB | Larger send buffer |
| `net.ipv4.tcp_rmem` | 4K-87K-16M | TCP receive buffer auto-tuning range |
| `net.ipv4.tcp_wmem` | 4K-65K-16M | TCP send buffer auto-tuning range |
| `net.ipv4.tcp_slow_start_after_idle` | 0 | Keep TCP window size after idle (better for WiFi) |
| `kernel.nmi_watchdog` | 0 | Disable NMI watchdog — saves CPU on laptop |

Apply changes manually:
```bash
sudo sysctl -p /etc/sysctl.d/99-thinkpad-t480s.conf
```

## Service Cleanup

`optimize-system.sh` disables services that are unnecessary on physical ThinkPad hardware:

| Service | Why disabled |
|---------|-------------|
| `vboxservice`, `vgauthd`, `vmtoolsd`, `qemu-guest-agent` | VM guest agents — not a VM |
| `livesys`, `livesys-late` | Live media remnants |
| `iscsi-onboot`, `iscsid`, `iscsi` | No iSCSI storage |
| `mdmonitor` | No software RAID |
| `NetworkManager-wait-online` | Blocks boot for no benefit on a laptop |
| `mcelog` | Deprecated, replaced by rasdaemon |
| `atd` | `at` job scheduler — cron suffices |
| `pcscd` | Smart card daemon — no smart cards |
| `gssproxy` | Kerberos GSSAPI proxy — not on enterprise domain |

## OOM Protection

`systemd-oomd` is enabled to prevent hard freezes under memory pressure. It monitors cgroup memory pressure and kills the heaviest offender before the kernel's OOM killer triggers a full freeze.

```bash
systemctl is-active systemd-oomd   # Check status
oomctl                              # View oomd state
```

## KDE Animation Speed

`optimize-system.sh` sets `AnimationDurationFactor=0.5` in `~/.config/kdeglobals`, halving all animation durations. Same visual effects, just faster. This does not change themes, layouts, or any other visual configuration.

Reset to default:
```bash
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 1.0
```

## ThinkPad-Specific Features

### ACPI Features
```bash
cat /proc/acpi/ibm/thinkpad
ls /proc/acpi/ibm/
```

Common features: `thinklight`, `hotkey`, `bluetooth`, `video`, `beep`.

### Firmware Updates
```bash
sudo fwupdmgr get-updates
sudo fwupdmgr update
sudo fwupdmgr get-devices
```

## Troubleshooting

### WiFi Issues

**WiFi not connecting to 5GHz/6GHz:**
```bash
# Check current connection
iw dev wlp61s0 link | grep freq

# Check priorities
nmcli -f NAME,autoconnect-priority connection show

# Force reconnect to 5GHz
nmcli connection up "TP-Link_D84E_5G"
```

**WiFi not working after module reload:**
```bash
lsmod | grep iwlwifi
sudo dmesg | grep -i iwlwifi | tail -20
sudo modprobe -v iwlwifi
```

**Slow WiFi speeds:**
```bash
iw dev wlp61s0 link | grep width     # Check channel width
iw dev wlp61s0 link | grep freq      # Check band
sudo iw dev wlp61s0 set power_save off  # Disable power save temporarily
```

### Power Management Issues

**Check which tool is managing power:**
```bash
systemctl is-active tlp              # Should be inactive
systemctl is-active tuned            # Should be active
tuned-adm active                     # Should show thinkpad-t480s
```

**TLP accidentally re-enabled:**
```bash
sudo systemctl disable --now tlp
sudo systemctl mask tlp
```

### Boot Time

After applying optimizations, check boot time improvement:
```bash
systemd-analyze                      # Total boot time
systemd-analyze blame | head -20     # Slowest services
systemd-analyze critical-chain       # Critical path
```

## Scripts Reference

| Script | Purpose | Run as |
|--------|---------|--------|
| `optimize-system.sh` | Full system optimization (WiFi, power, kernel, services, OOM, KDE) | `sudo` |
| `tune-thinkpad.sh` | WiFi module config, NM settings, tools, ACPI check | `sudo` |
| `create-kernel-config.sh` | Create/update sysctl config only | `sudo` |
| `optimize-bluetooth.sh` | Bluetooth optimization | `sudo` |
| `optimize-extras.sh` | DNS, hostname, boot speed, service cleanup, NMI watchdog | `sudo` |

## References

- [tuned Documentation](https://tuned-project.org/)
- [Intel AX210 Linux Support](https://www.intel.com/content/www/us/en/support/articles/000005511/wireless.html)
- [ThinkPad ACPI Documentation](https://www.thinkwiki.org/wiki/How_to_make_acpi_work)
- [Fedora Power Management](https://fedoraproject.org/wiki/Power_management)
- [systemd-oomd](https://www.freedesktop.org/software/systemd/man/latest/systemd-oomd.service.html)
