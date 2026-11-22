#!/usr/bin/env bash
# Runs as: root
# Switching to the Hearthbox user (sudo -iu) starts no session of its own, so nothing sets
# XDG_RUNTIME_DIR, which systemctl --user and podman need. Every login shell reads
# /etc/profile.d/, so the file sets it there, for the Hearthbox user only, and puts
# ~/.local/bin on PATH, where link-repo.sh links the hearthbox command. uninstall.sh
# deletes it.
set -e

# Read at every login, by every user: it sets nothing for anyone else, and leaves a
# value a real session set alone. The folder exists while lingering runs the user's
# systemd. grep, not ". /etc/hearthbox.env": its variable would land in every user's
# shell, and a missing file would break their login.
cat > /etc/profile.d/hearthbox.sh <<'PROFILE'
# Written by Hearthbox's install.sh (scripts/install/setup-shell-env.sh)
if grep -qx "HEARTHBOX_USER=$(id -un)" /etc/hearthbox.env 2> /dev/null; then
    if [ -z "$XDG_RUNTIME_DIR" ] && [ -d "/run/user/$(id -u)" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi
    # Not every distro's shell files put it on PATH. Once: a shell that reads this again
    # doesn't add it twice.
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
fi
PROFILE
echo "/etc/profile.d/hearthbox.sh written"
