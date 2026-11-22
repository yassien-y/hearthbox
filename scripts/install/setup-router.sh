#!/usr/bin/env bash
# Runs as: root
# Local mode's last step, after the services started: Install stops until the router
# hands out this machine as the network's DNS server, which local mode can't work
# without. Then this machine asks itself for its names too: it gets its network
# settings from the router (docs/setup.md), and the nftables rules send its own DNS
# queries to CoreDNS (setup-nftables.sh). So once this machine's connection is renewed
# (by Install where it knows how, otherwise by the user) and its lookup of home.<internal-domain>
# answers with its own address, the router change works. Root, to renew the connection,
# and so it runs in Install's own process: Ctrl+C at its prompt then stops it, while a
# user step's service would keep running.
set -e

# The address CoreDNS answers with, found by find-lan.sh at CoreDNS's start
lan_ip="$(sed -n 's/^LAN_IP=//p' "/run/user/$(id -u "$HEARTHBOX_USER")/hearthbox/lan.env")"

# How Install renews this machine's connection, so it gets the router's new DNS server,
# by what manages the interface with the LAN address. Empty: nothing Install knows, so
# the user reconnects it. pause: the connection drops for a few seconds while it does.
# settle: the command returns before the new lease and DNS server apply.
dev="$(ip -4 -o addr show | awk -v ip="$lan_ip" '{ split($4, a, "/") } a[1] == ip { print $2; exit }')"
# Set empty first: a renew, pause or settle variable in the environment would otherwise
# run as the renew command, show the drop note, or add a wait
renew=() pause="" settle=""
# Each test comes back empty or false where its tool isn't installed or doesn't manage
# the interface. NetworkManager: only a connection it set up itself ("connected", not
# "connected (externally)", untranslated), by its UUID, which needs no escaping. It has
# no renew command: reconnecting is how it gets a new lease. --wait 8: an Enter returns
# even if the reconnect hangs; NetworkManager keeps reconnecting by itself.
if [ "$(LC_ALL=C nmcli -g GENERAL.STATE device show "$dev" 2> /dev/null)" = "100 (connected)" ]; then
    renew=(nmcli --wait 8 connection up "$(nmcli -g GENERAL.CON-UUID device show "$dev")") pause=yes
# systemd-networkd: any setup state but "unmanaged" ("configured", "configuring", ...)
elif setup="$(networkctl list --no-legend "$dev" 2> /dev/null | awk '{ print $5 }')" &&
    [ -n "$setup" ] && [ "$setup" != unmanaged ]; then
    renew=(networkctl renew "$dev") settle=yes
# dhcpcd: only with an instance running for it, which has a control socket. Without one,
# dhcpcd -N starts a new instance. -4 also reaches an IPv4-only instance, the one
# Debian's ifupdown starts.
elif [ -S "/run/dhcpcd/$dev-4.sock" ] || [ -S "/run/dhcpcd/$dev.sock" ] || [ -S /run/dhcpcd/sock ]; then
    renew=(dhcpcd -4 -N "$dev") settle=yes
# ifupdown with dhclient (Debian upgraded from 12), which can't renew without releasing.
# ifupdown names dhclient's pid file after the interface; another ifupdown interface
# (static, or dhcpcd whose instance stopped) has nothing to renew. No time cap: killing
# ifup partway leaves the interface without an address, and an SSH session cut off.
elif [ -n "$(ifquery --state "$dev" 2> /dev/null)" ] && [ -e "/run/dhclient.$dev.pid" ]; then
    ifupdown_renew() { ifdown "$dev" && ifup "$dev"; }
    renew=(ifupdown_renew) pause=yes
fi

# The address home.<internal-domain> has for this machine, empty if it has none
lookup() {
    # A lookup before the change ("no such name", from the router) stays cached for a
    # while: cleared first, where systemd-resolved runs
    resolvectl flush-caches 2> /dev/null
    # At most 8 seconds: CoreDNS on this machine answers in milliseconds, while a lookup
    # nothing answers waits on every DNS server it has (42 seconds, measured on a laptop)
    timeout 8 getent ahostsv4 "home.$INTERNAL_DOMAIN" | awk '{ print $1; exit }'
}

# Renews this machine's connection where Install knows how, then looks up home.<internal-domain>
# once, so an Enter comes back within seconds (ifupdown's renewal apart, see above): a
# failure waits for the user's next Enter, which renews and checks again. The renewing
# command's output is only a success message; errors still show. Runs only as the
# loop's condition, where set -e is off: a failed renew is said.
check() {
    if [ ${#renew[@]} -gt 0 ]; then
        echo "renewing this server's connection"
        "${renew[@]}" > /dev/null || echo "renewing failed: see the message above"
        [ -z "$settle" ] || sleep 2
    fi
    [ "$(lookup)" = "$lan_ip" ]
}

stop="(Ctrl+C stops Install: run it again to continue)"
echo
echo "Set up your router now: it must hand out this server as the network's DNS server. On"
echo "your router's settings page (docs/setup.md, \"Set up your router\"):"
echo "  1. Reserve this server's address, $lan_ip, for it (\"DHCP reservation\", \"static lease\")"
echo "  2. Set the DNS server it hands out (DHCP or LAN settings) to $lan_ip"
if [ ${#renew[@]} -eq 0 ]; then
    echo "  3. Reconnect this server to the network (its cable, or its Wi-Fi off and on)"
    echo "Then press Enter: Install checks that this server gets the change."
else
    echo "Then press Enter: Install renews this server's connection, so it gets the change, and"
    echo "checks it."
fi
if [ -n "$pause" ]; then
    echo "Its connection drops for a few seconds then: over SSH, the session freezes and"
    echo "carries on, since the server keeps the address you reserved in step 1."
fi
read -rp "Press Enter when done $stop " _
until check; do
    echo
    echo "This server doesn't get itself as DNS server from the router yet. Check that:"
    echo "  - the router hands out $lan_ip as DNS server, and the change is saved"
    [ ${#renew[@]} -gt 0 ] ||
        echo "  - this server was reconnected to the network after the change"
    echo "  - this server gets its network settings from the router (automatic, DHCP): an"
    echo "    address or DNS server typed into its own network settings ignores the router"
    read -rp "Press Enter to check again $stop " _
done
echo "this server gets itself as DNS server: home.$INTERNAL_DOMAIN is $lan_ip"
