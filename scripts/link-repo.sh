#!/usr/bin/env bash
# Links the repo into place, so the links match the repo and SERVICE_GROUPS exactly:
# links that shouldn't exist anymore are removed. Stops if a destination exists and
# isn't a link.
set -e

link() {
    mkdir -p "$(dirname "$2")"
    # ln would put the link inside a real folder, or delete a real file
    if [ -e "$2" ] && [ ! -L "$2" ]; then
        echo "$2 exists and isn't a link: move it or delete it, then run again"
        exit 1
    fi
    ln -sfn "$1" "$2"
    echo "linked $2 -> $1"
}

unlink() {
    rm "$1"
    echo "unlinked $1"
}

units="$HOME/.config/containers/systemd"

# Which group folders this host has, from what Install saved. The spaces around it let
# the test below match whole names only.
groups=" $(grep -m1 '^SERVICE_GROUPS=' "$HOME/appdata/.env" | cut -d= -f2-) "

# Units directly in containers/, the shared drop-in folders (*.d) and core/ are always
# linked. Every other folder is a group: linked only if this host has it, and its link
# removed if it no longer does. vpn/ isn't one, so it's never linked whole: it holds both
# internet mode VPNs' units (below).
for item in "$REPO"/containers/*; do
    name="${item##*/}"
    if [[ -d "$item" && "$name" != *.d && "$name" != core && "$groups" != *" $name "* ]]; then
        if [ -L "$units/$name" ]; then unlink "$units/$name"; fi
    else
        link "$item" "$units/$name"
    fi
done
# vpn/ holds the units of two groups, netbird and headscale, each file named after its
# group (netbird-server.container, headscale.container, ...). Only this host's group's
# files are linked, one by one, and the other's links removed: never both, since both
# VPNs' servers publish the same ports.
for item in "$REPO"/containers/vpn/*; do
    name="${item##*/}"
    # The group: the name up to its first - or .
    if [[ "$groups" == *" ${name%%[-.]*} "* ]]; then
        link "$item" "$units/$name"
    elif [ -L "$units/$name" ]; then
        unlink "$units/$name"
    fi
done
# A unit or folder the repo no longer has: its link points nowhere
for item in "$units"/*; do
    if [ -L "$item" ] && [ ! -e "$item" ]; then unlink "$item"; fi
done
link "$REPO/scripts/hearthbox" "$HOME/.local/bin/hearthbox"