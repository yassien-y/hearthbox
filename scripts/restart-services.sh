#!/usr/bin/env bash
# Restarts every service, so the units and config just applied are the ones running,
# and stops services whose unit is gone (a removed group, or a service the repo dropped).
set -e

# Every linked .container unit, by service name
services="$(find -L "$HOME/.config/containers/systemd" -name '*.container' \
    -exec basename -s .container {} + | sed 's/$/.service/')"

# A unit with a mistake in it would look removed after daemon-reload, and the step
# below would stop its service. Test every unit first and stop here if one is broken,
# so a running service is never stopped because of a typo. verify runs the generators
# (Quadlet) into a temporary folder and checks what they make, without touching the
# running services. It prints only errors.
if systemd-analyze --user --generators=true verify $services; then
    echo "Units OK, restarting:" $services
else
    echo "A unit has errors; see the output above. Nothing was restarted."
    exit 1
fi

# Quadlet generates the services from the units: reload so it reads the current ones
systemctl --user daemon-reload
# A service whose unit is gone keeps running until stopped: systemd lists it as not-found.
# The active check is in awk, not a second --state=: systemd ORs those, which would list
# every running service.
stale="$(systemctl --user list-units --type=service --state=not-found --plain --no-legend |
    awk '$2 == "not-found" && $3 == "active" { print $1 }')"
if [ -n "$stale" ]; then
    echo "stopping services that are no longer installed: $stale"
    systemctl --user stop $stale
fi
systemctl --user restart $services
