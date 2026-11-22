#!/usr/bin/env bash
# Creates this host's own certificate authority, which signs the services' HTTPS
# certificate (scripts/containers/renew-cert.sh). Every device installs its root
# certificate once, from http://ca.<internal-domain>/root.crt, to trust the services.
# Install creates it once per installation. The root may only sign names under
# INTERNAL_DOMAIN (name constraints, config/step/root-ca.tpl), so a device that trusts it
# trusts nothing else it could sign.
set -e

# Install continuing an earlier run keeps the CA that run created: devices may already
# trust its root
if [ -f "$HOME/appdata/ca/root.crt" ] && [ -f "$HOME/appdata/ca/root.key" ]; then
    echo "the CA for $INTERNAL_DOMAIN exists"
    exit 0
fi
# 10 years: replacing it means installing it again on every device. No password on the
# key: renew-cert.sh signs with it unattended, at nginx's start. --force: a run cut off
# while creating it may have left one of the two files.
sh "$REPO/scripts/containers/step.sh" certificate create "Hearthbox CA ($INTERNAL_DOMAIN)" \
    /ca/root.crt /ca/root.key --template /templates/root-ca.tpl --set "domain=$INTERNAL_DOMAIN" \
    --not-after 87600h --no-password --insecure --force
echo "created the CA for $INTERNAL_DOMAIN"
