#!/usr/bin/env bash
# Runs as: root
# Copies the folder install.sh runs from (SOURCE_DIR) to the user's repo: the units,
# config and later steps all use it. The copy keeps its .git and origin, so hearthbox pull
# works and git records every change. Root, because the user may not be able to read
# SOURCE_DIR (e.g. in another user's home); the result is the user's.
set -e

# Install continuing an earlier run keeps the repo that run copied: it may have changes
# of the user's own since
if [ -e "$REPO" ]; then
    echo "$REPO exists"
    exit 0
fi
# Copied next to it, then moved into place: a run cut off midway leaves no half repo
# that the check above would keep. Its leftover is removed first: cp -r into an existing
# folder would put the copy inside it.
rm -rf "$REPO.partial"
# -r, not -a: the copy gets its new folder's SELinux label, not the source's
cp -r "$SOURCE_DIR" "$REPO.partial"
# The repo's hooks keep links in place after every git pull
git -C "$REPO.partial" config core.hooksPath scripts/hooks
chown -R "$HEARTHBOX_USER:$HEARTHBOX_USER" "$REPO.partial"
mv "$REPO.partial" "$REPO"
