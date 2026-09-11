# A closure environment was freed shallowly: every capture leaked

**Landed:** 2026-09-06, on top of `7eb8d76a`. Reported by the `cube_forge`
project as its GAPS **G80**, from the investigation "The relight box, and where
the frame's memory goes" (2026-09-05).

## Symptom

`dec_rc` on a defunctionalized closure released the environment cell and never
touched what the lambda captured. `march_decrc_local` is `free(p)` with no
child decrements, and `Drop.run` only routed a bare `EDecRC` through a
synthesized deep drop for *variant* types (`Repr.find_variant`), which a
`$Clo_...` struct never matched.

`cube_forge`'s `probes/drop_xmod`, maximum resident set size, same box:

| repro | before | after |
|---|---|---|
| `WHICH=5` — 1,000 closures each capturing a 1 MB array, called once, dropped | 1,073 MB | **9.5 MB** |

## The fix

`lib/tir/drop.ml`, `rewrite_apply_clo_drop`. A capturing apply function has
already loaded every capture it uses into a local, so it needs no layout
knowledge — only an answer to "did MY release of the environment free it?".
The `dec_rc $clo` Perceus splices in (`Perceus.insert_apply_fn_clo_drop`) is
rewritten to `let $freed = march_decrc_local_freed($clo)` — same reference, at
the same instant, only now remembered — and every tail is prefixed with

```
case $freed of True -> drop c1 ; drop c2 | _ -> ()
```

over those locals. Nothing about the closure layout, the object header, or the
existing release timing changes. Neither of the two designs the gap report
sketched (a drop-function pointer stored in the environment, a runtime release
reading capture kinds out of the header tag) is needed: an apply function
corresponds to exactly one `$Clo_...` definition.

**The ownership gate is load-bearing, not an optimisation.**
`Borrow.closure_escapes` states the rule it enforces: a closure that is only
ever the callee of an `ECallPtr` — a join point, an immediately-applied lambda
— does not transfer ownership of its captures, so the enclosing scope still
owns and still releases them, and releasing them again when the environment
dies is a double free. `owning_apply_fns` therefore admits a closure type only
when EVERY allocation site in the module is an `ELet`-bound `EAlloc` whose
closure escapes that binding; a stack allocation, an unrecognised shape, or no
allocation site at all all disqualify it. It reuses `Borrow.closure_escapes`
verbatim rather than re-deriving the verdict, so this pass and the borrow
fixpoint cannot drift on the one question that decides reclaim-versus-double-
free. Measured, `test/native/node_discovery.march`, 150 interleaved runs
against a same-box build of `7eb8d76a`:

| exit | main | ungated | gated |
|---|---|---|---|
| clean | 110 | 98 | 109 |
| SIGTRAP (`mfm_free`, a double free) | 12 | **25** | 13 |
| SIGBUS | 28 | 27 | 28 |

**`march_decrc_local_freed` is new** (`runtime/march_runtime.c`), because the
site being rewritten emitted `march_decrc_local` and the existing
`march_decrc_freed` differs from it in ATOMICITY POLICY, not just in the return
value: the former takes a non-atomic fast path off the scheduler, the latter is
unconditionally atomic. Splitting one object's decrements between the two loses
updates in both directions. The new helper mirrors `march_decrc_local`'s branch
structure exactly and returns 0 for a non-heap pointer — the opposite of
`march_decrc_freed`, deliberately, so a stack-promoted or tagged-scalar value
makes a caller skip its child releases.

## A measurement trap that cost most of this work

The first version of this was reported as unmergeable on the strength of
"SIGBUS 17 of 60 on the branch against 0 of 60 on main". That comparison was
**wrong**: the baseline binary had been compiled against the runtime as it
stood *before* `march_decrc_local_freed` was added, so it was an A/B of two
binary layouts, not of two compilers. The control that settles it is the
baseline compiler against the *current* runtime, where the only difference is a
dead, uncalled function — it crashes at the same rate (11 of 40). With both
sides on one runtime, SIGBUS is 28 against 28.

`node_discovery` carries at least two pre-existing memory bugs on main — a
malloc-freelist corruption in `Msgpack.encode_val` (SIGTRAP under
`march_decrc`, ~8% of runs) and this stack overflow in
`Msgpack.list_append` (~19% of runs, unaffected by a 16x larger
`MARCH_STACK_MAX`, so a cyclic list, very likely the same corruption) — and one
run hung for over an hour. **Rebuild both sides of any A/B against the same
runtime, interleave the runs, and compare per-signal counts, not pass counts.**

## What this does not fix

- **A bare `EDecRC` on a closure value at an outer site** — one dropped without
  ever being applied, or extracted from a data structure. Its type there is a
  function type, which names no layout, and the environment is not in hand to
  read captures out of.
- **Every closure the gate declines**, which is most of them: 2,001 of 5,305
  closure types qualified in the probe. `cube_forge`'s own live-object gauge is
  unchanged at 86 objects a frame.
- **`Array.set`, and so `WHICH=4`** (339 MB, unmoved). See
  `specs/todos/2026-09-06-closure-capture-release-widening.md`.

## Verification

- `dune build`, `scripts/run-tests.sh`: 706 tests, all suites passed.
  `@types-check --force` and `@grammar-check --force` clean. TIR snapshot
  goldens unchanged.
- `test/test_codegen.ml`'s byte-identical LLVM preamble golden updated for the
  new runtime declaration (the far-away test that a new runtime symbol always
  breaks).
- `cube_forge` on the built toolchain: `forge test` 467 tests / 0 failures;
  `scratch/frame_budget.sh` worst frame 6.04 ms against a 16 ms budget, drained
  mesh hash equal to the full-rebuild hash (413448066).
