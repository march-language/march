# Bastion: Vault (In-Memory Store)

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Vault is a built-in, in-memory key-value store for March — analogous to Erlang's ETS (Erlang Term Storage). It lives in the March stdlib, not in Bastion specifically, because it's useful far beyond web frameworks. However, Bastion relies on it heavily for caching, session storage, rate limiting, and other server-side state.

Vault tables are **named, process-safe, and shared** across all actors on a node. Any actor can read from or write to any Vault table without message passing. This makes Vault fundamentally different from actor state (which is private to one actor) — Vault is shared mutable state, carefully designed to be safe in a concurrent environment.

---

## Core API

```march
mod Vault do
  # Table creation — typically done at application startup
  fn new(name: Atom, opts: TableOpts) -> Table
  # opts: %{type: :set | :bag | :ordered_set, read_concurrency: Bool, write_concurrency: Bool}

  # Basic operations
  fn put(table: Table, key: k, value: v) -> :ok
  fn get(table: Table, key: k) -> Option(v)
  fn delete(table: Table, key: k) -> :ok
  fn has_key?(table: Table, key: k) -> Bool

  # Bulk operations
  fn put_many(table: Table, entries: List({k, v})) -> :ok
  fn get_all(table: Table) -> List({k, v})
  fn keys(table: Table) -> List(k)
  fn size(table: Table) -> Int

  # Conditional operations (atomic)
  fn put_new(table: Table, key: k, value: v) -> Bool          # insert only if key doesn't exist
  fn update(table: Table, key: k, fn(v) -> v) -> Option(v)    # atomic read-modify-write
  fn get_and_delete(table: Table, key: k) -> Option(v)        # atomic get + delete

  # TTL support
  fn put(table: Table, key: k, value: v, ttl: Int) -> :ok     # auto-expires after ttl milliseconds
  fn ttl(table: Table, key: k) -> Option(Int)                  # remaining TTL in ms

  # Pattern matching / queries (for :bag and :ordered_set types)
  fn match(table: Table, pattern: Pattern) -> List({k, v})
  fn select(table: Table, fn({k, v}) -> Bool) -> List({k, v})

  # Housekeeping
  fn clear(table: Table) -> :ok
  fn drop(table: Table) -> :ok
  fn info(table: Table) -> TableInfo                           # size, memory usage, type, etc.
end
```

---

## Table Types

```march
# :set — one value per key (default, most common)
cache = Vault.new(:response_cache, %{type: :set, read_concurrency: true})
Vault.put(cache, "/users/42", rendered_html, ttl: 60_000)  # expires in 60 seconds

# :bag — multiple values per key (useful for indexing, subscriptions)
subs = Vault.new(:subscriptions, %{type: :bag})
Vault.put(subs, "room:general", pid_1)
Vault.put(subs, "room:general", pid_2)
Vault.get_all_matching(subs, "room:general")  # [pid_1, pid_2]

# :ordered_set — keys are sorted (useful for range queries, leaderboards)
scores = Vault.new(:leaderboard, %{type: :ordered_set})
Vault.range(scores, min: 100, max: 200)  # all entries with keys between 100-200
```

---

## Concurrency Model

Vault tables are safe to read and write from any actor concurrently. The implementation uses:

- **Lock-free reads** when `read_concurrency: true` (the common case for caches)
- **Fine-grained locking per key** for writes (not table-level locks)
- **Atomic compound operations** (`put_new`, `update`, `get_and_delete`) for safe concurrent modifications without external locking

This means actors never need to coordinate via message passing to access shared Vault data. A web request handler can read from a cache table without blocking other handlers — critical for high-throughput serving.

---

## TTL and Expiration

Vault supports per-key TTL (time-to-live). Expired entries are cleaned up by a background sweeper actor that runs periodically (configurable interval, defaults to every 30 seconds). Reads of expired keys return `None` immediately — they don't wait for the sweeper.

```march
# Cache a database query result for 5 minutes
Vault.put(cache, cache_key, result, ttl: 300_000)

# Later: returns None if expired, Some(result) if still valid
case Vault.get(cache, cache_key) do
  Some(cached) -> cached
  None -> fetch_and_cache(cache_key)
end
```

---

## Per-Node, Not Distributed

Vault tables are **per-node** — they exist in the memory of a single March runtime instance. In a multi-node deployment, each node has its own independent Vault tables. This keeps the implementation simple and fast (no distributed consensus, no network round-trips).

For data that needs to be shared across nodes, use Depot (Postgres), an external Redis instance, or March's distributed PubSub. Vault is explicitly for node-local hot data.

---

## Application Startup

Vault tables are typically created in the application's supervision tree:

```march
mod MyApp do
  import Bastion

  fn start() do
    # Create Vault tables before starting the web server
    Vault.new(:response_cache, %{type: :set, read_concurrency: true})
    Vault.new(:fragment_cache, %{type: :set, read_concurrency: true})
    Vault.new(:rate_limits, %{type: :set, write_concurrency: true})
    Vault.new(:sessions, %{type: :set, read_concurrency: true})

    children = [
      {Vault.Sweeper, interval: 30_000},   # TTL expiration sweeper
      {Depot.Pool, MyApp.Config.db()},
      {Bastion.PubSub, name: MyApp.PubSub},
      {Bastion.Endpoint, MyApp.Endpoint, port: 4000}
    ]

    Bastion.Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

---

## Open Questions

- **Implementation details**: What's the underlying data structure? Hash array mapped trie (HAMT) for lock-free reads? How does the TTL sweeper interact with ongoing reads?
- **Memory overhead**: What are the memory overhead characteristics per entry?
- **Distributed option**: Should Vault support optional replication/sync across nodes (e.g., for session data), or remain strictly per-node?

See [open-questions.md](open-questions.md) for the full list.
