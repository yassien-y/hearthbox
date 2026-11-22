#!/usr/bin/env bash
# Enables the Podman API socket, for Glance's containers widget.
# Needs lingering, so the user's systemd is running.
set -e

systemctl --user enable --now podman.socket
