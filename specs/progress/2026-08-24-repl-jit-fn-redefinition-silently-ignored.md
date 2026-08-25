# REPL JIT: `fn` redefinition silently ignored on both backends

## Symptom

```
march(1)> fn f(x) do x + 1 end
march(2)> fn f(x) do x + 100 end
march(3)> f(1)
= 2            <- should be 101
```

The second definition printed `val f = <fn>` but had no effect, on BOTH the
clang and ORC JIT backends. Interpreter mode (`MARCH_REPL_INTERP=1`) already
rebound correctly (`= 101`), so the JIT paths diverged from the language's
Elixir-style rebinding semantics. Found 2026-08-24 while reviewing the ORC
REPL segfault fix (see that fix's spec, "Follow-up noticed" — landed on the
`claude/jit-repl-interpreted-perf-68373c` branch).

## Root cause

`lib/jit/repl_jit.ml` `run_decl`'s `is_fn_decl` path early-returned whenever
`Hashtbl.mem ctx.compiled_fns bind_name` — a guard added for `:reset`
scroll-replay (the scroll system resends prior cells verbatim; the function
is already compiled and its closure slot still valid, so recompiling is pure
waste). The guard could not tell a verbatim resend from a genuine
redefinition, so a new body for an existing name never recompiled and never
rebound the closure slot.

## Semantics decision

Redefinition rebinds, exactly as interpreter mode already does. The
mechanism the JIT already uses makes this natural: cross-fragment calls to a
REPL-defined `fn` resolve through its persistent closure SLOT
(`march_repl_get` + indirect call at closure+16 — verified in the emitted
fragment IR), not through the LLVM symbol, so rebinding the slot to a new
closure redirects every later call.

## Fix (lib/jit/repl_jit.ml)

- New `ctx.fn_fingerprints : bind_name -> Digest(Marshal(decl AST module))`,
  recorded only after the fragment compiles and loads (same
  success-only discipline as `mark_compiled_fns`). Each REPL input is parsed
  from its own fresh `Lexing.from_string`, so identical source text yields a
  byte-identical marshaled AST.
- `run_decl ~is_fn_decl:true` now distinguishes three cases:
  - **Replay** (compiled + fingerprint matches): keep the skip fast path.
  - **Redefinition** (compiled + fingerprint differs): recompile and rebind.
  - **No fingerprint on record** (compiled by the stdlib prelude or `:load`,
    not by `run_decl`): keep the historical skip — calls to those resolve as
    direct extern calls, not through a slot, so a redefinition could never
    take effect anyway.
- A redefinition is emitted under a session-unique symbol
  (`<name>$redef$<fragment-counter>`, via a capture-avoiding
  `rename_top_fn_refs` over the fragment's post-defun TIR so self-recursion
  and first-class self-references follow the rename): the earlier fragment
  already defined `<name>`, and the ORC backend's single JITDylib
  hard-errors on duplicate definitions (clang+dlopen would merely shadow
  ambiguously in the flat namespace).
- The freshly lowered `bind_name` is pulled back out of `partition_fns`'
  extern list (its OLD version being in `compiled_fns` had classified it as
  extern), and the old binding's slot is filtered out of `prev_slots` so the
  emitter doesn't emit a slot-loader `define @<name>()` that would collide
  with the original definition under ORC. This filter is what lets the fix
  work independently of the ORC internal-linkage loader fix on the
  `claude/jit-repl-interpreted-perf-68373c` branch; the two compose.
- The slot registration at the end rebinds the bare name to a fresh slot
  holding the new closure. The old slot keeps the old closure alive — one
  abandoned closure per redefinition, the same shape as `let` rebinding.

`val fragment_count : t -> int` was added to the `.mli` so tests can assert
the replay path compiles no new fragment.

## Validation

- `test/test_codegen.ml` `test_repl_jit_fn_redefinition` (in-process, clang):
  original body, redefinition (`101` not `2`), identical replay skips
  (fragment count unchanged) and keeps the binding, self-recursive
  redefinition reaches the new body, arity-changing redefinition works.
  Verified red against the un-fixed compiler (`Received: "2"`).
- `test/test_jit.ml` `repl_session` group: subprocess end-to-end sessions of
  the real binary for the clang backend, ORC backend (`MARCH_JIT_BACKEND=orc`,
  skips when libLLVM is absent), and interpreter mode. Subprocess so a
  backend SIGSEGV fails one test rather than the runner, and because the
  backend env vars are read once at module init. Both JIT sessions verified
  red pre-fix; interpreter green pre- and post-fix.
- Control sessions unchanged: `fn f; fn sq; sq(3); f(1)` and a redefinition
  with an intervening stdlib let-lambda both behave on clang.

## Known limitations (pre-existing, unchanged)

- `fn g(x) do f(x) end` referencing a prior REPL `fn` fails on both backends
  ("I cannot find `g`" / fragment IR collision) — the "Follow-up noticed"
  item on the ORC-fix branch. Because later REPL-defined functions cannot
  reference `f` at all today, there are no stale direct-call sites for a
  redefinition to miss; if that limitation is lifted, calls lowered as
  direct extern `f` calls inside OTHER functions would pin the version
  compiled at their definition time and should be revisited then.
- Redefining a stdlib/`:load`-ed function is still silently ignored (see
  above — no slot to rebind).
- A REPL `fn` whose body contains any lambda already fails its helpers
  fragment's dlopen on the clang backend (`symbol not found in flat
  namespace '_f'`) and loses the binding — reproduced on unmodified HEAD
  with a fresh HOME, so redefinition of such functions is untestable until
  that is fixed. Filed separately.
