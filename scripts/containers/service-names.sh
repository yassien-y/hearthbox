#!/bin/sh
# Prints the name of every service in nginx's map, one per line: renew-cert.sh signs the
# certificate for <name>.<internal-domain>, and headscale-records.sh gives Headscale a DNS record
# for each. Not the map's comment lines, which nginx allows there.
awk '/^map \$sub \$backend \{/ { inside = 1; next }
    inside && /^\}/ { exit } inside && NF && $1 !~ /^#/ { print $1 }' \
    "$HOME/repo/config/nginx/conf.d/sites.conf"
