#!/usr/bin/env bash
# Canonicalising IR diff: proves two compilers emit the same functions when
# the only expected differences are definition order and fresh-name numbering.
#
#   scripts/ir-canon-diff.sh <base-dir> <new-dir>
#
# Each argument is a directory of `.ll` files with matching names, for example
# the `work/` directory `scripts/ir-oracle.sh` leaves behind.  ir-oracle hashes
# the raw text, so a pass that reorders definitions or shifts a fresh-name
# counter turns every program red there even though no function changed.  This
# script splits each `.ll` into top-level chunks (a `define ... { ... }` body,
# or one line of anything else: globals, declares, metadata), masks the
# compiler's numbered names, sorts the chunks, and diffs the result.
#
# Masked: `$nafuse_lam<N>` / `$lam<N>`-style numbered suffixes after a `$`;
# the trailing counter of every register and label (`%ld355`, `case_br30:`);
# string-pool and record-shape global indices (`@.str121`, `@.fnt.s7`); the
# inliner's instance suffix (`_i85`); metadata numbers.  NOT masked: opcodes,
# types, constants, string contents, and every function symbol, so a changed
# body or a call that now resolves to a different function still shows.
#
# A masked name can hide a renumbering that swaps two distinct functions with
# identical bodies; that is the intended blind spot.  It cannot hide a function
# that exists on one side only, a changed body, or a changed callee.
#
# Exit 0: every program identical after canonicalisation.  Exit 1: lists each
# program that differs (diffs under <new-dir>/canon-diff/).  Exit 2: usage or a
# program missing from one side.
set -uo pipefail

USAGE='usage: ir-canon-diff.sh <base-dir> <new-dir>'
BASE="${1:?$USAGE}"
NEW="${2:?$USAGE}"
[ -d "$BASE" ] && [ -d "$NEW" ] || { echo "$USAGE"; exit 2; }

OUT="$NEW/canon-diff"
rm -rf "$OUT"; mkdir -p "$OUT"

canon() {
  python3 -I - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
chunks, cur, depth = [], [], 0
for line in text.split("\n"):
    if depth == 0 and not line.startswith("define "):
        if line.strip():
            chunks.append(line)
        continue
    cur.append(line)
    if depth == 0:
        depth = 1 if line.rstrip().endswith("{") else 0
        if depth == 0:
            chunks.append("\n".join(cur)); cur = []
    elif line == "}":
        depth = 0
        chunks.append("\n".join(cur)); cur = []
if cur:
    chunks.append("\n".join(cur))
mask = [
    (re.compile(r"(\$[A-Za-z_]*?)\d+"), r"\1N"),   # $nafuse_lam12, $lam3, $7
    (re.compile(r"%\d+\b"), "%N"),                 # numbered locals
    (re.compile(r"!\d+\b"), "!N"),                 # numbered metadata
    (re.compile(r"@\.fnt\.s\d+"), "@.fnt.sN"),      # fn-table string pool index
]
# The emitter's fresh-name counter is module-wide, so emitting two functions
# in the other order renumbers every register, label and string global in
# both: `%ld355`, `case_br30:`, `@.str121`.  Inlined locals also carry the
# inliner's instance counter (`%c_i85_i384.addr`).
local = re.compile(r"%[\w$.]+")
inl = re.compile(r"_i\d+")
trail = re.compile(r"\d+(?=$|\.)")
labeldef = re.compile(r"^([A-Za-z_.]+?)\d+:", re.M)
strglob = re.compile(r"@\.(str|strcell|recshape)\d+")
def mask_local(m):
    return trail.sub("N", inl.sub("_iN", m.group(0)))
out = []
for c in chunks:
    for rx, rep in mask:
        c = rx.sub(rep, c)
    c = local.sub(mask_local, c)
    c = labeldef.sub(r"\1N:", c)
    c = strglob.sub(r"@.\1N", c)
    out.append(c)
out.sort()
sys.stdout.write("\n".join(out) + "\n")
PY
}

total=0; differ=0; missing=0
for b in "$BASE"/*.ll; do
  [ -e "$b" ] || { echo "FATAL: no .ll files in $BASE"; exit 2; }
  name="$(basename "$b")"
  n="$NEW/$name"
  total=$((total + 1))
  if [ ! -f "$n" ]; then
    echo "MISSING in new: $name"; missing=$((missing + 1)); continue
  fi
  if cmp -s "$b" "$n"; then continue; fi
  canon "$b" > "$OUT/$name.base"
  canon "$n" > "$OUT/$name.new"
  if cmp -s "$OUT/$name.base" "$OUT/$name.new"; then
    rm -f "$OUT/$name.base" "$OUT/$name.new"
  else
    diff -u "$OUT/$name.base" "$OUT/$name.new" > "$OUT/$name.diff"
    echo "DIFFERS: $name ($(grep -c '^[+-][^+-]' "$OUT/$name.diff") lines)"
    differ=$((differ + 1))
  fi
done
for n in "$NEW"/*.ll; do
  [ -e "$n" ] || continue
  [ -f "$BASE/$(basename "$n")" ] || { echo "MISSING in base: $(basename "$n")"; missing=$((missing + 1)); }
done

[ "$total" -ge 1 ] || { echo "FATAL: nothing compared"; exit 2; }
if [ "$missing" -gt 0 ]; then
  echo "$missing program(s) present on one side only"; exit 2
fi
if [ "$differ" -gt 0 ]; then
  echo "CANONICAL IR CHANGED in $differ of $total programs (diffs: $OUT)"; exit 1
fi
echo "CANONICAL IR IDENTICAL across $total programs"
