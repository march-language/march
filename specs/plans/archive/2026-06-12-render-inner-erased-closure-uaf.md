# Plan: fix the `render_inner` erased-closure use-after-free (test 37 / `needs_rc(TVar)` collision)

**Status:** OPEN — root-caused, two fixes attempted and proven wrong, not yet fixed.
**Date:** 2026-06-12
**Owner of the conflicting change:** whoever wrote `080e31f` (`fix(tir): RC use-after-free on cross-module opaque types (needs_rc TVar)`).

---

## TL;DR

On current `main`, the bastion test `"Form.Wrapper.render renders form tag with action and method"` (test index 37) crashes with a use-after-free. A zero-arg closure parameter (`render_inner`) is freed *before* it is called. The crash was introduced by **`080e31f`**, which set `needs_rc (TVar _) = true` to fix the (separate) `Gate.cast` double-free. The two fixes are currently **mutually exclusive**: toggling that one line flips which test crashes.

A *related* desugar fix (the param-tuple boxing) already landed on `main` as `92dadd9`
(`fix(desugar): nested-module default-arg fns boxed params into a tuple → erased-closure UAF`).
That fix is correct and necessary but **not sufficient** — `080e31f` independently re-breaks test 37.

---

## The bug, precisely

### Symptom
- `bastion` test 37 crashes. Backtrace (under lldb, `-O0` build):
  - `EXC_BAD_ACCESS code=257 address=0x2` — i.e. an **indirect call to `0x2`** (a freed/garbage closure code pointer) from `Form.Wrapper.render`. That call is `render_inner()`.
  - At `-O2` the corruption cascades into `march_decrc_freed ← find$apply ← Form.Wrapper.render` (the freed memory gets reused, then `get_assign`'s `find` walks a garbage assigns list).
- A watchpoint on `conn`'s rc word shows `conn` is freed *legitimately* by `HttpServer.assigns` (the normal consume); the crash is `render_inner()` jumping to `0x2` afterwards. So **the victim is `render_inner`, not `conn`**.

### Why it happens (chain)
1. `Form.Wrapper.render` takes an untyped trailing closure param `render_inner`, called as `render_inner()` (zero args).
2. **Zero-arg closures are typed as a THUNK** — `fn () -> T` is typed `T` (its result), **not** `() -> T`. This is a deliberate, documented convention (see `test/native/zero_arg_closure_default.march`). In the *generic* (non-monomorphised, per-file-compiled) `render`, `render_inner`'s result type is unresolved, so `render_inner : '_NNNN` — a bare `TVar`.
3. `080e31f` set `needs_rc (TVar _) = true` (`lib/tir/perceus.ml`, ~line 187). Now this `TVar` thunk closure is RC-managed where before it was invisible.
4. In the full whole-program build (when `render`'s callees `CSRF.tag_string → CSRF.token → HttpServer.get_assign → find/assigns` are **inlined** into `render`), a **spurious `decrc_local(render_inner)` is placed early** — before the `call_ptr render_inner()` — so the closure is freed, then called → UAF.

### Confirmation (the decisive experiment)
Toggle the one line `lib/tir/perceus.ml:~187`:
```ocaml
(* 080e31f's change *)
| Tir.TVar _ -> true          (* main: test 37 CRASHES, Gate.cast (test 49) PASSES *)
| Tir.TVar _ -> false         (* revert: test 37 PASSES (suite reaches 49), Gate.cast (test 49) DOUBLE-FREES *)
```
Bastion's suite reaches **49 dots** with `false` (test 37 passes), and crashes at **37** with `true`. This is the whole conflict in one line.

---

## Code: where things live

| Concern | File:approx-line | Notes |
|---|---|---|
| `needs_rc (TVar _) = true` (the trigger) | `lib/tir/perceus.ml:187` | from `080e31f`; needed for Gate.cast |
| `infer_app` zero-arg case (`\| [], t -> t`) | `lib/typecheck/typecheck.ml:3533` | the thunk-typing of `f()` |
| Perceus ECallPtr RC (callee handling) | `lib/tir/perceus.ml:537` | consumed model (correct — do NOT change to borrow) |
| Perceus EApp `post_dec_vars` (reference pattern) | `lib/tir/perceus.ml:~462` | how borrowed-arg drops are placed after a call |
| desugar fix that landed (`92dadd9`) | `lib/desugar/desugar.ml:575` | nested default-arg fast-path; already on main |
| defun EApp→ECallPtr for erased closures | `lib/tir/defun.ml` (`838a37c`) | already converts `render_inner()` to ECallPtr |

### The two relevant March programs

**Regression fixture (single-file, currently PASSES — keep it passing):**
`test/native/zero_arg_closure_default.march` — a module-nested default-arg fn with a trailing zero-arg closure param. In single-file form, `render_inner` resolves to a concrete `String`, so the bug does NOT reproduce here. The bug needs the *generic* (cross-module / per-file) form where `render_inner` stays a `TVar`.

**Minimal demonstration of the thunk typing (why option (a) is wrong):**
```march
mod E do
  fn g(f) do f() end            -- generic: typechecks f as '_NNNN, NOT () -> '_a
  fn main() do
    let r = g(fn () -> 5)        -- fn () -> 5 is typed `Int` (thunk), not `() -> Int`
    println(int_to_string(r))
  end
end
```
`--dump-tir --no-opt` shows two instances: `fn g$Int(f : Int)` (mono, erased to result) and `fn g(f : '_31398) : '_31398` (generic, bare TVar). The generic `g` is the shape that breaks.

---

## Fixes that were TRIED and FAILED (do not repeat)

### ❌ (a) Typecheck `infer_app`: constrain zero-arg `TVar` callee to a function type
Added a case to `infer_app` (`typecheck.ml:3533`): for `[], t when idx = 0` and `repr t = TVar _`, `unify t (TArrow (t_unit, ret))` and return `ret`.
**Result:** breaks the deliberate thunk convention. `test/native/zero_arg_closure_default.march` fails to typecheck:
`I expected `String` but found `() -> String`` — because the passed `fn () -> ...` is typed as its *result*, not a function, so it can't unify with `() -> ret`. **The typecheck layer is the wrong place.**

### ❌ (c) Perceus ECallPtr: treat the callee `$clo` as borrowed (no incref + post-call drop)
Changed `ECallPtr (a, args)` (`perceus.ml:537`) so `a` (the closure) is borrowed: dropped after the call if dead-after, like EApp's `post_dec_vars`.
**Result:** double-free (`march: local RC underflow`, bastion test ~15). The generated closure-apply **OWNS/CONSUMES `$clo`** — Perceus drops it at the apply's scope exit. (The `incrc_local $clo` at the apply's entry is just the dup for `$clo`'s multiple internal uses — reading captured FVs + the recursive self-call.) So **the original consumed model is correct**; the real defect is a *spurious extra* drop added downstream.

---

## What we know about the spurious drop (the crux)

- Perceus's `--no-opt` output for `render` is **clean** (no `dec_rc render_inner`) and **byte-identical** between `needs_rc(TVar)` true/false (only SSA renumbering differs). So Perceus is not the source.
- None of the opt passes **add** an `EDecRC`: `inline.ml`/`cprop.ml`/`fusion.ml` only `subst_atom` existing RC ops; `dce.ml` only removes; `llvm_emit.ml` adds no param drops.
- The spurious `decrc_local(render_inner)` appears **only in the full whole-program build**, where `render`'s callees are inlined into it. With `needs_rc(TVar)=true` those callees (the `conn → get_assign → find/assigns` path, full of `TVar` list values) carry **extra RC ops**; one of them, after inlining + substitution, lands as a drop of `render_inner`.

**Leading hypothesis:** an inlined callee's existing `EDecRC` gets its atom substituted to `render_inner` (or an alias of it) during inlining/cprop, because the generic types make two distinct values look interchangeable. Find that substitution.

---

## Diagnostic plan (for the next agent)

### Build & run harness
- Dev compiler: build in the worktree with `dune build --root .` (NOT bare `dune build`).
- Shim for `forge`: `cp _build/default/bin/main.exe /tmp/marchroot/bin/march` and
  `ln -sfn <worktree>/runtime /tmp/marchroot/runtime` (the runtime symlink is needed; re-`cp` after every rebuild). Run bastion with
  `PATH=/tmp/marchroot/bin:$PATH MARCH_STDLIB=<worktree>/stdlib forge test` in `/Users/80197052/code/bastion`.
  Clear `<bastion>/.march/cas <bastion>/.march/build` before each run; clear `~/.march/cas ~/.cache/march/*` if you see stale `Undefined symbols`/linker errors.
- **Gotcha:** the resolver walks the *source directory* of the entry file. Do NOT put ad-hoc `.march` test files in `/tmp` — a concurrent session left `/tmp/marchbin/march` (a broken symlink) there and the walk crashes (`Sys_error /tmp/marchbin/march`). Use a clean subdir like `/tmp/mt/`.
- Build a debuggable binary directly from `bastion/test/bastion_test.ll`: `clang -O0 -g ... <runtime/*.c> ... test/bastion_test.ll -o /tmp/bt -lm` (see `bin/main.ml`'s clang invocation for the full flag list incl. openssl/zstd/brotli). `-O0` gives clean lldb frames (no inlining), `-O2` reproduces the original crash signature.

### Pin the spurious drop to a specific pass (the missing piece)
Render gets DCE'd in reduced repros (DCE seeds from `main`/`tm_tests`); it only survives in the full forge build. Two ways to see it surviving:
1. **Instrument `lib/tir/opt.ml`'s `run`/`apply`** to dump (or flag) `Form.Wrapper.render`'s body after each `(label, pass)`, gated by an env var, matching `fn.Tir.fn_name` ending in `Wrapper.render`. Then compile the **full test entry** with the test-runner main so render survives all opt iterations. `--compile`/`--emit-llvm` of the test file DCE the test functions (so render too) — find/replicate how `forge test` keeps `__march_test_N__` as DCE roots (`tm_tests`), or temporarily seed DCE with all fns. Watch for the first pass where `dec_rc render_inner` appears.
2. **Structural IR diff** (already done once, reproduce + extend): build the bastion `.ll` twice (`needs_rc(TVar)` true vs false), extract `@Form.Wrapper.render`, and diff the resolved `(rc_op, target .addr slot)` pairs. Confirmed result: `TVar=true` adds `+1 decrc_local` for each of `action, method, class, id, enctype, render_inner` (render's params). Trace which inlined callee those came from by also diffing the inlined callees (`CSRF.tag_string`, `HttpServer.get_assign`, `find$apply`, `HttpServer.assigns`).

### Confirm any candidate fix
A fix is correct iff ALL of:
- `bastion`: `forge test` passes test 37 **and** test 49 (`Gate.cast`) — i.e. reaches the full suite, no `RC underflow`/`SIGBUS`/jump-to-`0x2`.
- `dune runtest` is green, including `test/native/zero_arg_closure_default.march` (the existing erased-closure regression) and the `perceus` group's "incrc for unresolved-tvar value used twice (cross-module opaque)" test that `080e31f` added (this guards Gate.cast at the IR level).
- The compiler's own suite count doesn't drop.

---

## Proposed fix directions (in rough order of promise)

### (b) Narrow `needs_rc(TVar _)` — RECOMMENDED first attempt
`080e31f` made it `true` for ALL unresolved type-vars, to catch cross-module opaque **data** values (`gate`) that get double-freed. The collateral damage is **called thunk closures** (`render_inner`). If the two can be distinguished, narrow the predicate.
- Idea: distinguish at the *use* site rather than in `needs_rc`. A `TVar` value that is **called** (`ECallPtr` callee) is a closure consumed by the apply and must NOT receive an independent drop, whereas a `TVar` value that is **stored/returned/passed as data** is the Gate.cast case that needs the incref.
- Concretely: keep `needs_rc(TVar)=true`, but make the **inliner/cprop substitution** (or whatever lands the drop) not produce a drop for a value that is an `ECallPtr` callee. This requires finding the exact pass first (see diagnostics).

### (c′) Per-call-site borrow modes for ECallPtr (the "proper" but large fix)
The existing `ECallPtr` comment in `perceus.ml` explicitly calls this out: attach per-call-site borrow modes to closures at `EAlloc` time and plumb them through dispatch. This would let Perceus know whether a given apply consumes vs borrows `$clo`/args, instead of the current blanket "consumes args". Big, but it's the principled fix and would also remove the conservative inc/dec pairs around HOFs.

### (d) Resolve the thunk type instead of erasing (typecheck-adjacent, risky)
The root irritant is that a called zero-arg closure is typed as a bare `TVar` in the generic form. Rather than change `infer_app` globally (proven to break the thunk convention), consider: in **defun**, when converting `EApp(f,[]) → ECallPtr` for a locally-bound callee, also re-tag the callee var's type as a closure (`TPtr`/closure) so downstream RC treats it consistently as a heap closure rather than a generic `TVar`. Must verify this doesn't desync the var's type with other uses.

---

## Acceptance criteria
1. `forge test` in `/Users/80197052/code/bastion` runs the full suite with **no** `RC underflow` / `march_decrc_freed` / `SIGBUS` / jump-to-`0x2`, passing both test 37 (`Form.Wrapper.render`) and test 49 (`Gate.cast`).
2. `dune runtest` green; `test/native/zero_arg_closure_default.march` and the `perceus` Gate.cast IR test both still pass.
3. A new regression test added (a generic/cross-module fn with a zero-arg thunk closure param called after a heap-field-consuming call) that crashes pre-fix and passes post-fix — note this needs the *generic* shape, so it likely belongs as a multi-file fixture (entry + lib) rather than a single-file `test_march.ml` case, OR an IR-level assertion that `render_inner`'s only `EDecRC` is not placed before its `ECallPtr`.

## Background / related commits
- `92dadd9` fix(desugar): nested-module default-arg fns boxed params into a tuple → erased-closure UAF (landed; necessary, not sufficient)
- `838a37c` fix(defun): convert erased-type closure calls to ECallPtr (in main; makes `render_inner()` an ECallPtr)
- `080e31f` fix(tir): RC use-after-free on cross-module opaque types (`needs_rc TVar`) — **the trigger for this bug**
- Memory note: `project-bastion-csrf-uaf-rootcause` has the full investigation log + the verification-harness recipe.
