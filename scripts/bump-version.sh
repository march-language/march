#!/usr/bin/env bash
# The March release ritual.  See specs/2026-09-10-release-mechanism-design.md.
#
#   scripts/bump-version.sh 0.4.0            # full ritual
#   scripts/bump-version.sh --dry-run 0.4.0  # checks + report, no writes
#
# Guarded: clean tree -> on main, up to date -> build -> full test suite ->
# finalize CHANGELOG -> set version -> commit -> tag.  Aborts on any failure.
#
# It does NOT push.  Pushing a tag starts a publish; that stays a human
# decision, so the script prints the commands and stops.
set -euo pipefail

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi
if [ $# -ne 1 ]; then
  echo "usage: bump-version.sh [--dry-run] X.Y.Z" >&2
  exit 2
fi
version="$1"

case "$version" in
  v*) echo "bump-version.sh: pass the bare version (0.4.0), not the tag ($version)" >&2; exit 2 ;;
esac
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "bump-version.sh: '$version' is not X.Y.Z" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
. "$root/scripts/version.sh"

step() { printf '\n=== %s\n' "$1"; }
die()  { printf '\nbump-version.sh: %s\n' "$1" >&2; exit 1; }

# ── 1. preconditions ───────────────────────────────────────────────────────
step "1/7  preconditions"

[ -z "$(git status --porcelain)" ] || die "working tree is dirty; commit or discard first"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || die "on branch '$branch'; releases are cut from main"

# Fetch first: a bare `main`/`origin/main` comparison against a stale ref has
# silently merged old state in this repo before.
git fetch origin --quiet
behind="$(git rev-list --count HEAD..origin/main)"
[ "$behind" -eq 0 ] || die "main is $behind commit(s) behind origin/main; pull first"
ahead="$(git rev-list --count origin/main..HEAD)"
[ "$ahead" -eq 0 ] || die "main is $ahead commit(s) ahead of origin/main; push first"

current="$(march_version)"
[ "$current" != "$version" ] || die "dune-project already says $version"
if git rev-parse "v$version" >/dev/null 2>&1; then die "tag v$version already exists"; fi

grep -q '^## \[Unreleased\]' CHANGELOG.md || die "CHANGELOG.md has no ## [Unreleased] section"
unreleased="$(awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -c '^- ' || true)"
[ "$unreleased" -gt 0 ] || die "## [Unreleased] has no entries; nothing to release"
echo "  $current -> $version, $unreleased changelog bullet(s)"

# ── 2. build + full test suite ─────────────────────────────────────────────
step "2/7  build and test"
echo "  dune build"
dune build --root . 2>&1 | tail -5 || die "build failed"

echo "  scripts/run-tests.sh"
./scripts/run-tests.sh >/tmp/march-release-tests.log 2>&1 || {
  tail -30 /tmp/march-release-tests.log; die "test suite failed (full log: /tmp/march-release-tests.log)"; }
echo "    $(grep -c '\[OK\]' /tmp/march-release-tests.log) OK"

# run-tests.sh is alcotest-only.  These are NOT covered by it, and a green
# run-tests.sh has already coexisted with a red main (db44fbb3) for exactly
# this reason.
echo "  dune build @forge/test/runtest   (not covered by run-tests.sh)"
dune build --root . @forge/test/runtest >/tmp/march-release-forge.log 2>&1 || {
  tail -30 /tmp/march-release-forge.log; die "forge/test failed (log: /tmp/march-release-forge.log)"; }

# --force is load-bearing: without it these aliases exit 0 having done nothing.
for alias in @types-check @grammar-check; do
  echo "  dune build --force $alias   (CI-only; vacuous without --force)"
  dune build --root . --force "$alias" >/tmp/march-release-alias.log 2>&1 || {
    tail -30 /tmp/march-release-alias.log; die "$alias failed (log: /tmp/march-release-alias.log)"; }
done

echo "  scripts/check-docs.sh"
./scripts/check-docs.sh >/dev/null 2>&1 || die "doc-lint failed"

if [ "$dry_run" -eq 1 ]; then
  printf '\n--dry-run: all checks passed; no files written, no tag created.\n'
  exit 0
fi

# ── 3-6. finalize, bump, commit, tag ───────────────────────────────────────
step "3/7  finalize CHANGELOG"
today="$(date -u +%Y-%m-%d)"
tmp="$(mktemp)"
awk -v ver="$version" -v date="$today" '
  /^## \[Unreleased\]/ && !done {
    print "## [Unreleased]"; print ""; print "## [" ver "] - " date; done = 1; next
  }
  { print }
' CHANGELOG.md > "$tmp"
mv "$tmp" CHANGELOG.md
echo "  [Unreleased] -> [$version] - $today, fresh [Unreleased] opened"

step "4/7  set dune-project version"
tmp="$(mktemp)"
sed "s/^(version .*)$/(version $version)/" dune-project > "$tmp"
mv "$tmp" dune-project
[ "$(march_version)" = "$version" ] || die "dune-project rewrite did not take"
echo "  (version $version)"

step "5/7  regenerate opam files and verify the binary agrees"
dune build --root . @install 2>&1 | tail -3 || true
dune build --root . bin/main.exe 2>&1 | tail -3 || die "rebuild failed"
built="$(./_build/default/bin/main.exe --version | awk '{print $2}')"
[ "$built" = "$version" ] || die "built binary reports '$built', expected '$version'"
echo "  march --version reports $version"

step "6/7  commit and tag"
git add CHANGELOG.md dune-project march.opam march-lsp.opam forge.opam
git commit -q -m "release: $version"
git tag -a "v$version" -m "March $version"
./scripts/check-version-tag.sh "v$version" || die "tag guard failed on the release commit"
echo "  committed and tagged v$version"

step "7/7  next steps (not done for you)"
cat <<NEXT

  Push, in this order:

      git push origin main
      git push origin v$version      # this STARTS the release publish

  Still manual -- no script should own these:

    - docs/upgrading-to-${version//./-}.md   the migration guide
    - docs/_layouts/landing.html:466         hero badge "Early Access . v$current"
    - docs/tooling.md                        four examples pin a concrete version

    Also: docs/upgrading-to-0-3-0.md is linked from nowhere on the site. Link
    the new guide from the docs nav, and the 0.3.0 one retroactively.

  dune-project stays at $version (the last released version). Nightlies derive
  $version+patch-nightly.YYYYMMDD from it via scripts/nightly-version.sh; there
  is no -dev suffix to set.
NEXT
