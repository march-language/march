#!/usr/bin/env bash
# Regression: the whole-binary CAS key must digest the runtime directory that
# is ACTUALLY compiled.
#
# The bug: lib/cas/cas.ml resolved its own runtime-directory candidate list
# cwd-FIRST ("runtime", then exe-relative), while bin/main.ml resolves the
# sources it hands to clang exe-relative-FIRST, "independent of CWD".  With cwd
# at the repo root and the exe at _build/default/bin/main.exe, the cache key
# digested ./runtime/*.c while the compile used _build/default/runtime/*.c.
# Since a targeted `dune build bin/main.exe` does not refresh
# _build/default/runtime, the two diverge, and editing a runtime source printed
# `compiled <out> (cached)` for a binary containing none of the new code.
# Cas.compiler_identity does not cover it: the march executable's bytes do not
# change when only runtime C changes.
#
# This test simulates exactly that divergence: two runtime directories with
# different contents, the same March source, the same CAS store.  Compiling
# against the second directory must produce a binary built from ITS sources.
#
# Requires: MARCH_BIN, a working C toolchain (the rule is skipped without one).

set -u

MARCH_BIN=${MARCH_BIN:?MARCH_BIN must be set}
MARCH_BIN=$(cd "$(dirname "$MARCH_BIN")" && pwd)/$(basename "$MARCH_BIN")

if ! command -v cc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
  echo "cas_runtime_dir_check: no C compiler, skipping" >&2
  exit 0
fi

# The runtime sources as staged by dune (source_tree ../runtime dep).
SRC_RUNTIME=$(cd "$(dirname "$0")/../runtime" 2>/dev/null && pwd) || SRC_RUNTIME=""
if [ -z "$SRC_RUNTIME" ] || [ ! -f "$SRC_RUNTIME/march_runtime.c" ]; then
  echo "cas_runtime_dir_check: cannot locate runtime sources, skipping" >&2
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/march_cas_rtdir.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

# Two runtime trees: identical except that B announces itself at startup.
cp -R "$SRC_RUNTIME" rtA || exit 1
cp -R "$SRC_RUNTIME" rtB || exit 1
# dune stages source_tree deps read-only; the copies must be writable.
chmod -R u+w rtA rtB || exit 1
cat >> rtB/march_runtime.c <<'EOF'

/* cas_runtime_dir_check marker: observable proof of WHICH runtime dir was
   compiled into the binary. */
#include <stdio.h>
__attribute__((constructor))
static void march_cas_rtdir_marker(void) {
  fputs("RUNTIME_DIR_B\n", stderr);
}
EOF

cat > prog.march <<'EOF'
mod CasRtDirProg do

  fn main() : Int do
    println("ok")
    0
  end

end
EOF

fail() { echo "cas_runtime_dir_check: FAIL: $*" >&2; exit 1; }

compile() { # $1 = runtime dir, $2 = output binary
  MARCH_RUNTIME_DIR="$WORK/$1" "$MARCH_BIN" --compile -o "$2" prog.march \
    > "$2.compile.log" 2>&1
  rc=$?
  [ $rc -eq 0 ] || { cat "$2.compile.log" >&2; fail "compile against $1 exited $rc"; }
}

# 1. Compile against A.
compile rtA outA
./outA > outA.stdout 2> outA.stderr || fail "outA did not run"
grep -q RUNTIME_DIR_B outA.stderr && fail "binary built from rtA contains rtB's marker"

# 2. Compile the SAME source against A again — this must hit the cache, which
#    proves the store is shared and warm for step 3 (otherwise step 3 would
#    pass trivially, as a miss always recompiles).
compile rtA outA2
grep -q '(cached)' outA2.compile.log \
  || fail "second compile against the same runtime dir was not a cache hit; the rest of this test would be vacuous
$(cat outA2.compile.log)"

# 3. Compile the same source against B. Same March source, same flags, same
#    store — only the runtime directory differs, so the key must differ and the
#    resulting binary must be built from rtB's sources.
compile rtB outB
./outB > outB.stdout 2> outB.stderr || fail "outB did not run"
grep -q RUNTIME_DIR_B outB.stderr \
  || fail "compiling against rtB served a binary built from rtA's runtime sources (stale CAS hit)
compile log: $(cat outB.compile.log)
stderr: $(cat outB.stderr)"

# 4. And back to A: the key must track the directory in both directions rather
#    than merely being invalidated once.
compile rtA outA3
./outA3 > outA3.stdout 2> outA3.stderr || fail "outA3 did not run"
grep -q RUNTIME_DIR_B outA3.stderr \
  && fail "compiling against rtA served a binary built from rtB's runtime sources"

echo "cas_runtime_dir_check: ok" >&2
exit 0
