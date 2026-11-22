#!/bin/sh
# netbird-server's unit runs it in ExecStartPre (vpn/netbird-server.container).
# NetBird can't read the internal and public domains from its environment: this fills
# ${PUBLIC_DOMAIN} and ${INTERNAL_DOMAIN} (the dashboard's address) into the repo's
# config/netbird/config.yaml, and writes the result where the unit mounts it. At every
# start, so an edit in the repo applies at the next one.
set -e
out="${XDG_RUNTIME_DIR:?}/hearthbox/netbird.yaml"
mkdir -p "$(dirname "$out")"
sed -e "s/\${PUBLIC_DOMAIN}/${PUBLIC_DOMAIN:?}/g" -e "s/\${INTERNAL_DOMAIN}/${INTERNAL_DOMAIN:?}/g" \
    "$HOME/repo/config/netbird/config.yaml" > "$out"
