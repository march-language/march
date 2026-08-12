# SIMD: nested-closure recursive fn with a Simd-vector-typed parameter segfaults compiled

Filed during Task 4 (validation kernels) of the SIMD vector types plan
(`.superpowers/sdd/2026-08-10-simd-vector-types/`). Blocks the natural March
idiom for a SIMD accumulator loop — a locally-defined recursive `fn` nested
inside another function, threading the vector accumulator as a parameter —
from compiling correctly. Interpreted is correct; compiled segfaults (exit
139) regardless of `--opt` level (reproduces at `--opt 0`, `1`, `2`).

## Minimal repro

`.superpowers/sdd/2026-08-10-simd-vector-types/repro-nested-closure-simd-segfault.march`:

```march
mod T3 do
  needs IO.Console

  fn dot_simd(a, b) : Float do
    let n = NativeArray.length_f32(a)
    fn go(i, acc) do
      if i >= n do acc
      else
        let va = Simd.load_f32x4(a, i)
        let vb = Simd.load_f32x4(b, i)
        go(i + 4, Simd.fma_f32x4(va, vb, acc))
      end
    end
    let acc = go(0, Simd.splat_f32x4(0.0))
    Simd.sum_f32x4(acc)
  end

  fn main() : Unit do
    let a = NativeArray.from_list_f32([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0])
    let b = NativeArray.from_list_f32([2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0])
    println("dot_simd=" ++ float_to_string(dot_simd(a, b)))
  end
end
```

`march file.march` (interpreted) prints `dot_simd=72.` (correct). `march
--compile --opt 2 file.march -o out && ./out` segfaults (exit 139) before
printing anything.

**Workaround that avoids the bug**: hoist `go` to a top-level (module-level)
`fn`/`pfn` taking `a`, `b`, `n` as explicit parameters instead of capturing
them, e.g.:

```march
pfn go(a, b, i : Int, n : Int, acc) do
  if i >= n do acc
  else
    let va = Simd.load_f32x4(a, i)
    let vb = Simd.load_f32x4(b, i)
    go(a, b, i + 4, n, Simd.fma_f32x4(va, vb, acc))
  end
end
```

This compiles and runs correctly (verified with the same fixture, top-level
variant, at both small and 5M-element scale). `bench/simd_kernels.march`
uses this workaround for `dot_simd`.

## Root cause (from `--emit-llvm` IR, see the `.ll` file alongside the repro)

Two call sites for the closure's `$apply` function disagree on the calling
convention for the vector-typed accumulator parameter:

- The **indirect self-recursive call** inside `go$apply$3552`'s own body
  goes through the closure's function-pointer field with an explicit
  `(ptr, ptr, ptr) -> ptr` signature and correctly boxes the accumulator
  first (`%vbox222 = call ptr @march_simd_alloc(...)` then passes
  `ptr %vbox222`).
- The **initial direct call** that kicks off the loop from the enclosing
  function (`march_main` after inlining) calls `@go$apply$3552` by name but
  passes the *unboxed* register vector directly:
  `call ptr @go$apply$3552(ptr %ld123, ptr %cv127, <4 x float> %ld124)`
  — the callee's own definition is
  `define ptr @go$apply$3552(ptr %$clo.arg, ptr %i.arg, ptr nonnull dereferenceable(16) %acc.arg)`,
  i.e. it expects a boxed `ptr` for `acc.arg`, not a raw `<4 x float>`.

The direct call's argument type doesn't match the callee's actual parameter
type (LLVM lets a direct `call` declare its own signature independent of the
target's definition; this passes IR emission/linking but is UB at the ABI
boundary — the callee reads `acc.addr` as a pointer and dereferences a
box header that was never allocated, hence the segfault). Likely cause: the
register-residency lowering (Task 3, `lib/tir/perceus`/`llvm_emit`) treats
the vector-typed argument to the *first* call of a locally-defined recursive
closure as residency-eligible (unboxed, since the call site "looks"
straight-line before the loop starts), while the closure's own compiled body
— built once and shared by every recursive/indirect invocation — commits to
the boxed convention that indirect closure calls require. The two call
sites' emission has to agree on one convention for any parameter that both
a direct and an indirect call site can reach.

Task 1–3's residency fixtures (`test/native/simd_residency.march`) only
cover a straight-line kernel and a single-escape kernel, not a recursive
closure carrying a vector value as one of its own parameters — this gap
escaped that net. `dune build --root . @install &&
./_build/default/bin/main.exe --compile --opt 2
.superpowers/sdd/2026-08-10-simd-vector-types/repro-nested-closure-simd-segfault.march
-o /tmp/repro && /tmp/repro` reproduces on demand.

## Suggested next step

Whoever picks up compiled-path SIMD closure work next should either (a) make
the direct-call fast path for a local recursive closure agree with the
indirect/self-call convention for vector-typed parameters (box at both call
sites, or unbox uniformly with a residency proof that covers self-recursion),
or (b) short-circuit residency elision entirely for any closure whose own
body contains a self-recursive (indirect) call, falling back to the boxed
convention it already uses correctly. Add a `test/native/simd_residency.march`
(or a new fixture) case: a locally-defined recursive `fn` threading a vector
accumulator, asserted both for correctness (compiled output matches
interpreted) and, once fixed, for the box-count residency contract.

---

## RESOLVED 2026-08-11 (Task 4b)

Both the segfault and the per-iteration boxing it was filed alongside are
fixed. Commit: `fix(simd): vector params across closure kickoff/self-call ABI
+ native TCO accumulator slots`.

### The segfault (this file's subject)

The hypothesis above was **confirmed verbatim against the IR** — the direct
kickoff call emitted
`call ptr @go$apply$3552(ptr %ld123, ptr %cv127, <4 x float> %ld124)` against a
definition taking `ptr %acc.arg`.

The mechanism, though, is narrower and more boring than "residency lowering
treats the first call as residency-eligible". Nothing SIMD-aware was involved
at all. `llvm_emit.ml`'s **Boundary B** — the direct-call-to-an-apply-fn arm
that `known_call` produces when it rewrites a non-escaping `ECallPtr` into
`EApp(go$apply$N, ...)` — remaps arguments to the uniform ptr closure ABI with
this test:

```ocaml
if ty = "i64" || ty = "double" then coerce ctx ty v "ptr" ...
```

That is a hard-coded list of the two *then-known* non-ptr representations,
applied to the argument's **actual emitted LLVM type**. A `<4 x float>` is
neither, so it fell through the `else` branch and was passed verbatim. The
sibling **indirect** path (the closure-struct dispatch arm) does not have this
bug because it derives its argument types from the callee's **declared**
parameter types (all `ptr` — `llvm_ty` maps the SIMD `TCon`s to `ptr` by
design), so it boxed correctly. Two paths, two different sources of truth for
the same ABI.

Fix: add `|| is_vec_ty ty` to the Boundary B test, so a vector argument boxes
through `march_simd_alloc` exactly as a Float boxes through
`march_alloc_float`. One uniform ptr ABI, both call sites, no exceptions. Task
3's register-residency work is untouched — it was never implicated.

Verified: the repro compiles and prints `dot_simd=72.` at `--opt 0`, `1` and
`2`, matching the interpreter.

### The per-iteration boxing (the sibling defect)

The same file's benchmark half — a *top-level* self-tail-recursive helper
threading a vector accumulator — was boxing on every iteration. Root cause was
independent of the above: `Llvm_toplevel.emit_fn` types every parameter alloca
with `llvm_ty`, which is `ptr` for these types, so the TCO **back-edge**'s
coerce-to-param-type re-boxed the accumulator each time round the loop (and,
per the IR, nothing `dec_rc`s the slot's previous box, so the boxes
accumulated rather than being reused).

Fix: when a function `is_tco`, a parameter whose TIR type is one of the five
SIMD vector `TCon`s gets a **native `<N x T>` alloca** instead. The entry
prologue unboxes the (still boxed, still `ptr`) incoming argument once per
call; the back-edge's coerce is then an identity and the accumulator stays in
a vector register. The function **signature is deliberately unchanged**, so
every non-back-edge caller is unaffected — this is a loop-local
representation choice, not a new cross-call vector ABI.

Measured on `bench/simd_kernels.march` (5M f32 dot product): `dot_simd`
29.22 ms → **10.01 ms**, a 2.9x improvement, and the loop body's
`march_simd_alloc` count went 1-per-iteration → **0**.

### Test coverage added

`test/native/simd_nested_closure_acc.march` (+ `.expected` + two `test/dune`
rules) covers both shapes in one fixture — exactly the gap this file
identified in `simd_residency.march`:
- `nested_dot` (the nested-closure shape): compiled output diffed against
  interpreter output.
- `simd_acc_go` (the self-TCO shape): an `--emit-llvm` grep asserting the
  accumulator slot is native. The contract is a conjunction
  (`vstore >= 2 && alloc == 1 && fma >= 1`) because the allocation count alone
  is *not* falsifiable here — it was 1 before the fix (the per-iteration box)
  and is 1 after (the return-path box). The `store <4 x float> ... %acc.addr`
  count is what actually discriminates: 0 before, 2 after.

### Not fixed, and deliberately so

`dot_simd` still does **not** beat `dot_composed` (10.01 ms vs 2.55 ms), so the
Task 4 validation bar remains unmet. That is now a *different* problem, and it
is not about vectors: a hand-written March index loop emits, per iteration, a
volatile preemption load, `llvm.stacksave`/`stackrestore`, two
`march_incrc_local` calls and two `native_f32_arr_length` bounds-check calls,
plus body allocas outside the entry block that `mem2reg` cannot promote —
while `dot_composed` is a single call into a tight C runtime loop. An
attribution probe holding the loop framework constant measured the SIMD loop
at **4.0x faster than the equivalent scalar March index loop** (9.89 ms vs
39.95 ms), which is the SIMD lowering doing its job; the residual gap is
March-loop overhead. Filed as
`specs/todos/2026-08-11-march-index-loop-per-iteration-overhead.md`.

Mutual-TCO groups (`Llvm_tco.emit_mutual_tco_group`) still use `ptr` slots for
vector params — correct, just not accelerated. Only self-TCO was in scope.
