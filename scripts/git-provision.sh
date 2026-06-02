#!/usr/bin/env bash

ARGC="$#"

if [ $ARGC -ne 2 ]; then
	printf "usage: git-provision.sh <REPO> <REPO_DIR>"
	printf "REPO: link to a git repo, e.g. git@github.com:<user>/<repo>.git"
	printf "REPO_DIR: name of the folder you want REPO cloned as"
fi

REPO="$1"
REPO_DIR="$2"

git clone --no-checkout "${REPO}" "$REPO_DIR"
pushd "$REPO_DIR" || (echo "pushd $REPO_DIR failed, exiting" && exit 1)
git switch -c __dummy__ &&
	printf "**/\n*/" >.gitignore &&
	git add .gitignore &&
	git commit -m "dummy: deletes and gitignores everything"
git worktree add -B main main origin/main
git worktree add -B develop develop origin/develop
popd || (echo "popd $REPO_DIR failed, exiting" && exit 1)
