#!/usr/bin/env bash
# Remove the Legion Go 2 controller fix (units, /var files, Decky plugin).
set -euo pipefail

systemctl disable --now lg2-controller-fix.timer 2>/dev/null || true
systemctl stop  lg2-controller-fix.service      2>/dev/null || true
rm -f /etc/systemd/system/lg2-controller-fix.service \
      /etc/systemd/system/lg2-controller-fix.timer \
      /var/local/bin/lg2-controller-fix.sh \
      /etc/systemd/system-sleep/lg2-controller-fix
rm -rf /var/local/lib/lg2-fix
rm -rf /home/deck/homebrew/plugins/lg2-controller-fix
systemctl restart plugin_loader.service 2>/dev/null || true
systemctl daemon-reload
echo "Uninstalled."
