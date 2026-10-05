#!/usr/bin/env bash
# Remove the lab's hosts and network (scripts/lab/up.sh). The lab's state on
# this machine ($LAB_DIR: project copy, keys, logs) is kept; `--purge` removes
# it too.
set -u
source "$(dirname "$0")/lib.sh"
quiet=; purge=
for a in "$@"; do
  case $a in --quiet) quiet=1 ;; --purge) purge=1 ;; *) echo "usage: scripts/lab/down.sh [--purge]" >&2; exit 2 ;; esac
done
command -v docker > /dev/null 2>&1 || lab_die "docker is not installed"
ids=$(docker ps -aq --filter label=march-lab=1)
[ -n "$ids" ] && docker rm -f $ids > /dev/null
docker network rm "$LAB_NET" > /dev/null 2>&1
rm -f "$LAB_DIR/deployed"
[ -n "$purge" ] && rm -rf "$LAB_DIR"
[ -n "$quiet" ] || lab_say "down${purge:+ (and $LAB_DIR removed)}"
exit 0
