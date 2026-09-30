#!/usr/bin/env bash
# Re-seed the Legion Go 2 controller-fix units from the immutable-safe /var
# copy. SteamOS image updates rewrite /etc/systemd/system; Decky re-runs this
# on every boot and periodically, so the fix comes back on its own.
set -u
SRC=/var/local/lib/lg2-fix
changed=0
seed() { # $1=src $2=dest $3=mode
  if [[ ! -f "$2" ]] || ! cmp -s "$1" "$2"; then
    install -Dm "$3" "$1" "$2" && { changed=1; logger -t lg2-fix-bootstrap -- "seeded $2"; }
  fi
}

seed "$SRC/lg2-controller-fix.sh"           /var/local/bin/lg2-controller-fix.sh       755
seed "$SRC/lg2-controller-fix.service"      /etc/systemd/system/lg2-controller-fix.service 644
seed "$SRC/lg2-controller-fix.timer"        /etc/systemd/system/lg2-controller-fix.timer   644
seed "$SRC/system-sleep-lg2-controller-fix" /etc/systemd/system-sleep/lg2-controller-fix 755

if (( changed )); then
  systemctl daemon-reload
  systemctl enable lg2-controller-fix.timer >/dev/null 2>&1
fi
systemctl is-active --quiet lg2-controller-fix.timer || systemctl start lg2-controller-fix.timer
exit 0
