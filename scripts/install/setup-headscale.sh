#!/usr/bin/env bash
# Runs as: root
# Internet mode with Headscale, last step, after the services started: makes this machine
# a device in its own Headscale network, so the other devices reach nginx at its address
# there.
# - Installs the Tailscale client, which Headscale's devices run, as a system service. It
#   creates the tailscale0 interface nftables redirects from (setup-nftables.sh). It's the
#   one part of the setup that keeps running as root once Install is done: the other root
#   steps only configure the system during Install. Headscale doesn't support a client
#   on its own machine ("might work, but it is not supported", headscale.net FAQ): this
#   setup needs it, since devices reach nginx through it.
# - Stops until the owner has pointed the public name at this machine and opened the
#   router, shows what to set, and checks that Headscale answers there on Enter.
# - Creates Headscale's user, which owns every device, and a one-off key this machine
#   joins with.
# Each <service>.<internal-domain> then points at this machine's new address: Headscale's unit
# follows tailscale0's address in the background (scripts/containers/headscale-records.sh).
# Headscale is called on this machine (127.0.0.1:9443), with the public name, so the
# certificate checks out without going out to the internet and back.
set -e

host="hs.$PUBLIC_DOMAIN"
url="https://$host"

# A command as the Hearthbox user, in a session of its own, which rootless Podman and
# systemctl --user need (as install.sh's run_step)
as_user() { systemd-run --uid="$HEARTHBOX_USER" --property=PAMName=login --pipe --wait --quiet "$@"; }
# The headscale command, in its container
headscale() { as_user podman exec headscale headscale "$@"; }

# The client: a version Headscale supports, which is the last 10 releases
# (headscale.net/stable/about/clients). Only Install installs it, so hearthbox pull
# doesn't update it: Install run again installs the version pinned here, which runs from
# the next reboot (it doesn't restart the running client).
version=1.104.7
case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "The Tailscale client has no build for $(uname -m)."; exit 1 ;;
esac
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${version}_$arch.tgz" |
    tar -xz -C "$tmp" --strip-components=1
install -m 755 "$tmp/tailscale" "$tmp/tailscaled" /usr/local/bin/
# Its unit, from the same download, which expects the client in /usr/sbin: changed to
# where it is, outside the distro's folders. The unit reads its port and flags from
# /etc/default/tailscaled, which must exist: the download's defaults.
sed 's|/usr/sbin/tailscaled|/usr/local/bin/tailscaled|g' "$tmp/systemd/tailscaled.service" \
    > /etc/systemd/system/tailscaled.service
install -m 644 "$tmp/systemd/tailscaled.defaults" /etc/default/tailscaled
systemctl daemon-reload
systemctl enable --now tailscaled.service
echo "Tailscale client $version installed in /usr/local/bin"

# What public-name.sh needs, then its wait
sub=hs server=Headscale
# shellcheck source-path=SCRIPTDIR source=public-name.sh
. "$(dirname "$0")/public-name.sh"
# -s without -S: public-name.sh's message says more than curl's error. 60 seconds: getting
# the certificate takes Let's Encrypt a while.
server_answers() { curl --connect-to "$host:443:127.0.0.1:9443" -fs --max-time 60 -o /dev/null "$url/health"; }
wait_for_public_name

# Install run again after this machine joined finds it already in.
if ! tailscale ip -4 > /dev/null 2>&1; then
    # This server's Headscale user, named after the Hearthbox user. Created once: Install
    # run again after that finds it. Its ID, a number, is what keys need.
    user_id() { headscale users list -n "$HEARTHBOX_USER" -o json-line | grep -o '"id":[0-9]*' | head -n 1 | cut -d: -f2; }
    id="$(user_id)"
    if [ -z "$id" ]; then
        headscale users create "$HEARTHBOX_USER" > /dev/null
        id="$(user_id)"
        echo "Headscale's user $HEARTHBOX_USER created"
    fi
    # A one-off key for this machine to join with, valid for an hour. json-line: compact
    # JSON, which the greps match; plain json is indented, with spaces after the colons.
    key="$(headscale preauthkeys create --user "$id" --expiration 1h -o json-line |
        grep -o '"key":"[^"]*"' | head -n 1 | cut -d'"' -f4)"
    # --accept-dns=false: this machine keeps its own DNS server, which Tailscale's would
    # replace. Its services are reached from the other devices, not from here.
    tailscale up --login-server "$url" --auth-key "$key" --accept-dns=false
fi

echo
echo "To add a device: install the Tailscale app, set its server to $url (docs/setup.md,"
echo "\"Internet mode with Headscale\"), and log in. It shows a command with an ID: run it"
echo "here, as $HEARTHBOX_USER, starting with podman exec headscale:"
echo "  sudo -iu $HEARTHBOX_USER podman exec headscale headscale auth register --user $HEARTHBOX_USER --auth-id <ID>"
