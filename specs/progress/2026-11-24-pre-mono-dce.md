# A reachability prune before mono (2026-11-25)

Lowering prepends the whole stdlib, and Mono seeded every monomorphic function, so Mono,
Fusion and Defun processed about 6,300 functions for a program that reaches a few dozen; the
early DCE after Defun then dropped them. `Dce_pre_mono.prune` (`lib/tir/dce_pre_mono.ml`) now
runs just before Mono in `Contract_pipeline.run` and keeps only what the roots reach. On hello
world Mono sees 66 functions instead of 6,340. Design:
`specs/2026-11-24-stdlib-compile-floor-design.md` Part 2 (Part 1 was the lemma-erasure walk,
`2026-11-24-lemma-erase-single-walk.md`).

**Edges.** From a reached function: every name its body mentions, bound or free (Mono's
`ensure_atom_fns` does not check shadowing, so a local named like a top-level function must
keep it), plus `Mono.implicit_callees` of each: the calls Mono mints by name that the TIR does
not spell. Those are every impl of an interface method (`Tir_names.find_iface_impls`, with the
`to_string`→`show` alias) and the prelude's `__ord_lt`/`__ord_le`/`__ord_gt`/`__ord_ge` behind
`<`, `<=`, `>`, `>=`. The audit of Mono, Fusion and Defun for other minted names is in the
design doc ("Implicit-callee audit"); Fusion and Defun mint only functions they create.

**Roots.** `Dce.root_names` (the roots the later DCE passes use), the pipeline's
`extra_roots`, remote-ref targets, `__rpc_stub`s, and `@[no_alloc]` functions.

**Tripwire.** The prune returns the set it removed, and every `fn_table` lookup in Mono goes
through a helper that raises if the name is in it: `internal error: Mono resolved <callee>
(from <caller>), which the pre-mono prune removed; rerun with --disable-pass dce-pre-mono and
report it`. A missed implicit edge is then a loud compile error, not a silent fallback (the
shape of issue #1172, where a missing `__ord_lt` left `<` to the emitter).

**Switch.** `--disable-pass dce-pre-mono`. Off under hot reload, the JS target and `--opt 0`.

## Tests

- `test/test_dce_pre_mono.ml` (suite `dce-pre-mono` in `run_codegen`), 14 cases on hand-built
  TIR: each edge kind, duplicate names, roots, fail open/closed, and the tripwire on an ord
  helper and on an interface impl.
- `test/native/pre_mono_prune_ord_show.march`: tuples, a record and an ADT under each ordering
  operator, generic `when Ord`/`when Show` callers, hand-written `Show` through `to_string`, a
  function used only as a value, a local named like a top-level function. Same output
  interpreted, compiled, and compiled with the pass off.
- Proven red on real compiles: with `implicit_callees` blinded to the ord helpers, a tuple `<`
  fails with `Mono resolved __ord_lt (from main)`; blinded to interface impls,
  `Mono resolved Show$String.show (from println)`.
- Full `scripts/run-tests.sh` and `test_jit` pass. `scripts/determinism-oracle.sh --corpus all`:
  deterministic across 1,016 programs.

## What moved in the emitted IR

`scripts/oracle-base.sh types`: identical (the new fixture is the only change).
`scripts/oracle-base.sh ir`: the raw text changes for most programs, because functions are
emitted in a different order and the emitter's fresh-name counter is module-wide.
`scripts/ir-canon-diff.sh` (new) sorts the definitions and masks those counters. Against the
merge base `97b33cb18`, 476 of 528 programs are then identical. The other 52 differ in three
ways, and nothing else:

1. **A constructor of a same-named stdlib type resolves to another of those types** (20
   programs: 18 through `HashMap`/`Map`/`Hamt`'s `HEntry`, plus
   `native_h_sigil_safe_collision` and `native_session_party_released`). The cell's collision
   tag and header type id change together at every construction and match. This is an existing
   ambiguity that the prune only re-rolls: see
   `specs/todos/2026-11-25-ctor-entry-suffix-fallback-hashtbl-order.md`.
2. **A dead prelude `tail` is no longer emitted** (8 programs). Before, a stdlib function the
   program never reached made Mono keep `tail`, and DCE then kept it because a lifted closure
   has a parameter named `tail`. Nothing called it.
3. **Two fn-table provenance rows name the right file** (22 programs):
   `rev$apply$N_IOList_to_string` was attributed to `stdlib/compress.march` and is now
   `stdlib/iolist.march`; `find$apply$N_Json_get` likewise moved off `stdlib/http.march`. The
   provenance table is keyed by function name, and the same-named function that used to
   overwrite the entry is now pruned.

All 52 were compiled and run with both compilers: 50 print the same output (one benchmark's
timings aside) and 2 need a peer and time out the same way under both.

## Measured

2026-11-25, arm64, load average about 3, `--compile --opt 2 --timings`, merge base
`97b33cb18` against this change, 10 alternating runs each, private HOME per compiler, a fresh
unreachable `pfn` appended per run so the source-level cache misses.

| program | stamp | merge base | this change |
|---|---|---|---|
| hello world | `cas-hash` | 1.383 s (1.368–1.409) | 1.116 s (1.103–1.124) |
| hello world | lower → defun | 0.252 s | 0.036 s |
| `bench/tree_transform.march` | `cas-hash` | 1.388 s (1.370–1.401) | 1.125 s (1.110–1.139) |
| `bench/tree_transform.march` | lower → defun | 0.251 s | 0.036 s |

So about 0.27 s, 19% of the front end and whole-program passes. The prune itself costs about
0.035 s of what remains between `lower` and `defun`: it walks every reached body, and building
the name table touches all 6,340 functions.
