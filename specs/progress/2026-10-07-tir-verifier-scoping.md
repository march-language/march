# DONE 2026-10-07: A1 check 1, TIR verifier for scoping and references

Observability plan (`specs/plans/incremental-codegen-cas-plan.md`) §6, first of
the five checks.

## What landed

- **`lib/tir/tir_verify.ml`**: `check : stage:string -> ?borrow_map ->
  ?k_table -> ?iface_methods -> ?def_hashes -> ?known_fn -> tir_module ->
  (string * string) list`, in `Policy_dce.audit`'s shape: `(fn_name, message)`
  with the stage in each message. `enforce` raises `Failed (stage, findings)`
  (an exception printer renders them).
  - **Every `AVar` is bound.** It is a parameter, a `let`, a branch binder or an
    enclosing `ELetRec` function, or a global the emitter resolves.
  - **Every `EApp` callee resolves.** The rules mirror the emitter's
    known-callee test (`Llvm_calls.is_known_callee`): `tm_fns`, `tm_externs`,
    `Builtin_table` (#794), `march_` runtime symbols, the bare-to-qualified
    suffix fallback with its interface-mangled exclusion, and a local binding.
    Also accepted are the names the emitter handles in dedicated arms before
    that test: `&&`/`||`, the SIMD family, the `__native_*` map/fold decoders,
    dispatch sentinels and the `@[vectorize]` markers.
  - **`ADefRef` resolves.** By content hash when `def_hashes` is given, else by
    `did_name`. Nothing produces `ADefRef` yet.
  - **`ECallPtr` callees are callable.** The callee has a function, pointer,
    erased (`TVar`) or closure (`TCon`) type.
  - **No duplicate `fn_def` names**, from `tir-mono` on.
- **Installed**:
  - **CLI**: `--verify-tir` / `MARCH_VERIFY_TIR=1`. `Contract_pipeline.run`
    checks its input as `tir-lower`, then every pass at its `snap` and every
    inner `Opt` pass at `opt_snap`. A finding exits 3 (internal compiler error)
    with the findings. The flag is in the CAS key, so a verified compile is
    never satisfied by an unverified cached artifact.
  - **Always on in tests**: the TIR snapshot harness (`test_snapshots.ml`, every
    stage) and the four hand-rolled pipelines in `test_codegen.ml` (a `verified`
    wrapper per pass).
  - **Oracle**: `test_oracle` sets `MARCH_VERIFY_TIR=1` for every compile it
    runs. Exit 3 is already an `is_failure` ICE there.
  - **REPL/JIT**: `Repl_jit.lower_module` under the env var, with
    `?borrow_map:None`. It accepts functions earlier fragments compiled and REPL
    globals, and both call sites now run it inside `with_prior_fns`, as the
    emitter does. Only the emitter reads that table, so behaviour with the
    verifier off is unchanged.
- The plan's "add the missing snap before `tir-trmc`": `Trmc.transform_module`
  is already followed by `snap "tir-trmc"` (#782). What was un-snapped was the
  pipeline's input, now verified as `tir-lower` inside `run`. The driver's own
  `tir-lower` snap is a dump hook, so it is not called twice.

## Red

`test/test_codegen.ml` group `tir_verify` covers:
- a clean module, with no findings;
- an unbound variable, and a `let` binder leaking into a sibling branch;
- an unknown callee;
- `ECallPtr` through an `Int`;
- a duplicate name (post-mono only);
- a dangling `ADefRef`;
- `enforce` raising.

## Sweep: every finding classified

`--verify-tir --compile --opt 2` over `test/snapshots/src`, `bench/` and
`test/native` (434 programs). The codegen and JIT suites ran with
`MARCH_VERIFY_TIR=1`, so every program they compile was verified too. Each
finding was a verifier false positive, and each check was fixed:

| Finding | Why it is not a bug | Fix |
|---|---|---|
| `&&`, `||`, `simd_<t>_<op>`, `__native_*_inline`, `__vectorize_marker_*` | handled by a dedicated emitter arm before its known-callee test | mirror those arms |
| bare `from_json` in `JsonStream.typed_events` | a derive-Json interface method that `iface_methods` does not list. Mono resolves it when reachable: a compiled program calling `each_typed` on a derived record builds and runs | accept the derive-Json methods |
| `to_json` with no codec | an unresolved interface call is a USER error the emitter reports (the missing-JsonTo-impl diagnostic). The verifier preempted it with exit 3 | accept interface-method names at every stage |
| duplicate `head`/`unwrap`/`inspect` at `tir-lower` | a program fn shadowing a generic prelude fn. Mono keeps one: a user `head` returning 42 wins, interpreted and compiled | duplicates checked from `tir-mono` on |
| `Js.Dom.*` / `Js.Canvas.*` in native builds | JS-only modules, referenced in never-reached code on purpose (`test/native/js_dom_available.march`). A reachable call still fails at emission | accept the `Js.` namespace |
| REPL `OptMod.mk` (a `:load`ed module's fn) | compiled by an earlier fragment | verify inside `with_prior_fns` |

No real bug was found, so no todo was filed. The twelve programs that exit 1
in the sweep fail identically without the flag: FFI link libraries, a JS
target, or the HTTP harness.

## Next

Check 2 (type consistency), 3 (RC balance), 4 (repr) and 5 (pass contracts),
each its own PR. `borrow_map` and `k_table` are already parameters.
