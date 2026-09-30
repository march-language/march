# Compiled: destructuring a tuple and moving its fields on leaked them (fixed 2026-09-30)

**Reproduced on origin/main (b931328e5, and again on 771430bf3)** with the todo's program, both
`--compile` and `--compile --opt 2`: `delta: 20` (two objects per call, the two
moved strings). The constructor-pattern variant printed `delta: 0`.

## Root cause

Two halves of the pipeline disagreed about who owns a tuple pattern's fields.

- **Codegen** (`lib/tir/llvm_case.ml`, the `strip_scrut_decrc` arm): when the arm
  opens with `dec_rc <scrutinee>`, it emits `march_decrc_freed`; on the unique
  path each field's reference *moves* to its pattern binder, on the shared path
  each field is `march_incrc`'d. Either way the binders **own** their fields.
- **Perceus** (`lib/tir/perceus_core.ml`, ECase, `scrutinee_borrowed`): forced
  every TTuple/TRecord scrutinee "borrowed" unconditionally, on the premise that
  aggregates were `needs_rc = false` and Perceus never freed them. That premise
  died when `Kind.needs_rc_of` started treating aggregates as owning (see its
  comment); the stale clause stayed. Treating the fields as borrowed made every
  escaping pattern variable take a SECOND reference (`let c = inc_rc $f4; $f4`)
  that nothing released, and skipped the drop of a field the arm never used.

The constructor path never had the clause, which is why the variant leaked
nothing.

## Fix

Delete the unconditional aggregate disjunct from `scrutinee_borrowed`. A tuple
that is *not* consumed by the arm (live after the case, or still mentioned in
the arm body) is already borrowed through the two remaining disjuncts, so a
tuple that is an element of a borrowed list keeps borrowed fields; only the
consumed case changes, and that is the case where the `dec_rc` is emitted.

Side effect: a tuple of scalars (`(Int, Int)`) whose binders are typed `'_` no
longer gets `inc_rc` on each binder (and dead ones get a `dec_rc`); all of these
are no-ops on a tagged scalar at run time, so the emitted IR is smaller. Pinned
by the regenerated `test/snapshots/perceus/tuple_atom_string_arms.expected`.

## Verification

- `test/native/tuple_destructure_leak_probe.march` (dune rule, `--opt 2`):
  five legs, `live_allocs()` deltas printed as booleans plus each leg's result
  value: fields moved into a constructor (the reported shape), a dead field and
  an all-dead pattern, a tuple still live after the match (shared fields), a
  nested tuple pattern, and tuples that are elements of a list the function
  only borrows. RED on origin/main: four legs read `flat: false`; GREEN: all
  `flat: true` and the printed values are identical before and after (no
  use-after-free introduced). The todo's exact program: `delta: 20` -> `0`.
- `test/snapshots/src/tuple_destructure_moved_fields.march` (lower + perceus)
  pins the constructor-pattern control next to the tuple pattern.
- An `interp_tuple_destructure_leak_probe` rule diffs the interpreted run
  against the same `.expected` (the interpreter's `live_allocs()` never grows,
  so its `flat:` column is all true). That makes the printed leg values a
  compiled-vs-interpreted correctness golden as well as a leak guard.
- ASAN (Linux container, `march-amdr-repro`, ubuntu arm64; `MARCH_SANITIZE=1
  MARCH_DEBUG_RUNTIME=1`):
  - `specs/lang/golden/sanitize.sh`: golden 47/47 clean, native 32/32
    clean. two-node: 52 clean and 4 skipped (need root). The other 11 did not
    run at first because forge and `test/hcr_deploy.exe` were not built in the
    container. Rerun with both built and the gate's own
    `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`: all 11 clean. Total: 138
    clean, 0 failed, 4 skipped.
  - The todo's program, the leak probe, the new snapshot source, and every
    `test/native/*tuple*`/`*toml*` fixture showed no ASAN error (no
    use-after-free or double free). LeakSanitizer reports remain for 5 of
    them, and each is identical to or SMALLER than origin/main's, measured by
    swapping origin/main's `perceus_core.ml` into the same container:

    | program | origin/main | branch |
    |---|---|---|
    | todo program | 26 allocs leaked | 0 |
    | tuple_destructure_leak_probe | 516 | 0 |
    | toml_get_int | 48 | 36 |
    | tuple_atom_string_arms, let_tuple_nested, tuple_destructure_rc, tuple_show | 1 / 9 / 1 / 1 | same |

- `test/test_eval.ml` `perceus` "tuple param multi-destruct no RC underflow"
  FAILED on the first full run. It asserted `use_first` contains an `EIncRC`,
  and the new TIR snapshot `tuple_param_borrowed_destruct` shows what that
  increment was. In origin/main's post-Perceus `use_first` the arm opens with
  `dec_rc pair` (so codegen hands both fields over OWNED), then does
  `let x = inc_rc $f1` and never drops `$f2`. That is a second reference on
  the used field and no release of the dead one: the leak this change fixes.
  The branch drops `$f2` and moves `$f1`. The test now asserts that ownership
  shape (the arm consumes `pair`, the dead field is dropped once, the used
  field is not duplicated), and it FAILS on origin/main ("dead field is
  dropped exactly once", expected 1, received 0). Because the old test guarded
  an RC UNDERFLOW, the runtime side got its own leg in the leak probe: a
  borrowed tuple parameter destructured on every iteration (a field returned,
  one stored in a constructor, one passed to an owning call, a nested
  pattern), then the caller's tuples printed intact. ASAN-clean with leak
  detection on, at both `--compile` and `--opt 2`, in the Linux container.
- Benchmarks compiled `--opt 2`, 9 interleaved runs each, origin/main
  (771430bf3) vs branch, medians: `tree_transform` 0.761 s / 0.742 s,
  `list_ops` 0.089 s / 0.088 s, `binary_trees` 0.247 s / 0.247 s. The outputs
  are identical. Load average was 8-10, so compare the ratios.
