#!/usr/bin/env bash
# Downloads every image the units use before restart-services starts them. Downloaded
# by a service's start instead, a big image on a slow connection runs past systemd's
# start limit and the service fails. Here no limit applies, and the progress shows.
# Also gets the newest version of an image whose tag moves (a major version, e.g.
# jellyfin:12): Podman alone
# only downloads an image that's missing.
set -e

# The linked units, not the repo's: only this host's groups' images, including .image
# units for images a script runs. -R follows the links into the repo. One image at a
# time, so each gets the whole connection.
grep -Rh --include='*.container' --include='*.image' '^Image=' "$HOME/.config/containers/systemd" |
    cut -d= -f2- | sort -u |
    while read -r image; do
        podman pull "$image"
        # Every unit runs with UserNS=keep-id. Storage that can't shift IDs copies the
        # image's files for that mapping at its first container, which at a service's
        # start counts against systemd's start limit. A container created and removed
        # here makes the copy with no limit, one image at a time; the services reuse it.
        podman rm "$(podman create --userns=keep-id "$image" true)" > /dev/null
    done
