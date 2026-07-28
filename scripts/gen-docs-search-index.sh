#!/usr/bin/env bash
#
# gen-docs-search-index.sh — regenerate the committed Pagefind index at docs/pagefind/.
#
# WHY THIS IS COMMITTED, when generated artifacts normally are not
# ------------------------------------------------------------------
# march-lang.org is NOT served by .github/workflows/deploy-pages.yml. That workflow
# publishes a fully-built site to the march-language.github.io repo, but the production
# domain is served by *this* repo's own GitHub Pages, configured as:
#
#     repo march-language/march   cname march-lang.org   source {branch: main, path: /docs}
#
# i.e. GitHub's own legacy Jekyll runs over docs/ directly. There is no post-build hook in
# that path, so a search index can only reach march-lang.org by being committed — exactly
# the same reason the 114 generated stdlib API pages under docs/docs/stdlib/ are committed
# (see gen-stdlib-docs.sh; note its header claims deploy-pages.yml serves march-lang.org,
# which is not correct).
#
# Jekyll's source root is docs/, so a directory at docs/pagefind/ is served at /pagefind/,
# which is where _includes/search.html looks for it.
#
# CONSEQUENCE: this index goes stale whenever docs content or layouts change, and stale
# means the live search silently returns outdated results. `--check` guards that, and runs
# in CI.
#
# Usage:
#   scripts/gen-docs-search-index.sh            regenerate docs/pagefind/
#   scripts/gen-docs-search-index.sh --check    verify it is up to date (exit 1 if stale)

set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"

MODE="${1:-generate}"
OUT_DIR="$ROOT/docs/pagefind"
DIGEST_FILE="$OUT_DIR/.source-digest"

# Jekyll's SCSS converter reads files using the process locale and dies on the first
# non-ASCII byte under a bare/POSIX one.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# Resolved as an ARGV array, not a shell function: `xargs` execs a real binary and cannot
# see shell functions. A function named `sha256` silently resolved to macOS's /sbin/sha256
# under xargs while failing outright on Linux ("xargs: sha256: No such file or directory"),
# which made the digest both non-portable and green locally.
if command -v sha256sum >/dev/null 2>&1; then
  SHA=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  SHA=(shasum -a 256)
else
  echo "error: need either sha256sum or shasum on PATH" >&2
  exit 1
fi

# A digest over every file that can affect what gets indexed: page content (*.md), the
# generated stdlib API pages and the layouts/includes that wrap them (*.html). Paths are
# included in the hash so a rename is caught too.
#
# Not byte-comparing the index itself: Pagefind's output is deliberately NOT reproducible
# (filenames and the entry hash embed a per-run content hash — verified: two consecutive
# runs over identical input produce different en_*.pf_filter names), so `git diff` on the
# index would fail on every run and teach everyone to ignore it.
#
# Listed with `git ls-files`, NOT `find`: only TRACKED files reach GitHub Pages, so only
# tracked files may influence the digest. A bare `find docs` walks the working tree and
# silently folds in untracked pages, which makes the committed digest unreproducible for
# anyone else — including CI, whose clean checkout does not have them. `.gitignore` line
# 44 ignores `docs/superpowers/` while sibling plans committed before that rule are still
# tracked, so an ignored `.md` sitting in that directory is the ordinary case, not an
# exotic one. Observed 2026-07-28: a local plan file there made `--check` pass locally and
# fail in CI with a digest mismatch and no indication why.
source_digest() {
  git ls-files -z -- docs \
    | tr '\0' '\n' \
    | grep -E '\.(md|html)$' \
    | grep -v '^docs/pagefind/' \
    | LC_ALL=C sort \
    | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done \
    | tr '\n' '\0' \
    | xargs -0 "${SHA[@]}" \
    | "${SHA[@]}" \
    | cut -d' ' -f1
}

CURRENT="$(source_digest)"

# Print the digest and stop. Useful for diagnosing a staleness failure, and for
# re-stamping .source-digest when the digest ALGORITHM changed but the index contents did
# not — regenerating would otherwise churn 193 content-hashed files for nothing.
if [ "$MODE" = "--digest" ]; then
  echo "$CURRENT"
  exit 0
fi

if [ "$MODE" = "--check" ]; then
  if [ ! -f "$DIGEST_FILE" ]; then
    echo "error: $DIGEST_FILE is missing — the committed search index has never been generated." >&2
    echo "       Run: scripts/gen-docs-search-index.sh" >&2
    exit 1
  fi
  RECORDED="$(cat "$DIGEST_FILE")"
  if [ "$CURRENT" != "$RECORDED" ]; then
    echo "error: docs/pagefind/ is STALE — docs content or layouts changed since it was built." >&2
    echo "       recorded: $RECORDED" >&2
    echo "       current:  $CURRENT" >&2
    echo "       Regenerate and commit:  scripts/gen-docs-search-index.sh" >&2
    exit 1
  fi
  echo "ok — committed search index matches docs sources ($CURRENT)"
  exit 0
fi

# ── Regenerate ────────────────────────────────────────────────────────────────
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

# The system Ruby on macOS is 2.6, far too old for the github-pages gem; mise provides
# 3.3, matching ruby-version in .github/workflows/deploy-pages.yml.
if command -v mise >/dev/null 2>&1 && mise ls ruby 2>/dev/null | grep -q '3\.3'; then
  BUNDLE=(mise x ruby@3.3 -- bundle)
else
  BUNDLE=(bundle)
fi

echo "==> Building Jekyll site"
(cd docs && "${BUNDLE[@]}" install --quiet)
(cd docs && "${BUNDLE[@]}" exec jekyll build --baseurl "" --destination "$BUILD_DIR")

"$ROOT/scripts/build-search-index.sh" "$BUILD_DIR"

echo "==> Syncing index into docs/pagefind/"
# Replace wholesale rather than merging: Pagefind's filenames are content-hashed, so a
# merge would silently accumulate every previous generation's orphaned shards.
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -R "$BUILD_DIR/pagefind/." "$OUT_DIR/"

printf '%s\n' "$CURRENT" > "$DIGEST_FILE"

echo "==> docs/pagefind/ regenerated ($(find "$OUT_DIR" -type f | wc -l | tr -d ' ') files, $(du -sh "$OUT_DIR" | cut -f1))"
echo "    Commit it together with the docs change that prompted it."
