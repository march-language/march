# FBIP reuse for record updates

**Status:** design, not landed (2026-09-03)
**Depends on:** `2026-09-03-aggregate-rc-deep-drop-design.md`. Cannot land before it — see "Why this is blocked".

## Problem

FBIP in-place reuse fires for single-constructor variants but never for record
updates. The same two-field shape, written both ways:

```
variant bump:  reuse b as Box.Box($t, m)      -- EReuse
record  bump:  { b with n = $t }              -- fresh cell + full field copy
```

Whole-program `EReuse` counts confirm it: the variant fixture adds exactly one
reuse site, the record fixture adds zero.

`Perceus_fbip` matches only `EAlloc` and `EAllocHole`. `EUpdate` falls into the
terminal catch-all in `fbip_expr` and is returned unchanged, reaching
`Llvm_emit_data.emit_update`, which unconditionally `emit_heap_alloc`s and
copies every field.

## Why this is blocked on aggregate RC

Three independent blockers, all removed by the aggregate-RC project. The third
is the one that makes ordering mandatory rather than merely convenient.

1. **No reuse source.** `Perceus_fbip` is built on one idea: an owned aggregate
   gets a `dec_rc`, and `try_fbip_sink` moves that dec down onto an allocation.
   Before aggregate RC there is no aggregate dec to sink.
2. **The marker cannot be minted.** `same_arity` accepts only the `$fbip$`
   encoding, produced solely by `add_scrutinee_free_for` in the `ECase` arm,
   which is guarded on `needs_rc v.v_ty` and on the type being `TCon`. A record
   update has no `ECase` at all.
3. **The safety guard is vacuous.** `emit_reuse_uniform` guards in-place
   mutation on a runtime `RC == 1` check. Without aggregate RC, record cells are
   allocated at 1 and never inc'd or dec'd, so the check is *always true*. An
   FBIP path built on it would mutate genuinely shared records in place:
   ```march
   let a = { n: 1, m: 2 }
   let b = { a with n: 5 }
   print(a.n)      -- must print 1; in-place reuse under a vacuous guard prints 5
   ```
   That is a wrong-answer miscompile, not a missed optimisation.

## Status update 2026-09-04 (after the aggregate-RC work landed)

Of the three blockers above, one is gone and two changed shape. Re-read this
before starting; the original blocker list is now partly stale.

**Blocker 3 (vacuous guard) — RESOLVED.** Aggregates now carry real refcounts
(`Rc_types.needs_rc` is true for `TTuple`/`TRecord`), so
`emit_reuse_uniform`'s `RC == 1` check means something. The shared-record
miscompile described above is no longer the hazard it was.

**Blocker 2 (no marker) — still true, still fine.** Unchanged: records need no
arity check, so `same_arity`/`$fbip$` stay out of it.

**Blocker 1 (no reuse source) — still true, and now for TWO reasons.**

1. *The guard would read an inflated refcount.* Every `EField` projection puts
   an `inc_rc` on its aggregate source, so on the canonical shape the base is at
   RC 2 exactly when the update runs:

   ```
   let c = let $t30230 = (inc_rc a; a.n) + 1 in
           { a with n = $t30230 }        -- a's RC is 2 here
   ```

   A reuse guard reads 2, takes the fresh-allocation branch, and reuse silently
   never fires. So this is not only a leak (2001 live objects over 1000
   iterations) — it would make record reuse a NO-OP even once implemented.
   Removing that inc is blocked on
   `specs/repros/2026-09-04-niche-record-payload-double-release.md`, which is
   therefore on the critical path for reuse being effective, not merely for the
   leak.

2. *The aggregate's drop is in the wrong POSITION.* `Perceus_fbip` matches
   `dec` THEN `alloc` (`fbip_expr`'s `ELet(_, EDecRC, ELet(result, EAlloc ..))`
   and `try_fbip_sink`'s `ESeq(EDecRC, body)`). The scope-end drop added by the
   aggregate-RC work emits the opposite order — the dec lands after the whole
   scope:

   ```
   let a = { n = 1, s = "x" } in
   let c = { a with n = 5 } in
   ... dec_rc a          -- far below the update; nothing to sink
   ```

   This was a deliberate, conservative choice (see the comment on the scope-end
   drop in `perceus_core.ml`): dropping at LAST USE instead would require
   proving no borrowed field outlives the projection. Reuse needs exactly that
   last-use placement, so this project must either do that proof or give the
   update site its own reuse-source rule rather than relying on `try_fbip_sink`.

Net: the aggregate-RC work made reuse SAFE to attempt but not yet POSSIBLE. Both
remaining items are about the base's refcount — its value at the update site,
and where its release is emitted.

## What already exists

Codegen is largely done. `Llvm_emit_alloc.emit_reuse_uniform` already handles
`EReuse (atom, TRecord fields, args)`: the `RC == 1` guard, in-place field
writes in natural record slot representation, a fresh-allocation fallback that
decs the original, phi merge, and shape-id stamping on the result so record
introspection still works. It also carries the niche-shaped-source guard.

## Design

**Reuse source.** In `Perceus_fbip`, treat an `EUpdate (AVar base, updates)` as
a reuse target when `base`'s owning `dec_rc` is available to sink onto it, the
same shape `try_fbip_sink` already recognises for `EAlloc`. Records need no
arity check: `EUpdate`'s result has the base's field list by construction, so
sizes match by typing. `same_arity` and the `$fbip$` marker are therefore not
extended to records — the size question they answer does not arise.

**Reuse target — two candidate lowerings.** Decide during implementation, with
a measurement:

- *(a) Rewrite to `EReuse`.* Bind each unchanged field with `EField`, then emit
  `EReuse (AVar base, TRecord all_fields, sorted_atoms)`. No new TIR shape and
  no new codegen — `emit_reuse_uniform` handles it today. Costs a load/store per
  unchanged field; in the reuse branch these are self-copies (load slot *i*,
  store slot *i*) that LLVM should eliminate, which is the thing to verify.
- *(b) Reuse token on `EUpdate`.* Add an `atom option` token, as `EAllocHole`
  already does, and give `emit_update` an `RC == 1` branch writing only the
  changed fields. Strictly less work at runtime; costs a variant-shape change
  rippling through roughly ten match sites.

Start with (a). It is smaller, reuses reviewed machinery, and if LLVM does
eliminate the self-copies the runtime difference disappears. Fall back to (b)
only on evidence from the emitted IR.

**Ownership of overwritten fields — the one genuinely new problem.** Variant
FBIP gets this free: a match arm's `br_vars` take ownership of the children, so
the reused cell's old field values already have owners. `{ b with n: … }` never
destructures `b`, so nothing releases the old value of an overwritten field. The
reuse branch must `dec_rc` the previous contents of each updated slot, and only
in the reuse branch — the fresh branch already decs the whole base cell, whose
deep drop (from the aggregate-RC project) releases those fields.

This asymmetry between the two branches is the correctness core of this project
and needs a witness fixture with a heap-valued updated field, checked under ASAN
in both the unique and shared cases.

## Non-goals

- Cross-shape reuse (reusing a dead record cell for a different record type).
  `EReuse`'s full-overwrite invariant would need the arity machinery back.
- Reuse for the dynamic-shape `march_record_update_dyn` path.
- Tuples. `ETuple` has no update form; a separate question.

## Verification

- The `EReuse` count **must** move here, in the opposite direction from the
  aggregate-RC project's gate: assert the record fixture gains reuse sites and
  name the expected count.
- Correctness witnesses: shared-record (`{ a with n: 5 }` then read `a.n`);
  heap-valued overwritten field, unique and shared; self-referential update
  (`{ b with f: b.f }`), which `args_alias_reuse` guards for `EAlloc` and which
  needs its analogue here.
- TIR snapshots regenerated deliberately; `git diff test/snapshots/` is the
  review artifact.
- ASAN corpus sweep in Docker. Leak fixtures from the aggregate-RC project must
  stay flat.
- `bench/tree_transform.march` is the Perceus/FBIP benchmark; add a
  record-update benchmark, since no existing benchmark exercises this path.

## Risks

1. **Overwritten-field leak or double-free.** The branch asymmetry above. The
   single highest risk in this project.
2. **Shared-record mutation.** Depends entirely on aggregate RC making the
   `RC == 1` guard meaningful. Assert the shared witness explicitly rather than
   trusting the guard.
3. **Self-referential update.** `args_alias_reuse` exists because
   `Some(result) -> Ok(result)` reusing the scrutinee stored a cell's address
   into its own field. `{ b with f: g(b.f) }` is the analogous shape.
4. **Actor state records.** Actor structs are records; `emit_reuse_ctor` already
   has a dedicated actor-struct path that deliberately skips the RC check.
   Reuse reaching actor structs by this new route must be checked, not assumed.

## Landing obligations

Per `CLAUDE.md`: `specs/progress/` entry, `CHANGELOG.md` bullet under
`### Added`, and a benchmark result recorded against `specs/benchmarks.md`.
