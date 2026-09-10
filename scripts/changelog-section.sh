#!/usr/bin/env bash
# Print one version's section of CHANGELOG.md, without its own heading.
#
#   scripts/changelog-section.sh 0.4.0
#   scripts/changelog-section.sh --max-bytes 100000 0.4.0
#
# Used by release.yml to build the GitHub Release body, so a release's notes are
# the changelog entry rather than a fixed install blurb.  Exits non-zero when the
# section is missing or empty, so a release cannot publish empty notes.
#
# --max-bytes truncates at a LINE boundary and appends a pointer to the full
# changelog.  This is not hypothetical: a GitHub release body is capped at
# 125,000 characters and the 0.3.0 section is 321KB, so an untruncated body
# would be rejected by the API at publish time -- after the artifacts had
# already been built and uploaded.
set -euo pipefail

max_bytes=""
if [ "${1:-}" = "--max-bytes" ]; then
  if [ $# -lt 2 ]; then echo "usage: changelog-section.sh [--max-bytes N] X.Y.Z" >&2; exit 2; fi
  max_bytes="$2"; shift 2
fi
if [ $# -ne 1 ]; then
  echo "usage: changelog-section.sh [--max-bytes N] X.Y.Z" >&2
  exit 2
fi
version="$1"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
f="$root/CHANGELOG.md"
[ -f "$f" ] || { echo "changelog-section.sh: no CHANGELOG.md at $f" >&2; exit 1; }

section="$(awk -v want="## [$version]" '
  index($0, want) == 1 { inside = 1; next }
  inside && /^## \[/   { exit }
  inside               { print }
' "$f")"

section="$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')"

if [ -z "$section" ]; then
  echo "changelog-section.sh: no non-empty '## [$version]' section in CHANGELOG.md" >&2
  echo "  sections present:" >&2
  grep -n '^## \[' "$f" | sed 's/^/    /' >&2
  exit 1
fi

if [ -n "$max_bytes" ] && [ "$(printf '%s' "$section" | wc -c)" -gt "$max_bytes" ]; then
  url="https://github.com/march-language/march/blob/v${version}/CHANGELOG.md"
  # Reserve room for the trailer, then cut at the last whole line that fits.
  trailer=$'\n\n---\n\n*These notes are truncated. The full '"$version"' changelog is at ['"$url"']('"$url"').*'
  budget=$(( max_bytes - ${#trailer} ))
  # A here-string, NOT a pipe: awk exits early once the budget is spent, which
  # would SIGPIPE an upstream printf and -- under `set -o pipefail` -- abort the
  # script before the trailer is ever emitted.  That failure is silent and still
  # produces an under-budget body, so a size-only check does not catch it.
  body="$(awk -v budget="$budget" '
    { n = length($0) + 1; if (used + n > budget) exit; used += n; print }' <<< "$section")"
  printf '%s\n%s\n' "$body" "$trailer"
else
  printf '%s\n' "$section"
fi
