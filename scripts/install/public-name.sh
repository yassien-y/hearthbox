# shellcheck shell=bash
# The variables the sourcing script sets (below) are unassigned to shellcheck here
# shellcheck disable=SC2154
# Sourced by setup-netbird.sh and setup-headscale.sh, internet mode's last steps: the wait
# until the VPN's server answers at its public name. Not a step of its own: it needs the
# server running, and each VPN checks its server differently.
# The sourcing script sets host (the public name), sub (the name's first label, the DNS
# record's host) and server (the server's name in messages), and defines server_answers,
# which succeeds once the server answers at $host with a valid certificate.

# Where the DNS record and the router must point: this machine's LAN address (the
# IPv4 port forward's target) and its stable global IPv6 addresses, without the
# temporary ones that change every few hours
lan_ip="$(ip -4 -o route get 1.1.1.1 2> /dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p')"
ipv6="$(ip -6 -o addr show scope global -temporary -deprecated 2> /dev/null |
    awk '{ sub("/.*", "", $4); print $4 }' | xargs)"

# The addresses the public name has, empty if none: a lookup before the record existed
# stays cached for a while, so cleared first where systemd-resolved runs. At most 8
# seconds, like the local mode check.
resolve() {
    resolvectl flush-caches 2> /dev/null
    # --no-addrconfig: every record, AAAA too, even on a server without IPv6
    timeout 8 getent --no-addrconfig ahosts "$host" | awk '{ print $1 }' | sort -u | xargs
}
# IPv6 addresses the name has that aren't this server's, empty if none. Checked here,
# with nothing outside: Let's Encrypt tries an AAAA record first, so a wrong one fails
# its check even when the A record is right. The A record can't be checked from here:
# only something outside sees the home's public IPv4.
wrong_ipv6() {
    local addr
    for addr in $addrs; do
        [[ "$addr" == *:* && " $ipv6 " != *" $addr "* ]] && printf '%s ' "$addr"
    done
    true
}
# The server answers once it has its certificate, which it gets from Let's Encrypt at
# the first connection: Let's Encrypt connects to the public name, port 443. Only once
# the name resolves and no AAAA record points elsewhere: a failed validation counts
# against Let's Encrypt's 5 per name per hour.
check() {
    addrs="$(resolve)" wrong=""
    [ -n "$addrs" ] || return 1
    wrong="$(wrong_ipv6)"
    [ -z "$wrong" ] || return 1
    server_answers
}

wait_for_public_name() {
    local stop="(Ctrl+C stops Install: run it again to continue)"
    echo
    echo "Set up your public domain and router now, so devices and Let's Encrypt reach $server"
    echo "at $host from the internet (docs/setup.md, \"Internet mode\")."
    echo "Use IPv4, IPv6, or both: each needs its own steps."
    echo
    echo "For each DNS record at your public domain's DNS provider:"
    echo "  - Host (or Name): $sub. The provider adds the rest: check the record list then shows"
    echo "    exactly $host, not $host.$PUBLIC_DOMAIN."
    echo "  - Proxy (Cloudflare's orange cloud and the like): off, \"DNS only\". A proxied record"
    echo "    points at the provider instead of your home, and $server can't work through it."
    echo
    echo "If you use IPv4:"
    echo "  1. Check that your internet provider gives you a public IPv4 of your own: the internet"
    echo "     (WAN) address on your router's status page must match the address a \"what is my"
    echo "     IP\" website shows you from home. If they differ, your provider shares one IPv4"
    echo "     between many customers (CGNAT; the router's address often starts with 100.64 to"
    echo "     100.127). Nothing on the internet can then reach this server over IPv4, and no"
    if [ -n "$ipv6" ]; then
        echo "     setting on your router changes that: use IPv6 instead (skip the IPv4 steps), or"
        echo "     ask your internet provider for a static public IPv4 address."
    else
        echo "     setting on your router changes that. This server has no IPv6 to use instead:"
        echo "     ask your internet provider for a static public IPv4 address."
    fi
    echo "  2. At your public domain's DNS provider, create an A record: host $sub, value your home's"
    echo "     public IPv4 address"
    echo "  3. On your router, forward TCP port 443 and UDP port 3478 to this server, $lan_ip,"
    echo "     on the same ports"
    echo
    if [ -n "$ipv6" ]; then
        echo "If you use IPv6:"
        echo "  1. At your public domain's DNS provider, create an AAAA record: host $sub, value this"
        echo "     server's IPv6 address, $ipv6"
        echo "  2. On your router, add a firewall rule letting TCP port 443 and UDP port 3478 in to"
        echo "     $ipv6"
    else
        echo "This server has no IPv6 address, so only IPv4 can work."
    fi
    echo
    echo "Then press Enter: Install checks that $host answers. Let's Encrypt allows 5 failed"
    echo "checks per hour, so finish first."
    read -rp "Press Enter when done $stop " _
    until check; do
        echo
        if [ -z "$addrs" ]; then
            echo "$host doesn't resolve yet. Check that:"
            echo "  - its A or AAAA record exists at your public domain's DNS provider, with the name $sub"
            echo "  - it had time to spread: a new record can take a few minutes, sometimes longer"
        elif [ -n "$wrong" ]; then
            echo "$host has an AAAA record that isn't this server: $wrong"
            if [ -n "$ipv6" ]; then
                echo "Change it at your public domain's DNS provider to this server's IPv6: $ipv6"
            else
                echo "This server has no IPv6: delete the AAAA record at your public domain's DNS provider,"
                echo "and keep only the A record."
            fi
            echo "Let's Encrypt wasn't asked yet, so this cost none of its 5 failed checks per hour."
        else
            echo "$host doesn't answer with a valid certificate yet. It points at: $addrs"
            echo "If you use IPv4, check that:"
            echo "  - the A record is your home's public IPv4, the address a \"what is my IP\" website"
            echo "    shows you from home"
            echo "  - your router forwards TCP port 443 and UDP port 3478 to $lan_ip"
            echo "  - your router's internet (WAN) address is that same public IPv4. If it differs,"
            echo "    your provider uses CGNAT, and no port forward can reach this server over IPv4:"
            if [ -n "$ipv6" ]; then
                echo "    delete the A record and use IPv6 instead, or ask your internet provider for a"
                echo "    static public IPv4 address"
            else
                echo "    this server has no IPv6 to use instead, so ask your internet provider for a"
                echo "    static public IPv4 address"
            fi
            if [ -n "$ipv6" ]; then
                echo "If you use IPv6, check that:"
                echo "  - your router lets TCP port 443 and UDP port 3478 in to $ipv6"
            fi
            echo "Let's Encrypt allows 5 failed checks per hour: fix it first, then check again."
        fi
        read -rp "Press Enter to check again $stop " _
    done
}
