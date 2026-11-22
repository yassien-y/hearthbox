#!/usr/bin/env bash
# Runs as: root
# Internet mode's last step, after the services started: makes this machine a device in
# its own NetBird network, so the other devices reach nginx at its NetBird address, and
# points every <service>.<internal-domain> at it, through its NetBird name.
# - Installs NetBird's client, the same version as the server, as a system service. It
#   creates the wt0 interface nftables redirects from (setup-nftables.sh). It's the one
#   part of the setup that keeps running as root once Install is done: the other root
#   steps only configure the system during Install.
# - Stops until the owner has pointed the public name at this machine and opened the
#   router, shows what to set, and checks that the server answers there on Enter.
# - Asks for NetBird's owner and creates it through the server's setup API, which also
#   returns a token for the rest. The server is new from this Install, so it has no owner
#   yet, unless someone else created one: its setup API answers anyone until then.
# With the token: NetBird's login made to require an authenticator code, a setup key this
# machine joins with, and a DNS zone whose *.<internal-domain> record points at this
# machine's own name in NetBird, which NetBird keeps pointed at its current address. Last,
# it pauses for the owner to log in once and set up the authenticator: it can't check
# that they did.
# The API is called on this machine (127.0.0.1:9443), with the public name, so the
# certificate checks out without going out to the internet and back.
set -e

host="nbs.$PUBLIC_DOMAIN"
url="https://$host"

# curl to the server, on this machine
nb_curl() { curl --connect-to "$host:443:127.0.0.1:9443" "$@"; }
# The API, as the token's user: method, path, then more curl options (the JSON body)
api() { nb_curl -fsS -X "$1" -H "Authorization: $auth" -H 'Content-Type: application/json' "${@:3}" "$url/api$2"; }
# The first string value of a JSON field, from stdin: no jq on every host. The API's
# fields come in a fixed order, so the first match is the right one.
json_value() { grep -o "\"$1\":\"[^\"]*\"" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/'; }
# A string inside JSON quotes: backslashes and quotes escaped
json_escape() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }

# The client, from the unit's image tag
version="$(sed -n 's|^Image=docker.io/netbirdio/netbird-server:||p' "$REPO/containers/vpn/netbird-server.container")"
case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "NetBird's client has no build for $(uname -m)."; exit 1 ;;
esac
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://github.com/netbirdio/netbird/releases/download/v$version/netbird_${version}_linux_$arch.tar.gz" |
    tar -xz -C "$tmp" netbird
install -m 755 "$tmp/netbird" /usr/local/bin/netbird
echo "NetBird client $version installed in /usr/local/bin"
# Install run again after this step was cut off finds the service already installed,
# which netbird service install refuses
systemctl cat netbird.service > /dev/null 2>&1 || netbird service install
systemctl start netbird.service
# netbird up (below) talks to the service: only once it answers
for _ in $(seq 10); do netbird status > /dev/null 2>&1 && break; sleep 1; done

# What public-name.sh needs, then its wait
sub=nbs server="NetBird's server"
# shellcheck source-path=SCRIPTDIR source=public-name.sh
. "$(dirname "$0")/public-name.sh"
# -s without -S: public-name.sh's message says more than curl's error. 60 seconds: getting
# the certificate takes Let's Encrypt a while. Its answer says whether the owner exists
# yet (below).
server_answers() { instance="$(nb_curl -fs --max-time 60 "$url/api/instance")"; }
wait_for_public_name

# The owner exists: either an earlier run of this Install created it (Install run again
# on a finished host, which has nothing left to do here), or someone else did before
# this Install could, through the setup API that answers anyone until then
claimed() {
    echo "NetBird's owner already exists. If an earlier run of Install set this server up,"
    echo "it's done: nothing more to do. Otherwise someone else created it before this"
    echo "Install could: run uninstall.sh, then Install again."
    exit 1
}
[[ "$instance" == *'"setup_required":true'* ]] || claimed

echo
echo "NetBird's owner: the email and password you log in to NetBird with."
email="" password=""
until [[ "$email" == ?*@?* ]]; do read -rp "Owner's email: " email; done
while :; do
    read -rsp "Owner's password (8 characters or more): " password; echo
    # NetBird refuses passwords under 8 characters: said before asking to repeat it
    [ "${#password}" -ge 8 ] || { echo "Use 8 characters or more."; continue; }
    read -rsp "The same password again: " again; echo
    [ "$password" = "$again" ] && break
    echo "The passwords don't match."
done
body="{\"email\":\"$(json_escape "$email")\",\"name\":\"$(json_escape "$email")\""
body+=",\"password\":\"$(json_escape "$password")\",\"create_pat\":true,\"pat_expire_in\":1}"
# On stdin, so the password never shows in the process list. The status code on the
# last line.
response="$(printf '%s' "$body" | nb_curl -sS -X POST -H 'Content-Type: application/json' \
    --data @- -w '\n%{http_code}' "$url/api/setup")"
case "$(printf '%s\n' "$response" | tail -n 1)" in
    200) ;;
    # Someone else's setup call came first
    412) claimed ;;
    *) echo "NetBird's setup failed: $(printf '%s\n' "$response" | sed '$d')"; exit 1 ;;
esac
auth="Token $(printf '%s' "$response" | json_value personal_access_token)"
echo "NetBird's owner $email created"

# Every login with a NetBird password needs an authenticator code from now on: the
# login page is on the internet. It's a setting of the whole NetBird network (NetBird's
# "account"), which the API only replaces as a whole: the settings just read go back with
# that one value changed. Right after the owner exists, so no login happens without it.
account="$(api GET /accounts)"
account="${account#[}" account="${account%]}"
api PUT "/accounts/$(printf '%s' "$account" | json_value id)" \
    --data "${account/\"local_mfa_enabled\":false/\"local_mfa_enabled\":true}" |
    grep -q '"local_mfa_enabled":true' ||
    { echo "NetBird's login couldn't be made to require an authenticator code."; exit 1; }
echo "NetBird's login requires an authenticator code"

# A one-off key for this machine to join with
key="$(api POST /setup-keys --data '{"name":"hearthbox host","type":"one-off","expires_in":3600,"auto_groups":[],"usage_limit":1}' |
    json_value key)"
netbird up --management-url "$url:443" --setup-key "$key" --interface-name wt0
# Every device is in the All group, which the zone goes to
all_group="$(api GET '/groups?name=All' | json_value id)"
# This machine's own name in NetBird's DNS (<label>.<peer domain>), which NetBird keeps
# pointed at its current address: a record pointing at the name follows the address when
# it changes (edited in the dashboard, or the network's range changed). From the local
# client's compact JSON: the fqdn right after wireguardPort, since each device in "peers",
# listed first, has an fqdn of its own.
name="$(netbird status --json | grep -o '"wireguardPort":[0-9]*,"fqdn":"[^"]*"' | cut -d'"' -f6)"
zone="$(api POST /dns/zones --data "{\"name\":\"Hearthbox services\",\"domain\":\"$INTERNAL_DOMAIN\",\"distribution_groups\":[\"$all_group\"],\"enable_search_domain\":false}" |
    grep -o '"id":"[^"]*","name"' | cut -d'"' -f4)"
api POST "/dns/zones/$zone/records" > /dev/null \
    --data "{\"name\":\"*.$INTERNAL_DOMAIN\",\"type\":\"CNAME\",\"content\":\"$name\",\"ttl\":300}"
echo "every *.$INTERNAL_DOMAIN points at this machine's NetBird name, $name"

# Until the owner has set up an authenticator, the password alone still logs in: the
# first login with it sets one up
echo
echo "Log in to NetBird once now: in the NetBird app on one of your devices, set the server"
echo "to $url and log in as $email. After the password, it asks you to set up an"
echo "authenticator app (Google Authenticator, Aegis, 1Password, ...): from then on, every"
echo "login asks for its code. Until you do, the password alone still logs in."
read -rp "Press Enter when done " _
