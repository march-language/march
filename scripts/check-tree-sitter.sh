#!/usr/bin/env bash
# check-tree-sitter.sh — does tree-sitter-march/ parse the March the compiler accepts?
#
# Design: specs/2026-09-23-tree-sitter-grammar-sync-design.md §6.1.  Every
# step runs against a grammar built HERE, from this checkout, in a private
# temp HOME: `tree-sitter parse` otherwise resolves the grammar through
# ~/.config/tree-sitter/config.json (which can name another checkout) and a
# cached march.dylib that `tree-sitter generate` does not invalidate.
#
#   1. freshness  delete src/parser.c, `tree-sitter generate` (its exit status
#                 checked: a failed generate leaves the OLD parser.c buildable),
#                 and require parser.c / grammar.json / node-types.json to match
#                 the committed files;
#   2. corpus     `tree-sitter test -p` (never -l: 0.26 ignores it and uses a
#                 cached library keyed by language name);
#   3. queries    every .scm under tree-sitter-march/queries/ and
#                 zed-march/languages/march/ must compile against the grammar;
#   4. ratchet    every .march under stdlib/ test/ examples/ bench/ specs/lang/
#                 (except specs/lang/grammar/reject/) must parse with no ERROR or
#                 MISSING node, unless listed in tree-sitter-march/known-failures.txt;
#                 a listed file that now parses, or no longer exists, is also red,
#                 so the list only shrinks.
#
#   --self-test   instead prove the ratchet measures the grammar it just built:
#                 remove the match-arm `when` guard from a copy, rebuild, and
#                 require test/snapshots/src/guard_match.march to start failing.
#
# Needs the tree-sitter CLI (0.26.x: the committed parser.c was generated with
# 0.26.7, and another version regenerates it differently) and a C compiler.
set -uo pipefail
export LC_ALL=C

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TSM="$ROOT/tree-sitter-march"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/check-tree-sitter.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CACHE_HOME="$TMP/home/.cache"
mkdir -p "$HOME"

red=0
fail() { echo "FAIL: $*"; red=1; }

command -v tree-sitter >/dev/null || { echo "tree-sitter CLI not found"; exit 2; }

# build <grammar-dir> <out-lib>: generate from scratch, then compile.
build() {
  local dir=$1 lib=$2
  rm -f "$dir/src/parser.c"
  if ! (cd "$dir" && tree-sitter generate >"$TMP/generate.log" 2>&1); then
    cat "$TMP/generate.log"; return 1
  fi
  [ -f "$dir/src/parser.c" ] || { echo "generate wrote no parser.c"; return 1; }
  (cd "$dir" && tree-sitter build -o "$lib" . >"$TMP/build.log" 2>&1) || { cat "$TMP/build.log"; return 1; }
}

corpus_files() {
  (cd "$ROOT" && find stdlib test examples bench specs/lang -name '*.march' \
      -not -path 'specs/lang/grammar/reject/*' | LC_ALL=C sort)
}

# failing <lib>: accepted-by-tree-sitter test — prints files with ERROR/MISSING.
failing() {
  corpus_files > "$TMP/paths.txt"
  (cd "$ROOT" && tree-sitter parse -l "$1" --lang-name march -q -s --paths "$TMP/paths.txt" 2>/dev/null) \
    | grep -E '\((ERROR|MISSING)' | awk '{print $1}' | LC_ALL=C sort -u
}

if [ "${1:-}" = "--self-test" ]; then
  cp -R "$TSM" "$TMP/good" && cp -R "$TSM" "$TMP/bad"
  python3 - "$TMP/bad/grammar.js" <<'EOF' || exit 2
import sys
p = sys.argv[1]; s = open(p).read()
needle = "      optional($.when_guard),\n      '->',\n      field('body', $.block_body),"
assert needle in s, "self-test perturbation site not found in grammar.js"
open(p, 'w').write(s.replace(needle, "      '->',\n      field('body', $.block_body),", 1))
EOF
  build "$TMP/good" "$TMP/good.so" || { echo "self-test: build failed"; exit 1; }
  build "$TMP/bad" "$TMP/bad.so" || { echo "self-test: perturbed build failed"; exit 1; }
  failing "$TMP/good.so" > "$TMP/good.txt"
  failing "$TMP/bad.so" > "$TMP/bad.txt"
  if comm -13 "$TMP/good.txt" "$TMP/bad.txt" | grep -qx 'test/snapshots/src/guard_match.march'; then
    echo "self-test: ok (removing match-arm guards breaks guard_match.march)"
    exit 0
  fi
  echo "self-test: FAIL — the perturbed grammar did not change the result, so the"
  echo "check is not measuring the grammar it builds."
  exit 1
fi

# 1. freshness
cp -R "$TSM" "$TMP/tsm"
if ! build "$TMP/tsm" "$TMP/march.so"; then
  echo "FAIL: tree-sitter generate/build failed"; exit 1
fi
for f in src/parser.c src/grammar.json src/node-types.json; do
  cmp -s "$TSM/$f" "$TMP/tsm/$f" || fail "tree-sitter-march/$f is stale: run \`tree-sitter generate\` in tree-sitter-march/ and commit it"
done

# 2. corpus tests
if ! (cd "$TMP/tsm" && tree-sitter test -p . >"$TMP/test.log" 2>&1); then
  grep -E '✗|failed' "$TMP/test.log" | head -20
  fail "tree-sitter test: corpus expectations do not match"
fi
if grep -lE '\((ERROR|MISSING)' "$TSM"/test/corpus/*.txt >/dev/null 2>&1; then
  fail "a test/corpus expectation contains an ERROR or MISSING node"
fi

# 3. queries
for q in "$TSM"/queries/*.scm "$ROOT"/zed-march/languages/march/*.scm; do
  [ -f "$q" ] || continue
  # Captured, not piped into grep: under pipefail the query command's own
  # non-zero exit would make the `if` false exactly when the query is broken.
  qout=$(cd "$ROOT" && tree-sitter query -p "$TMP/tsm" "$q" stdlib/list.march 2>&1)
  if grep -qE 'Query compilation failed|Query error' <<<"$qout"; then
    fail "query does not compile against the grammar: ${q#$ROOT/}"
  fi
done

# 4. ratchet
failing "$TMP/march.so" > "$TMP/failing.txt"
grep -vE '^\s*(#|$)' "$TSM/known-failures.txt" | awk '{print $1}' | LC_ALL=C sort -u > "$TMP/known.txt"
new=$(comm -23 "$TMP/failing.txt" "$TMP/known.txt")
stale=$(comm -13 "$TMP/failing.txt" "$TMP/known.txt")
if [ -n "$new" ]; then
  echo "$new" | sed 's/^/  new tree-sitter failure: /'
  fail "files the grammar cannot parse (fix grammar.js, or list them in tree-sitter-march/known-failures.txt with a todo)"
fi
if [ -n "$stale" ]; then
  echo "$stale" | sed 's/^/  stale entry (parses now, or no longer exists): /'
  fail "delete these lines from tree-sitter-march/known-failures.txt"
fi

total=$(wc -l < "$TMP/paths.txt" | tr -d ' ')
nfail=$(wc -l < "$TMP/failing.txt" | tr -d ' ')
echo "tree-sitter: $((total - nfail))/$total files parse clean; $nfail known failures"
[ $red -eq 0 ] && echo "check-tree-sitter: ok" || echo "check-tree-sitter: FAILED"
exit $red
