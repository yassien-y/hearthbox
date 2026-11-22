#!/bin/sh
# Writes Headscale's DNS records, ~/appdata/headscale/records/extra-records.json
# (config/headscale/config.yaml): one per name in nginx's map, and one for ca (where
# devices download the CA's root certificate, served by nginx outside its map), each
# <name>.<internal-domain> pointing at this machine's address in Headscale's network, on
# tailscale0. Each name, not *.<internal-domain>: the Tailscale app only looks up exact names.
# Headscale reloads the file when it changes, so nothing restarts.
# Headscale's unit runs it in the background for as long as Headscale runs
# (vpn/headscale.container). It writes the records when it starts, which every hearthbox
# update and boot does, so a change to the map applies then; and again at every change of
# tailscale0's address, e.g. when it gets it at boot, or after this machine joined
# Headscale again.
set -e

file="$HOME/appdata/headscale/records/extra-records.json"

write() {
    addr="$(ip -4 -o addr show dev tailscale0 2> /dev/null | awk '{ sub("/.*", "", $4); print $4; exit }')"
    # No address (tailscaled stopped, or not connected to Headscale yet): the file keeps
    # the last records. An empty list would remove every name until the address is back,
    # and it comes back the same unless this machine joins Headscale again.
    [ -n "$addr" ] || return 0
    records=""
    for name in ca $(sh "$HOME/repo/scripts/containers/service-names.sh"); do
        records="$records${records:+,}{\"name\":\"$name.$INTERNAL_DOMAIN\",\"type\":\"A\",\"value\":\"$addr\"}"
    done
    # Written next to it, then moved into place: Headscale, now or at its next start, never
    # reads a file cut off midway. Chained with &&, not left to set -e: the loop below
    # calls this with ||, which switches set -e off inside it.
    printf '[%s]\n' "$records" > "$file.tmp" &&
        mv "$file.tmp" "$file" &&
        echo "records under $INTERNAL_DOMAIN point at $addr"
}

write || echo "couldn't write the records" >&2
# Every IPv4 address change, on any interface: monitoring tailscale0 alone fails while the
# interface doesn't exist. A failed write, here or above, mustn't end the script: nothing
# starts it again until Headscale restarts.
ip -4 -o monitor address | while read -r line; do
    case "$line" in *tailscale0*) write || echo "couldn't write the records" >&2 ;; esac
done
