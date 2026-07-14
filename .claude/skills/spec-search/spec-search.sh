#!/usr/bin/env bash
# Full-text search over the vendored March spec docs (specs/lang, specs/impl,
# specs/features) via the FTS5 index in spec-search.db, sitting next to this
# script. Self-locating: works from any cwd, and after this whole directory
# is copied elsewhere (e.g. ~/.claude/skills/spec-search/).
#
# Usage: spec-search.sh [-n N] [--json] "<query>"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB="$SCRIPT_DIR/spec-search.db"

N=10
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)
      N="$2"
      shift 2
      ;;
    --json)
      JSON=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "unknown flag: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

QUERY="${1:-}"
if [[ -z "$QUERY" ]]; then
  echo "usage: spec-search.sh [-n N] [--json] \"<query>\"" >&2
  exit 1
fi

if [[ ! -f "$DB" ]]; then
  echo "error: $DB not found (expected next to spec-search.sh)" >&2
  exit 1
fi

# Build a safe FTS5 MATCH string: each whitespace-separated word, stripped to
# alnum/_/- and double-quoted as a literal token, ANDed together implicitly.
# This avoids both SQL-injection (no quotes survive stripping) and FTS5
# query-syntax injection (quoted tokens can't be reinterpreted as operators).
MATCH=""
for word in $QUERY; do
  clean="$(printf '%s' "$word" | tr -cd '[:alnum:]_-')"
  if [[ -n "$clean" ]]; then
    MATCH+="\"$clean\" "
  fi
done
MATCH="${MATCH% }"

if [[ -z "$MATCH" ]]; then
  echo "error: query has no searchable terms after sanitizing" >&2
  exit 1
fi

if [[ "$JSON" -eq 1 ]]; then
  sqlite3 -json "$DB" <<SQL
SELECT file, heading_path, lineno, end_lineno,
       snippet(sections, 2, '**', '**', ' ... ', 20) AS snippet,
       bm25(sections) AS score
FROM sections
WHERE sections MATCH '$MATCH'
ORDER BY bm25(sections)
LIMIT $N;
SQL
else
  sqlite3 "$DB" <<SQL
.mode list
SELECT file || ':' || heading_path || '  (L' || lineno || '-' || (end_lineno - 1) || ')' || char(10) ||
       snippet(sections, 2, '>> ', ' <<', ' ... ', 24) || char(10) || '---'
FROM sections
WHERE sections MATCH '$MATCH'
ORDER BY bm25(sections)
LIMIT $N;
SQL
fi
