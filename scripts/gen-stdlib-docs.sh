#!/usr/bin/env bash
#
# gen-stdlib-docs.sh — regenerate the committed stdlib API-reference HTML.
#
# The site at march-lang.org serves pre-generated HTML committed to the repo. Nothing in
# CI runs the doc generator. So whenever a stdlib module is added/changed, these pages
# must be regenerated and committed, or the live site goes stale (which is exactly how
# the 11 modules added after 2026-04-13 went missing from the reference).
#
# WHICH SITE IS PRODUCTION: march-lang.org is served by THIS repo's own GitHub Pages —
# `cname march-lang.org, source {branch: main, path: /docs}`, i.e. GitHub's own legacy
# Jekyll running over docs/ with no post-build hook. It is NOT served by
# deploy-pages.yml, which publishes a separately-built copy to the
# march-language.github.io repo (reachable at https://march-language.github.io/). An
# earlier version of this comment claimed deploy-pages.yml served march-lang.org; it does
# not, and that mistake is why docs/pagefind/ initially shipped missing from production.
# Anything that must appear on march-lang.org has to be committed under docs/.
#
# OUTPUT PATH: the generated reference is served at the URL /docs/stdlib/. Jekyll's
# source root is the `docs/` directory, and a directory's URL is its path *relative to
# that root* — so to land at /docs/stdlib/ the files must live at docs/docs/stdlib/.
# (The hand-written docs pages reach /docs/... via explicit front-matter `permalink:`
# keys, which these generated static HTML files can't carry.)
#
# This script encapsulates the otherwise-tribal regeneration command. It builds the
# in-repo compiler + forge, obtains the march_doc generator, and runs `forge doc`.
#
# Usage:  scripts/gen-stdlib-docs.sh
#
# Requirements: dune + the OCaml toolchain on PATH (in CI, after `eval $(opam env)`).
# march_doc is auto-cloned from GitHub if not already present locally.
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$ROOT"

# Served at /docs/stdlib/ ; physically nested under docs/ (the Jekyll source root).
OUT_DIR="docs/docs/stdlib"

echo "==> Building compiler + forge"
# --root pins the build to this checkout. Required when running from a git worktree
# nested inside another repo (plain `dune build` walks up to the parent); harmless in a
# standalone CI checkout.
dune build --root "$ROOT" bin/main.exe forge/bin/main.exe

# Expose the freshly-built compiler as `march` ON PATH. We copy (not symlink) into the
# dune bin dir: the compiler locates its C runtime exe-relative as ../runtime, which is
# _build/default/runtime (dune's copy). A symlink elsewhere would break that resolution.
cp -f _build/default/bin/main.exe _build/default/bin/march
export PATH="$ROOT/_build/default/bin:$PATH"

# Obtain the march_doc generator. `forge doc` discovers it as ./march_doc (cwd-relative),
# ../march_doc, ~/code/march_doc, or the global archive registry. In CI none exist, so
# clone the public repo into ./march_doc (it has no external deps).
if [ ! -d march_doc ] && [ ! -d "$HOME/code/march_doc" ]; then
  echo "==> Cloning march_doc generator"
  git clone --depth 1 https://github.com/march-language/march_doc.git march_doc
fi

echo "==> Generating stdlib docs into $OUT_DIR/ (served at /docs/stdlib/)"
export MARCH_STDLIB="$ROOT/stdlib"
_build/default/forge/bin/main.exe doc --stdlib -o "$OUT_DIR"

# The module URI was renamed URI -> Uri; on case-insensitive filesystems git may keep
# the old-case filename while the regenerated index links the new case (a 404 on
# case-sensitive Pages servers). If git still tracks the upper-case path, rename it.
# Guarded by `ls-files` so it is a safe no-op once the rename has landed.
if git ls-files --error-unmatch "$OUT_DIR/URI.html" >/dev/null 2>&1; then
  git mv -f "$OUT_DIR/URI.html" "$OUT_DIR/Uri.html"
fi

echo "==> Done. Review with: git status $OUT_DIR"
