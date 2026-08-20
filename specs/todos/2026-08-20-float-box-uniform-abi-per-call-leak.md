# Uniform-ptr closure ABI leaks TWO Float boxes per call (~64 B/call)

Filed 2026-08-20, split out of
`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md` (which now tracks
only the two Task-trampoline sites). **A fix was attempted and reverted** —
read "Two fixes that do not work" before trying again, both were measured.

## What leaks

Closure dispatch uses a uniform ptr ABI: an apply wrapper's params and result
are all `ptr`, because the dispatch reads GP registers and a `double` would land
in an FP register. So a Float crossing a closure boundary is boxed twice and
neither box is released:

* **argument** — `Llvm_ctx.coerce`'s `"double" -> "ptr"` arm at the call site
  allocates a fresh `march_alloc_float`;
* **return** — the apply wrapper boxes its `double` result on the way out (same
  coerce; `Llvm_calls.clo_wrap_define`'s `double` return arm does the same).

**This is not numeric-code-only.** It costs a pair of allocations for every call
to any higher-order function or closure taking or returning a `Float` — a
comparator, a callback, `List.map` over Floats. In a long-running server it is
unbounded.

## Measurement

Darwin arm64, `--compile --opt 2`, 1,000,000 indirect closure calls, signal =
`live_allocs()` (NOT RSS — see `test/native/native_arr_fold_leak_probe.march`
for why):

| | `live_allocs()` delta |
|---|---|
| Float argument + Float return | **2,000,001** |
| wire-tagged Int control, same shape | **1** |

Exactly two objects per call. The probe used (reproduce with this — it is
deliberately shaped so `known_call` cannot devirtualise the call into
`EApp(apply_fn, ...)` and inline the boxing away; a directly-applied lambda
optimises the defect out entirely and measures nothing):

```march
pfn call_n(f : (Float) -> Float, n : Int, acc : Float) : Float do
  if n <= 0 do acc else call_n(f, n - 1, f(acc)) end
end
pfn float_leg(n : Int) : Int do
  let fs = [fn (x : Float) -> x +. 1.0, fn (x : Float) -> x +. 2.0]
  match List.head_opt(fs) do
    Some(f) -> float_to_int(call_n(f, n, 0.0))
    None    -> -1
  end
end
```

## Two fixes that do not work

### 1. Release in the callee's entry prologue — DOUBLE FREE

The obvious fix, and the one
`specs/todos/2026-08-12-float-boxing-trampoline-apply-wrapper-leak.md`
originally proposed: a `march_decrc_local` after the `march_unbox_float` in
`Llvm_toplevel.emit_fn`'s `is_apply_wrapper && ty = "double"` arm.

Unsound. The codebase already had the argument written down for the SIMD
analogue (the `native_vec_slot` comment in the same function): *the callee
cannot tell an owned temporary from a borrowed reference to a box someone else
owns; the call site can, because it knows whether it created the box.*

It is also a concrete double free against the C runtime:
`native_float_arr_fold` materialises each element with `march_alloc_float` and
releases it **itself** with `march_decrc(elem)` after the call. A callee that
also released would drop the same box twice.

### 2. Release at the `ECallPtr` call site — USE AFTER FREE (measured SIGBUS)

Attempted 2026-08-20 in `lib/tir/llvm_emit.ml`'s `ECallPtr` arm: keep the
declared param LLVM types from before the uniform-ABI remap, and release an
argument box only when the declared param type is `"double"` *and* the
argument's actual emitted type is `"double"` (so the coerce really allocated).
Plus unbox-and-release the return box when the call's return type is `double`.

It closed the leak completely — 2,000,001 → 1, verified against a revert
control on the same fixture — **and it crashed `bench/array_numeric.march` with
SIGBUS (exit 138)**, which no test in `@runtest` catches because benchmarks are
not part of it.

Root cause, and the trap to avoid next time: **the caller's declared param type
and the callee's actual param type can disagree.** The call site reads the
closure variable's `TFn` type, which said `Float`; the callee's param had been
left generic by mono/defun, so its prologue is

```llvm
%acc.addr = alloca ptr
store ptr %acc.arg, ptr %acc.addr    ; stores the POINTER — no unbox, RETAINS it
```

i.e. the callee keeps the box, and the call-site release frees it underneath.
Minimal repro (crashes at 100,000 elements, passes at 5 — it is a
use-after-free, so small inputs are benign):

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

This is exactly why the SIMD fix keys its release off `ctx.native_vec_params`,
a table populated from the **callee definition**, rather than off the call-site
type. At an `ECallPtr` the callee is not statically known, so that table is not
consultable — which is what makes this the hard case rather than a peephole.

## What the fix probably is

Either:

* **Devirtualized path only.** Apply the call-site release only on the
  `EApp(apply_fn, ...)` path (the `is_apply_fn resolved_name` branch, which
  already has the `record_temp_box` machinery), keyed off a
  `native_vec_params`-style table of which apply-fn params are genuinely
  `double` in the *emitted definition*. Safe, but does not cover the
  `ECallPtr` hot loop above, so it would only partially close the leak.
* **Perceus-level accounting.** Give the temp box a TIR identity so ownership
  is tracked properly instead of being invisible to the RC pass — this is the
  same gap named in
  `specs/todos/2026-08-12-simd-nontco-vector-param-leak.md` for vectors, and
  the two probably want one fix.

Either way the erased/generic-param case has to be settled first: as long as a
`Float` argument can reach a callee whose param stayed `ptr`, no caller-side
rule can be both leak-free and safe.

## Verification bar for the next attempt

1. The probe above, RED before / GREEN after.
2. `bench/array_numeric.march` compiled and RUN to completion — this is the
   witness that killed attempt 2 and `@runtest` does not cover it.
3. `MARCH_BIN=$PWD/_build/default/bin/main.exe ./specs/lang/golden/sanitize.sh`
   (attempt 2 passed this and was still wrong — necessary, not sufficient).
4. Full `dune build --root . @runtest` plus `scripts/run-tests.sh`.
