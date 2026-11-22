#!/usr/bin/env bash
# Runs as: root
# Files shared between services (media, downloads, photos), writable by the containers,
# in a folder of their own under /srv, named after the project: the internal domain can change,
# the files stay put. Root, because /srv is root's: the folders inside it are created
# by the services that mount them, as they start (scripts/containers/create-folders.sh).
set -e
srv="/srv/hearthbox"

mkdir -p "$srv"
# -R: /srv/hearthbox outlives Uninstall, and the new user may get another user ID than the
# one whose files are already there. Owner only: groups someone set on purpose stay.
# Symbolic links aren't followed (-R's default), so a link can't hand over a file
# outside it.
chown -R "$HEARTHBOX_USER" "$srv"
echo "$srv, with everything in it, owned by $HEARTHBOX_USER"
# With SELinux, containers may only use files labelled container_file_t. Labelled here,
# once, instead of :z on the mounts, which would relabel the whole library at every
# container start. New files and folders inherit the label from their folder. -R:
# /srv/hearthbox outlives Uninstall, which resets its labels, so Install relabels what's
# already there.
if [ -e /sys/fs/selinux/enforce ]; then
    chcon -R -t container_file_t "$srv"
    echo "$srv labelled for containers (SELinux)"
fi
