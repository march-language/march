# A2: provenance side table + `--debug-info` (function-level DWARF, `!march.provenance`)

**LANDED 2026-10-06.** Item A2 of `specs/plans/incremental-codegen-cas-plan.md` §7, as shaped
by the review notes in §19. Scope of this entry: the table, its seeding and rename hooks, pass
recording, `--debug-info` with function-level `!dbg`, `!march.provenance`, `--dump-provenance`.
Follow-ups, not here: the `.march_build` manifest sidecar, per-instruction `!dbg` with real
line numbers, structural symbol names (B1).

## The table (`lib/tir/provenance.ml`)

`fn_name -> origin`, where `origin = { src_span; host; derived; passes }`. A side table, not a
TIR field: `fn_def` has no span, and adding one would churn every TIR snapshot and
`Serialize` (precedent: `js_emit.ml`'s `fn_lines`). Derivations: `Mono_of (generic, tyargs)`,
`Fusion_of (producer, consumer)`, `Hof_spec_of (g, apply)`, `Defun_of lambda`,
`Join_point_of`, `Inlined_from`, `Clone_of (orig, reason)` (TRMC `$dps`, the unboxed Float
clones of Hof_spec / Native_map_inline).

**Lifecycle.** Module-level, like `Mono.repr_table` / `Fusion.gensym_ctr`, but **reset at the
start of `Lower.lower_module`, not of `Contract_pipeline.run`** as the plan first said: the
seed happens at the end of lowering, before the pipeline exists, so a reset there would have
erased it. For the REPL/JIT, which lowers one fragment per call through the same
`Lower.lower_module`, this makes the table per-fragment with no opt-out needed; the JIT's own
pass list (`lib/jit/repl_jit.ml`) records into it harmlessly and the REPL never sets
`debug_info`, so no fragment carries metadata.

**Seeding.** Lowering `note_span`s every parsed fn under its creation-time name
(`Lower_decls.lower_fn_def`; lambdas and local `fn`s in `lower_expr.ml`, so a lifted lambda has
the lambda's own span) and calls `Provenance.rename` at every post-creation rename: the
stdlib-module prefix (`lower_decls.ml`), the user-module prefix, the impl-method mangle and the
builtin-shadow rename (`lower.ml`), and `uniquify_fn`'s `$shN` suffix. `seed_from_lowering` at
the end of `lower_module` walks the final `tm_fns` against the noted spans. A span is skipped
only when it is `Ast.dummy_span` (line 0), **not** when its file name is empty: a module parsed
from a string (tests, REPL) has lines and no file, and the first version of this filter made
every test-side lookup return `None`.

**Recording.** Mono (specialisation), Fusion (the three `$fused_*` generators and the
NativeArray chain lambda; host = the fn being rewritten, via `with_host`), Hof_spec (`$hspec$N`
clones and `$ufast$` unboxed clones), Defun (`lift_lambda`, host from
`Provenance.nested_fn_hosts`, span inherited from the lambda), TRMC (`$dps`), Native_map_inline.
`record ~from:orig` copies span/host/derivations from the origin, so `ident$Int` points at
`ident`'s line. **Completeness without trusting every pass:** `Contract_pipeline.run` wraps its
`snap` hook with `Provenance.sweep ~pass:name`, and sweeps once more at the end, so any top-level
fn a pass created without recording (Drop's `$clodrop$…`, Cap_passing's registrars, …) still
gets an origin naming the pass that made it. On a program that loads the whole stdlib that is
~9.2k entries; `--dump-provenance` prints them all (name, span, host, derivations, passes;
tab-separated, sorted) for A5's determinism oracle.

## `--debug-info` (`lib/tir/llvm_toplevel.ml`, `bin/main.ml`)

A new flag, distinct from `--debug`/`--debug-tui` (the interpreter's time-travel debugger).
Driver-set into `Llvm_toplevel.debug_info`; own CAS tag `dbginfo` in `codegen_cas_tags`; passes
`-g` to clang (native and wasm links). Under it the emitter adds:

- a `distinct !DISubprogram` per March function, attached as `!dbg !N` on its `define`, with
  `name` = the TIR name and `linkageName` = the mangled symbol, at the function's
  `Provenance.effective_span` (own span, else the host chain's, else the module file line 1);
  one `!DIFile` per distinct source file, interned;
- the `!llvm.dbg.cu` / `!llvm.module.flags` block (`Debug Info Version` 3, `Dwarf Version` 4
  for ld64; lld reads it fine);
- `!march.provenance = !{…}`, one `!{!"name", !"span=… host=… derived=… passes=…"}` per function;
- **a `!dbg` on every `call` inside a `!dbg` function.** This was forced, not chosen: LLVM's
  verifier rejects a call without a location in a function that has a subprogram when the
  callee has one too ("inlinable function call in a function with debug info must have a !dbg
  location") and then *drops the module's debug info entirely* ("ignoring invalid debug info"),
  so function-only `!dbg` would have produced binaries with no DWARF at all. The location is the
  function's own line (`!DILocation(line: L, scope: !N)`, emitted as `!N+1` right after each
  subprogram), so it is still function granularity, stated per call. Done as a text pass
  (`attach_call_dbg`) over the finished module, like `Llvm_rc_inline`, because calls are printed
  by a dozen emitter files and the attachment must be total.

Emitter glue that is not a March function (the C `main` entry wrapper, `march_clo_drops_register`)
carries no subprogram and needs none; the verifier's rule is about the caller's subprogram.

**Byte-identical when off.** Every addition is behind `!debug_info`; the `define` format string
gains an empty suffix. Proven with `scripts/ir-oracle.sh` (baseline with a frozen pre-change
`main.exe`, check with the new one; red-proved by a check with a wrapper that forces
`--debug-info`, which changes every program's hash). The REPL path (`ctx.repl`) is additionally
excluded in `emit_fn_body`.

**`Llvm_rc_inline`.** Its rewrite runs after emission and only inspects `define` lines (passed
through) and `call … @march_incrc(` lines; a trailing `, !dbg !N` survives the rewrite. Covered
by `test_provenance.ml` (verifier run on the IR before and after `rewrite`) and by the
`--compile --debug-info` end-to-end case, which goes through `maybe_inline_rc`.

## What a `--debug-info` binary shows

Same program (`boom` panics inside `main`), `lldb --batch -o "b march_panic" -o run -o bt`:

```
# without
frame #2: 0x000000010001e380 smoke_nodbg`march_main + 1400
# with --debug-info
frame #2: 0x000000010001e380 smoke_dbg`march_main at prov_smoke.march:18 [opt]
```

Function granularity is enough for ASan, `perf` and crash backtraces to name March functions
and their defining line. macOS: lldb reads the DWARF from the object files it links; for a
symbolised *crash report* ld64 still wants `dsymutil`. Not automated as a CI test: driving
`lldb`/`gdb` in batch mode from alcotest is fragile across runners, so the manual check above is
the documented one; what CI does run is the `--compile --debug-info` end-to-end case (links with
`-g`, runs, panics with the expected message) and the verifier gates.

## Tests

- `test/test_provenance.ml` (suite `provenance`, registered in `codegen_suites`): every final
  top-level fn has an origin and every synthetic one a host or a derivation; a nested-module fn
  keeps its span under its prefixed name; `ident$Int` / `ident$String` are `Mono_of`; the user
  lambdas are `Defun_of` with hosts `main` / `pipeline`; the `imap`/`ifold` pipeline's
  `$fused_mf_*` is `Fusion_of (imap, ifold)` hosted by `pipeline`; off = no metadata in the
  module; on = `!dbg` on every March define, one subprogram per `!dbg` define, every call in a
  `!dbg` function located, `!march.provenance` present, verifier-clean before and after the
  inline-RC rewrite; `attach_call_dbg` RED-first (a call outside a `!dbg` function is left
  alone); `Slow`: `--compile --debug-info` links and runs.
- `test/test_ir_verify.ml`: the native corpus gate now runs a second time under `--debug-info`
  (`emit_llvm_ir_to_file ?extra_flags`).

## Not done / deferred

- `.march_build` manifest sidecar (plan §7, "Build manifest as a sidecar").
- Per-instruction `!dbg` with real line numbers (plan §18.6) — would need spans on TIR
  expressions, which this side table deliberately avoids.
- `Join_point_of` / `Inlined_from` are declared but nothing records them yet: join points are
  nested fn_defs (never top-level) and `Inline` only freshens local `letrec` names; they are
  there for B1's pass-by-pass threading.
- `--dump-provenance` prints stdlib spans with the path lowering saw
  (`…/_build/default/bin/../../../stdlib/x.march`), un-normalised; A5 should normalise or
  accept it as machine-stable.
