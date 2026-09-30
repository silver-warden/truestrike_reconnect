#!/usr/bin/env bash
# Legion Go 2 controller fix installer (Decky-resilient).
# Run as root:  sudo bash install.sh
set -euo pipefail
cd "$(dirname "$0")"

DECK_UID=$(id -u deck)
DECK_GID=$(id -g deck)
PLUGIN_DIR=/home/deck/homebrew/plugins/lg2-controller-fix

# 1. canonical copies on the persistent /var partition
install -Dm755 lg2-controller-fix.sh           /var/local/lib/lg2-fix/lg2-controller-fix.sh
install -Dm644 lg2-controller-fix.service      /var/local/lib/lg2-fix/lg2-controller-fix.service
install -Dm644 lg2-controller-fix.timer        /var/local/lib/lg2-fix/lg2-controller-fix.timer
install -Dm755 sleep-lg2-controller-fix        /var/local/lib/lg2-fix/system-sleep-lg2-controller-fix
install -Dm755 lg2-fix-bootstrap.sh            /var/local/lib/lg2-fix/lg2-fix-bootstrap.sh

# 2. Decky plugin (re-seeds the units after every update/boot)
install -d -o "$DECK_UID" -g "$DECK_GID" "$PLUGIN_DIR" "$PLUGIN_DIR/dist"
install -o "$DECK_UID" -g "$DECK_GID" -m644 plugin/plugin.json      "$PLUGIN_DIR/plugin.json"
install -o "$DECK_UID" -g "$DECK_GID" -m644 plugin/package.json     "$PLUGIN_DIR/package.json"
install -o "$DECK_UID" -g "$DECK_GID" -m644 plugin/main.py          "$PLUGIN_DIR/main.py"
install -o "$DECK_UID" -g "$DECK_GID" -m644 plugin/dist/index.js    "$PLUGIN_DIR/dist/index.js"

# 3. seed the live units right now
/var/local/lib/lg2-fix/lg2-fix-bootstrap.sh </dev/null

# 4. load the plugin immediately
systemctl restart plugin_loader.service || true

sleep 3
echo
echo "== plugin status =="
journalctl -b -u plugin_loader --no-pager 2>/dev/null | grep -iE 'LG2|Loaded' | tail -10
echo "== timer status =="
systemctl --no-pager is-enabled lg2-controller-fix.timer || true
systemctl --no-pager is-active  lg2-controller-fix.timer || true
