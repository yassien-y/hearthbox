#!/bin/sh
# Runs smallstep's step CLI in a throwaway container, for this host's own certificate
# authority: Install's create-ca step and renew-cert.sh both use it, so the image and its
# mounts are set in one place. Mounts the CA (/ca), nginx's certificates (/certs) and the
# repo's templates (/templates).
set -e

# The version core/step-cli.image pins, which hearthbox update downloads ahead
image="$(sed -n 's/^Image=//p' "$HOME/repo/containers/core/step-cli.image")"
# Podman won't create missing bind-mount folders
mkdir -p "$HOME/appdata/ca" "$HOME/appdata/nginx/certs"
# keep-id maps the Hearthbox user to its own UID in the container, and --user runs step as
# that UID: the image's own user (step, UID 1000) is another user unless the Hearthbox
# user happens to be UID 1000, and can't write the Hearthbox user's folders
exec podman run --rm --quiet --userns=keep-id --user "$(id -u):$(id -g)" \
    -v "$HOME/appdata/ca:/ca:Z" \
    -v "$HOME/appdata/nginx/certs:/certs:Z" \
    -v "$HOME/repo/config/step:/templates:ro,Z" \
    "$image" step "$@"
