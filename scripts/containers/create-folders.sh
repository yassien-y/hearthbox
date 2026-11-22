#!/bin/sh
# Every unit runs it in ExecStartPre (container.d/00-common.conf), with its own name.
# Podman won't create missing bind-mount folders, so this creates the ones the unit
# mounts from ~/appdata and /srv/hearthbox, right before it starts. Other paths (the
# repo's config, system files) must already exist: an empty one would hide a mistake.
set -e

# The unit's own file and drop-ins, among the linked units: -L follows the links into
# the repo. Only the host side of each Volume= line, with systemd's %h filled in.
find -L "$HOME/.config/containers/systemd" \
        \( -name "$1.container" -o -path "*/$1.container.d/*.conf" \) -exec cat {} + |
    sed -n 's/^Volume=\([^:]*\):.*/\1/p' |
    sed "s|^%h|$HOME|" |
    grep -E "^($HOME/appdata|/srv/hearthbox)(/|$)" |
    while read -r dir; do mkdir -p "$dir"; done
