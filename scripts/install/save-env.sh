#!/usr/bin/env bash
# Saves Install's answers to ~/appdata/.env, which link-repo reads on every update and
# the units load: the service groups, the internal domain, and in internet mode the public domain
# the VPN's server is reached at.
set -e

# -p: Install continuing an earlier run finds it already there
mkdir -p "$HOME/appdata"
# Written next to it, then moved into place: Install run again takes a .env it finds as
# complete answers, which a run cut off midway through writing would not leave
{
    printf 'SERVICE_GROUPS=%s\nINTERNAL_DOMAIN=%s\n' "$SERVICE_GROUPS" "$INTERNAL_DOMAIN"
    # Empty in local mode
    [ -z "$PUBLIC_DOMAIN" ] || printf 'PUBLIC_DOMAIN=%s\n' "$PUBLIC_DOMAIN"
} > "$HOME/appdata/.env.partial"
mv "$HOME/appdata/.env.partial" "$HOME/appdata/.env"
