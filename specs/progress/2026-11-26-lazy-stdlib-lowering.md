# Stdlib function bodies are lowered on demand (2026-11-26)

Hello world's compile lowered all ~4,200 stdlib module functions to TIR, and
`Dce_pre_mono.prune` (`2026-11-24-pre-mono-dce.md`) then kept about a hundred. Now the
native compile lowers only the stdlib bodies the prune can reach. The emitted program is
byte-identical to eager lowering's; the two prerequisites that made that possible are
`2026-11-26-local-fn-provenance.md` and `2026-11-26-function-local-fresh-counters.md`.

## Design

`Lower.lower_module ?lazy_bodies` (opt-in; only `bin/main.ml` passes it). Everything that is
not a stdlib **module** function body is lowered eagerly exactly as before: types, ctor
tables, impl methods (76 small bodies, messy Pass 1 state), actors, module lets, the
prelude's top-level fns, the entry file, every `MARCH_LIB_PATH` file, synthesised fns.

For a fn of a stdlib-span module (`lower_mod_decls`, `DFn` arm), Pass 2 puts a **stub** in
`!fns` at the position its body would take (the import/alias handlers scan `!fns` by name):
the real name and parameters, return type `Unit`, body `$march_unlowered()`
(`Tir_names.unlowered_marker`; nothing has that name). The stub carries a closure that
lowers the body later exactly as the eager arm does (`lower_fn_def`, `rename_scoped_vars`,
`Provenance.rename`). Bookkeeping that needs only the name (`note_fn_needs`,
`note_fn_grant`, `Hot_reload.note_work_entry`) still runs at the stub.

After Pass 2 a demand loop lowers bodies from a worklist: `Dce_pre_mono.walk`, the prune's
own worklist and edge rule (every name a body mentions or has free, plus
`Mono.implicit_callees`), factored out of `prune` so the two cannot drift. Its `defs`
callback lowers every stub of a name when the name is first reached (duplicates: all).
Roots: `Dce.root_names` on the stubbed module, every eagerly lowered fn written outside the
stdlib (user code: also covers analyses before the prune that look at unreached user fns,
and the driver's mainless roots), stdlib fns lowered eagerly as roots (below), the module's
top-level let initialisers (folded into fns later), `Authority.launch_init`, the remote-ref
targets of every eager body (the prune pins those of any body, reached or not) and of every
lowered one, and `lz_extra_roots ()`: the names passes between lowering and the prune may
add calls to. Unforced stubs stay in `tm_fns`; the prune removes them.

## Hazards and how each is handled

1. **Alias tables grow during Pass 2.** `_use_aliases`, `_module_aliases` and each module's
   `current_module_aliases` are written through `Lower_state.set_use_alias`,
   `set_module_alias`, `set_module_import`, which (only while lazy lowering is on) log each
   write with a clock value. A stub records the clock at its declaration; when its body is
   lowered, `alias_view` is set to it and `resolve_use_alias` reads every table as it stood
   then (`find_global_as_of`, `find_module_import`). Off, a write is a `Hashtbl.replace` and
   a read a `find_opt`. Fixture: `test/native/lazy_lower_shadow/` (the entry imports a
   library module whose `reverse` does not reverse; `Result.collect` calls the prelude's
   `reverse` bare). Without the view it printed `collected: 3, 2, 1`.
2. **Dynamic scopes.** `_current_module_fns`, `_enclosing_module_fns`, `_builtin_shadows`
   (also read by `rename_tir_vars`) are captured at the stub and reinstated around the
   late lowering (`Fun.protect`). Unit test "enclosing-module scope reinstated".
3. **Passes after lowering that mint calls by name.** `Auth_rt.minted_callees` lists what
   `restricts`/`frames`/`grants`/`captures` can add given their tables
   (`Authority.enter_fn`, `frame_layer`, `restrict_layer`, `enter_grant`, `grant_layer`,
   `foreign_guard`); the driver passes it as `lz_extra_roots`. `Auth_native` and
   `Vectorize_mark` add only builtins. `Net_scope.rewrite`, `Mock_dispatch.rewrite` and
   `Auth_rt.grants` also analyse whole modules before the prune, so lazy lowering is simply
   off when net scopes are declared, in a test/mocking build, or with a grants file.
   Fixture: `test/native/lazy_lower_fn_needs.march`; `bench/cap_capture_closures.march`.
4. **Roots visible only by name or signature** are lowered eagerly and seeded: a stdlib fn
   named `main`, a migrate fn, `*_migrate_msg`, `*__rpc_stub`, a fn with a `needs` clause,
   an alloc-contract fn (`Alloc_contract.collect`), a fn with a policy-tagged parameter
   (`Policy_dce.policies_of_fn` on the stub, whose parameters come from
   `Lower_decls.fn_params`, the parameter half of `lower_fn_def` factored out, no body), and
   a fn whose AST contains `restrict`, `mock` or `remote_ref_hashes` (whole-program facts:
   `restrict_sites`, `mock_sites`, pinned remote-ref targets). Also eager: a qualified name
   declared twice (its provenance key must end with the last declaration's).
5. **No roots.** If `Dce.root_names ~fail_open:false` finds nothing, every stub is lowered,
   in declaration order. Fixture `test/native/lazy_lower_rootless/entry.march` (in its own
   directory: its IR is the whole stdlib, ~60 MB, which the sweeps over
   `test/native/*.march` need not pay for); unit test "no root: every body lowered".
6. **A stdlib module loaded from disk mid-body** (`_ensure_module_lowered`) appends its fns
   where that body is lowered. `Lower_state.lazy_module_load_hook` refuses (fails loudly,
   naming the module and the switch) a load from a late-lowered body, and a load from an
   eager body when a body deferred before it names the module (eager lowering would have
   loaded it there). `test/native/lazy_niche.march` loads `LazyNicheProbe` from `main`;
   a first cut that refused every load under lazy lowering broke it (the gate caught it).
7. **Impl methods** are not deferred.

Also checked after the loop: lowering the bodies added no top-level fns, types or restrict
layers (fails loudly otherwise).

**Tripwire.** `Dce_pre_mono.prune` raises when its walk reaches a stub: `internal error: the
pre-mono prune reached <fn>, a standard-library function whose body lazy lowering did not
lower; rerun with --disable-pass lazy-lower and report it`. An unreached stub lands in the
removed set, so Mono's `pruned_lookup` tripwire covers names Mono mints.

**Off switch / where it is off.** `--disable-pass lazy-lower` (`Pass_switch.known`, so
`--list-passes` documents it; in the CAS key like every pass switch). Off wherever the
prune is off (`--opt 0`, hot reload, JS, `--disable-pass dce-pre-mono`), and for
`--compile-so`, every wasm target, `--test`, `--report-contracts`, `--dump-phases`,
`MARCH_DUMP_TXT`, `march query`, `--verify-tir`/`MARCH_VERIFY_TIR`, `MARCH_TRMC_REPORT`,
`MARCH_ALIAS_AUDIT`, and the three ocap cases in hazard 3. Every other caller of
`lower_module` (REPL/JIT, LSP, `Cap_static`, `Contract_pipeline.check_contracts`,
`js_pipeline`, `lower_more`, the tests) lowers eagerly because it does not pass the option.

## Proof

**Identity gate** `scripts/lazy-lower-gate.sh` (CI job `lazy-lower-gate`): every IR-oracle
corpus program plus the `test/native/*/entry.march` fixtures, `--emit-llvm` with and without
`--disable-pass lazy-lower`, same compiler and HOME; `.ll` byte-identical and the same
compile outcome. Run 2026-11-26 on this commit's compiler: 567 programs, **537 identical, 0
different**, 30 skipped (they fail to compile both ways, as in the IR oracle), lazy lowering
engaged on 534 (the other 3 have no entry point, so every body is lowered). `--self-test`
(eager side also `--disable-pass opt`) reports RED.

Red proofs (each a deliberately broken compiler):

| perturbation | gate | unit test |
|---|---|---|
| no alias view (bodies read the live tables) | RED: `lazy_lower_shadow_entry` differs (`$Clo_go$0_reverse` vs a string constant); the only corpus program that sees it, which is why the fixture exists | "aliases as of the declaration" fails |
| `lz_extra_roots` ignored | RED: `native_lazy_lower_fn_needs` and `bench_cap_capture_closures` fail with the tripwire on `Authority.enter_fn` | |
| no fail-open forcing | RED: `lazy_lower_rootless` fails with the tripwire (`Actor.Theory.bounded_enq`) | "no root: every body lowered" fails |
| scopes not reinstated | not run over the corpus (the run died when the disk filled) | "enclosing-module scope reinstated" fails |

`test/test_lazy_lower.ml` (suite `lazy-lower` in `run_codegen`, 9 cases): the shared walk,
the prune refusing a reached stub (also one with code in front of it), an unreached stub
in the removed set, and five in-process lowerings of a program with a pretend stdlib (files
registered in `stdlib_source_files`) comparing each lazily lowered body with eager
lowering's text.

## Runs

2026-11-26, arm64 macOS, load average 5 to 35 from other sessions. The disk filled twice
during the session (another process; free space fell under 200 MB), which killed a first
round of suites with `No space left on device`; everything below was rerun after space came
back.

- Suites, all passing: `run_codegen` 841 (the 9 new included), `eval` 309, `stdlib` 924
  (on the first run `https server (compiled, end-to-end)` case 7 failed with `plain
  listener on port 63057 failed: Address already in use`, a port another process held;
  the group rerun alone passed, 17/17), `stdlib_march` 88, `test_jit` 65, `errors` 490,
  `test_reports` 24, `run_snapshots` 70, and the LSP suites: `lsp` 422, `utf16` 5,
  `jsonrpc` 37, `incremental` 10, `query_cli` 9.
- `run_compiler` (1,779 cases) run one process per group, six at a time, because one
  process would have outlasted run-tests.sh's 40-minute suite limit at that load: every
  group passes.
- `scripts/oracle-base.sh ir types --base dec976ea7` (this branch before the change): ir,
  532 programs emit and 30 skip on both sides, all 532 byte-identical, the only manifest
  line added is the new `native_lazy_lower_fn_needs`; types, the core-AST and diagnostic
  channels identical, the new fixture again the only added line (both oracles report it as a
  change, so the script exits 1).
- `scripts/determinism-oracle.sh --corpus small`: deterministic across 32 programs and four
  conditions (`src_auth_capture` skips, as before).

**Timing.** `--compile --opt 2 --timings`, this change against `dec976ea7`, 8 alternating
runs each (hello world's first, cold-cache pair dropped), one private HOME and scratch cwd
per compiler, a fresh unreachable `pfn probe_N` per run so the source cache misses, load
average 5 to 8:

| program | stamp | `dec976ea7` | this change |
|---|---|---|---|
| hello world | lower stage (typecheck to lower) | 0.256 s (0.250-0.266) | 0.140 s (0.136-0.146) |
| hello world | `cas-hash` | 1.655 s (1.605-1.709) | 1.498 s (1.475-1.544) |
| `bench/tree_transform.march` | lower stage | 0.251 s (0.247-0.263) | 0.136 s (0.133-0.206) |
| `bench/tree_transform.march` | `cas-hash` | 1.651 s (1.597-1.795) | 1.524 s (1.458-2.441) |

So about 0.12 s less lowering and 0.13 to 0.16 s less to `cas-hash` (the prune also has
fewer bodies to walk). What remains of the lower stage (0.14 s) was not profiled: the
eager parts (prelude, impl methods, user code), the stub checks (an AST walk and the
parameter types of every deferred fn) and the post-lowering passes before the `lower`
stamp.

## Found by CI after review

- **A name minted after lowering by a pass merged from main.** `Auth_rt.frames` (scoped
  tail calls, #1338) calls `Authority.frame_in_force`; `Auth_rt.minted_callees` now lists it.
  The tripwire named it on `test/snapshots/src/auth_tail_hop.march` and
  `test/cap_conformance/frame_mutual_tail.march`. The gate now also covers
  `test/cap_conformance` (62 programs compile, 30 are rejected both ways).
- **The walk's roots were not the prune's roots.** The prune pins every RPC stub and every
  policy-tagged fn wherever it lives; the walk pinned them only among stdlib stubs and relied
  on user code being seeded for the rest. Under `--stdlib-source` the entry file is a
  stdlib-span file, so `demo/load_server.march`'s eagerly lowered `report_load__rpc_stub` was
  neither, and the tripwire fired on `ClusterLoad.local`. The rule is now one function,
  `Dce_pre_mono.is_pinned`, used by the prune and by the walk for stubs and eagerly lowered
  fns alike. `LAZY_GATE_FLAGS` passes extra flags to both sides of the gate, and CI runs it
  over `demo/*.march` with `--stdlib-source`, as `demo/dune` builds them: red on
  `load_server` before the fix, 8 identical after (1 rejected both ways).

## Not done

- The scopes-not-reinstated perturbation was not run over the whole corpus.
- `Net_scope`, `Mock_dispatch` and dependency grants keep lazy lowering off rather than
  declaring their minted names; a program using them compiles as before.
- A mainless program with fns of its own (the driver roots those) lowers every body, as a
  rootless one does, since lowering does not know the driver's mainless roots.
