# DONE 2026-09-20: Vault's write lock is sharded by bucket — the last of the four ETS items

Item 2 (write concurrency / partitioning) was the only one left open. It is done,
so the whole file moves here; the original, with items 1, 3 and 4 already marked
delivered, follows below.

## The measurement first, because the file demanded one

The todo said: *do not implement it speculatively — get a workload that
measurably serialises on the write mutex first.* So the first deliverable is
`test/test_vault_write_scale.c`, the writer twin of item 1's reader harness
(distinct keys per thread, median-of-5, core-adaptive thread count, on the same
`vault-scale` alias rather than `runtest`).

On this repo's 14-core dev box, T=4, each thread rewriting its own 64
pre-inserted keys, **the same harness on both sides**:

| runtime | parallel median | solo median | ratio |
|---|---|---|---|
| one exclusive lock per table (before) | 165–183 ms | 14 ms | **11.8x – 13.1x** |
| lock sharded by bucket (after) | 37–45 ms | 14–15 ms | **2.5x – 3.2x** |

Both figures move with host load, like every number the sibling reader harness
produces (its own header documents four rounds of chasing exactly that): on a
box busy with other suites the after-figure was later sampled at 4.2x, still
well inside the harness's 6.0x bound and still a third of the before-figure
measured the same way. The pair above was taken back to back on the same box,
which is what makes the comparison meaningful; treat the absolute numbers as
indicative and re-measure both sides together before concluding anything.

Plain serialisation would be 4.0x, so the before-figure was *three times worse
than serialising*. That is the part worth recording: it was not simply "one
writer at a time". `vault_wr_lock` also stores the writer flag and drains all
16 reader stripes, so four writers bounced those cache lines against each other
on top of queueing on the one mutex. Partitioning removes both halves at once,
which is why the gain (4x) exceeds what the queueing alone could explain.

## The change

`vault_data` holds `VAULT_WR_SHARDS = 16` shards, each with its own
`vault_rwlock_t` and its own entry count on its own cache line. A key's shard is
the low bits of its bucket index, and `vault_hash` already returns that index,
so every keyed operation (`get`, `set`, `set_ttl`, `put_new`, `incr`,
`push_capped`, `drop`) locks exactly one shard — it only ever touches one
bucket. This is how ETS partitions a table, and it composes with the striped
read lock rather than replacing it: a reader still hashes to a stripe, now
within its bucket's shard.

`VAULT_RD_STRIPES` is deliberately left at 16. Reducing it would claw back most
of the memory below (4 stripes/shard measured 11 KB per table against 23 KB, with
read scaling 2.04x versus 1.53x — both inside the reader harness's bound), but
that parameter carries item 1's own measurement trail and re-tuning it here would
be a second, unjustified change in the same commit.

## What it costs

- **Memory per table: 5,312 → 23,552 bytes** (measured `sizeof(vault_data)`;
  16 shards × 1,216 bytes plus the 512-bucket array). Tables are few — the actor
  registry, `Config`, a cluster node's three — so ~18 KB each is not a real cost.
  If the table count ever grows, trade `VAULT_RD_STRIPES` down as above.
- **`size` and `keys` are no longer whole-table snapshots.** They walk shard by
  shard, holding one shard's read lock at a time, so an insert into an
  already-visited shard is missed while a later shard is being walked. ETS makes
  the same trade for a partitioned table, and neither call promised atomicity
  before: both recount live entries as they walk and skip expired ones, so a
  concurrent writer could always change the answer. Restoring it would mean
  holding all 16 read locks across an O(n) walk, blocking every writer in the
  table. Documented on `vault_data` and in `stdlib/vault.march`'s own docs.

## What the residual 2.5x–3.2x is not

Not shard collision: 16, 32 and 64 shards all measure the same within noise. It
is the per-write work that is shared whatever the lock does — `malloc`/`free` of
the key's C-string copy and the Unit return allocation, both taking the
allocator's locks. Reducing those is separate work; this item was the lock.

## Verification

- `dune build @vault-scale`: both harnesses pass. Read scaling unchanged
  (2.24x against a 3.60x bound; item 1's own figure was ~2.0x median).
- The write harness's assertion is non-vacuous: the pre-change runtime fails it
  (165–183 ms against its 84 ms bound).
- `test_vault_concurrency` (3 readers against 1 writer over a shared key set,
  the correctness hammer, on `runtest`) passes, as does the full suite.
- **Sanitizers, with a control that proves they can see a failure here.**
  `test_vault_hammer.c` (3 readers looping `get` against 1 writer looping
  `set`/`drop` over the same keys) built with `-fsanitize=address` and with
  `-fsanitize=thread`, in the `march-sbx-test-ubuntu` container: **no findings**
  on the sharded runtime, and none on the pre-change one either.

  A clean sanitizer run means nothing until the oracle is shown to be
  sensitive, and two attempted controls were NOT:

  - *shard depends on the calling thread* (so two threads on one bucket take
    different locks): no findings. The window in which a reader holds a pointer
    to a node the writer unlinks is nanoseconds; it was simply never hit.
  - *free the unlinked node after the unlock instead of before*: no findings,
    and on reflection this is not even a bug. The writer drains the readers
    BEFORE unlinking, so no reader can be holding the removed node, and a
    reader arriving after the unlink cannot reach it.

  The control that works removes the drain itself (`vault_wr_lock` stops
  waiting for the reader stripes), which is precisely the property the lock
  provides. Both sanitizers then fire immediately: ASAN aborts on the
  runtime's own `RC underflow` guard, and TSAN reports 15 findings, including
  data races in `vault_find`, `march_vault_get` and `march_vault_drop`. That
  is the failure class a mis-sharded lock would produce, so the clean runs
  above are evidence rather than absence of evidence.

---

The original filing follows.

`[P2]` # Move Vault toward ETS semantics: write partitioning, typed handles

Vault (`stdlib/vault.march`, `runtime/march_extras.c`) is March's ETS: a
C-backed, process-global, in-memory key/value table, documented as *"shared
across all actors without message passing"*. Four properties kept it from being
the substrate a registry — or any read-heavy shared table — should be built on.
**Three have shipped; one remains open and is what this file now tracks.**

This file is now item 2 only. Item 3 (typed table handles) shipped 2026-08-14
— see `specs/progress/2026-08-14-vault-typed-handles.md`, which also records
what typed handles deliberately do NOT close (`new`/`open`/`whereis` mint a
handle at a caller-chosen element type; `ns_*` and `Config` stay erased).

Filed out of the named-registry design
(`specs/2026-08-12-named-registry-design.md`), which depended on items 1 and 4.
Every item stands on its own merit for existing Vault users.

## Delivered

- **1. Concurrent reads — DONE** (2026-08-12, commits `6a9c7491..acf9a35b`).
  Shipped as a **striped reader-count lock**, not the epoch/RCU or
  centralized-counter designs this file originally sketched, and explicitly
  **not** `pthread_rwlock_t` — which was built first and measured *worse* than
  the exclusive mutex it replaced on Darwin (~18x vs ~9.5x four-thread/solo) and
  rejected on that measurement. Reads of *distinct* keys now scale close to
  linearly; reads of the *same* key remain bounded by refcount contention on
  that key's one shared value, which is an orthogonal cost no table-lock design
  removes. Full measurement trail and the seq_cst exclusion-pair fix:
  `specs/progress/2026-08-12-named-registry.md`.
- **4. Capability shape — DONE** (2026-08-12, commit `3c4e566a`). Reads are
  capability-free: `get`/`size`/`keys` lose `needs IO.Mut`;
  `new`/`whereis`/`set`/`set_ttl`/`drop`/`update`/`put_new`/`incr`/
  `push_capped`/`ns_set`/`ns_get`/`ns_drop` keep it. `whereis` keeps it because
  it mints a handle **from a string** (the ambient-authority case), not because
  it writes; the three `ns_*` wrappers keep it for the same reason, regardless
  of whether the wrapped op is a read (`ns_get`) or a write. The accepted costs
  — a use-site audit signal traded for boundary auditability, and the loss of
  `needs` as a purity signal on `get` — were taken deliberately; the reasoning
  is preserved in the design spec's §7, and the trade-off is written into the
  capability docs rather than left to be discovered.

## 2. Write concurrency / partitioning — DONE 2026-09-20 (see the header above)

One mutex covers a whole table, so concurrent writers to unrelated keys
serialise. Elixir partitions by `:erlang.phash2(term, limit)`. A per-bucket (or
per-shard) lock is the cheap version and composes with the striped read lock
already shipped.

**Staleness note (2026-08-14), resolved 2026-09-20:** this item was honest but
*unmotivated by measurement* for five weeks. What finally motivated it was not the
registration storm below but a direct harness (`test_vault_write_scale.c`): writes
to unrelated keys cost 11.8x–13.1x solo at four threads, three times worse than
plain serialisation. The instruction not to implement it speculatively was right —
and the number it asked for turned out to be much larger than the queueing model
predicted, because the drain of the reader stripes was the bigger half. The
original note follows. The registration storm it was filed against —
40 000 register + 40 000 retire pairs in `bench/actors/spawn_churn.march` — cost
~1.6 µs per pair and added ~60–70 ms to a ~900 ms scenario, against a 120 000 ms
gate, with no measurable effect on the `fanin` send path. Nothing in the tree
today contends on Vault writes hard enough to justify the change. Keep it open
as a known structural limit, but **do not implement it speculatively** — get a
workload that measurably serialises on the write mutex first, or this is just
added complexity in a lock that a review round already had to fix a memory-order
bug in.

## 3. Typed table handles — DONE (2026-08-14)

Shipped as `Vault(v)` — phantom in the ELEMENT type only, no key parameter
(keys are stringified, and `stdlib/config.march` keys one table with both
2-tuples and 3-tuples) — plus a `Vault`-scoped value restriction, without
which the phantom parameter would be decoration: March generalizes let-bound
applications, so `let t = Vault.new("t")` would otherwise re-instantiate the
element type at every use. Residual erasure (handle minting from a name,
`ns_*`, `Config`) is enumerated in
`specs/progress/2026-08-14-vault-typed-handles.md`.

## Acceptance

- ~~A read-heavy Vault benchmark scales with cores instead of serialising.~~ DONE (item 1).
- ~~A module that only reads a table it was handed needs no `needs` line, and the
  capability docs explain where the authority came from instead.~~ DONE (item 4).
- ~~Storing an `Int` and reading it as a `Pid` is a type error.~~ DONE (item 3),
  for a handle that was bound rather than minted inline.
- ~~Concurrent writers to unrelated keys in one table do not serialise.~~ DONE
  (item 2, 2026-09-20): 11.8x–13.1x → 2.5x–3.2x at four threads, against 4.0x for
  full serialisation. The residual is allocator cost per write, not the lock.

## Backend divergence found 2026-09-02 — FIXED 2026-09-10

`Vault.new` on an already-registered name returned a fresh table interpreted
and the same table compiled. The interpreter now matches the compiled runtime;
see `specs/progress/2026-09-10-vault-new-same-name-backend-parity.md`.
