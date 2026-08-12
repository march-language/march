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
