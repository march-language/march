#!/usr/bin/env bash
#
# serve-docs.sh — build the docs site WITH its search index and serve it locally.
#
# Why not `jekyll serve`? The Pagefind index lives at _site/pagefind/, which Jekyll does
# not know about and wipes on every rebuild. So a plain `jekyll serve` gives you a site
# whose ⌘K box reports a missing index. This script does the full production sequence —
# jekyll build -> pagefind -> serve the static output — which is what CI does too.
#
# Trade-off: no live reload. Re-run the script after editing.
#
# Usage:  scripts/serve-docs.sh [port]        (default port: 4000)

set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"

PORT="${1:-4000}"
SITE_DIR="$ROOT/_site"

# Jekyll's SCSS converter reads files using the process locale. Under a bare/POSIX
# locale it treats them as US-ASCII and dies on the first non-ASCII byte ("Invalid
# US-ASCII character \xE2"). CI sets a UTF-8 locale by default; interactive shells here
# may not.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# The system Ruby on macOS is 2.6, far too old for the github-pages gem. mise provides
# 3.3 (matching ruby-version in .github/workflows/deploy-pages.yml). Fall back to a
# bare `bundle` when mise is absent, e.g. in CI.
if command -v mise >/dev/null 2>&1 && mise ls ruby 2>/dev/null | grep -q '3\.3'; then
  BUNDLE=(mise x ruby@3.3 -- bundle)
else
  BUNDLE=(bundle)
fi

echo "==> Installing docs gems"
(cd docs && "${BUNDLE[@]}" install --quiet)

echo "==> Building Jekyll site"
(cd docs && "${BUNDLE[@]}" exec jekyll build --baseurl "" --destination "$SITE_DIR")

scripts/build-search-index.sh "$SITE_DIR"

echo "==> Serving $SITE_DIR at http://localhost:$PORT"
# Ruby's stdlib httpd: no extra dependency, and unlike `jekyll serve` it serves the
# built output verbatim, pagefind/ included.
if command -v mise >/dev/null 2>&1 && mise ls ruby 2>/dev/null | grep -q '3\.3'; then
  exec mise x ruby@3.3 -- ruby -run -e httpd -- "$SITE_DIR" -p "$PORT"
else
  exec ruby -run -e httpd -- "$SITE_DIR" -p "$PORT"
fi
