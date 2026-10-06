# One builtin-callee table; an unknown callee is a compile error

First deliverable of A1 (TIR verifier) in
`specs/plans/incremental-codegen-cas-plan.md` §6.

## Before

TIR has no builtin constructor: a builtin call is an ordinary `EApp` on the bare
runtime name. The LLVM emitter's two direct-call sites
(`Llvm_emit_call.emit_generic_app` and `emit_callptr_global`) each decided
"known callee" from `top_fns`, `extern_map`, a `march_` C-symbol prefix,
`Llvm_builtins.builtin_ret_ty <> None`, and a hard-coded list of eleven I/O
names (`panic`, `println`, `read_line`, ...). Anything else got a forward
`declare` built from the call-site types, recorded in `ctx.unknown_decls`, so a
mistyped or unregistered builtin failed at link time, or linked to an unrelated
same-named C symbol.

## After

- `lib/tir/builtin_table.ml`: `is_builtin`, `all` (sorted, unique), `ret_ty`.
  Sources: the row table `Llvm_builtins.builtins` unioned with
  `Builtin_name.all`. The union is not redundant: 24 `Builtin_name` members
  (`int_div`, `negate`, `task_cancel`, `signal_watch`, ...) are synthesized by
  their emit arm and have no row. Every name on the old I/O list has a row with
  a `ret_ty`, so the list was already redundant and is gone.
- `Llvm_calls.is_known_callee` is the one known-callee test both sites call:
  `top_fns || extern_map || march_ prefix || Builtin_table.is_builtin`. The
  `march_` prefix stays: lowering calls runtime symbols by C name and the
  preamble declares them (an undeclared one is an LLVM error, not a silent link).
- Unknown callee: after `fail_if_unresolved_iface_method` gets its chance,
  `Llvm_calls.unknown_callee` raises `Unknown_callee`
  ("`` `foo` (called from `bar`) is not a function in scope and not a runtime
  builtin ``"); `bin/main.ml` renders it as `error:` and exits 1. TIR has no
  spans, so the enclosing function is the position.
- One legitimate fallback user remains and keeps its `declare`: a REPL/JIT
  fragment calling a function compiled in an EARLIER fragment (e.g. `Mod.f`
  after `:load Mod`). The call is not in the fragment's TIR, and the on-use
  `declare` is what lets dlopen bind it. `Repl_jit` binds its `compiled_fns`
  around every fragment emit (`Llvm_ctx.with_repl_prior_fns`); the emitter
  declares a still-unknown callee only if it is in that table
  (`Llvm_calls.declare_prior_fragment_fn`). Outside a JIT emit the binding is
  `None`. `ctx.unknown_decls` now dedups only these and the SIMD arm's
  intrinsic declares.
- The preamble is not derived from the table (that would change its pinned
  bytes); separate follow-up.

## Did anything rely on the fallback?

Only the REPL/JIT case above. The old known set is a subset of the new one, so emitted
IR can only change where a call used to reach the `declare` fallback, and now
such a call is an error instead. The IR oracle (`scripts/ir-oracle.sh`'s
405-program corpus, run as a parallel replica under heavy machine load; same
corpus, tags, command and manifest format) shows 404 byte-identical, and one
change:

- `test/native/js_dom_timeout_callback.march` (a `--target js` fixture; its
  real dune rule builds JS and is unaffected). Emitted natively it called
  `Js.Dom.set_timeout`, which a native build does not include, so the old
  compiler emitted `declare ptr @Js.Dom.set_timeout(...)` and the build died
  at link (`Undefined symbols: _Js.Dom.set_timeout`, reproduced with the base
  compiler). It is now `` error: `Js.Dom.set_timeout` (called from `main`) is
  not a function in scope and not a runtime builtin ``. (`stdlib/dom.march`'s
  header says a native call "panics"; it was a link error, now a compile
  error.)

The three pre-existing skips (`bench/http_get*.march`, an `if` without
`else`) are unchanged.

The full suite found the rest:
- `repl_jit_cross_line` B12 (`:load`ed `OptMod.mk` called from the next
  fragment) is the JIT case above.
- `llvm_emit correctness` "int tag wrapper IR" lowered a module calling
  `map` without the stdlib; its IR only ever passed because the test reads
  text and never links. It now defines a local `map`.
- The iface-guard negative control, which pinned the old
  `declare ptr @describe`, now asserts `Unknown_callee`.

## Oddity noticed, not changed

`Llvm_builtins.builtins` has a row for `main` (`c_name = march_main`,
`ret_ty = None`), so `main` is a "builtin". Behavior is unchanged (the
`march_` prefix already made it known); pinned in
`test_builtin_table_ret_ty_or_special`'s explicit list.

## Tests

`llvm_builtins_preamble_golden` gained: table sorted/unique; covers every row,
every `Builtin_name`, and the old I/O names (each with a `ret_ty`); every member
has a `ret_ty`, a dedicated arm, or no C symbol, except an explicit list
(`main`); an `EApp` and an `ECallPtr` to `nonexistent_fn` raise
`Unknown_callee` naming callee and caller; with a prior-fragment table bound,
that name gets its on-use `declare`, and a name outside the table is still an
error.
