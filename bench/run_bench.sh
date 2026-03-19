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
# TREE-TRANSFORM SOURCE: depth=20 tree, inc_leaves x100 (FBIP showcase)
# March rewrites nodes in-place (RC=1); other langs allocate fresh nodes.
# ============================================================================

# --- C -----------------------------------------------------------------------
cat > "$TMP/tt.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
typedef struct T { int is_leaf; long val; struct T *l, *r; } T;
T* mk(int d) {
    T* n = malloc(sizeof(T));
    if (d==0) { n->is_leaf=1; n->val=0; n->l=NULL; n->r=NULL; }
    else { n->is_leaf=0; n->val=0; n->l=mk(d-1); n->r=mk(d-1); }
    return n;
}
T* inc(T* t) {
    T* n = malloc(sizeof(T));
    if (t->is_leaf) { n->is_leaf=1; n->val=t->val+1; n->l=NULL; n->r=NULL; }
    else { n->is_leaf=0; n->val=0; n->l=inc(t->l); n->r=inc(t->r); }
    return n;
}
void fr(T* t) { if (!t->is_leaf) { fr(t->l); fr(t->r); } free(t); }
long sm(T* t) { return t->is_leaf ? t->val : sm(t->l)+sm(t->r); }
int main() {
    T* t = mk(20);
    for (int i=0; i<100; i++) { T* t2=inc(t); fr(t); t=t2; }
    printf("%ld\n", sm(t)); fr(t);
    return 0;
}
EOF

# --- OCaml -------------------------------------------------------------------
cat > "$TMP/tt.ml" <<'EOF'
type t = Leaf of int | Node of t * t
let rec mk d = if d=0 then Leaf 0 else Node(mk(d-1), mk(d-1))
let rec inc = function Leaf n -> Leaf(n+1) | Node(l,r) -> Node(inc l, inc r)
let rec sum = function Leaf n -> n | Node(l,r) -> sum l + sum r
let () =
  let t = ref (mk 20) in
  for _ = 1 to 100 do t := inc !t done;
  Printf.printf "%d\n" (sum !t)
EOF

# --- Python ------------------------------------------------------------------
cat > "$TMP/tt.py" <<'EOF'
import sys; sys.setrecursionlimit(2000000)
class L:
    __slots__=['v']
    def __init__(self,v): self.v=v
class N:
    __slots__=['l','r']
    def __init__(self,l,r): self.l=l; self.r=r
def mk(d): return L(0) if d==0 else N(mk(d-1),mk(d-1))
def inc(t):
    if isinstance(t,L): return L(t.v+1)
    return N(inc(t.l),inc(t.r))
def sm(t): return t.v if isinstance(t,L) else sm(t.l)+sm(t.r)
t=mk(20)
for _ in range(100): t=inc(t)
print(sm(t))
EOF

# --- Rust --------------------------------------------------------------------
cat > "$TMP/tt.rs" <<'EOF'
enum T { L(i64), N(Box<T>,Box<T>) }
fn mk(d:u32)->T { if d==0{T::L(0)}else{T::N(Box::new(mk(d-1)),Box::new(mk(d-1)))} }
fn inc(t:T)->T { match t { T::L(n)=>T::L(n+1), T::N(l,r)=>T::N(Box::new(inc(*l)),Box::new(inc(*r))) } }
fn sm(t:&T)->i64 { match t { T::L(n)=>*n, T::N(l,r)=>sm(l)+sm(r) } }
fn main() {
    let mut t=mk(20);
    for _ in 0..100 { t=inc(t); }
    println!("{}",sm(&t));
}
EOF

# --- Go ----------------------------------------------------------------------
cat > "$TMP/tt.go" <<'EOF'
package main
import "fmt"
type T struct{ isLeaf bool; val int64; l,r *T }
func mk(d int)*T {
    if d==0 { return &T{isLeaf:true} }
    return &T{l:mk(d-1),r:mk(d-1)}
}
func inc(t *T)*T {
    if t.isLeaf { return &T{isLeaf:true,val:t.val+1} }
    return &T{l:inc(t.l),r:inc(t.r)}
}
func sm(t *T) int64 { if t.isLeaf { return t.val }; return sm(t.l)+sm(t.r) }
func main() {
    t:=mk(20)
    for i:=0;i<100;i++ { t=inc(t) }
    fmt.Println(sm(t))
}
EOF

# ============================================================================
# LIST-OPS SOURCE: range(1..1M) |> map(*2) |> filter(%3=0) |> fold(+,0)
# Tests closure call overhead and HOF pipeline performance.
# ============================================================================

# --- C (arrays) --------------------------------------------------------------
cat > "$TMP/lo.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
int main() {
    int n=1000000;
    long *buf = malloc(n*sizeof(long));
    int m=0;
    for(int i=1;i<=n;i++){ long v=i*2; if(v%3==0) buf[m++]=v; }
    long total=0;
    for(int i=0;i<m;i++) total+=buf[i];
    printf("%ld\n",total);
    free(buf);
    return 0;
}
EOF

# --- OCaml (List) ------------------------------------------------------------
cat > "$TMP/lo.ml" <<'EOF'
let () =
  let xs = List.init 1000000 (fun i -> (i+1)*2) in
  let zs = List.filter (fun x -> x mod 3 = 0) xs in
  let total = List.fold_left (+) 0 zs in
  Printf.printf "%d\n" total
EOF

# --- Python ------------------------------------------------------------------
cat > "$TMP/lo.py" <<'EOF'
xs = range(1,1000001)
ys = (x*2 for x in xs)
zs = [y for y in ys if y%3==0]
print(sum(zs))
EOF

# --- Rust (iterators) --------------------------------------------------------
cat > "$TMP/lo.rs" <<'EOF'
fn main() {
    let total:i64=(1i64..=1000000).map(|x|x*2).filter(|x|x%3==0).sum();
    println!("{}",total);
}
EOF

# --- Go ----------------------------------------------------------------------
cat > "$TMP/lo.go" <<'EOF'
package main
import "fmt"
func main() {
    total:=int64(0)
    for i:=int64(1);i<=1000000;i++{
        v:=i*2; if v%3==0 { total+=v }
    }
    fmt.Println(total)
}
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
# STRING BENCHMARKS: string_build (500K integers joined) and string_pipeline
# ============================================================================

# --- C (string_build) -------------------------------------------------------
cat > "$TMP/sb.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    /* allocate a buffer big enough for 500000 ints + null */
    char *buf = malloc(4000000);
    char *p = buf;
    for (int i = 500000; i >= 1; i--) {
        p += sprintf(p, "%d", i);
    }
    printf("%zu\n", (size_t)(p - buf));
    free(buf);
}
EOF

# --- C (string_pipeline) ----------------------------------------------------
cat > "$TMP/sp.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(void) {
    /* Build list of 1..100000, double each, join with "," */
    char *buf = malloc(8000000);
    char *p = buf;
    for (int i = 100000; i >= 1; i--) {
        if (p != buf) *p++ = ',';
        p += sprintf(p, "%d", i * 2);
    }
    printf("%zu\n", (size_t)(p - buf));
    free(buf);
}
EOF

# --- OCaml (string_build) ---------------------------------------------------
cat > "$TMP/sb.ml" <<'EOF'
let () =
  let buf = Buffer.create (4 * 1024 * 1024) in
  for i = 500000 downto 1 do
    Buffer.add_string buf (string_of_int i)
  done;
  print_int (Buffer.length buf); print_newline ()
EOF

# --- OCaml (string_pipeline) ------------------------------------------------
cat > "$TMP/sp.ml" <<'EOF'
let () =
  let buf = Buffer.create (8 * 1024 * 1024) in
  for i = 100000 downto 1 do
    if i < 100000 then Buffer.add_char buf ',';
    Buffer.add_string buf (string_of_int (i * 2))
  done;
  print_int (Buffer.length buf); print_newline ()
EOF

# --- Python (string_build) --------------------------------------------------
cat > "$TMP/sb.py" <<'EOF'
import sys
s = "".join(str(i) for i in range(500000, 0, -1))
print(len(s))
EOF

# --- Python (string_pipeline) -----------------------------------------------
cat > "$TMP/sp.py" <<'EOF'
s = ",".join(str(i * 2) for i in range(100000, 0, -1))
print(len(s))
EOF

# --- Rust (string_build) ----------------------------------------------------
cat > "$TMP/sb.rs" <<'EOF'
fn main() {
    let s: String = (1..=500000_usize).rev().map(|i| i.to_string()).collect();
    println!("{}", s.len());
}
EOF

# --- Rust (string_pipeline) -------------------------------------------------
cat > "$TMP/sp.rs" <<'EOF'
fn main() {
    let parts: Vec<String> = (1..=100000_i64).rev().map(|i| (i * 2).to_string()).collect();
    let s = parts.join(",");
    println!("{}", s.len());
}
EOF

# --- Go (string_build) ------------------------------------------------------
cat > "$TMP/sb.go" <<'EOF'
package main
import (
    "fmt"
    "strings"
    "strconv"
)
func main() {
    parts := make([]string, 500000)
    for i := 0; i < 500000; i++ { parts[i] = strconv.Itoa(500000 - i) }
    s := strings.Join(parts, "")
    fmt.Println(len(s))
}
EOF

# --- Go (string_pipeline) ---------------------------------------------------
cat > "$TMP/sp.go" <<'EOF'
package main
import (
    "fmt"
    "strings"
    "strconv"
)
func main() {
    parts := make([]string, 100000)
    for i := 0; i < 100000; i++ { parts[i] = strconv.FormatInt(int64(100000-i)*2, 10) }
    s := strings.Join(parts, ",")
    fmt.Println(len(s))
}
EOF

# ============================================================================
# COMPILE
# ============================================================================
bold "Compiling..."

# March
DUNE=/Users/80197052/.opam/march/bin/dune
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/fib.march            -o "$TMP/march_fib" 2>/dev/null)
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/binary_trees.march   -o "$TMP/march_bt"  2>/dev/null)
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/tree_transform.march -o "$TMP/march_tt"  2>/dev/null)
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/list_ops.march        -o "$TMP/march_lo"  2>/dev/null)
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/string_build.march    -o "$TMP/march_sb"  2>/dev/null)
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/string_pipeline.march -o "$TMP/march_sp"  2>/dev/null)

# C
if has clang; then
  clang -O2 -o "$TMP/c_fib" "$TMP/fib.c"
  clang -O2 -o "$TMP/c_bt"  "$TMP/bt.c"
  clang -O2 -o "$TMP/c_tt"  "$TMP/tt.c"
  clang -O2 -o "$TMP/c_lo"  "$TMP/lo.c"
  clang -O2 -o "$TMP/c_sb"  "$TMP/sb.c"
  clang -O2 -o "$TMP/c_sp"  "$TMP/sp.c"
fi

# OCaml
OCAMLOPT=/Users/80197052/.opam/march/bin/ocamlopt
if [ -x "$OCAMLOPT" ]; then
  "$OCAMLOPT" "$TMP/fib.ml" -o "$TMP/ocaml_fib" 2>/dev/null
  "$OCAMLOPT" "$TMP/bt.ml"  -o "$TMP/ocaml_bt"  2>/dev/null
  "$OCAMLOPT" "$TMP/tt.ml"  -o "$TMP/ocaml_tt"  2>/dev/null
  "$OCAMLOPT" "$TMP/lo.ml"  -o "$TMP/ocaml_lo"  2>/dev/null
  "$OCAMLOPT" "$TMP/sb.ml"  -o "$TMP/ocaml_sb"  2>/dev/null
  "$OCAMLOPT" "$TMP/sp.ml"  -o "$TMP/ocaml_sp"  2>/dev/null
elif has ocamlopt; then
  ocamlopt "$TMP/fib.ml" -o "$TMP/ocaml_fib" 2>/dev/null
  ocamlopt "$TMP/bt.ml"  -o "$TMP/ocaml_bt"  2>/dev/null
  ocamlopt "$TMP/tt.ml"  -o "$TMP/ocaml_tt"  2>/dev/null
  ocamlopt "$TMP/lo.ml"  -o "$TMP/ocaml_lo"  2>/dev/null
  ocamlopt "$TMP/sb.ml"  -o "$TMP/ocaml_sb"  2>/dev/null
  ocamlopt "$TMP/sp.ml"  -o "$TMP/ocaml_sp"  2>/dev/null
fi

# Rust
if has rustc; then
  rustc -O "$TMP/fib.rs" -o "$TMP/rust_fib" 2>/dev/null
  rustc -O "$TMP/bt.rs"  -o "$TMP/rust_bt"  2>/dev/null
  rustc -O "$TMP/tt.rs"  -o "$TMP/rust_tt"  2>/dev/null
  rustc -O "$TMP/lo.rs"  -o "$TMP/rust_lo"  2>/dev/null
  rustc -O "$TMP/sb.rs"  -o "$TMP/rust_sb"  2>/dev/null
  rustc -O "$TMP/sp.rs"  -o "$TMP/rust_sp"  2>/dev/null
fi

# Go
if has go; then
  go build -o "$TMP/go_fib" "$TMP/fib.go" 2>/dev/null
  go build -o "$TMP/go_bt"  "$TMP/bt.go"  2>/dev/null
  go build -o "$TMP/go_tt"  "$TMP/tt.go"  2>/dev/null
  go build -o "$TMP/go_lo"  "$TMP/lo.go"  2>/dev/null
  go build -o "$TMP/go_sb"  "$TMP/sb.go"  2>/dev/null
  go build -o "$TMP/go_sp"  "$TMP/sp.go"  2>/dev/null
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
bold "═══ tree-transform: depth=20, inc_leaves x100 (FBIP) ═══"
printf '  March rewrites in-place (RC=1); others always alloc fresh nodes.\n'
printf '  %-10s %-12s\n' "Language" "Time"
printf '  %-10s %-12s\n' "--------" "----"
run_if      "$TMP/march_tt"  "March"
run_if      "$TMP/c_tt"      "C"
run_if      "$TMP/ocaml_tt"  "OCaml"
run_if_interp python3 "$TMP/tt.py"  "Python"
run_if      "$TMP/rust_tt"   "Rust"
run_if      "$TMP/go_tt"     "Go"

echo ""
bold "═══ list-ops: range(1M) |> map(*2) |> filter(%3=0) |> fold(+) ═══"
printf '  Tests closure call overhead. C/Go/Rust use direct loops (best case).\n'
printf '  %-10s %-12s\n' "Language" "Time"
printf '  %-10s %-12s\n' "--------" "----"
run_if      "$TMP/march_lo"  "March"
run_if      "$TMP/c_lo"      "C"
run_if      "$TMP/ocaml_lo"  "OCaml"
run_if_interp python3 "$TMP/lo.py"  "Python"
run_if      "$TMP/rust_lo"   "Rust"
run_if      "$TMP/go_lo"     "Go"

echo ""
bold "═══ string-build: join 500K int strings ═══"
printf '  March uses string_join on List(String). C uses a pre-allocated buffer.\n'
printf '  OCaml/Rust use Buffer/String::collect. Tests: int_to_string, string_join.\n'
printf '  %-10s %-12s\n' "Language" "Time"
printf '  %-10s %-12s\n' "--------" "----"
run_if      "$TMP/march_sb" "March"
run_if      "$TMP/c_sb"     "C"
run_if      "$TMP/ocaml_sb" "OCaml"
run_if_interp python3 "$TMP/sb.py" "Python"
run_if      "$TMP/rust_sb"  "Rust"
run_if      "$TMP/go_sb"    "Go"

echo ""
bold "═══ string-pipeline: build, double, rejoin 100K int strings ═══"
printf '  March uses string_join + string_to_int + list map.\n'
printf '  Tests: string_join, string_to_int, int_to_string, pattern match.\n'
printf '  %-10s %-12s\n' "Language" "Time"
printf '  %-10s %-12s\n' "--------" "----"
run_if      "$TMP/march_sp" "March"
run_if      "$TMP/c_sp"     "C"
run_if      "$TMP/ocaml_sp" "OCaml"
run_if_interp python3 "$TMP/sp.py" "Python"
run_if      "$TMP/rust_sp"  "Rust"
run_if      "$TMP/go_sp"    "Go"

echo ""
