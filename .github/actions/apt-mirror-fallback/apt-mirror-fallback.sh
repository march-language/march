#!/usr/bin/env bash
# Point apt at Ubuntu mirrors outside ubuntu.com when the runner's default
# mirror does not resolve.
#
# Why: on 2026-11-11 Canonical's authoritative nameservers went unreachable.
# Every `apt-get install` on a GitHub ubuntu-24.04 runner (ours, and the one
# inside ocaml/setup-ocaml) then spent about a minute per package on
# "Temporary failure resolving 'azure.archive.ubuntu.com'" until the job hit
# its timeout. All three hosts in the image's /etc/apt/apt-mirrors.txt are
# under ubuntu.com, so apt's own mirror fallback did not help.
#
# What it does: nothing on a non-Linux runner, and nothing while the configured
# mirror resolves. Otherwise it rewrites the mirror list (amd64 image) and any
# direct ubuntu.com URI in ubuntu.sources (arm64 image) to university and
# kernel.org mirrors, then refreshes the package lists.
#
# APT_MIRROR_FALLBACK_FORCE=1 takes the fallback path even when DNS is fine
# (for testing the fallback itself).
set -u

[ "$(uname -s)" = Linux ] || exit 0
command -v apt-get > /dev/null || exit 0

mirror_file=/etc/apt/apt-mirrors.txt
sources_file=/etc/apt/sources.list.d/ubuntu.sources

case "$(dpkg --print-architecture)" in
  amd64 | i386)
    probe=archive.ubuntu.com
    mirrors=(
      http://mirrors.edge.kernel.org/ubuntu/
      http://mirror.math.princeton.edu/pub/ubuntu/
      http://mirrors.mit.edu/ubuntu/
    )
    ;;
  *)
    probe=ports.ubuntu.com
    mirrors=(
      http://mirrors.mit.edu/ubuntu-ports/
      http://mirror.csclub.uwaterloo.ca/ubuntu-ports/
      http://mirrors.ocf.berkeley.edu/ubuntu-ports/
    )
    ;;
esac

# The host apt will actually try first, when the image names one.
if [ -s "$mirror_file" ]; then
  first=$(sed -nE 's#^https?://([^/[:space:]]+).*#\1#p' "$mirror_file" | head -n 1)
  [ -n "$first" ] && probe=$first
fi

resolves() {
  local _
  for _ in 1 2 3; do
    timeout 10 getent hosts "$1" > /dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

if [ "${APT_MIRROR_FALLBACK_FORCE:-0}" != 1 ] && resolves "$probe"; then
  echo "apt mirror $probe resolves; leaving apt as it is."
  exit 0
fi

# Try the fallbacks in order. One counts only when it answers AND a full
# package-list refresh from it finishes, under a hard time limit: a mirror
# that accepts the connection and then stalls must not cost the job's timeout
# either (seen with one of these during the outage).
point_apt_at() {
  local chosen=$1 m n=2
  if [ -f "$mirror_file" ]; then
    {
      printf '%s\tpriority:1\n' "$chosen"
      for m in "${mirrors[@]}"; do
        [ "$m" = "$chosen" ] && continue
        printf '%s\tpriority:%d\n' "$m" "$n"
        n=$((n + 1))
      done
    } | sudo tee "$mirror_file" > /dev/null
  fi
  if [ -f "$sources_file" ]; then
    sudo sed -i -E \
      "s#^(URIs:[[:space:]]*)https?://[a-z0-9.-]+/(pub/)?ubuntu(-ports)?/?[[:space:]]*\$#\1${chosen}#" \
      "$sources_file"
  fi
}

# Keep what the image shipped, to put back if no fallback works.
backup=$(mktemp -d)
[ -f "$mirror_file" ] && cp "$mirror_file" "$backup/mirrors"
[ -f "$sources_file" ] && cp "$sources_file" "$backup/sources"

# Only Ubuntu's own archive is refreshed (a PPA or vendor repo keeps the lists
# the image shipped), and a failure to fetch counts as a failure.
refresh=(apt-get update
  -o Dir::Etc::sourcelist="$sources_file" -o Dir::Etc::sourceparts=/dev/null
  -o APT::Get::List-Cleanup=0 -o APT::Update::Error-Mode=any
  -o Acquire::Retries=1 -o Acquire::http::Timeout=20)

for m in "${mirrors[@]}"; do
  curl -fsS -m 20 -o /dev/null "${m}dists/noble/InRelease" || continue
  point_apt_at "$m"
  if sudo timeout -k 10 240 "${refresh[@]}"; then
    echo "::warning::apt is using the fallback mirror $m for this job (default mirror: $probe)."
    exit 0
  fi
  echo "fallback mirror $m did not finish a package-list refresh; trying the next."
done

[ -f "$backup/mirrors" ] && sudo cp "$backup/mirrors" "$mirror_file"
[ -f "$backup/sources" ] && sudo cp "$backup/sources" "$sources_file"
echo "::warning::apt mirror $probe does not resolve and no fallback mirror worked; leaving apt as it is."
exit 0
