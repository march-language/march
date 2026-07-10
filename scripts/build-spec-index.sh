#!/usr/bin/env bash
# Rebuilds the spec-search FTS5 index from specs/lang, specs/impl, and
# specs/features into .claude/skills/spec-search/ (docs/ + spec-search.db).
#
# Run this after editing files in those directories, review the diff under
# .claude/skills/spec-search/, commit, then re-copy that directory to
# ~/.claude/skills/spec-search/ to make the change visible to Claude.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills/spec-search"
DOCS_DIR="$SKILL_DIR/docs"

for cmd in python3 sqlite3 git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: $cmd not found on PATH" >&2
    exit 1
  fi
done

for src in specs/lang specs/impl specs/features; do
  if [[ ! -d "$REPO_ROOT/$src" ]]; then
    echo "error: $REPO_ROOT/$src does not exist" >&2
    exit 1
  fi
done

rm -rf "$DOCS_DIR"
mkdir -p "$DOCS_DIR/lang" "$DOCS_DIR/impl" "$DOCS_DIR/features"

cp "$REPO_ROOT"/specs/lang/*.md "$DOCS_DIR/lang/"
cp "$REPO_ROOT"/specs/impl/*.md "$DOCS_DIR/impl/"
cp "$REPO_ROOT"/specs/features/*.md "$DOCS_DIR/features/"

COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
DATE="$(date -u +%Y-%m-%d)"

python3 "$REPO_ROOT/scripts/spec_index_build.py" "$SKILL_DIR" "$COMMIT" "$DATE"

SECTION_COUNT="$(sqlite3 "$SKILL_DIR/spec-search.db" 'SELECT count(*) FROM sections;')"
echo "Built $SKILL_DIR/spec-search.db ($SECTION_COUNT sections, commit ${COMMIT:0:8}, $DATE)"
