#!/usr/bin/env bash
#
# build-search-index.sh — build the Pagefind full-text index for a built docs site.
#
# Pagefind is a POST-BUILD indexer: it crawls generated HTML rather than Jekyll sources.
# That is load-bearing here, because the searchable site has two families of pages that
# share no source format:
#
#   * ~55 Jekyll pages (guides, cookbook, landing) rendered from docs/**/*.md, and
#   * 114 stdlib API pages under docs/docs/stdlib/*.html — pre-generated static HTML
#     committed to this repo by the EXTERNAL `march_doc` tool (see gen-stdlib-docs.sh).
#
# Indexing the output is the only point at which both are the same kind of thing.
#
# Pages opt IN by carrying `data-pagefind-body`. Pagefind's rule is that once any page in
# the crawl has that attribute, ONLY pages with it are indexed — which is how the
# playground, Tetris, perihelion and decision-graph pages stay out with no exclude rules.
# The Jekyll layouts set the attribute themselves; the stdlib pages can't, because we do
# not own their generator, so this script injects it into the BUILT COPY below. Operating
# on the build output means a future stdlib regeneration can never undo it.
#
# Usage:  scripts/build-search-index.sh [site-dir]      (default: ./_site)

set -euo pipefail

# Pinned: an index built by one Pagefind version is read by that version's pagefind.js,
# and floating the version would silently change ranking between deploys.
PAGEFIND_VERSION="1.3.0"

SITE_DIR="${1:-_site}"

if [ ! -d "$SITE_DIR" ]; then
  echo "error: site directory '$SITE_DIR' does not exist — build the site first" >&2
  exit 1
fi

# ── Mark the generated stdlib pages as indexable ──────────────────────────────
#
# `<main id="main">` on those pages holds the module body only; the ~1900-line symbol
# sidebar is a sibling `<nav id="sb">` and so is correctly left out of the index. Without
# this, every stdlib page would either be skipped entirely or match every symbol name in
# the whole library.
STDLIB_DIR="$SITE_DIR/docs/stdlib"
if [ -d "$STDLIB_DIR" ]; then
  # BSD sed (macOS) and GNU sed (CI) disagree on -i; -i.bak is the portable spelling.
  find "$STDLIB_DIR" -name '*.html' -exec sed -i.bak \
    's|<main id="main">|<main id="main" data-pagefind-body data-pagefind-filter="section:Stdlib">|g' {} +
  find "$STDLIB_DIR" -name '*.html.bak' -delete
  echo "==> Tagged $(find "$STDLIB_DIR" -name '*.html' | wc -l | tr -d ' ') stdlib pages as indexable"
else
  echo "warning: $STDLIB_DIR not found — stdlib API pages will be missing from search" >&2
fi

# ── Build the index ───────────────────────────────────────────────────────────
#
# Clear any pre-existing output first. The committed docs/pagefind/ copy is served by
# GitHub's Jekyll (see gen-docs-search-index.sh) and therefore lands in $SITE_DIR during
# the Jekyll build. Pagefind's filenames are content-hashed, so without this the previous
# generation's hashed .pf_meta / .pf_filter files would survive alongside the new ones.
rm -rf "$SITE_DIR/pagefind"

echo "==> Running Pagefind $PAGEFIND_VERSION over $SITE_DIR"
npx -y "pagefind@$PAGEFIND_VERSION" --site "$SITE_DIR"

# ── Assert the index is non-empty ─────────────────────────────────────────────
#
# The failure mode this guards against is silent: if the `data-pagefind-body` markers are
# ever dropped from the layouts, Pagefind still exits 0 and still writes a pagefind/
# directory — it just indexes nothing, and the site ships a search box that finds
# nothing. Fail the build loudly instead.
ENTRY="$SITE_DIR/pagefind/pagefind.js"
if [ ! -f "$ENTRY" ]; then
  echo "error: Pagefind produced no $ENTRY" >&2
  exit 1
fi

# Each indexed page becomes one fragment file.
FRAGMENTS=$(find "$SITE_DIR/pagefind/fragment" -name '*.pf_fragment' 2>/dev/null | wc -l | tr -d ' ')
MIN_PAGES=100
if [ "$FRAGMENTS" -lt "$MIN_PAGES" ]; then
  echo "error: search index has only $FRAGMENTS pages (expected >= $MIN_PAGES)." >&2
  echo "       Check that the layouts still carry data-pagefind-body." >&2
  exit 1
fi

echo "==> Search index built: $FRAGMENTS pages"
