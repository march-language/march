# Distributed Algorithms — Stdlib Design

**Date:** 2026-06-20
**Status:** Approved, pending implementation plan
**Approach:** C — two shared interfaces (`CRDT`, `Hashable`), plain modules elsewhere

---

## Overview

Five new stdlib modules covering three problem areas:

| Area | Modules |
|------|---------|
| Efficient functional sequences | `deque.march` |
| Content-addressed data | `merkle.march` |
| Distributed coordination | `vector_clock.march`, `crdt.march`, `consistent_hash.march` |

These modules are additive — no existing stdlib module is modified. They integrate via existing types (`Map`, `Set`, `OrderedMap`, `Crypto`, `Seq`) and two new interfaces.

---

## Shared Interfaces

Defined in their respective home modules and available for `impl` elsewhere.

```march
-- defined in crdt.march
interface CRDT(t) do
  fn merge(a : t, b : t) : t    -- associative, commutative, idempotent
  fn equal(a : t, b : t) : Bool
end

-- defined in merkle.march
interface Hashable(a) do
  fn hash(x : a) : Bytes
end
```

`CRDT` enables generic sync loops: any actor holding a `t` that `impl CRDT(t)` can
receive a peer's state and call `merge` without knowing which CRDT it is.

`Hashable` is the only thing `Merkle` requires of its element type — users provide
an impl for their domain types, and `Crypto.sha256` does the actual hashing.

---

## Module 1: `Deque(a)` — 2-3 Finger Tree

**File:** `stdlib/deque.march`
**Dependencies:** none

### Motivation

`List` is O(1) cons but O(n) append. `Seq` is a lazy church-encoded fold — not a
stored data structure. Neither supports efficient concat, split, or double-ended push/pop.
`Deque` fills this gap with a persistent 2-3 finger tree.

### Internal Types (private)

```march
ptype Digit(a) = One(a) | Two(a, a) | Three(a, a, a) | Four(a, a, a, a)
ptype Node(a)  = Node2(a, a) | Node3(a, a, a)
ptype FT(a)    = Empty | Single(a) | Deep(Digit(a), FT(Node(a)), Digit(a))
ptype Deque(a) = Deque(Int, FT(a))   -- cached size + tree
```

Size is cached at the top level so `length` is O(1) without full annotation machinery.
All structural operations (push, pop, concat, split) maintain the cached count.

### Public API

```march
fn empty()                    : Deque(a)
fn singleton(x)               : Deque(a)
fn is_empty(d)                : Bool
fn length(d)                  : Int            -- O(1)

fn push_front(d, x)           : Deque(a)       -- O(1) amortized
fn push_back(d, x)            : Deque(a)       -- O(1) amortized
fn pop_front(d)               : Option((a, Deque(a)))  -- O(1) amortized
fn pop_back(d)                : Option((a, Deque(a)))  -- O(1) amortized
fn front(d)                   : Option(a)
fn back(d)                    : Option(a)

fn concat(d1, d2)             : Deque(a)               -- O(log n)
fn split_at(d, i)             : (Deque(a), Deque(a))   -- O(log n)
fn get(d, i)                  : Option(a)              -- O(log n)

fn from_list(xs)              : Deque(a)       -- O(n)
fn to_list(d)                 : List(a)        -- O(n)
fn to_seq(d)                  : Seq(a)         -- O(n), lazy fold over elements
fn map(d, f)                  : Deque(b)       -- O(n)
fn foldl(d, init, f)          : b              -- O(n), left-to-right
fn foldr(d, init, f)          : b              -- O(n), right-to-left
```

### Performance Summary

| Operation | Complexity |
|-----------|-----------|
| push_front / push_back | O(1) amortized |
| pop_front / pop_back | O(1) amortized |
| concat | O(log n) |
| split_at / get | O(log n) |
| length / is_empty | O(1) |
| from_list / to_list / map / fold | O(n) |

### Out of Scope (v1)

Measured/annotated finger trees (needed for priority queues, interval trees, ropes).
These require a `Monoid` constraint on annotations and significantly more complexity.
Add when a concrete use case (e.g. a `Rope` module) demands it.

---

## Module 2: `Merkle(a)` — Hash Tree

**File:** `stdlib/merkle.march`
**Dependencies:** `crypto.march`, `list.march`

### Motivation

March's module system and package store are already content-addressed (SHA-256).
`Merkle` lets users build the same guarantees for their own data: tamper-evident
trees with O(k log n) diff — the primitive for efficient state sync between actors
or nodes. The planned "live islands" WebSocket feature will need exactly this for
reconnect reconciliation.

### Types

```march
type Hash = Bytes   -- 32 bytes (SHA-256 output)

type MerkleTree(a) =
  | Leaf(Hash, a)
  | Branch(Hash, MerkleTree(a), MerkleTree(a))

type ProofStep = Left(Hash) | Right(Hash)
type Proof = List(ProofStep)
```

### Hash computation

- Leaf: `Crypto.sha256(hash(x))` where `hash` comes from `Hashable(a)`
- Branch: `Crypto.sha256(left_hash ++ right_hash)`

The `Hashable` interface is defined here. Users provide a `Bytes` serialisation of
their value; `Merkle` handles the tree-level hashing.

### Public API

```march
interface Hashable(a) do
  fn hash(x : a) : Bytes
end

fn from_list(xs)              : MerkleTree(a)  when Hashable(a)
fn singleton(x)               : MerkleTree(a)  when Hashable(a)
fn concat(t1, t2)             : MerkleTree(a)  when Hashable(a)

fn root_hash(t)               : Hash
fn size(t)                    : Int
fn leaves(t)                  : List(a)

fn proof(t, i)                : Option(Proof)
fn verify(root, value, proof) : Bool           when Hashable(a)

fn diff(t1, t2)               : List((Int, a, a))
-- Returns [(leaf_index, value_in_t1, value_in_t2)] for differing leaves.
-- Compares root hashes first; identical subtrees short-circuit.
-- Cost: O(k log n) where k = number of differing leaves.
```

### `from_list` construction

Builds a balanced binary tree bottom-up by pairing adjacent elements, then pairing
pairs, until one root remains. A list of odd length promotes the last element unchanged
to the next level.

### Sync protocol sketch

```
actor A and actor B each hold a MerkleTree:
1. Exchange root_hash — if equal, done.
2. Compare left child hashes, right child hashes.
3. Recurse only into subtrees whose hashes differ.
4. At leaves: exchange the differing values.
```

This is the same protocol Git uses for pack negotiation and IPFS uses for block sync.

---

## Module 3: `VectorClock`

**File:** `stdlib/vector_clock.march`
**Dependencies:** `map.march`

### Motivation

Vector clocks answer "did event A happen before event B?" — the foundational
question for causal ordering in a distributed actor system. Required by `LWWRegister`
in `crdt.march` for merge ordering.

### Types

```march
type VectorClock = VectorClock(Map(String, Int))

type ClockOrder = Before | After | Concurrent | Equal
```

### Public API

```march
fn new()                      : VectorClock
fn tick(vc, actor_id)         : VectorClock        -- increment own slot
fn merge(vc1, vc2)            : VectorClock        -- pointwise max
fn compare(vc1, vc2)          : ClockOrder
fn happens_before(vc1, vc2)   : Bool
fn concurrent(vc1, vc2)       : Bool
fn get(vc, actor_id)          : Int                -- 0 if absent
fn to_list(vc)                : List((String, Int))
fn from_list(pairs)           : VectorClock
```

### Compare semantics

- `Before`: `vc1[i] <= vc2[i]` for all i, strict for at least one
- `After`: `vc1[i] >= vc2[i]` for all i, strict for at least one
- `Equal`: `vc1[i] == vc2[i]` for all i
- `Concurrent`: some i where `vc1[i] > vc2[i]` AND some j where `vc1[j] < vc2[j]`

---

## Module 4: `CRDT`

**File:** `stdlib/crdt.march`
**Dependencies:** `vector_clock.march`, `map.march`, `set.march`

### Motivation

CRDTs (Conflict-free Replicated Data Types) let distributed actors converge on
consistent state without coordination — actors can merge states in any order and
always reach the same result. State-based CRDTs (chosen here) are simpler to
implement correctly: actors periodically broadcast their full state; any receiver
calls `merge`.

### Interface

```march
interface CRDT(t) do
  fn merge(a : t, b : t) : t    -- associative, commutative, idempotent
  fn equal(a : t, b : t) : Bool
end
```

### GCounter — grow-only counter

```march
mod GCounter do
  type T = GCounter(Map(String, Int))

  fn new()                    : T
  fn increment(gc, actor_id)  : T
  fn value(gc)                : Int   -- sum of all actor slots
  impl CRDT(T)
end
```

Merge: pointwise max per actor slot. An actor may only increment its own slot.

### PNCounter — increment and decrement

```march
mod PNCounter do
  type T = PNCounter(GCounter.T, GCounter.T)   -- (increments, decrements)

  fn new()                    : T
  fn increment(pn, actor_id)  : T
  fn decrement(pn, actor_id)  : T
  fn value(pn)                : Int   -- sum(pos) - sum(neg)
  impl CRDT(T)
end
```

Merge: merge each GCounter independently.

### LWWRegister — last-write-wins register

```march
mod LWWRegister do
  type T(a) = LWWRegister(a, VectorClock)

  fn new(initial, vc)         : T(a)
  fn set(r, value, vc)        : T(a)
  fn get(r)                   : a
  impl CRDT(T(a))
end
```

Merge: keep the value whose vector clock is `After` the other. If `Concurrent`,
use a deterministic total order on `VectorClock` as a tiebreaker: compare the
sum of all slot values first (higher wins), then lexicographic order on the
serialised map (higher wins). This is arbitrary but stable — all actors converge
to the same value. Applications that care about concurrent-write semantics should
use `ORSet` instead.

### ORSet — observed-remove set

```march
mod ORSet do
  type T(a) = ORSet(Map(a, Set(String)))   -- element → set of unique add-tags

  fn new()                    : T(a)
  fn add(s, x, tag)           : T(a)   -- tag must be globally unique; use UUID.v4()
  fn remove(s, x)             : T(a)
  fn member(s, x)             : Bool
  fn to_set(s)                : Set(a)
  impl CRDT(T(a))
end
```

Merge: union the tag-sets for each element. An element is present iff its tag-set
is non-empty. `remove` deletes all *currently observed* tags for x; any concurrent
`add` (with a new tag) survives the merge — add wins over concurrent remove.

---

## Module 5: `ConsistentHash(a)` — hash ring

**File:** `stdlib/consistent_hash.march`
**Dependencies:** `ordered_map.march`, `crypto.march`

### Motivation

When distributing work across a pool of actors (or nodes), naive modulo-N hashing
reassigns most keys when N changes. Consistent hashing ensures only `keys/N` keys
move when a node joins or leaves. Essential for sharding Vault tables, actor pools,
or connection pools across a cluster.

### Types

```march
type HashRing(a) = HashRing(
  OrderedMap(Int, a),   -- virtual ring positions → physical node
  Map(String, a),       -- node_id → node (for remove by id)
  Int                   -- replicas per physical node
)
```

### Public API

```march
fn new(replicas)              : HashRing(a)
fn add_node(ring, id, node)   : HashRing(a)
fn remove_node(ring, id)      : HashRing(a)
fn get(ring, key)             : Option(a)      -- O(log n) clockwise successor
fn get_n(ring, key, n)        : List(a)        -- n distinct physical nodes
fn nodes(ring)                : List(a)        -- all physical nodes (deduplicated)
fn node_count(ring)           : Int
fn is_empty(ring)             : Bool
```

### Ring construction

For each physical node with id `nid`, compute virtual positions:
```
for i in 0..(replicas-1):
  position = first_4_bytes_as_int(Crypto.sha256(nid ++ ":" ++ int_to_string(i)))
  insert position → node into OrderedMap
```

### Key lookup

Hash the key with SHA-256, take the first 4 bytes as Int, find the smallest
position in the ring that is `>=` that value (wrap around to the smallest position
if none found). Return the node at that position.

`get_n` walks clockwise from the key's position, collecting distinct physical nodes
(skipping virtual positions that map to an already-collected node) until `n` nodes
are collected or the ring is exhausted.

### Replica count guidance

- 100–200 replicas per node gives good distribution for small clusters (3–10 nodes)
- Higher replica counts improve uniformity at the cost of memory and add/remove time

---

## Dependencies Map

```
deque.march
  (no deps)

vector_clock.march
  └── map.march

merkle.march
  ├── crypto.march
  └── list.march

crdt.march
  ├── vector_clock.march
  ├── map.march
  └── set.march

consistent_hash.march
  ├── ordered_map.march
  └── crypto.march
```

---

## Integration with Existing Stdlib

| New module | Integrates with |
|-----------|----------------|
| `Deque` | `Seq.to_seq` / `List.from_list` for pipeline interop |
| `Merkle` | `Crypto.sha256` for hashing; natural fit with `BastionPubSub` state sync |
| `VectorClock` | Actor message envelopes; feeds into `LWWRegister` |
| `CRDT.*` | `BastionPubSub` for broadcast; future live-islands reconnect |
| `ConsistentHash` | Actor pools, Vault table sharding, connection pools |

---

## Implementation Order

Build in dependency order — each module's tests pass before the next starts:

1. `Deque` — pure, no deps, good warm-up
2. `VectorClock` — small, needed by CRDT
3. `Merkle` — independent, moderate complexity
4. `CRDT` (GCounter → PNCounter → LWWRegister → ORSet) — builds on VectorClock
5. `ConsistentHash` — independent, uses ordered_map + crypto

---

## Out of Scope (v1)

- **Annotated finger trees** (`Measured` interface for priority queues / ropes)
- **Op-based CRDTs** (require guaranteed delivery; state-based is sufficient for actor broadcast)
- **Multi-party vector clocks beyond String actor IDs** (Lamport clocks, hybrid logical clocks)
- **`rebalance_diff(old_ring, new_ring)`** for `ConsistentHash` (useful for migration planning, deferred)
- **Live islands WebSocket integration** (depends on a separate "live islands" feature)
