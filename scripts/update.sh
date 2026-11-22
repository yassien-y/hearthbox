#!/usr/bin/env bash
# Applies the repo in $REPO to this user. Install ends with it, hearthbox update runs it,
# and hearthbox pull runs it after pulling, so the list of steps exists only here.
# Stops at the first step that fails, so nothing restarts on a half-applied repo.
set -e

for name in link-repo pull-images restart-services; do
    echo
    echo "== $name"
    bash "$REPO/scripts/$name.sh"
done
