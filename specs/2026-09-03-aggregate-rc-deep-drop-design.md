# Aggregate RC: deep-drop records and tuples

**Status:** design, not landed (2026-09-03)
**Depends on:** nothing. **Unblocks:** `2026-09-03-record-fbip-reuse-design.md`.

## Problem

Record and tuple cells are allocated and never freed. So are the heap values
they own. This is unconditional and unbounded: it is not a corner case, it is
every aggregate the program ever builds.

Measured on a 200,000-iteration loop that rebuilds a `{ n : Int, s : String }`
each turn, against the identical program written with a two-field variant:

| 200k iterations            | string allocs | string frees | leaked                  | peak RSS |
|----------------------------|---------------|--------------|-------------------------|----------|
| record `{ n, s }`          | 400,003       | 200,001      | ~200k strings + 200k boxes | 15.2 MB |
| variant `Box(n, s)`        | 400,003       | 400,001      | none                    | 2.4 MB  |

An all-scalar aggregate leaks its box alone (~32 B/iteration: 20M iterations of
a `{ n : Int, m : Int }` loop peaks at 645 MB against the variant control's
2.3 MB). Tuples leak identically to records — same root cause, same numbers.

Note when reproducing: `string_concat` of two string *literals* is
constant-folded, so a fixture built from literals allocates nothing per
iteration and will show only the box leaking. The string argument must depend
on the loop variable.

## Root cause

`Rc_types.needs_rc` is `false` for `TTuple` and `TRecord`
(`lib/tir/rc_types.ml`), so Perceus emits no RC ops on the aggregate cell and
never decides it is dead. `Drop.droppable_ctors` matches only `TCon`, so the
deep-drop pass declines them too — `lib/tir/drop.ml` says so in as many words:
*"Their drop story is a separate question, untouched here."*

`drop.ml` (`bb069c88`, 2026-07) closed exactly this leak for variants. Records
and tuples were deferred and never filed.

## What is already correct (and therefore out of scope)

The change is much narrower than "give aggregates an ownership model", because
the ownership model is already there and already right. Only the death event is
missing.

1. **The aggregate owns its fields.** Construction transfers ownership in, with
   no dec on the field:
   ```
   let $t30218 : String = string_concat("v", int_to_string(i)) in
   { n = $t30217, s = $t30218 }        -- no dec_rc $t30218
   ```
2. **`EField` borrows.** `insert_rc_expr`'s `ELet` case marks a field extracted
   from an in-scope aggregate as `borrowed_field_vars` (condition 4,
   `lib/tir/perceus_core.ml`), so the owner stays responsible for its RC.
3. **An escaping field is dup'd.** When a borrowed field leaves the function,
   Perceus emits the `inc_rc`, leaving the aggregate's own reference intact:
   ```
   let $rc_614 : String = b.s in
   inc_rc $rc_614;
   $rc_614
   ```
4. **Tuples and records share one extraction path.** Tuple destructuring lowers
   to `EField` with `$fv0`/`$fv1` names, not to an `ECase`. One mechanism, one
   reconciliation point, one fix.

Points 1 and 3 are precisely the precondition a deep drop needs: every field the
aggregate still holds at its death is a reference the aggregate owns and nobody
else will release. No change to `EField` handling is required or wanted.

## Design

Two changes.

**1. `lib/tir/rc_types.ml` — `needs_rc (TTuple _ | TRecord _)` becomes `true`.**
`borrow_eligible` is unchanged (stays `true`; the `0b52510d` record-liveness fix
depends on it). Aggregates then flow through the RC paths that already exist:
last-use `EDecRC`, `find_inc_vars` on the `ERecord`/`ETuple`/`EUpdate`/`EAlloc`
arms, and the `ECase` cross-branch dead-variable dec.

**2. `lib/tir/drop.ml` — synthesize deep drops for aggregate shapes.**
`droppable_ctors` currently returns `None` for every non-`TCon`. Extend it so a
record is a single implicit constructor over its fields (sorted by name, which
is `TRecord`'s own invariant and the layout order `emit_record` uses) and a
tuple likewise over its element types. The synthesized `__drop$R…` projects
fields with `EField` instead of destructuring with an `ECase`, then decs the
cell.

The truth-table docs in `lib/tir/rc_types.ml` and `specs/perceus-invariants.md`
must be updated in the same commit; both currently assert the old behaviour as
deliberate, with bug history attached, and a future reader who trusts them will
undo this.

### Why the documented double-free warning does not apply

`rc_types.ml` warns that flipping `needs_rc` for aggregates causes
"double-frees on tuple/record fields", citing `390dff00` (the Toml `get_str`
pair-list corruption). That warning is about the **read** path: fields extracted
from a live aggregate must not be independently freed. `borrowed_field_vars`
handles that and is untouched here. The **death** path is disjoint and simply
absent. The two are orthogonal; this must be written into the doc, because the
existing text reads as prohibiting the whole change.

## Non-goals

- Removing or reworking `borrowed_field_vars`. The borrow path is correct.
- Stack-promoting aggregates. `escape.ml` only promotes `EAlloc`, never
  `ERecord`/`ETuple`. A real opportunity, separate project.
- Any FBIP or reuse behaviour. See the reuse-neutrality gate below.

## Verification

**Leak signal.** RSS is load-dependent and a poor regression detector. The
runtime already maintains an exact live-object count
(`march_live_alloc_count`, bumped on alloc and free, exported as
`march_live_allocs()`, `runtime/march_runtime.c`) but never prints it. Add one
line to `str_stats_dump` emitting `live_objs`. Fixtures then run at two sizes
(N=1,000 and N=100,000) and assert `live_objs` is identical and small; a leak
scales with N and nothing else does.

Editing `runtime/*.c` requires a build that restages `_build/default/runtime`;
a targeted `dune build bin/main.exe` does not, and the edit is then silently
absent from the build.

**Fixtures.** Each at both N: record with scalar fields; record with a `String`
field; tuple; record update; variant holding a record field; aliasing witness
(`let b = a`, both used); shared-record correctness witness
(`{ a with n: 5 }` then read `a.n`, must print the original).

**Gates.**

| check | expected | role |
|---|---|---|
| whole-program `EReuse` count | **unchanged** | hard gate: proves reuse-neutrality |
| `scripts/types-oracle.sh` | green | no typing change |
| `scripts/refine-oracle.sh` | green | no refinement change |
| `scripts/ir-oracle.sh` | **red by design** | not a gate; the enumeration of added decs, to be read |
| `test/snapshots/perceus/*` | changed | regenerate deliberately; the diff is the review artifact |
| ASAN corpus sweep | clean | primary instrument for the real risk |

`EReuse` must not move: `Perceus_fbip.same_arity` accepts only the `$fbip$`
marker, minted solely by `add_scrutinee_free_for` for `TCon` scrutinees. New
aggregate decs are therefore invisible to reuse. If the count changes,
something is wrong.

Run oracles under a private `HOME` (`~/.cache/march` is shared across worktrees
and its cached spans carry the populating worktree's absolute paths).

**Suites.** `scripts/run-tests.sh` full, plus what it does not cover:
`test_refinecheck.exe` directly (z3 on `PATH`, or ~588 cases skip while alcotest
still exits 0), the LSP suites from the repo root, and the CI-only dune rules
`@types-check` / `@grammar-check` with `--force`, asserting on log contents
rather than exit code.

ASAN must run in Docker; `sanitize.sh` passing on this Mac runs zero programs.

**Benchmarks.** `tree_transform`, `list_ops`, `binary_trees`, compiled at
`--opt 2`, same-box A/B against a compiler built at the base commit. Expect a
small cost from added RC ops and a large win in aggregate-heavy code.

## Risks

1. **Double-free on fields — the `390dff00` class.** The aggregate's deep drop
   firing on a field some other owner also releases. Mitigated by points 2 and 3
   above being left alone; ASAN and the Toml pair-list tests are the instruments.
2. **Premature free while a field is borrowed — the `0b52510d` class.** A
   `cfg:borrowed` record param whose extracted `String` outlives the aggregate's
   dec. Needs the multi-call-in-one-loop-arm witness, not just the simple case.
3. **Aliasing.** Two variables, one box. Ordinary Perceus inc/dec covers it, but
   aggregates have never travelled that path; explicit witness rather than trust.
4. **Actor state.** Actor structs are records (field 0 named `$d_dispatch`) and
   will now receive decs they never got. `Repr.is_actor_struct_type` guards the
   FBIP path; whether the dec path needs the same guard is open.
5. **Closure capture.** Aggregates captured as closure FVs stay owned by the
   closure struct; aggregate decs must not double-fire on them.
6. **Recursive aggregate shapes.** A record whose field type reaches the record
   again would make `drop_fn_for` recurse; it memoises by mangled type and
   registers the name before building the body, which handles the variant case,
   but the aggregate path must be checked against the same hazard.

## Landing obligations

Per `CLAUDE.md`: a dated entry in `specs/progress/`, a `CHANGELOG.md` bullet
under `[Unreleased] / ### Fixed`, and the two truth-table docs updated in the
same commit. File the tuple/record stack-promotion opportunity as a new
`specs/todos/` item.
