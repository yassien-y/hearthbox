#!/usr/bin/env bash
# Runs as: root
# Starts the user's services at boot, without anyone logging in.
set -e

loginctl enable-linger "$HEARTHBOX_USER"
echo "lingering enabled for $HEARTHBOX_USER"
