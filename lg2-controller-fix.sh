#!/usr/bin/env bash
# Lenovo Legion Go 2 (SteamOS): recover controllers when InputPlumber fails to
# keep/expose its virtual gamepad target (Steam Input then sees nothing, even
# though the controllers are attached and electrically fine).
#
# The fault can appear at boot OR later when switching desktop <-> gaming mode
# (InputPlumber target churn). This script is run repeatedly by a systemd
# timer and is cheap+idempotent.
#
# Two recovery paths, both idempotent and bounded by a per-boot budget:
#  1. Nudge: once per Steam session (new steam pid = cold boot OR a
#     desktop<->gaming switch), restart InputPlumber so Steam re-enumerates the
#     gamepad. Steam can miss the virtual gamepad during InputPlumber's target
#     churn even though the node exists, which the node check below can't see.
#  2. Missing-node: physical Legion controller attached (USB 17ef:61eb) but NO
#     virtual gamepad (no js handler under /devices/virtual/input/) persisting
#     across a confirmation re-check -> restart InputPlumber.
set -u

TAG=lg2-controller-fix
log() { logger -t "$TAG" -- "$*"; echo "$*"; }

STATE_DIR=/run/lg2-fix
CONFIRM_SLEEP=${LG2_CONFIRM_SLEEP:-12}
MAX_RESTARTS_PER_BOOT=${LG2_MAX_RESTARTS:-5}
STEAM_SETTLE=${LG2_STEAM_SETTLE:-15}
NUDGE_STATE="$STATE_DIR/nudged_pid"
RESUME_WINDOW=${LG2_RESUME_WINDOW:-120}
RESUME_ATTACH_WAIT=${LG2_RESUME_ATTACH_WAIT:-15}
RESUME_CONFIRM_SLEEP=${LG2_RESUME_CONFIRM_SLEEP:-4}

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

# Seconds since logind reported a resume completed (0 = never slept this
# boot). busctl call output: "btttt <succ> <wakeup> <prepare> <sleep> <wake>"
# with CLOCK_MONOTONIC timestamps in usec. Fails soft: no property -> no
# resume fast path.
resume_age_s() {
  local out sig succ wakeup rest now
  out=$(busctl --no-pager -- call org.freedesktop.login1 /org/freedesktop/login1 \
    org.freedesktop.login1.Manager GetLastSleepProgress 2>/dev/null) || return 1
  read -r sig succ wakeup _rest <<< "$out" || return 1
  [[ "$wakeup" =~ ^[0-9]+$ ]] && (( wakeup > 0 )) || return 1
  now=$(awk '{printf "%d", $1 * 1000000}' /proc/uptime)
  echo $(( (now - wakeup) / 1000000 ))
}

# Fresh resume: the controller USB link drops over suspend and re-enumerates
# a couple of seconds after wake, InputPlumber re-creates the composite
# device on its default (xbox-elite) target and never restores deck-uhid,
# and Steam keeps its pid (so the nudge path can't help). Wait out the
# re-attach and shorten the confirmation sleep: the fault is confirmed by
# definition here, and the 12s default is pure latency (~30s dead
# controllers after every wake).
resume_age=$(resume_age_s || true)
if [[ -n "$resume_age" ]] && (( resume_age <= RESUME_WINDOW )); then
  log "fresh resume (${resume_age}s ago): waiting up to ${RESUME_ATTACH_WAIT}s for controller re-attach"
  for (( i = 0; i < RESUME_ATTACH_WAIT; i++ )); do
    source_attached && break
    sleep 1
  done
  CONFIRM_SLEEP=$RESUME_CONFIRM_SLEEP
fi

if ! source_attached; then
  # controllers detached: nothing to do
  exit 0
fi

# --- once-per-Steam-session nudge -------------------------------------------
# Steam Input enumerates gamepads when the client (re)starts. InputPlumber's
# target churn at boot AND on desktop<->gaming switches (xbox-elite -> deck-uhid)
# can create the virtual gamepad in a window Steam misses, leaving Steam bound
# to nothing even though the node exists -- which the node-present check below
# cannot see. Force one fresh add event per new Steam session so it re-
# enumerates. Each cold boot and each mode switch is a new steam pid, so this
# covers both. Bounded by the same per-boot budget to survive steam flapping.
steam_pid() { pgrep -n -u deck -x steam 2>/dev/null; }
steam_age() { ps -o etimes= -p "$1" 2>/dev/null | tr -d ' '; }

spid=$(steam_pid)
if [[ -n "$spid" && "$spid" != "$(cat "$NUDGE_STATE" 2>/dev/null)" ]]; then
  # only nudge once Steam has settled, else it isn't listening yet and we'd
  # burn the one nudge for this session; skip (without marking) and retry next tick
  age=$(steam_age "$spid"); age=${age:-999}
  if (( age >= STEAM_SETTLE )); then
    nudge_budget=$(cat "$STATE_DIR/restarts" 2>/dev/null || echo 0)
    if (( nudge_budget < MAX_RESTARTS_PER_BOOT )); then
      echo "$spid" > "$NUDGE_STATE"
      echo "$((nudge_budget + 1))" > "$STATE_DIR/restarts"
      log "Steam session pid $spid (age ${age}s) -> nudging InputPlumber so Steam re-enumerates the gamepad (restart #$((nudge_budget + 1))/$MAX_RESTARTS_PER_BOOT this boot)"
      systemctl restart inputplumber
      exit 0
    fi
  fi
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
