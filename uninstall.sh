#!/usr/bin/env bash
# Removes what install.sh set up, as root: stops every service, removes the port
# redirects, and deletes the rootless user with its home (~/repo, ~/appdata, images).
# Keeps /srv/hearthbox, with the media and downloads, and the packages the setup needed.
#
# Run it from any copy of the repo: sudo ./uninstall.sh

# Started with sh (dash on Debian and Ubuntu), which can't read the rest: run it with bash
if [ -z "$BASH_VERSION" ]; then
    command -v bash > /dev/null || { echo "uninstall.sh needs bash: install it, then run it again."; exit 1; }
    exec bash "$0" "$@"
fi
set -e

[ "$(id -u)" -eq 0 ] || { echo "Run as root, with sudo."; exit 1; }
# Asks to confirm, so input must be a terminal: without one, the read would end the
# script without a word
[ -t 0 ] || { echo "uninstall.sh is interactive: run it from a terminal"; exit 1; }

# A value from a file of KEY=value lines: file, then key. Empty if the file is missing.
env_value() { grep -m1 "^$2=" "$1" 2> /dev/null | cut -d= -f2-; }

# The user Install created, which it records first thing (create-user.sh)
[ -f /etc/hearthbox.env ] || { echo "Found no /etc/hearthbox.env: nothing is installed, nothing was removed."; exit 1; }
user="$(env_value /etc/hearthbox.env HEARTHBOX_USER)"
# Empty if Install stopped before creating the user: the steps for it are skipped
home="$(getent passwd "$user" | cut -d: -f6)"
# Read now: the file goes with the home. The groups say which router settings the
# message at the end asks to undo. Missing if Install stopped before saving them.
groups=" $(env_value "$home/appdata/.env" SERVICE_GROUPS) "
# The user's logs are named after its UID, which is gone once the user is deleted
[ -z "$home" ] || uid="$(id -u "$user")"

echo
echo "This will:"
if [ -n "$home" ]; then
    echo "  - disable lingering for $user, and stop all its services"
fi
echo "  - remove the port redirects (hearthbox-nftables.service and /etc/hearthbox.nft)"
# Only in their own mode: in another, a client in that place is the owner's own, not
# Install's
[[ "$groups" != *" netbird "* || ! -e /usr/local/bin/netbird ]] ||
    echo "  - remove NetBird's client: its service, /usr/local/bin/netbird, its state in /var/lib/netbird and its logs in /var/log/netbird"
[[ "$groups" != *" headscale "* || ! -e /usr/local/bin/tailscaled ]] ||
    echo "  - remove the Tailscale client: its service, /usr/local/bin/tailscale and tailscaled, /etc/default/tailscaled, and its state in /var/lib/tailscale and /var/cache/tailscale"
if [ -n "$home" ]; then
    echo "  - delete the user $user and its group, and DELETE $home with everything in it:"
    echo "    ~/repo with any changes you made, ~/appdata with every app's data, and the images"
fi
echo "  - delete /etc/profile.d/hearthbox.sh, which sets up $user's shell"
echo "  - delete /etc/hearthbox.env, Install's record of the user"
echo "It keeps /srv/hearthbox, with the media and downloads."
[ ! -e /sys/fs/selinux/enforce ] ||
    echo "  and resets its labels for containers back to the system's (SELinux)"
echo
# No by default: what it deletes can't be brought back
read -rp "Continue? [y/N] " answer
case "$answer" in [yY]*) ;; *) echo "Cancelled: nothing was removed."; exit 0 ;; esac

echo
if [ -n "$home" ]; then
    loginctl disable-linger "$user"
    echo "lingering disabled for $user"
    # Ends every session of the user, a shell open with sudo -iu included: userdel
    # refuses a user that still has processes running. Checked: logind doesn't know a
    # user with no session and no lingering.
    if loginctl show-user "$user" > /dev/null 2>&1; then
        loginctl terminate-user "$user"
    fi
    # Waits until every container and the Podman socket stopped: terminate-user doesn't
    systemctl stop "user@$uid.service"
    echo "sessions and services of $user stopped"
fi

# Checked: missing if Install stopped before setting them up, or a run that stopped
# further down already removed them
if [ -e /etc/systemd/system/hearthbox-nftables.service ]; then
    # Stopping it runs its ExecStop, which removes the rules from the kernel. Disabled,
    # so nothing loads them at boot.
    systemctl disable --now hearthbox-nftables.service
    rm /etc/systemd/system/hearthbox-nftables.service
    # systemd keeps the deleted unit loaded until it reloads
    systemctl daemon-reload
    echo "port redirects removed"
fi
# Outside the check: Install writes it just before the unit, so it can exist without it
rm -f /etc/hearthbox.nft

# Install's setup-netbird step installed it. Checked: missing if Install stopped before
# that step, or a run that stopped further down already removed it.
if [[ "$groups" == *" netbird "* && -e /usr/local/bin/netbird ]]; then
    # Stopping its service takes wt0 down with it. Checked: Install may have stopped
    # between installing the client and its service.
    if systemctl cat netbird.service > /dev/null 2>&1; then
        systemctl stop netbird.service
        netbird service uninstall
    fi
    # Its state holds this machine's identity on the deleted server
    rm -rf /usr/local/bin/netbird /var/lib/netbird /var/log/netbird
    echo "NetBird's client removed"
fi

# Install's setup-headscale step installed it. Checked: missing if Install stopped before
# that step, or a run that stopped further down already removed it.
if [[ "$groups" == *" headscale "* && -e /usr/local/bin/tailscaled ]]; then
    # Stopping it takes tailscale0 and its firewall rules down with it. Checked: Install
    # may have stopped between installing the client and its unit.
    if [ -e /etc/systemd/system/tailscaled.service ]; then
        systemctl disable --now tailscaled.service
        rm /etc/systemd/system/tailscaled.service
        # systemd keeps the deleted unit loaded until it reloads
        systemctl daemon-reload
    fi
    # Its state holds this machine's identity on the deleted Headscale
    rm -rf /usr/local/bin/tailscale /usr/local/bin/tailscaled /etc/default/tailscaled \
        /var/lib/tailscale /var/cache/tailscale
    echo "the Tailscale client removed"
fi

# Install labelled it for containers (create-srv-hearthbox.sh): back to the system's
# default, so confined services like Samba can use it again. Checked: it may have been
# moved or deleted since.
if [ -e /sys/fs/selinux/enforce ] && [ -d /srv/hearthbox ]; then
    restorecon -R /srv/hearthbox
    echo "/srv/hearthbox labels reset (SELinux)"
fi

if [ -n "$home" ]; then
    # Its services logged to a journal of its own, outside the home. Rotating first makes
    # journald close the file it writes to, so the deleted files free their space.
    journalctl --rotate
    rm -f /var/log/journal/*/"user-$uid".journal /var/log/journal/*/"user-$uid"@* \
          /run/log/journal/*/"user-$uid".journal /run/log/journal/*/"user-$uid"@*
    echo "deleted the logs of $user's services"

    # As late as possible: until the user is gone, a run that stopped at any step above
    # can run again and redo it. -r deletes the home with it. Its group goes too, since
    # useradd created it for this user.
    userdel -r "$user"
    echo "deleted user $user and $home"
fi

# -f: missing if Install stopped before writing it, or a run that stopped below already
# removed it
rm -f /etc/profile.d/hearthbox.sh
echo "deleted /etc/profile.d/hearthbox.sh"

# Last: until it's gone, a run that stopped above can run again and find the user
rm /etc/hearthbox.env
echo "deleted /etc/hearthbox.env"

echo
echo "Done. Kept /srv/hearthbox, with your media and downloads: delete it yourself if you"
echo "don't need it. The setup needed podman, git and nftables (and curl, in internet"
echo "mode): they're still installed. Remove them with your package manager if nothing"
echo "else uses them. Your devices can remove the server's root certificate: it's harmless"
echo "to keep, since its key is deleted."
# The router settings from docs/setup.md now point at services that are gone, and
# uninstall.sh can't change the router
echo
if [[ "$groups" == *" lan "* ]]; then
    echo "IMPORTANT: your router still gives out this machine as the network's DNS server,"
    echo "which no longer answers. Until you change it, devices on your network can't open"
    echo "any website. In the router's DHCP or LAN settings, set the DNS server back to"
    echo "automatic (or to the router's own address), then reconnect your devices."
elif [[ "$groups" == *" netbird "* ]]; then
    echo "IMPORTANT: NetBird's server is gone, so your devices' NetBird apps can no longer"
    echo "connect. On your router, close ports 443 (TCP) and 3478 (UDP) to this machine, and"
    echo "delete the DNS record for nbs.<public-domain>."
elif [[ "$groups" == *" headscale "* ]]; then
    echo "IMPORTANT: Headscale is gone, so your devices' Tailscale apps can no longer connect"
    echo "to it. On your router, close ports 443 (TCP) and 3478 (UDP) to this machine, and"
    echo "delete the DNS record for hs.<public-domain>."
fi
