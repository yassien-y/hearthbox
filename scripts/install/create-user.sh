#!/usr/bin/env bash
# Runs as: root
# Creates the rootless user that owns every container. On a first run, install.sh made
# sure it didn't exist; Install run again takes it from /etc/hearthbox.env, so it's the
# user an earlier run created. useradd also gives it the subordinate UID/GID ranges
# rootless Podman needs.
set -e

# Recorded before anything else changes, so uninstall.sh finds the user even when a
# later step fails and leaves Install half done
printf 'HEARTHBOX_USER=%s\n' "$HEARTHBOX_USER" > /etc/hearthbox.env
echo "/etc/hearthbox.env written"

# Install continuing an earlier run finds the user that run created
if id "$HEARTHBOX_USER" > /dev/null 2>&1; then
    echo "user $HEARTHBOX_USER exists"
else
    useradd --create-home "$HEARTHBOX_USER"
    echo "created user $HEARTHBOX_USER"
fi
# useradd gives ranges only if /etc/subuid and /etc/subgid exist and /etc/login.defs
# allows them (SUB_UID_COUNT): without, rootless Podman fails at the first container start
grep -q "^$HEARTHBOX_USER:" /etc/subuid && grep -q "^$HEARTHBOX_USER:" /etc/subgid ||
    { echo "$HEARTHBOX_USER has no /etc/subuid or /etc/subgid range: rootless Podman won't work"; exit 1; }
