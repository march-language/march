#!/usr/bin/env bash
# Assert a release tag matches the in-tree version.
#
#   scripts/check-version-tag.sh v0.4.0
#
# Run as the FIRST step of release.yml's publish job, before any artifact is
# uploaded.  forge resolves `march = "~> X.Y"` and `.march-version` pins against
# GitHub release TAGS, so a tag that disagrees with the version compiled into
# the binary makes forge's resolver silently lie about what is installed.
#
# The failure this actually catches: tagging vX.Y.Z on a tree whose dune-project
# still says the previous version, i.e. a forgotten bump.
set -euo pipefail

# NOTE: deliberately not using ${1:?usage ... {a|b} ...} -- brace expansion in
# that form ends at the FIRST '}', which has silently mangled arguments in this
# repo's oracle scripts before.
if [ $# -ne 1 ]; then
  echo "usage: check-version-tag.sh vX.Y.Z" >&2
  exit 2
fi
tag="$1"

. "$(dirname "${BASH_SOURCE[0]}")/version.sh"

case "$tag" in
  v*) ;;
  *) echo "check-version-tag.sh: tag '$tag' does not start with 'v'" >&2; exit 1 ;;
esac

tag_version="${tag#v}"
tree_version="$(march_version)"

if [ "$tag_version" != "$tree_version" ]; then
  echo "check-version-tag.sh: tag/tree version mismatch" >&2
  echo "  pushed tag        : $tag  (version $tag_version)" >&2
  echo "  dune-project says : $tree_version" >&2
  echo >&2
  echo "The binaries this release would publish report $tree_version, but the" >&2
  echo "release page would claim $tag_version.  Bump dune-project and re-tag," >&2
  echo "or delete the tag -- do not publish a release that disagrees with its" >&2
  echo "own artifacts." >&2
  exit 1
fi

echo "check-version-tag.sh: OK -- tag $tag matches in-tree version $tree_version"
