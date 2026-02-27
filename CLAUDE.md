# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Shell scripts for optimizing a ThinkPad T480s running Fedora 43 KDE Plasma with an Intel AX210 WiFi 6E card.

## Running

No build system. Scripts are run directly with sudo:

```bash
sudo bash optimize-system.sh        # Primary: WiFi, power, kernel params, services, OOM, KDE
sudo bash optimize-extras.sh        # Secondary: DNS, hostname, boot speed, service cleanup
sudo bash tune-thinkpad.sh          # Original: WiFi module config, NM settings, tools, ACPI
```

Verification after running:
```bash
systemd-analyze                        # Boot time
iw dev wlp61s0 link                    # WiFi band
tuned-adm active                       # Power profile (should show thinkpad-t480s)
cat /proc/sys/vm/swappiness            # Should be 10
```

## Script Architecture

`optimize-system.sh` is the primary script and covers the most ground:
- WiFi band priority via NetworkManager autoconnect priorities (5GHz > 6GHz > 2.4GHz)
- Power management: disables TLP (masks it), keeps `tuned-ppd` active for KDE Plasma integration
- Custom tuned profiles: `thinkpad-t480s` (AC) and `thinkpad-t480s-battery` inheriting from balanced/balanced-battery
- Kernel params via `/etc/sysctl.d/99-thinkpad-t480s.conf` (swappiness, vfs cache, dirty writeback, TCP buffers, NMI watchdog)
- Service cleanup: disables VM guest agents, iSCSI, mdmonitor, NetworkManager-wait-online, and other unnecessary services
- Enables `systemd-oomd` for OOM protection
- KDE animation speed reduction (`AnimationDurationFactor=0.5`)

`tune-thinkpad.sh` orchestrates the other scripts and adds WiFi module params (`/etc/modprobe.d/iwlwifi-ax210.conf`) and NetworkManager config.

Supporting scripts: `optimize-bluetooth.sh`, `optimize-extras.sh`, `create-kernel-config.sh`, `apply-thinkpad-optimizations.sh`.

AI terminal setup scripts (`install-ai-terminal.sh`, `install-ai-terminal-uv.sh`, `setup-ai-terminal.sh`) are unrelated utilities.

## Conventions

- All scripts use `#!/usr/bin/env bash` with `set -euo pipefail`
- Scripts require root/sudo — check early and fail with clear message
- Scripts must be idempotent (safe to run multiple times)
- Back up config files before modifying them
- `tlp-thinkpad-t480s.conf` is the TLP config (now disabled in favor of tuned)
- See `THINKPAD_TUNING.md` for detailed documentation of each optimization, troubleshooting, and useful commands
