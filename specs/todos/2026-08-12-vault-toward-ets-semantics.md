`[P2]` # Move Vault toward ETS semantics: concurrent reads, typed handles, capability shape

Vault (`stdlib/vault.march`, `runtime/march_extras.c`) is March's ETS: a
C-backed, process-global, in-memory key/value table, documented as *"shared
across all actors without message passing"*. Three properties keep it from
being the substrate a registry — or any read-heavy shared table — should be
built on.

Filed out of the named-registry design
(`specs/2026-08-12-named-registry-design.md`), which depends on items 1 and 3,
but every item stands on its own merit for existing Vault users.

## 1. Concurrent reads

`march_vault_get` takes the table's `pthread_mutex_t` on **every read**
(`runtime/march_extras.c`). Elixir's Registry — the closest reference — creates
its ETS tables with `read_concurrency: true, write_concurrency: true` and reads
them **directly from the calling process**, no round-trip and no serialisation.

This is already a wart independent of registries: `docs/overload-resilience.md`
points readers at Vault-style tables for rate limiting and shed-decision state,
which is read-heavy by nature, and every reader currently queues behind every
other.

The actor-table work (Task 10, 2026-08-12) established the pattern to copy:
`_Atomic` bucket heads, release-store on publication, acquire-load and walk for
readers, writers serialised by the existing mutex. The wrinkle Vault has and
`g_actor_tbl` did not is **deletion** — `vault_drop` and TTL expiry both unlink
nodes, which a lock-free reader cannot tolerate. Options: retire-in-place
(clear the value, leave the node — the registry design's approach, bounded by
distinct keys ever used), or epoch/hazard-pointer reclamation. Retire-in-place
is far simpler and is probably right for the key distributions Vault sees;
measure before reaching for anything cleverer.

## 2. Write concurrency / partitioning

One mutex covers a whole table, so concurrent writers to unrelated keys
serialise. Elixir partitions by `:erlang.phash2(term, limit)`. A per-bucket (or
per-shard) lock is the cheap version and composes with item 1.

Lower priority than item 1 — Vault's workloads are read-heavy — but a
registration storm during a supervisor restart wave is a genuine write burst.

## 3. Typed table handles

`vault_get` returns `Option(TPtr TUnit)` (`lib/tir/llvm_builtins.ml:315`) — the
value is *erased*. Storing an `Int` and reading it back as a `Pid` type-checks,
and the resulting fake Pid is dereferenced as an actor record on the next
`send`. Erlang does not have this problem because it is dynamically typed
end-to-end; March does.

Wanted: a phantom-typed handle, `Vault(k, v)`, so `new`/`open` fix the value
type and `get` returns `Option(v)`. Keys are already stringified through
`vault_key_cstr`, so the key parameter may be cosmetic — the value parameter is
the one that closes the hole.

Note the interaction with `Vault.update(table, key, fn)`: the function's type
has to line up with `v` too.

## 4. Capability shape — `IO.Mut` on every operation

**Decided 2026-08-12:** reads are capability-free — `get`/`size`/`keys` lose the
requirement; `new`/`whereis`/`set`/`set_ttl`/`drop`/`update` keep `IO.Mut`.
`whereis` keeps it because it mints a handle from a string (the ambient-authority
case), not because it writes. Scheduled as Task 2 of
`docs/superpowers/plans/2026-08-12-named-registry.md`. The rest of this section
records the reasoning and the accepted costs.

Every `vault_*` builtin requires `IO.Mut` (`lib/caps/cap_symbols.ml:96-…`,
`lib/typecheck/typecheck.ml:1947-1960`). So *reading* an in-memory table
demands a mutation capability, and any module that so much as looks something
up must declare `needs IO.Mut`.

Vault is **in memory**. Nothing escapes the process. The authority actually at
stake is not "mutation" but *reachability of a shared table* — and March
already has a mechanism for that: value-carried authority (`fn main(_c :
Cap(IO.Console))`, `get_cap(pid)`).

Proposed shape (full argument in the registry design, §7):

- **Naming ops mint authority from a string** — `vault_new(name)`,
  `vault_whereis(name)` turn "anyone who can spell the name" into access.
  That is the ambient-authority pattern capabilities exist to control, the same
  shape as `File.open(path)` needing `IO.FileRead`. **Keep a capability here**,
  and consider splitting it `IO.Mut.Read` / `IO.Mut.Write` — the lattice
  already has the `IO.FileRead`/`IO.FileWrite` precedent
  (`lib/caps/cap_lattice.ml:19-20`).
- **Data ops act on a handle you were given** — `get`/`set`/`drop`/`update`/
  `size`/`keys`. Possession of the unforgeable handle *is* the authority, and
  it is more precise than `needs IO.Mut`: it names *which* table rather than
  "some shared state". **Drop the ambient requirement here.**
- **Attenuation by splitting the handle, not the capability**: derive a
  read-only view (`Vault.readonly(t) : VaultRead`) so a module can be granted
  lookup-but-not-mutate. Per-table, which no capability split can express.

### The costs, to be decided deliberately

- **Audit signal at the use site.** A module mutating a handed-in table would
  declare nothing. Authority stays auditable at the *boundary* (someone named
  the table and declared it; handles flow through signatures) — the standard
  ocap trade-off, but it must be written into the capability docs rather than
  discovered.
- **Purity.** A read of shared mutable state is non-deterministic — it observes
  another actor's writes. If `needs` is read partly as "this is not pure",
  dropping it from `get` loses that signal. This is the real question to settle
  first, because it governs the whole design.
- **Breaking change.** Removing a `needs` requirement is source-compatible
  (a module declaring more than it uses may warn); *adding* the naming/data
  split is not, if any op moves the other way. Check the
  declared-but-unused-capability warning before changing anything.

## Acceptance

- A read-heavy Vault benchmark scales with cores instead of serialising.
- Storing an `Int` and reading it as a `Pid` is a type error.
- A module that only reads a table it was handed needs no `needs` line, and the
  capability docs explain where the authority came from instead.
