# Legion Go 2 TrueStrike controller reconnect fix

Automatically reconnects the **Lenovo Legion Go 2**'s **TrueStrike controllers**
on startup and on resume from sleep, so they are picked up automatically
instead of having to physically detach and reattach them, or dig through the
controller pairing settings, every single time.

## Install

```console
$ git clone https://github.com/silver-warden/truestrike_reconnect.git
$ cd truestrike_reconnect
$ sudo bash install.sh
```

That installs everything and turns it on immediately. To update later:
`git pull && sudo bash install.sh`.

You can also grab "Code → Download zip" from GitHub, unpack it and run
`sudo bash install.sh` from the folder. Note this is **not a single-file
script** — it needs the repo folder, because it installs a couple of `systemd`
services and an optional [Decky][decky] plugin that restores functionality after
SteamOS updates.

### Why it needs sudo

The controllers are exposed to Steam by a system service
([InputPlumber][inputplumber]), and the only reliable way to get them back is to
tell that service to re-scan. So the installer uses `root` to:

- drop two small `systemd` units (a periodic health-check timer + a resume hook)
  into `/etc/systemd/system`, and
- copy its own scripts to `/var` and install the optional root Decky plugin.

## Uninstall

```console
$ sudo bash uninstall.sh
```

Removes the `systemd` units, the resume hook, the `/var` copies and the plugin.

---

Everything below is the technical detail, for anyone who's curious how it works
or wants to tune it.

## The problem

On the Legion Go 2 the TrueStrike controllers reach Steam Input through
[InputPlumber][inputplumber], which exposes them as a virtual gamepad
(`deck-uhid`, "Valve Steam Deck Controller"). Sometimes that virtual gamepad
never makes it to Steam, and the controllers look dead even though they are
attached and electrically fine. **Restarting InputPlumber always fixes it** —
this tool just does that automatically.

Two distinct causes, found by digging through `journalctl`:

1. **Missing target.** InputPlumber comes up without ever creating the virtual
   gamepad node.
2. **Enumeration race.** InputPlumber churns its gamepad target
   at startup (`xbox-elite` → `deck-uhid`) on cold boot, on resume, **and on
   every Desktop ↔ Gaming switch**. Steam Input enumerates gamepads when it
   starts; if it enumerates during that churn window it **misses the final node
   and never binds** — even though the node is right there and InputPlumber
   looks perfectly healthy. A naive "does the gamepad node exist?" check can't
   see this, which is why simple watchdogs still drop ~1 in 5 boots.

Both are cured by forcing one fresh gamepad *add* event after Steam is up.

## How it works

A `systemd` timer runs a check every 60s (and 20s after boot); a `systemd` sleep
hook runs it again after resume. Each pass is cheap and idempotent:

1. **Detached?** If the physical controller (USB `17ef:61eb`) isn't attached, do
   nothing.
2. **Nudge (once per Steam session).** If the `steam` process is new since the
   last run and has been up ≥15s, restart InputPlumber once so Steam
   re-enumerates. A cold boot, a resume and a Desktop↔Gaming switch each spawn a
   *new* `steam` pid, so one rule covers them all — including the race above.
3. **Missing-target recovery.** If no virtual gamepad node exists and that
   persists across a 12s confirmation re-check, restart InputPlumber.
4. **Loop guard.** All restarts share a per-boot budget so a genuinely broken
   system can't thrash.

A nudge restarts **only InputPlumber** — it never touches Steam, so it can't
close your session or kick you out of a game. Worst case is a ~1s controller
blink while Steam is loading, and it fires once per session, not continuously.

## Configuration

Optional environment overrides (set via `systemctl edit lg2-controller-fix.service`):

| Variable | Default | Meaning |
| --- | --- | --- |
| `LG2_STEAM_SETTLE` | `15` | Seconds a new `steam` process must be up before it's nudged (so Steam is actually listening). |
| `LG2_CONFIRM_SLEEP` | `12` | How long the missing-node fault must persist before restarting. |
| `LG2_MAX_RESTARTS` | `5` | Max InputPlumber restarts per boot (loop guard). |

## What gets installed

| Path | Purpose |
| --- | --- |
| `/var/local/lib/lg2-fix/*` | Canonical copies (writable `/var`; the source of truth for re-seeding). |
| `/var/local/bin/lg2-controller-fix.sh` | The check / nudge / restart script the timer runs. |
| `/etc/systemd/system/lg2-controller-fix.{service,timer}` | `oneshot` unit + `OnBootSec=20`, `OnUnitInactiveSec=60` timer. |
| `/etc/systemd/system-sleep/lg2-controller-fix` | Re-runs the check after resume. |
| `~/homebrew/plugins/lg2-controller-fix/` | Optional root Decky plugin (see below). |

### Update resilience

SteamOS image updates can rewrite `/etc/systemd/system` and silently drop the
units. The authoritative copies live under `/var/local/lib/lg2-fix/`, and the
root [Decky][decky] plugin runs `lg2-fix-bootstrap.sh` on load and every 5
minutes to re-seed the units and re-enable the timer. If you don't use Decky,
just re-run `sudo bash install.sh` after a major SteamOS update.

## Requirements

- **Lenovo Legion Go 2** on **SteamOS** (relies on [InputPlumber][inputplumber]).
- `root` for install/uninstall.
- [Decky Plugin Loader][decky] — optional, only for surviving SteamOS updates.

Steam Input runs inside the Steam client on current SteamOS, so the fix keys on
the `steam` process rather than the now-inactive `steamcontrollerd`.

## Verify it's working

```console
$ systemctl status lg2-controller-fix.timer      # should be active
$ journalctl -t lg2-controller-fix -b            # nudge / restart events this boot
```

Example line when the nudge fires:

```
Steam session pid 38708 (age 1055s) -> nudging InputPlumber so Steam re-enumerates the gamepad (restart #1/5 this boot)
```

## License

Licensed under the [Apache License, Version 2.0][apache] — see [LICENSE](LICENSE).

## Disclaimer

This repository was produced with AI assistance and is provided **as is**, with
no warranties of any kind. It installs `systemd` units that restart the system
input daemon and must run as root; read the scripts before running them.

[apache]: https://www.apache.org/licenses/LICENSE-2.0
[inputplumber]: https://github.com/ShadowBlip/InputPlumber
[decky]: https://github.com/SteamDeckHomebrew/decky-loader
