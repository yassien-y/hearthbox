#!/bin/sh
# nginx's unit runs it in ExecStartPre (core/nginx.container). Signs the HTTPS certificate
# for the services, with this host's CA (Install's create-ca step), when it's missing,
# wasn't signed by the current CA, doesn't name exactly the services in nginx's map, or
# has under 90 days left. So renewal needs no timer: every boot and every hearthbox update
# starts nginx, and a service added to the map gets its name at that restart.
# Each name is listed, not *.<internal-domain>: browsers refuse a wildcard right under a
# single-label domain like hearthbox.
# 825 days: the longest Apple devices accept, and long enough that a server running
# that long without a restart is unlikely.
set -e

step() { sh "$HOME/repo/scripts/containers/step.sh" "$@"; }
certs="$HOME/appdata/nginx/certs"

[ -f "$HOME/appdata/ca/root.crt" ] || { echo "root CA missing: run Install again, which creates it" >&2; exit 1; }

# The root certificate, which nginx serves at http://ca.<internal-domain>/root.crt for devices to
# install. A copy, so nginx never gets the CA's key. This runs before the folder
# creation in 00-common.conf, so it makes its folder itself.
mkdir -p "$certs"
cp "$HOME/appdata/ca/root.crt" "$certs/root.crt"

# <name>.<internal-domain> for every name in nginx's map, sorted to compare with the certificate's
names="$(sh "$HOME/repo/scripts/containers/service-names.sh" | sed "s/\$/.$INTERNAL_DOMAIN/" | sort)"

# Kept if signed by the current root, unexpired, naming the same services, and with 90
# days left. needs-renewal exits 1 when it has them; 0 (needs renewal) or an error
# means a new one.
if [ -f "$certs/services.crt" ] &&
    step certificate verify /certs/services.crt --roots /ca/root.crt 2> /dev/null &&
    [ "$(step certificate inspect /certs/services.crt --format json |
        awk '/"dns_names"/ { inside = 1; next } inside && /\]/ { exit } inside { gsub(/[ ",]/, ""); print }' |
        sort)" = "$names" ]; then
    status=0
    step certificate needs-renewal /certs/services.crt --expires-in 2160h || status=$?
    [ "$status" -ne 1 ] || exit 0
fi

# One --san per name; the first is also the certificate's subject
set --
for name in $names; do set -- "$@" --san "$name"; done
step certificate create "$(printf '%s\n' "$names" | head -n 1)" /certs/services.crt /certs/services.key "$@" \
    --profile leaf --ca /ca/root.crt --ca-key /ca/root.key \
    --not-after 19800h --no-password --insecure --force
echo "signed the services' certificate for:" $names
