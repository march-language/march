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

## 2. Write concurrency / partitioning — OPEN, but no measured motivation yet

One mutex covers a whole table, so concurrent writers to unrelated keys
serialise. Elixir partitions by `:erlang.phash2(term, limit)`. A per-bucket (or
per-shard) lock is the cheap version and composes with the striped read lock
already shipped.

**Staleness note (2026-08-14):** this item is honest but currently
*unmotivated by measurement*. The registration storm it was filed against —
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
- Concurrent writers to unrelated keys in one table do not serialise.
  **Open (item 2) — see the staleness note; want a measured workload first.**

## Backend divergence found 2026-09-02: `Vault.new(name)` twice

`Vault.new` with a name that is already registered returns a **fresh** table in
the interpreter and the **same** table compiled. Probe (`main` must take
`Cap(IO)` — a narrower grant is refused before the program runs, which hid this
on the first attempt):

```march
let a = Vault.new("vn_probe")
Vault.set(a, "k", 42)
let b = Vault.new("vn_probe")
match Vault.get(b, "k") do
  Some(v) -> println("same table: " ++ int_to_string(v))
  None    -> println("FRESH table")
end
```

```
interpreted:  FRESH table
compiled:     same table: 42
```

Found because `test/session/stream_replay.march`'s first `drain` re-created its
tables by name: the interpreter drained an empty queue and the trace stopped
after one line, while the compiled binary ran the whole protocol. Whichever
semantics ETS-style tables should have, the two backends must agree; the
interpreter's fresh table is the one that silently loses data, so it is the
more dangerous side. The fixture now closes over the handles instead.

