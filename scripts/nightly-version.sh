#!/usr/bin/env bash
# Print the version string for today's nightly: X.Y.(Z+1)-nightly.YYYYMMDD
#
# The in-tree version is the last RELEASED version (see scripts/version.sh), so
# a nightly must claim something strictly greater than it -- otherwise the
# nightly sorts BELOW the release it postdates, which is what happened to every
# nightly between 2026-08-23 and this script landing (all labelled
# 0.3.0-nightly.*).  Patch-incrementing is the conservative choice: the result
# sorts above the last release and below any plausible next one, whether that
# turns out to be a patch, a minor or a major.
#
# It deliberately does NOT try to predict the next release number.  Nightlies
# are pre-releases, and forge's resolver excludes pre-releases from `~>`
# constraints by design (see resolver_constraint.ml), so the string's only job
# is to order correctly -- not to advertise intent.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/version.sh"

base="$(march_version)"

case "$base" in
  *-*)
    echo "nightly-version.sh: in-tree version '$base' carries a pre-release suffix;" >&2
    echo "  this repo's convention is a plain released version in dune-project." >&2
    exit 1 ;;
esac

IFS=. read -r major minor patch <<< "$base"
if ! [ "$major" -eq "$major" ] 2>/dev/null \
   || ! [ "$minor" -eq "$minor" ] 2>/dev/null \
   || ! [ "$patch" -eq "$patch" ] 2>/dev/null; then
  echo "nightly-version.sh: '$base' is not X.Y.Z" >&2
  exit 1
fi

printf '%s.%s.%s-nightly.%s\n' "$major" "$minor" "$((patch + 1))" "$(date -u +%Y%m%d)"
