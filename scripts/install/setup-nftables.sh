#!/usr/bin/env bash
# Runs as: root
# Redirects ports 80 and 443 to nginx's published ports 8080 and 8443 in the kernel
# (nftables), so rootless nginx needs no privileged port. The rules hold no IP: they
# match packets for any of this machine's own addresses, checked per packet, so they keep
# working when an address changes.
# The rules load at boot from a service of our own, hearthbox-nftables: every distro's
# nftables.service reads a different file, and some (Debian's) flush every other rule
# first, including Podman's.
set -e

dns_nat="" dns_local="" dns_filter="" vpn_if=""
case " $SERVICE_GROUPS " in
    *" netbird "*) vpn_if=wt0 vpn_name=NetBird ;;
    *" headscale "*) vpn_if=tailscale0 vpn_name=Headscale ;;
esac
if [ -n "$vpn_if" ]; then
    # Internet mode: nginx only for the VPN's devices, whose traffic arrives on its
    # client's interface: NetBird's wt0 (setup-netbird.sh) or Tailscale's tailscale0
    # (setup-headscale.sh). Port 443 from anywhere else, and from this machine itself (its
    # own client), is for the VPN's server, rootless on 9443. So this machine can't open
    # the services itself.
    from=$vpn_if
    prerouting="iifname \"$vpn_if\" fib daddr type local tcp dport 80 redirect to :8080
        iifname \"$vpn_if\" fib daddr type local tcp dport 443 redirect to :8443
        fib daddr type local tcp dport 443 redirect to :9443"
    output='fib daddr type local tcp dport 443 redirect to :9443'
else
    # Local mode: any interface, so devices on the LAN reach nginx, and this machine too
    from="any interface"
    prerouting='fib daddr type local tcp dport 80 redirect to :8080
        fib daddr type local tcp dport 443 redirect to :8443'
    output="$prerouting"
    # Local mode also answers the LAN's DNS: CoreDNS can't bind port 53 rootless, so it's
    # published on 1053 (lan/coredns.container). DNS uses udp, and tcp for long answers.
    dns_nat='fib daddr type local meta l4proto { tcp, udp } th dport 53 redirect to :1053'
    # This machine's own queries too: once the router hands out this machine as the DNS
    # server, it uses it itself. Except systemd-resolved's own addresses, which are the
    # system's resolver, not a DNS server for the LAN.
    dns_local="ip daddr { 127.0.0.53, 127.0.0.54 } meta l4proto { tcp, udp } th dport 53 accept
        $dns_nat"
    dns_filter='meta l4proto { tcp, udp } th dport 1053 ct status dnat accept
        meta l4proto { tcp, udp } th dport 1053 drop'
fi

cat > /etc/hearthbox.nft <<NFT
# Written by install.sh (scripts/install/setup-nftables.sh), loaded by hearthbox-nftables.service.
table inet hearthbox {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        # fib daddr type local: only traffic for this machine, never traffic routed through it
        ${prerouting}
        ${dns_nat}
    }
    # Traffic this machine sends to itself (localhost, or its own address) never passes
    # prerouting: the redirects it needs, from here
    chain output {
        type nat hook output priority dstnat; policy accept;
        ${output}
        ${dns_local}
    }
    # nginx (and CoreDNS) are published on every interface: only traffic redirected above
    # may reach them
    chain input {
        type filter hook input priority filter;
        tcp dport { 8080, 8443 } ct status dnat accept
        tcp dport { 8080, 8443 } drop
        ${dns_filter}
    }
}
NFT

cat > /etc/systemd/system/hearthbox-nftables.service <<'UNIT'
# Written by install.sh (scripts/install/setup-nftables.sh)
[Unit]
Description=Hearthbox port redirects
# Loaded before the network comes up, so nginx and CoreDNS are never reachable on their
# published ports without the drop rules. Like the distros' nftables.service, it skips
# the default dependencies, which would hold networking back until basic.target.
DefaultDependencies=no
Wants=network-pre.target
Before=network-pre.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=nft -f /etc/hearthbox.nft
ExecStop=nft delete table inet hearthbox

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable hearthbox-nftables.service
# Restart, not start: Install run again loads the rules just written, where start would
# leave the ones already loaded. Its ExecStop removes the old table first.
systemctl restart hearthbox-nftables.service
echo "redirect active: ports 80 and 443 on $from -> 8080 and 8443 (nginx)"
[ -z "$vpn_if" ] || echo "redirect active: port 443 elsewhere -> 9443 ($vpn_name)"
[ -z "$dns_nat" ] || echo "redirect active: DNS (port 53) on $from and this machine -> 1053"
