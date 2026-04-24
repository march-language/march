# JIT / REPL improvement plan

**Date:** 2026-04-22
**Scope:** `lib/jit/repl_jit.ml`, `lib/tir/llvm_emit.ml`, `lib/repl/repl.ml`, `test/repl_smoke_test.sh`

Plan derived from an audit of the March REPL JIT. Groups fixes into three
phases by ROI: correctness first (wrong answers shown to users), then
performance, then feature gaps.

---

## Phase 1 — Correctness (pretty-printer + state hygiene)

These are silent user-visible bugs. Tackle first.

### 1.1 Tuple fields display wrong values

**Symptom**
```
(42, 99)         →  (21, 49)
(true, false)    →  (false, false)
[(1,2), (3,4)]   →  [(0, 1), (1, 2)]
```

**Root cause** [lib/jit/repl_jit.ml:245-250](../../lib/jit/repl_jit.ml:245) —
`pp_field` always right-shifts `TInt`/`TBool` scalars by 1 assuming a tag
bit. ADT payloads (Some/Ok) are tagged so they render correctly; tuple
fields are stored untagged.

**Fix** — split `pp_field` into two variants, or thread a `tagged:bool`
flag from the parent. Concretely:
- Tuples: pass `~tagged:false` for scalar fields.
- ADTs (Cons, Some, Ok): pass `~tagged:true`.
- Decide tagging at the parent's call site in `pp_heap_value` where the
  parent type is already known.

**Acceptance** — smoke-test additions:
```
(42, 99)         ⇒ (42, 99)
(true, false)    ⇒ (true, false)
[(1,2), (3,4)]   ⇒ [(1, 2), (3, 4)]
```

**Effort** — ~15 LOC.

### 1.2 User-defined ADTs print as `#<tag:0>`

**Symptom**
```
type Color = Red | Green(Int) | Blue(String)
Red       → #<tag:0>
Green(42) → #<tag:0>
```

**Root cause** [lib/jit/repl_jit.ml:221-224](../../lib/jit/repl_jit.ml:221)
— `pp_heap_value` hardcodes `List`/`Option`/`Result` and falls through to
`#<tag:N>` for every other `TCon`.

**Fix** — thread `tir.tm_types` (already available in `run_expr`) into a
new `global_type_defs : (string, Tir.type_def) Hashtbl.t` on `ctx`, updated
from `run_decl` alongside `global_tir_tys`. Extend `pp_heap_value`: when
`ty = TCon (name, args)` and `name` is in `global_type_defs`, look up the
constructor by `heap_tag`, substitute type-arg bindings into its payload
types, render as `Name(...)`.

**Acceptance**
```
Red          ⇒ Red
Green(42)    ⇒ Green(42)
Blue("hi")   ⇒ Blue("hi")
```

**Effort** — ~60 LOC (type-arg substitution is the fiddly part).

### 1.3 Polymorphic return type recovery

**Root cause** [lib/jit/repl_jit.ml:317-321](../../lib/jit/repl_jit.ml:317)
— `find_retvar` only walks `EAtom`/`ESeq`/`ELet`. Bodies ending in
`EIfEq`, `EMatch`, `ECase` fall back to `#<0xADDR>`.

**Fix** — extend the match to recurse into all branch bodies; if every
branch returns the same TIR type, use it; else fall back. Alternative:
capture the monomorphized `ret_ty` from mono's substitution table rather
than re-deriving.

**Effort** — ~25 LOC.

### 1.4 Record literals don't parse in REPL

**Symptom** — `{x: x, y: y}` ⇒ parse error.

**Action** — confirm if this is REPL-specific (token filter) or a broader
parser gap. If broader, punt to a parser-owned ticket. If REPL-specific,
investigate how the REPL wraps input into a module.

**Effort** — investigation first.

### 1.5 Temp-file cleanup on startup

**Problem** — `/tmp/march_jit/repl_*.ll/.so` accumulates when the REPL is
SIGKILL'd; `cleanup` at [lib/jit/repl_jit.ml:594](../../lib/jit/repl_jit.ml:594)
only runs on clean exit.

**Fix** — at `create` time, stat the tmp dir and delete stale files older
than N minutes (or just delete all files on startup — the previous session
is dead). Keep `MARCH_KEEP_LL` as an escape hatch.

**Effort** — ~10 LOC.

### 1.6 Smoke-test comment is stale

[test/repl_smoke_test.sh:12-26](../../test/repl_smoke_test.sh:12) still
describes the cross-fragment declare bug as open, though the prior session
fixed it and the XFAIL tests now pass. Rewrite the KNOWN ISSUES block to
reflect actual current gaps (1.1, 1.2 above).

**Effort** — docs only.

---

## Phase 2 — Performance (drop clang-driver overhead)

Measured cold start ~4s (stdlib compile dominates), warm ~0.3s, each
subsequent fragment ~150-200ms. All dominated by `clang -shared` driver.

### 2.1 Drop to `-O0` for fragments

**Change** — [lib/jit/repl_jit.ml:96](../../lib/jit/repl_jit.ml:96)
`clang -shared -fPIC -O1` → `-O0 -fno-lto`. Stdlib stays at its current
-O1 cached build; only REPL fragments drop.

**Expected** — fragment time drops ~40%.

**Risk** — none user-visible. Stdlib is the hot path; REPL code runs
once.

**Effort** — 1 line + re-run smoke test.

### 2.2 Pipe IR via stdin

**Change** — replace the `.ll` write + exec with
`clang -x ir -o SO -` feeding IR on stdin. Saves the file-write round-trip
and keeps `MARCH_KEEP_LL` by shelling to `tee` when set.

**Expected** — 5-15ms per fragment.

**Effort** — ~20 LOC.

### 2.3 Migrate to LLVM ORC JIT (strategic)

**Change** — replace the `clang → .so → dlopen` pipeline with in-process
LLVM ORCv2. Each fragment:
- `LLVMParseIRInContext` on the IR string
- `LLVMOrcLLJITAddLLVMIRModule` into the session JIT
- `LLVMOrcLLJITLookup` for the fragment's main symbol

**Expected** — per-fragment latency 150ms → 10-30ms (5-10x).

**Cross-cutting wins**
- Cross-fragment symbols auto-resolve via the JIT symbol table — the
  `compiled_fns` / `partition_fns` / `mark_compiled_fns` bookkeeping in
  `repl_jit.ml:111-150` can be deleted.
- `extern_fns` declare-emission in `llvm_emit.ml` still needed (LLVM IR
  validation), but the "is it already loaded" check moves to a single
  LLJIT symbol lookup.

**Plan**
1. Decide bindings strategy. Two options:
   - **OCaml `llvm` opam package** — has `Llvm_executionengine` (MCJIT,
     older but functional). Pro: no custom C. Con: MCJIT is legacy,
     ORCv2 coverage incomplete.
   - **Custom C stubs** in [lib/jit/jit_stubs.c](../../lib/jit/jit_stubs.c)
     around `LLVMOrcLLJIT*` APIs. Pro: picks ORCv2 directly. Con: ~400
     LOC of bindings.
2. Prototype on MCJIT first — smaller diff, validates the approach.
3. Once MCJIT path runs the smoke test, revisit ORCv2 if latency isn't
   there yet.
4. Keep the stdlib `.so` dlopen path: stdlib is precompiled once and
   loaded via RTLD_GLOBAL, so the JIT just inherits those symbols (same
   as today).

**Risk** — largest diff in the plan. Stage behind an env flag
(`MARCH_JIT_BACKEND=orc` vs `clang`) so the old path remains as a
fallback during development.

**Effort** — MCJIT prototype: 1-2 days. ORCv2 migration: 3-5 days
additional.

### 2.4 Content-hash fragment cache

**Change** — hash the fragment IR. If a `.so` for that hash already sits
in `~/.cache/march/fragments/`, skip clang and dlopen directly.

**Hit rate** — likely low in interactive REPL, but useful for scripted
sessions and the smoke test itself (which runs the REPL many times with
identical input).

**Effort** — ~30 LOC. Orthogonal to 2.3 — applies to either backend.

---

## Phase 3 — Feature gaps (REPL reaches AOT parity)

Ordered by user demand, not implementation cost.

### 3.1 User-defined `impl Interface(Type)`

**State** — parses, typechecks, but the interface-dispatch table built
for stdlib impls isn't rebuilt for REPL-declared impls. Interface method
calls against user-declared impls fail to dispatch.

**Investigation needed** — locate where stdlib impl tables are
synthesized (likely `lib/tir/mono.ml` or `llvm_emit.ml`) and lift that
into a per-fragment pass.

### 3.2 Actors in the REPL ✅ DONE (2026-04-23)

**Problem** — actor declarations register only in the interpreter's
scheduler, but JIT-compiled `spawn`/`send`/`run_until_idle` call the
*runtime's* native scheduler. Two schedulers, one registry: messages
were enqueued but never dispatched, `println` inside handlers dropped,
`run_until_idle()` returned `1` instead of `()`.

**Resolution** — rather than dual-registering actors into both
schedulers (requires JIT IR-gen for `DActor` + scheduler-init hook), we
guarantee a single scheduler by flipping the REPL back to the
interpreter once any `DActor` is seen. New `actors_declared` ref in
`lib/repl/repl.ml` guards the three JIT paths (fn decl, let decl,
ReplExpr) in both `run_simple` and `run_tui`. Basic JIT path still runs
for pre-actor code in the same session (arith, lets, fns); once
`actor Counter do ... end` is parsed, subsequent forms go through the
interpreter and `println` inside message handlers reaches stdout.

### 3.3 Records

Blocked on 1.4 (parse). Once records parse, pp_heap_value needs a case
for `TRecord` that iterates the field list (reuse `tm_types` lookup like
1.2).

### 3.4 Multi-file user imports

**State** — stdlib modules resolve via `MARCH_LIB_PATH`; user `use`
imports don't because the REPL's `tc_env` only bootstraps with stdlib.

**Effort** — medium. Either surface `MARCH_LIB_PATH` into the REPL
entry point, or add a `:load path.march` command.

### 3.5 Async / effects / session types

**State** — out of scope for near-term. Session-type verification runs
pre-TIR so errors surface, but the JIT doesn't emit session-protocol
runtime hooks. Document as known-unsupported; reassess when AOT has
shipped these features end-to-end.

---

## Rollout

**Sprint 1 (correctness)** — 1.1, 1.2, 1.3, 1.5, 1.6. Ship as one
commit; smoke test grows to cover tuple/ADT pretty-print.

**Sprint 2 (quick perf wins)** — 2.1, 2.2. Measure per-fragment latency
before/after.

**Sprint 3 (strategic perf)** — 2.3 MCJIT prototype behind
`MARCH_JIT_BACKEND` flag. Decide on ORCv2 migration based on profile
data.

**Sprint 4 (feature parity)** — pick from 3.1-3.4 based on what users hit
most in the smoke test and the AOT test suite.

## Success metrics

- Smoke test: **0 XFAIL**, covers tuples + user ADT printing.
- Warm-start single-fragment latency: **<100ms** (target) vs. ~170ms
  today.
- Cross-fragment session (10 defs): **<500ms total** (target) vs.
  ~1.5-2s today.
- `dune runtest` unchanged at 147 tests passing.

## Non-goals

- Rewriting the stdlib precompile path — it's already cached and fast
  enough.
- Changing the tagged-integer ABI. Only the display layer is touched.
- Replacing clang as the AOT compiler. Plan touches the REPL JIT only.
