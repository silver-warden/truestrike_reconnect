#!/usr/bin/env bash
# Lenovo Legion Go 2 (SteamOS): recover controllers when InputPlumber fails to
# keep/expose its virtual gamepad target (Steam Input then sees nothing, even
# though the controllers are attached and electrically fine).
#
# The fault can appear at boot OR later when switching desktop <-> gaming mode
# (InputPlumber target churn). This script is run repeatedly by a systemd
# timer and is cheap+idempotent.
#
# Predicate: physical Legion controller attached (USB 17ef:61eb) but NO
# virtual gamepad (no js handler under /devices/virtual/input/) -> restart
# InputPlumber after the condition persists across a confirmation re-check.
set -u

TAG=lg2-controller-fix
log() { logger -t "$TAG" -- "$*"; echo "$*"; }

STATE_DIR=/run/lg2-fix
CONFIRM_SLEEP=${LG2_CONFIRM_SLEEP:-12}
MAX_RESTARTS_PER_BOOT=${LG2_MAX_RESTARTS:-5}

mkdir -p "$STATE_DIR"

source_attached() {
  local d
  for d in /sys/bus/usb/devices/*/; do
    [[ -f "${d}idVendor" ]] || continue
    if [[ "$(<"${d}idVendor")" == "17ef" && "$(<"${d}idProduct")" == "61eb" ]]; then
      return 0
    fi
  done
  return 1
}

virtual_gamepad_present() {
  awk '
    /^S: Sysfs=\/devices\/virtual\/input\// { v = 1 }
    /^H: Handlers=.*js[0-9]/ && v           { found = 1; exit }
    /^$/                                      { v = 0 }
    END { exit !found }
  ' /proc/bus/input/devices
}

if ! source_attached; then
  # controllers detached: nothing to do
  exit 0
fi

if virtual_gamepad_present; then
  # healthy: clear the per-boot restart budget
  rm -f "$STATE_DIR/restarts"
  exit 0
fi

# Fault seen once -> confirm it persists (avoids racing transient re-creation)
sleep "$CONFIRM_SLEEP"
if virtual_gamepad_present; then
  log "virtual gamepad re-appeared on re-check; no action"
  exit 0
fi

restarts=$(cat "$STATE_DIR/restarts" 2>/dev/null || echo 0)
if (( restarts >= MAX_RESTARTS_PER_BOOT )); then
  log "controllers attached, virtual gamepad missing, but restart budget ($MAX_RESTARTS_PER_BOOT/boot) exhausted; giving up"
  exit 1
fi

restarts=$((restarts + 1))
echo "$restarts" > "$STATE_DIR/restarts"
log "controllers attached and virtual gamepad MISSING for >${CONFIRM_SLEEP}s -> restarting InputPlumber (restart #$restarts/$MAX_RESTARTS_PER_BOOT this boot)"
systemctl restart inputplumber
exit 0
