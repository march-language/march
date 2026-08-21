# Uniform-ptr closure ABI Float boxes: released at the call site (fixed 2026-08-21)

Closed `specs/todos/2026-08-20-float-box-uniform-abi-per-call-leak.md` (this file
is its `git mv`). Filed 2026-08-20 after TWO failed fixes; the third one landed.
Companion probe: `test/native/native_float_box_abi_leak_probe.march` (in
`@runtest`, threshold < 1000).

## What leaked

Closure dispatch uses a uniform ptr ABI, so a Float crossing an indirect
closure boundary was boxed twice and neither box was released:

* **argument** — `Llvm_ctx.coerce`'s `"double" -> "ptr"` arm at the call site
  (`march_alloc_float`);
* **return** — the callee's return path boxes its `double` result (same
  coerce; `Llvm_calls.clo_wrap_define`'s double-return arm).

Not numeric-code-only: every call to any HOF/closure taking or returning a
Float paid ~2 × 32 B, unbounded — comparators, callbacks, `List.map` over
Floats, long-running servers.

## Measured (Darwin arm64, `--compile --opt 2`, probe above)

| | `live_allocs()` delta |
|---|---|
| unfixed, all legs (5.1M closure calls) | **7,200,003** |
| — float_leg (1M calls, Float→Float, ECallPtr) | 2,000,001 |
| — fparam_leg (1M, Float arg only) | 1,000,000 |
| — fret_leg (1M, Float ret only) | 1,000,000 |
| — int_leg control (1M, wire-tagged) | 0 |
| — devirt/selfrec shapes | 3,000,002 + 200,000 |
| fixed, all legs | **1** |

## The fix — caller-side releases in `lib/tir/llvm_emit.ml`

Both prior attempts (callee-side release: double-free vs the C runtime's own
`march_decrc(elem)`; naive call-site release: measured SIGBUS UAF in
`bench/array_numeric.march`) are documented below in the original filing. The
landed fix keeps the release at the call site but closes both holes:

1. **ECallPtr dispatch arm** (indirect calls):
   * arg box: released after the call, recorded only when the call site's own
     coerce created it (declared param `double` AND the argument was actually
     emitted as `double`), and **alias-guarded** — a pointer-equality check
     against the raw returned ptr skips the release when a generic
     (erased-param) callee handed the argument box back as a borrowed
     flow-through alias. That alias is then released exactly once by:
   * ret box: when the declared return type is Float, the fresh box the callee
     allocated on its return path is unboxed and released immediately; the
     call now yields a raw `("double", d)` and consumers that need the erased
     form re-box fresh (Float is immutable — unobservable).
2. **EApp Boundary B** (devirtualized `EApp(apply_fn, ...)` after known_call):
   same two releases, with the arg release keyed off the **callee
   definition's** declared param types (`top_fn_param_tys` + the same arity
   guard as the SIMD `native_vec_idxs` machinery) — a param that stayed
   generic `ptr` is never released (still leaks: the safe direction). No
   alias guard needed: a genuinely-`double` param is unboxed in the callee
   prologue and cannot flow back out as the same box.

### The third trap, found by this probe: self-tail-calls

The first draft of these releases emitted post-call instructions on a local
recursive fn's self-call (`ECallPtr` through defun's `let go = $clo`
self-binding). That defeated LLVM's tail-call elimination — the only thing
keeping such recursion O(1) stack — and a shape that ran 1,000,000 deep
SIGBUSed (green-thread stack overflow, lldb-confirmed guard-page fault) at
20,000. Both arms now **exempt (potential) self-calls**: the ECallPtr arm by
comparing the callee variable's name against
`Tir_names.apply_fn_base ctx.cur_emit_fn` (a name-shadowing false positive
only leaks), Boundary B by `resolved_name <> ctx.cur_emit_fn`. The exempted
back-edge keeps its pre-existing per-iteration leak — see
`specs/todos/2026-08-21-selfrec-closure-float-tail-call.md` for the real fix
(march-level TCO for self-recursive apply fns). The probe's `selfrec_leg`
runs 1M deep OUTSIDE the leak-measurement window as the stack canary.

## Why the ownership argument is sound

Same invariant PR #313's runtime-side fold fix already relies on: every
Float-typed value leaving an apply fn through the erased ABI is a FRESH
`march_float_box` the caller solely owns (Float captures are stored as raw
doubles; a genuinely-`double` param is unboxed at entry and its box pointer
never read again). The two non-fresh shapes are exactly the ones excluded:
generic-param callees (Boundary B never lists them; ECallPtr's alias guard
catches the flow-through) and self-calls (exempted wholesale).

## Verification

* Probe RED 7,200,003 → GREEN 1 (numbers above, same fixture).
* Both prior attempts' killers pass: `list_sum_float` over 100k elements
  (attempt 2's measured UAF — correct value, rc=0) and `bench/array_numeric`
  (attempt 2's measured SIGBUS — clean run).
* Double-await on one Float task still returns the value twice (the task
  sites were NOT touched — still open, see
  `specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md`).
* Full `@runtest` (includes this probe + the #313 acc-leak probe + SIMD
  probes), `scripts/run-tests.sh`, TIR snapshots (emission-level change only
  — no TIR shape diff), compiled benchmarks, sanitize/oracle sweeps: see the
  landing commit message for results.

---

*The original 2026-08-20 filing follows, kept for the two failed-fix
post-mortems it documents.*

## Two fixes that do not work (original filing)

### 1. Release in the callee's entry prologue — DOUBLE FREE

The obvious fix: a `march_decrc_local` after the `march_unbox_float` in
`Llvm_toplevel.emit_fn`'s `is_apply_wrapper && ty = "double"` arm.

Unsound: the callee cannot tell an owned temporary from a borrowed reference
to a box someone else owns; the call site can, because it knows whether it
created the box. Concretely, `native_float_arr_fold` materialises each
element with `march_alloc_float` and releases it **itself** with
`march_decrc(elem)` after the call — a callee that also released would drop
the same box twice.

### 2. Release at the `ECallPtr` call site, unguarded — USE AFTER FREE

Attempted 2026-08-20: release keyed off the caller's declared param type
alone. Closed the leak completely (2,000,001 → 1) **and crashed
`bench/array_numeric.march` with SIGBUS (exit 138)**. Root cause: the
caller's declared param type and the callee's actual param type can disagree
— a callee whose param stayed generic stores the box pointer (retains it),
and can return it as a borrowed alias; the call-site release freed it
underneath. Minimal repro (crashes at 100,000 elements, passes at 5):

```march
pfn list_sum_float(lst : List(Float)) : Float do
  fn go(xs : List(Float), acc : Float) : Float do
    match xs do
    Nil -> acc
    Cons(h, t) -> go(t, acc +. h)
    end
  end
  go(lst, 0.0)
end
-- main: list_sum_float(List.map(List.range(0, 100000), fn i -> int_to_float(i % 10)))
```

The landed fix's alias guard + callee-definition keying are the direct
answers to this post-mortem.
