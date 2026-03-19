#!/usr/bin/env bash
# Benchmarks Game comparison: fib(40) and binary-trees(15)
# Languages: March, C, OCaml, Python, Rust, Go
# Run from the march repo root: bash bench/run_bench.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  %-10s %-12s  %s\n' "$1" "$2" "$3"; }
skip() { printf '  %-10s %-12s  (not found)\n' "$1" "$2"; }

# --- timing helper -----------------------------------------------------------
# Runs $@ silently, returns elapsed milliseconds on stdout.
timeit_ms() {
  python3 - "$@" <<'PYEOF'
import sys, time, subprocess
start = time.perf_counter()
subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
elapsed = time.perf_counter() - start
print(f"{elapsed*1000:.1f}")
PYEOF
}

# Checks if a command exists.
has() { command -v "$1" > /dev/null 2>&1; }

# ============================================================================
# FIB SOURCE: naive recursive fib(40)
# ============================================================================

# --- C -----------------------------------------------------------------------
cat > "$TMP/fib.c" <<'EOF'
#include <stdio.h>
long fib(int n) { return n < 2 ? n : fib(n-1) + fib(n-2); }
int main() { printf("%ld\n", fib(40)); return 0; }
EOF

# --- OCaml -------------------------------------------------------------------
cat > "$TMP/fib.ml" <<'EOF'
let rec fib n = if n < 2 then n else fib(n-1) + fib(n-2)
let () = Printf.printf "%d\n" (fib 40)
EOF

# --- Python ------------------------------------------------------------------
cat > "$TMP/fib.py" <<'EOF'
import sys; sys.setrecursionlimit(100000)
def fib(n): return n if n < 2 else fib(n-1) + fib(n-2)
print(fib(40))
EOF

# --- Rust --------------------------------------------------------------------
cat > "$TMP/fib.rs" <<'EOF'
fn fib(n: u64) -> u64 { if n < 2 { n } else { fib(n-1) + fib(n-2) } }
fn main() { println!("{}", fib(40)); }
EOF

# --- Go ----------------------------------------------------------------------
cat > "$TMP/fib.go" <<'EOF'
package main
import "fmt"
func fib(n int) int { if n < 2 { return n }; return fib(n-1) + fib(n-2) }
func main() { fmt.Println(fib(40)) }
EOF

# ============================================================================
# BINARY-TREES SOURCE: depth=15
# ============================================================================

# --- C -----------------------------------------------------------------------
cat > "$TMP/bt.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
typedef struct N { struct N *l, *r; } N;
N* mk(int d) {
    N* n = malloc(sizeof(N));
    if (d > 0) { n->l = mk(d-1); n->r = mk(d-1); }
    else { n->l = NULL; n->r = NULL; }
    return n;
}
int chk(N* n) { return n->l ? chk(n->l) + chk(n->r) + 1 : 1; }
void fr(N* n)  { if (n->l) { fr(n->l); fr(n->r); } free(n); }
int main() {
    int n=15, mn=4, mx = n > mn+2 ? n : mn+2, st = mx+1;
    N* s = mk(st); printf("stretch tree of depth %d check: %d\n", st, chk(s)); fr(s);
    N* ll = mk(mx);
    for (int d=mn; d<=mx; d+=2) {
        int it = 1 << (mx-d+mn); long sum=0;
        for (int i=0;i<it;i++) { N* t=mk(d); sum+=chk(t); fr(t); }
        printf("%d trees of depth %d check: %ld\n", it, d, sum);
    }
    printf("long lived tree of depth %d check: %d\n", mx, chk(ll)); fr(ll);
    return 0;
}
EOF

# --- OCaml -------------------------------------------------------------------
cat > "$TMP/bt.ml" <<'EOF'
type t = L | N of t * t
let rec mk d = if d=0 then L else N(mk(d-1), mk(d-1))
let rec chk = function L -> 1 | N(l,r) -> chk l + chk r + 1
let () =
  let n=15 and mn=4 in
  let mx = max n (mn+2) in
  let st = mx+1 in
  Printf.printf "stretch tree of depth %d check: %d\n" st (chk (mk st));
  let ll = mk mx in
  let d = ref mn in
  while !d <= mx do
    let it = 1 lsl (mx - !d + mn) in
    let sum = ref 0 in
    for _ = 1 to it do sum := !sum + chk(mk !d) done;
    Printf.printf "%d trees of depth %d check: %d\n" it !d !sum;
    d := !d + 2
  done;
  Printf.printf "long lived tree of depth %d check: %d\n" mx (chk ll)
EOF

# --- Python ------------------------------------------------------------------
cat > "$TMP/bt.py" <<'EOF'
import sys; sys.setrecursionlimit(1000000)
class N:
    __slots__ = ['l','r']
    def __init__(self,l,r): self.l=l; self.r=r
def mk(d):
    if d==0: return N(None,None)
    return N(mk(d-1),mk(d-1))
def chk(n):
    if n.l is None: return 1
    return chk(n.l)+chk(n.r)+1
n=15; mn=4; mx=max(n,mn+2); st=mx+1
print(f"stretch tree of depth {st} check: {chk(mk(st))}")
ll=mk(mx)
for d in range(mn,mx+1,2):
    it=1<<(mx-d+mn); s=sum(chk(mk(d)) for _ in range(it))
    print(f"{it} trees of depth {d} check: {s}")
print(f"long lived tree of depth {mx} check: {chk(ll)}")
EOF

# --- Rust --------------------------------------------------------------------
cat > "$TMP/bt.rs" <<'EOF'
enum T { L, N(Box<T>, Box<T>) }
fn mk(d: u32) -> T {
    if d==0 { T::L } else { T::N(Box::new(mk(d-1)), Box::new(mk(d-1))) }
}
fn chk(t: &T) -> i64 { match t { T::L => 1, T::N(l,r) => chk(l)+chk(r)+1 } }
fn main() {
    let (n,mn): (u32,u32) = (15,4);
    let mx = n.max(mn+2); let st = mx+1;
    println!("stretch tree of depth {} check: {}", st, chk(&mk(st)));
    let ll = mk(mx);
    let mut d = mn;
    while d <= mx {
        let it = 1i64 << (mx-d+mn);
        let sum: i64 = (0..it).map(|_| chk(&mk(d))).sum();
        println!("{} trees of depth {} check: {}", it, d, sum);
        d += 2;
    }
    println!("long lived tree of depth {} check: {}", mx, chk(&ll));
}
EOF

# --- Go ----------------------------------------------------------------------
cat > "$TMP/bt.go" <<'EOF'
package main
import "fmt"
type T struct{ l, r *T }
func mk(d int) *T {
    if d==0 { return &T{} }
    return &T{mk(d-1), mk(d-1)}
}
func chk(t *T) int {
    if t.l==nil { return 1 }
    return chk(t.l)+chk(t.r)+1
}
func main() {
    n,mn := 15,4; mx := n; if mn+2 > mx { mx=mn+2 }
    st := mx+1
    fmt.Printf("stretch tree of depth %d check: %d\n", st, chk(mk(st)))
    ll := mk(mx)
    for d:=mn; d<=mx; d+=2 {
        it := 1<<uint(mx-d+mn); sum:=0
        for i:=0; i<it; i++ { sum+=chk(mk(d)) }
        fmt.Printf("%d trees of depth %d check: %d\n", it, d, sum)
    }
    fmt.Printf("long lived tree of depth %d check: %d\n", mx, chk(ll))
}
EOF

# ============================================================================
# COMPILE
# ============================================================================
bold "Compiling..."

# March
DUNE=/Users/80197052/.opam/march/bin/dune
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/fib.march -o "$TMP/march_fib" 2>/dev/null)
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/binary_trees.march -o "$TMP/march_bt" 2>/dev/null)

# C
if has clang; then
  clang -O2 -o "$TMP/c_fib" "$TMP/fib.c"
  clang -O2 -o "$TMP/c_bt"  "$TMP/bt.c"
fi

# OCaml
OCAMLOPT=/Users/80197052/.opam/march/bin/ocamlopt
if [ -x "$OCAMLOPT" ]; then
  "$OCAMLOPT" "$TMP/fib.ml" -o "$TMP/ocaml_fib" 2>/dev/null
  "$OCAMLOPT" "$TMP/bt.ml"  -o "$TMP/ocaml_bt"  2>/dev/null
elif has ocamlopt; then
  ocamlopt "$TMP/fib.ml" -o "$TMP/ocaml_fib" 2>/dev/null
  ocamlopt "$TMP/bt.ml"  -o "$TMP/ocaml_bt"  2>/dev/null
fi

# Rust
if has rustc; then
  rustc -O "$TMP/fib.rs" -o "$TMP/rust_fib" 2>/dev/null
  rustc -O "$TMP/bt.rs"  -o "$TMP/rust_bt"  2>/dev/null
fi

# Go
if has go; then
  go build -o "$TMP/go_fib" "$TMP/fib.go" 2>/dev/null
  go build -o "$TMP/go_bt"  "$TMP/bt.go"  2>/dev/null
fi

# ============================================================================
# RUN & PRINT
# ============================================================================

run_if() {
  local bin="$1" label="$2"
  if [ -x "$bin" ]; then
    ms=$(timeit_ms "$bin" 2>/dev/null)
    ok "$label" "${ms} ms" ""
  else
    skip "$label" ""
  fi
}

run_if_interp() {
  local interp="$1" src="$2" label="$3"
  if has "$interp"; then
    ms=$(timeit_ms "$interp" "$src" 2>/dev/null)
    ok "$label" "${ms} ms" ""
  else
    skip "$label" ""
  fi
}

echo ""
bold "═══ fib(40) ═══"
printf '  %-10s %-12s\n' "Language" "Time"
printf '  %-10s %-12s\n' "--------" "----"
run_if      "$TMP/march_fib" "March"
run_if      "$TMP/c_fib"     "C"
run_if      "$TMP/ocaml_fib" "OCaml"
run_if_interp python3 "$TMP/fib.py" "Python"
run_if      "$TMP/rust_fib"  "Rust"
run_if      "$TMP/go_fib"    "Go"

echo ""
bold "═══ binary-trees(15) ═══"
printf '  %-10s %-12s\n' "Language" "Time"
printf '  %-10s %-12s\n' "--------" "----"
run_if      "$TMP/march_bt"  "March"
run_if      "$TMP/c_bt"      "C"
run_if      "$TMP/ocaml_bt"  "OCaml"
run_if_interp python3 "$TMP/bt.py"  "Python"
run_if      "$TMP/rust_bt"   "Rust"
run_if      "$TMP/go_bt"     "Go"

echo ""
