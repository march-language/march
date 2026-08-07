# Drop-guided reuse: only match scrutinees are reuse candidates

**Filed:** 2026-08-07
**Priority:** P4 — measured, and the measurement says don't build it. Filed so
the gap is recorded rather than re-derived from the paper.

March's FBIP reuse only ever fires on the drop of a **match scrutinee**. Lorenzen
& Leijen's *Reference Counting with Frame Limited Reuse* (ICFP'22,
MSR-TR-2021-30) turns **every** drop into a reuse candidate. This file records
what that gap is actually worth, because the number is much smaller than reading
the paper suggests.

## Where we already match the paper

The paper's central move is to run reuse *after* RC insertion, rewriting
`drop` → `dropru`. We do exactly that — `perceus.ml`'s pass-ordering contract is

    Phase 0.5 scrut-escape -> Phase 2 insert_rc -> Phase 3 elide -> Phase 4 insert_fbip

and `Perceus_fbip.fbip_expr` rewrites an already-inserted `EDecRC` adjacent to an
`EAlloc` into `EReuse`. `EReuse` lowers to the conditional token (`icmp eq i64
%rc, 1` → reuse-in-place / fresh-alloc) in `llvm_emit.ml`.

So we are **not** the paper's algorithm K (§2.2: Koka's implementation skips
liveness analysis entirely) — `add_scrutinee_free_for` does check
`not (mem v live_after) && not (name_free_in v body)` before emitting the drop.
And we are not algorithm D (§2.2: Ullrich & de Moura push reuse into branches,
forcing a `dup` on the parameter and an arbitrary peak-heap increase) — we never
insert a reuse token ahead of a call.

## The actual gap

`EDecRC of atom` (`tir.ml`) carries no shape. Arity is smuggled through the
dropped var's **type name**: `add_scrutinee_free_for` rewrites `v.v_ty` to
`TCon("$fbip$List.Cons", [TUnit; TUnit])`, and `Perceus_fbip.same_arity` accepts
*only* that marker encoding. There are ~12 `decrc_for` sites in `perceus.ml`;
exactly one mints the marker.

The other 11 can't simply mint it. At an arm head the constructor is known
(`br_tag`, arity = `|br_vars|`). At a dead binding of type `Result(Int, String)`
you know only the type — `Ok` and `Err` may have different field counts. Guessing
from the type's *parameter* count is what produced the historical 8-byte heap
overflow that `same_arity`'s doc comment describes.

The runtime cannot arbitrate either: the header is
`{ int64_t rc; int32_t tag; int32_t pad; }` (`march_runtime.h`) — no size or
field count — and `march_decrc` just `free(p)`s without walking children.

## Measurement (2026-08-07)

Method: temporary instrumentation inside `Perceus_fbip`, mirroring
`try_fbip_sink`'s own traversal so the counts describe the real pass rather than
a regex over the pretty-printed dump. Reverted after measuring. Subject:
`bench/tree_transform.march` compiled with its full stdlib link closure.

**4,838 drop→alloc adjacencies**, by why reuse was refused:

| reason | count | addressable? |
|---|---:|---|
| `arity_mismatch` (marker present, sizes differ) | 1,433 | no — genuinely incompatible cells |
| `no_marker_other` (dropped value isn't a `TCon`: closures, strings, tuples) | 1,405 | no — not ADT cells |
| `nullary_alloc` (target ctor has 0 fields) | 638 | no — nothing to reuse into |
| `no_marker_tcon` | 633 | **yes** |
| `no_marker_tvar` (erased type) | 153 | yes, runtime check only |
| `REUSED` (fires today) | 576 | — |

The addressable set is 786, but it does not survive decomposition:

- **387** target `$Clo_$jp*/1` join-point closures — 1-field closure cells that
  are join-point plumbing, not user data. `Escape` (which runs *after* Perceus,
  so this is measured at `tir-escape`, not `tir-perceus`) stack-allocates 1,803
  of the 4,153 jp-closure allocations; the other 2,350 do stay on the heap, so
  these are not all free. But the pass that should be claiming them is `Escape`,
  not FBIP: stack-allocating a join-point closure beats reusing a dropped cell
  to build one.
- **372** target `Result.Err/1` / `Result.Ok/1` — `let?`-style error
  propagation. Cold by construction, and 1-field targets.
- **27** target real data constructors. This is the entire prize:

```
18  List.Cons/2
 5  HEntry.HBranch/2
 2  Names.Names/1
 1  PresenceState.PresenceState/1
 1  Option.Some/1
```

## Why we are not building it

The natural fix ("Route A") is to store the field count in the header's unused
`int32_t pad` at offset 12 — zero extra bytes, one extra store — and change the
`EReuse` guard from `rc == 1` to `rc == 1 && nfields == k`, dropping
`same_arity`'s marker requirement so every drop becomes a candidate.

That means touching every allocation site in `runtime/` and `llvm_emit.ml` and
re-validating repr agreement across Boxed / Newtype / Niche / actor-struct /
string / float-box / closure cells — the exact area that has repeatedly produced
compiled-only bugs (see `specs/progress/` for the Html/IOList tag collision, the
niche/newtype scrut double-free, the `string_to_float` SIGSEGV). Verification,
not implementation, is the bulk of the cost: 16 perceus TIR goldens churn, plus
a mandatory ASAN sweep and the full Slow suite.

Paying that for 27 static sites, most of them cold, is a bad trade.

A narrower variant ("Route C" — mint the marker for single-constructor variant
types, where arity is unambiguous) was scoped and dropped: single-ctor types are
*reached* by matching on them, which is already the covered scrutinee path.
Records and tuples are not candidates at all, since `lower.ml` emits `ERecord` /
`ETuple` for them and FBIP only matches `EAlloc`.

## Caveats on the measurement

- These are **static** site counts, not execution counts. 18 `List.Cons` sites
  inside a hot loop would matter more than the number suggests.
- One program's link closure. A DataFrame-heavy app could shift the mix — though
  the `Result.Err` concentration looks like a general property of `let?` error
  propagation rather than anything specific to this benchmark.
- Re-run the instrumentation before acting on this file; it is a snapshot of
  2026-08-07, and the other passes that ate most of the gap (escape analysis, the
  scrutinee path) are themselves still moving.
- The stage matters when re-measuring: `MARCH_DUMP_TXT=tir-perceus` shows **zero**
  `stack_alloc`, because `Escape` runs after Perceus. Use `tir-escape` for any
  claim about what is heap- vs stack-allocated. Also note `grep -c 'alloc X'`
  double-counts, since `stack_alloc` contains the substring `alloc`.

## What would change the verdict

A workload where the dynamic count of the 27 sites is large, or a program shape
where `no_marker_tvar` (erased-type drops, 153 today) dominates — those can only
be recovered by a runtime check, so they are the real argument for Route A if
they ever grow.

## References

- Paper: <https://www.microsoft.com/en-us/research/wp-content/uploads/2021/11/flreuse-tr-v1.pdf>
- ACM DL: <https://dl.acm.org/doi/10.1145/3547634>
- Code: `lib/tir/perceus.ml` (`add_scrutinee_free_for`), `lib/tir/perceus_fbip.ml`
  (`same_arity`, `try_fbip_sink`), `lib/tir/llvm_emit.ml` (`EReuse`),
  `runtime/march_runtime.h` (object header)
