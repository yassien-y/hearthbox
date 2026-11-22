#!/usr/bin/env bash
# Sets up a host as root: checks that the commands it needs are installed, creates the
# rootless Hearthbox user, runs the steps in scripts/install/, then scripts/update.sh,
# then the last step for the mode (setup-router, setup-netbird or setup-headscale).
# On a host that already has an installation, finished or not, it continues it with its
# saved settings, so running it again after it was cut off picks up where it stopped.
# Starting over is uninstall.sh, then Install. Between them, the user keeps it up to
# date with hearthbox pull and hearthbox update, which need no root.
#
# Run it from curl, which clones the repo itself:
#   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/yassien-y/hearthbox/master/install.sh)"
# or from a clone of the repo: sudo ./install.sh
#
# Each step runs as the rootless Hearthbox user, unless its script has a "# Runs as: root" line.

# Started with sh (dash on Debian and Ubuntu), which can't read the rest: run it with bash
if [ -z "$BASH_VERSION" ]; then
    command -v bash > /dev/null || { echo "install.sh needs bash: install it, then run it again."; exit 1; }
    exec bash "$0" "$@"
fi
set -e

# Where a run from curl clones the repo from. A fork sets its own URL here.
repo_url="https://github.com/yassien-y/hearthbox"

[ "$(id -u)" -eq 0 ] || { echo "Run as root, with sudo."; exit 1; }
# Asks questions, so input must be a terminal: without one, the first read would end the
# script without a word
[ -t 0 ] || { echo "install.sh is interactive: run it from a terminal"; exit 1; }
# An installation already here, finished or not, is continued with its saved settings:
# Install run again after it was cut off (a dropped SSH session) picks up where it
# stopped. Never a second installation for another user: it would overwrite Uninstall's
# only record of the first one (/etc/hearthbox.env) and fight it for the same ports.
HEARTHBOX_USER="" saved="" continuing="" cancelled="Cancelled: nothing was set up."
if [ -e /etc/hearthbox.env ]; then
    HEARTHBOX_USER="$(grep -m1 '^HEARTHBOX_USER=' /etc/hearthbox.env | cut -d= -f2-)"
    # Install's answers, if it got as far as saving them (save-env)
    saved="$(getent passwd "$HEARTHBOX_USER" | cut -d: -f6)/appdata/.env"
    [ -f "$saved" ] || saved=""
    continuing=yes
    # What an earlier run set up stays
    cancelled="Cancelled: nothing more was changed. Run Install again to continue."
fi

# Stops if a command the setup needs is missing, before anything changes. It installs
# none itself, so which packages the host has stays the owner's choice.
need() {
    local missing=() name
    for name in "$@"; do command -v "$name" > /dev/null || missing+=("$name"); done
    [ "${#missing[@]}" -gt 0 ] || return 0
    echo "Not found: ${missing[*]}. Install them with your distro's package manager, then run again."
    # The one whose package has another name
    [[ " ${missing[*]} " != *" nft "* ]] || echo "nft comes in the nftables package."
    exit 1
}
# nft: the port redirects (setup-nftables). podman: every service. git: ~/repo is a
# clone. Here, before the questions: a run from curl needs git to get the repo.
need nft podman git
# The shared drop-in (containers/container.d/) needs Podman 5.2: an older one ignores it,
# and every container would start without the common settings. sort -C succeeds only if
# the lines are already in order, i.e. 5.2 <= version.
version="$(podman --version | awk '{ print $3 }')"
printf '5.2\n%s\n' "$version" | sort -C -V ||
    { echo "Podman $version is too old: the setup needs 5.2 or newer. Your distro's next release may have it."; exit 1; }

if [ -n "${BASH_SOURCE[0]}" ]; then
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # From curl (bash -c), there's no file and no clone to copy into ~/repo: clone the
    # repo into a temporary folder, deleted however Install ends
    SOURCE_DIR="$(mktemp -d)/hearthbox"
    trap 'rm -rf "$(dirname "$SOURCE_DIR")"' EXIT
    git clone --quiet "$repo_url" "$SOURCE_DIR"
fi

# The internet mode's VPN, from SERVICE_GROUPS: vpn is its group (empty in local mode),
# vpn_name its name in messages, vpn_sub the subdomain of the public domain its server is at
set_vpn() {
    vpn="" vpn_name="" vpn_sub=""
    case " $SERVICE_GROUPS " in
        *" netbird "*) vpn=netbird vpn_name=NetBird vpn_sub=nbs ;;
        *" headscale "*) vpn=headscale vpn_name=Headscale vpn_sub=hs ;;
    esac
}

# What won't be asked, and why
if [ -n "$continuing" ]; then
    echo "Installation found with the following settings:"
    echo "  - Hearthbox user: $HEARTHBOX_USER"
    if [ -n "$saved" ]; then
        saved_value() { grep -m1 "^$1=" "$saved" | cut -d= -f2-; }
        SERVICE_GROUPS="$(saved_value SERVICE_GROUPS)"
        INTERNAL_DOMAIN="$(saved_value INTERNAL_DOMAIN)"
        PUBLIC_DOMAIN="$(saved_value PUBLIC_DOMAIN)"
        set_vpn
        if [ -n "$vpn" ]; then
            echo "  - reached from: the internet, through $vpn_name at $vpn_sub.$PUBLIC_DOMAIN"
        else
            echo "  - reached from: the local network"
        fi
        echo "  - internal domain: $INTERNAL_DOMAIN"
        # The groups besides lan, netbird or headscale, which the line above already says
        optional="$(printf '%s\n' $SERVICE_GROUPS | grep -vx -e lan -e netbird -e headscale | xargs)"
        echo "  - optional service groups: ${optional:-none}"
    fi
    # Install run again only continues: changing them is starting over
    echo
    echo "To change these settings, run uninstall.sh, then run Install again."
    [ -n "$saved" ] ||
        echo "The other answers weren't saved before it stopped, so they're asked again."
fi
if [ -z "$HEARTHBOX_USER" ]; then
    read -rp "Rootless Hearthbox user, which owns every container [podmanager]: " HEARTHBOX_USER
    HEARTHBOX_USER="${HEARTHBOX_USER:-podmanager}"
    # A new user only: Uninstall deletes the user with its home, which must never be an
    # account Install didn't create. Its group too: useradd creates one of the same name,
    # and stops if it exists.
    ! id "$HEARTHBOX_USER" > /dev/null 2>&1 && ! getent group "$HEARTHBOX_USER" > /dev/null ||
        { echo "$HEARTHBOX_USER already exists: choose a name for a new user."; exit 1; }
fi
# ~/repo is always a git clone: a copy of this folder, so this folder must be one
[ -d "$SOURCE_DIR/.git" ] ||
    { echo "Run install.sh from a git clone of the repo (git clone <url>), not a copy without git."; exit 1; }

if [ -z "$saved" ]; then
    echo "Where will the services be reached from?"
    echo "  1) Local network: services at <service>.<internal-domain>, needs your router to hand"
    echo "     out this server as DNS server: Install walks you through it"
    echo "  2) Internet: installs Headscale or NetBird, needs a public domain for it"
    read -rp "Choose [1/2]: " reach
    case "$reach" in
        # The lan/ group is CoreDNS, the LAN's DNS server
        1) SERVICE_GROUPS="lan" ;;
        2)
            echo
            echo "Which one?"
            echo "  1) Headscale: the simplest, for a few people. Devices use the Tailscale app, and each"
            echo "     new device is approved with a command on this server."
            echo "  2) NetBird: for more people, with access control: a web dashboard to manage users,"
            echo "     devices and access rules. Devices use the NetBird app, and log in with a password"
            echo "     and an authenticator code."
            read -rp "Choose [1]: " which
            # Each is the group of the same name: its units in containers/vpn/, named after
            # it (its server, and NetBird's dashboard)
            case "${which:-1}" in
                1) SERVICE_GROUPS="headscale" ;;
                2) SERVICE_GROUPS="netbird" ;;
                *) echo "$cancelled"; exit 1 ;;
            esac
            ;;
        *) echo "$cancelled"; exit 1 ;;
    esac
    set_vpn

    # The internal and public domains become DNS names, certificates' names, and the VPN
    # servers' configs through sed: only lowercase letters, digits, dots and hyphens
    valid_domain() { [[ "$1" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; }
    while :; do
        read -rp "Internal domain: services will be at <service>.<internal-domain>, e.g. home.hearthbox [hearthbox]: " INTERNAL_DOMAIN
        INTERNAL_DOMAIN="${INTERNAL_DOMAIN:-hearthbox}"
        valid_domain "$INTERNAL_DOMAIN" && break
        echo "Use only lowercase letters, digits, dots and hyphens (e.g. hearthbox or my-lab)."
    done

    PUBLIC_DOMAIN=""
    if [ -n "$vpn" ]; then
        # Devices reach the VPN's server from anywhere at <vpn_sub>.<public-domain>, so it
        # must be a domain whose DNS records you set
        while :; do
            read -rp "Public domain you own, e.g. example.com ($vpn_name will be at $vpn_sub.example.com): " PUBLIC_DOMAIN
            valid_domain "$PUBLIC_DOMAIN" && [[ "$PUBLIC_DOMAIN" == *.* ]] && break
            echo "Type a public domain you own, e.g. example.com."
        done
    fi

    # Every folder in containers/ that isn't a drop-in (*.d) is an optional group,
    # so a new folder shows up here by itself. core/ isn't (every host runs it), and lan/
    # and vpn/ aren't: the questions above decide them.
    # Every group starts ticked, except ai: Ollama's image is large and runs its models on
    # the CPU, slow on most home servers, so it's only installed if asked for.
    choices=() ticked=()
    for dir in "$SOURCE_DIR"/containers/*/; do
        name="$(basename "$dir")"
        [[ "$name" == *.d || "$name" == core || "$name" == lan || "$name" == vpn ]] && continue
        choices+=("$name")
        if [ "$name" = ai ]; then ticked+=(0); else ticked+=(1); fi
    done
    while :; do
        echo
        echo "Which optional service groups do you want?"
        for i in "${!choices[@]}"; do
            mark=" "; [ "${ticked[$i]}" = 0 ] || mark=x
            # The services in the folder are its description, including those in an app's
            # own subfolder (vault/immich/)
            printf '  %d) [%s] %s: %s\n' $((i + 1)) "$mark" "${choices[$i]}" \
                "$(find "$SOURCE_DIR/containers/${choices[$i]}" -name '*.container' -printf '%f\n' |
                    sed 's/\.container$//' | sort | xargs)"
        done
        read -rp "Type a number to toggle it, or press Enter to continue: " n
        [ -n "$n" ] || break
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#choices[@]}" ] &&
            ticked[$((n - 1))]=$((1 - ticked[$((n - 1))]))
    done
    for i in "${!choices[@]}"; do
        [ "${ticked[$i]}" = 0 ] || SERVICE_GROUPS+="${SERVICE_GROUPS:+ }${choices[$i]}"
    done
fi

# Where the port redirects take traffic from, for the summary: in internet mode, only
# the VPN's devices reach nginx
if [ -n "$vpn" ]; then
    redirect_from="$vpn_name devices"
    # The setup step downloads the VPN's client, and checks that its server answers
    need curl
    # Headscale mode installs its own Tailscale client (setup-headscale.sh), where
    # Uninstall removes it. One installed another way is this machine's own Tailscale
    # connection, which joining Headscale would take over.
    if [ "$vpn" = headscale ] && command -v tailscaled > /dev/null && [ ! -e /usr/local/bin/tailscaled ]; then
        echo "Tailscale is already installed here, and Headscale mode needs a client of its own:"
        echo "remove Tailscale first, or choose NetBird. $cancelled"
        exit 1
    fi
else
    redirect_from="any network"
fi

echo
echo "This will:"
echo "  - install the core services and these groups: $SERVICE_GROUPS"
echo "  - save the user in /etc/hearthbox.env, for uninstall.sh                         [root]"
echo "  - create the user $HEARTHBOX_USER, with no password (reach it with sudo -iu)  [root]"
echo "  - copy $SOURCE_DIR to ~$HEARTHBOX_USER/repo, with its git history          [root]"
echo "  - enable lingering for $HEARTHBOX_USER, so its services start at boot          [root]"
echo "  - let systemctl --user work after sudo -iu $HEARTHBOX_USER (/etc/profile.d/hearthbox.sh) [root]"
echo "  - create /srv/hearthbox, for files shared between services, and make it and everything"
echo "    already in it owned by $HEARTHBOX_USER                                        [root]"
[ ! -e /sys/fs/selinux/enforce ] ||
    echo "    and label it for containers (SELinux)"
echo "  - redirect ports 80 and 443 from $redirect_from to nginx (nftables)       [root]"
[[ " $SERVICE_GROUPS " != *" lan "* ]] ||
    echo "  - redirect DNS (port 53) from any network to CoreDNS (nftables)           [root]"
[ -z "$vpn" ] ||
    echo "  - redirect port 443 from anywhere else to $vpn_name's server (nftables)     [root]"
echo "  - save the internal domain${vpn:+, the public domain} and the service groups in ~/appdata/.env"
echo "  - enable the Podman API socket (for Glance)"
echo "  - create the certificate authority for the services' HTTPS"
echo "  - link the repo into place"
echo "  - download every service's image"
echo "  - check the units, and start every service"
if [[ " $SERVICE_GROUPS " == *" lan "* ]]; then
    echo "  - stop until your router hands out this server as DNS server (required), then renew"
    echo "    this server's connection where it can (otherwise you reconnect it), and check it [root]"
fi
if [ "$vpn" = netbird ]; then
    echo "  - install NetBird's client in /usr/local/bin, as a system service, and add this"
    echo "    machine to NetBird, at nbs.$PUBLIC_DOMAIN                                [root]"
    echo "  - ask for NetBird's owner (an email and a password), and create it"
    echo "  - make NetBird's login require an authenticator code"
    echo "  - point every *.$INTERNAL_DOMAIN at this machine, for NetBird devices"
    echo "  - pause for you to log in once and set up your authenticator app"
fi
if [ "$vpn" = headscale ]; then
    echo "  - install the Tailscale client, as a system service                                [root]"
    echo "  - create Headscale's user $HEARTHBOX_USER, and add this machine to Headscale, at"
    echo "    hs.$PUBLIC_DOMAIN"
    echo "  - point each service's name under $INTERNAL_DOMAIN at this machine's Headscale"
    echo "    address, for Headscale devices, and keep it pointed there"
fi
echo "Steps not marked [root] run as $HEARTHBOX_USER."
echo
read -rp "Continue? [Y/n] " answer
case "$answer" in [nN]*) echo "$cancelled"; exit 0 ;; esac

# Runs <folder>/<name>.sh: as root if the script says so, otherwise as the rootless
# Hearthbox user.
run_step() {
    local folder="$1" name="$2"
    local home script="$SOURCE_DIR/$folder/$name.sh"
    home="$(getent passwd "$HEARTHBOX_USER" | cut -d: -f6)"
    # What every step gets
    local vars=(REPO="$home/repo" SERVICE_GROUPS="$SERVICE_GROUPS"
                INTERNAL_DOMAIN="$INTERNAL_DOMAIN" PUBLIC_DOMAIN="$PUBLIC_DOMAIN")
    echo
    if grep -qx '# Runs as: root' "$script"; then
        echo "== $name (root)"
        env "${vars[@]}" HEARTHBOX_USER="$HEARTHBOX_USER" SOURCE_DIR="$SOURCE_DIR" bash "$script"
    else
        echo "== $name ($HEARTHBOX_USER)"
        # In a session of the user's own (PAMName=login), which sets up the XDG_RUNTIME_DIR
        # systemctl --user needs: switching users inside root's session never does. From
        # the user's clone, which the root steps created by now: the user may not be able
        # to read this copy, and the clone has the same files the units use.
        systemd-run --uid="$HEARTHBOX_USER" --property=PAMName=login --pipe --wait --quiet \
            "${vars[@]/#/--setenv=}" bash "$home/repo/$folder/$name.sh"
    fi
}

# Install's own steps, in the order they run: scripts/install/<name>.sh. The steps
# that apply the repo come after these, from scripts/update.sh, then the mode's last step.
for name in create-user copy-repo enable-lingering setup-shell-env create-srv-hearthbox \
            setup-nftables save-env enable-podman-socket create-ca; do
    run_step scripts/install "$name"
done
run_step scripts update
# Last, as root, and needing the services running. Local mode: the router change, since
# CoreDNS must answer before the router hands it out. Internet mode: the VPN's server must
# answer, and the step installs its client.
[[ " $SERVICE_GROUPS " != *" lan "* ]] || run_step scripts/install setup-router
[ -z "$vpn" ] || run_step scripts/install "setup-$vpn"

echo
echo "Done. Everything runs as $HEARTHBOX_USER (sudo -iu $HEARTHBOX_USER): hearthbox update applies"
echo "changes you make in ~/repo, and hearthbox pull gets new versions if ~/repo has a git remote."
echo
echo "On each device, install this server's root certificate once, so it trusts the services'"
echo "HTTPS: open http://ca.$INTERNAL_DOMAIN/root.crt (docs/setup.md)."
case "$vpn" in
    netbird)
        echo "Devices reach the services through NetBird's app, with server https://nbs.$PUBLIC_DOMAIN."
        echo "Manage users, devices and access rules in NetBird's dashboard, from a device"
        echo "connected to NetBird: https://netbird.$INTERNAL_DOMAIN"
        ;;
    headscale)
        echo "Devices reach the services through the Tailscale app, with server https://hs.$PUBLIC_DOMAIN."
        echo "Approve each new device on this server (docs/setup.md, \"Internet mode with Headscale\")."
        ;;
esac
