#!/bin/sh
# CoreDNS's unit runs it in ExecStartPre. Finds the router and this machine's address
# on the LAN, and writes them to the file the unit loads. So nobody sets them, and a
# changed address is picked up at the next start.
set -e
out="${XDG_RUNTIME_DIR:?}/hearthbox/lan.env"
mkdir -p "$(dirname "$out")"
# The router: the main table's default route through one (via). A VPN sends the
# internet through its own table or narrower routes and leaves this one, and its tunnel
# has no router. With several (Wi-Fi and Ethernet), the lowest metric: the one in use.
# Unquoted on purpose: set -- splits awk's line into $1 (metric), $2 (router), $3 (dev)
# shellcheck disable=SC2046
set -- $(ip -4 route show table main default |
    awk '{ v = ""; d = ""; m = 0
           for (i = 1; i < NF; i++) {
               if ($i == "via") v = $(i + 1)
               if ($i == "dev") d = $(i + 1)
               if ($i == "metric") m = $(i + 1)
           }
           if (v != "") print m, v, d }' |
    sort -n | head -n 1)
router="$2" dev="$3"
# This machine's address: the router's interface's own, since not every network
# manager writes it on the route
[ -z "$dev" ] ||
    lan_ip="$(ip -4 -o addr show dev "$dev" scope global | awk '{ sub("/.*", "", $4); print $4; exit }')"
[ -n "$lan_ip" ] || { echo "Found no router: is this machine connected to the local network?" >&2; exit 1; }
printf 'LAN_IP=%s\nDNS_UPSTREAM=%s\n' "$lan_ip" "$router" > "$out"
