# A field read out of a borrowed scrutinee no longer refcounts

**Landed:** 2026-09-04. Found while root-causing a voxel engine's meshing
throughput; filed there as G73. Carries a cherry-pick of `bfb16dac`
(`fix(borrow): NativeArray reads borrow their array`, from branch
`claude/borrow-native-array-reads`) as a prerequisite — without it the
motivating accessor's parameter is inferred `own`, and the shape this fix
targets never arises. That commit is unchanged and separately committed.

## The problem

```march
type Chunk = Chunk(NativeU8Arr)
fn get(c : Chunk, i : Int) : Int do
  match c do Chunk(a) -> NativeArray.get_u8(a, i) end
end
```

`MARCH_DEBUG_BORROW=1` says `get(c:borrow, i:own)` — borrow inference is
right. Perceus still emitted, for that single array read:

```
Chunk($f) -> let a : NativeU8Arr = inc_rc $f; $f in
               let $rc : Int = native_u8_arr_get(a, i) in
               dec_rc a; $rc
```

Two independent mechanisms, each locally correct:

1. The `ECase` **scrutinee-borrowed re-add** (`specs/perceus-invariants.md`
   §6) puts `$f` in the branch's live-at-exit set. `let a = $f` is then an
   alias binding whose source is live, so `find_inc_vars` mints `a` its own
   reference.
2. `a` is dead after the call and `native_u8_arr_get`'s array parameter is
   borrowed, so §2's borrowed-position rule schedules the post-call
   `dec_rc` — the callee will not release what the caller lent it.

Neither is needed: `c` is alive for the whole call and `a` never leaves the
arm.

It is not cheap overhead. `march_incrc_local` reads a `_Thread_local`
(`march_sched_in_scheduler()`) and then **always defers to the atomic
`march_incrc`** on a scheduler thread, so inside `List.pmap_n` there is no
non-atomic refcounting at all. An atomic read-modify-write on a header that
other workers are reading concurrently is a cache line bouncing between
cores in exclusive state — for a *read*. The reporting profile, `sample`
over a meshing loop at 14 scheduler threads, shows ~27 600 top-of-stack
samples in refcounting against ~9 000 in the mesher itself.

## What landed

One `env` field, at one site: `lib/tir/perceus_core.ml`'s `ECase` case now
adds a branch's `needs_rc` `br_vars` to `env_for_br.borrowed_field_vars`
when the scrutinee is live across the whole case.

No new mechanism. Such a br_var *is* a borrowed field var in exactly the
sense the `ELet` `is_borrowed_field` cases and §7 already define, and every
consequence falls out of the existing discipline:

- the alias-binding arm of `ELet` skips RC processing of `let a = <br_var>`
  (no dup at the projection);
- the `borrowed_field_vars` exclusion in `EApp`/`ECallPtr`'s
  `post_dec_vars` filter suppresses the post-call drop;
- a **consuming** use still dups, because the `la` re-add already made the
  br_vars live at every such use. The dup for an escaping projection is not
  removed, only moved from the projection site to the escaping use.

### The safety gate

Gated on `StringSet.mem v.v_name live_after` **alone**, not on the full
`scrutinee_borrowed` disjunction that drives the `la` re-add. The premise
is "the parent outlives the arm", and only that disjunct establishes it.
The other two are deliberately excluded:

- `name_free_in v br_body` — §6's path-insensitive conservatism — says only
  that the scrutinee is *mentioned* somewhere in the arm. Ownership
  transfers into the body, which may consume and free it part-way through
  while a projected field is still being read. Today that field holds its
  own `+1` and survives; eliding it there would turn §6's deliberate
  leak-not-crash into a use-after-free.
- `TTuple`/`TRecord` scrutinees are `needs_rc = false`, so Perceus never
  sees the aggregate's lifetime and cannot discharge the premise at all.

Both exclusions leave elidable pairs on the table. That is the acceptable
direction to be wrong in.

`specs/perceus-invariants.md` §6.1 is the governing account.

## Verification

**Machine caveat.** Every measurement below was taken on a box whose 1-minute
load average was 129-134: four other worktrees were running benchmarks and a
`cube_forge` test binary concurrently. Absolute wall-clock numbers from this
box are worthless; only IR-shape facts, exit codes and back-to-back ratios are
reported.

### IR shape

- `MARCH_DEBUG_BORROW=1` on the motivating accessor reports `get(c:borrow,
  i:own)` (it reports `c:own` without the `bfb16dac` prerequisite, which is
  why that commit rides along).
- `--dump-tir` on the `Chunk` accessor: `Chunk($f) -> let a = $f in
  NativeArray.get_u8(a, i)` — the `inc_rc`/`dec_rc` pair is gone.
- `--emit-llvm` on a self-recursive read loop over the wrapper
  (`burn_cell`, the probe's mode-F shape): **zero** `march_incrc`/
  `march_decrc` calls in the emitted loop, against one pair per iteration
  before.

### Escape controls (the elision must not fire when the projection leaves)

Probed base-vs-fix on: the projection **returned** from the arm; **stored in a
constructor**; passed at an **owned argument position**; **captured by an
escaping closure**; and read **twice** at borrowed positions. In every
escaping case exactly one dup survives — **moved** from the projection site to
the escaping use, not removed. All five programs print identical output under
the interpreter and both compiled binaries.

### Suites

- **TIR goldens.** All 33 pre-existing goldens are **unchanged** — the corpus
  had no fixture for this shape at all, which is why the pair stayed invisible.
  New fixture `test/snapshots/src/borrowed_scrutinee_field_read.march` plus its
  two goldens; `read_only` is two projections and two borrowed reads with zero
  RC ops, and the `escapes` control carries exactly one `inc_rc` at the return.
  37/37 green, and green again on a re-run without `UPDATE_SNAPSHOTS`.
- **`scripts/run-tests.sh`** — one failure, a stale assertion, fixed here.
  `test_codegen.ml`'s `test_tco_self_dup_arg_decref_on_live_path` asserted
  `incs > 0` on a `walk(xs:borrow, acc)` list walk whose forwarded tail is
  exactly this shape. Measured `@walk` counts: base **1 inc / 1 dec**, fixed
  **0 / 0**. The balance invariant it guards (an unbalanced dup leaks every
  cons cell) is untouched; the `incs > 0` clause was a non-vacuousness guard
  that only made sense while a dup was unavoidable, and is replaced by pinning
  the exact new count. Checked it is not a leak or a UAF rather than assumed:
  500-element list, 2000 borrowed walks, interpreter and both compiled binaries
  print `1000000 / 1 / 500`, the list is intact and re-walkable afterwards, max
  RSS 2 375 680 (base) vs 2 392 064 (fixed). The group is 10/10 after the
  update. Everything else in the run passed (1018, 277, 878, 61, 24, 361, 5,
  36, 10, 7, 693 tests across the suites).

### Deferred to CI

The differential oracle (`test/test_properties.exe`), `dune build @oracle`, the
RC-sensitive benchmarks and the `pmap_scaling` probe were still running locally
when this landed — zero failures reported up to that point, but the box's load
made them unusable as timing evidence and slow as correctness evidence. CI runs
them on an idle machine; treat that run, not this one, as the verdict on the
benchmark numbers.
