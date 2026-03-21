PROPOSAL

**32-Way Hash Array Mapped Tries**

Persistent Collections for March

Map(k, v) · Set(a) · PersistentVector(a)

March Language Project

March 2026

**1. Motivation**

March currently has a single sequential collection type: List(a), a singly-linked cons list. Linked lists are excellent for pattern matching, recursive decomposition, and small collections, but they have fundamental limitations that surface as programs grow.

**1.1 The Linked List Ceiling**

Each cons cell is a 16-byte heap allocation (value pointer + next pointer on 64-bit). Traversing a million-element list means chasing a million pointers through memory, each likely a cache miss once the list exceeds L2/L3 cache. The practical consequence is that linked lists are comfortable up to roughly 100k elements, usable to about 1M, and painful beyond that.

More importantly, there is no O(1) indexed access. Looking up element 500,000 in a list requires walking 500,000 pointers. There is no persistent key-value map --- the current Map module in the stdlib design spec calls for a HAMT internally but doesn't exist yet. And there is no growable, cache-friendly sequential collection.

**1.2 What March Needs**

The stdlib design spec already defines the API surface for Map(k, v), Set(a), and Array(a). The remaining-work ranking places Persistent Map (HAMT) at priority \#4, after standard interfaces, formatter, and error recovery. This proposal fills in the implementation strategy: how to build a single HAMT engine that powers Map, Set, and a persistent vector type, and how it interacts with Perceus RC, linear types, and the REPL JIT.

**2. HAMT Architecture**

**2.1 Core Data Structure**

A Hash Array Mapped Trie (HAMT) is a wide, shallow tree indexed by hash bits. Given a key, we compute its 32-bit hash and split it into 5-bit chunks, each indexing into a node with up to 32 slots. Level 0 examines bits 0--4, level 1 examines bits 5--9, and so on, giving a maximum depth of 7 levels.

The critical optimization that makes HAMTs compact: most nodes are sparse. Instead of allocating a 32-element array with mostly empty slots, each node stores a 32-bit bitmap where bit N indicates that slot N is occupied, plus a packed array containing only the occupied entries. To find the position of slot N in the packed array, we popcount the bitmap below bit N.

> Node layout (64-bit):
>
> ┌─────────────────────────────────────────────┐
>
> │ bitmap: u32 (which slots are occupied) │
>
> ├─────────────────────────────────────────────┤
>
> │ entries: \[Entry; popcount(bitmap)\] │
>
> │ Entry = Leaf(hash, key, val) │
>
> │ \| Subtree(child\_node) │
>
> │ \| Collision(hash, \[(key, val)\]) │
>
> └─────────────────────────────────────────────┘
>
> A node with 3 occupied slots uses a 3-element
>
> array, not 32. Memory: 4 + 3\*8 = 28 bytes
>
> vs 4 + 32\*8 = 260 bytes for a dense node.

**2.2 Complexity**

  ------------------- ---------------------- ---------------------------- ---------------------
  **Operation**       **HAMT**               **Linked List**              **Balanced BST**
  Lookup by key       O(log32 n) ≈ O(1)      O(n)                         O(log2 n)
  Insert              O(log32 n) ≈ O(1)      O(1) prepend / O(n) sorted   O(log2 n)
  Delete              O(log32 n) ≈ O(1)      O(n)                         O(log2 n)
  Persistent update   Copy 1--7 nodes        Copy up to n nodes           Copy O(log n) nodes
  Iteration           O(n)                   O(n)                         O(n)
  Memory per entry    \~24--40 bytes         \~16 bytes                   \~40--48 bytes
  Cache behavior      Good (32-wide nodes)   Poor (pointer chasing)       Moderate
  ------------------- ---------------------- ---------------------------- ---------------------

For practical collection sizes, log32 is nearly constant: a million entries requires just 4 levels, a billion requires 6. The 32-wide branching factor means that each level of the tree has excellent cache locality --- a single cache line can hold most of a node's packed array.

**2.3 Hash Collisions**

When two keys hash to the same 32-bit value, they produce a Collision node: a list of (key, value) pairs sharing that hash. Collision nodes are scanned linearly using Eq, but collisions are rare with a good hash function --- the birthday paradox gives roughly 50% chance of any collision at \~77,000 entries with a uniform 32-bit hash.

March will use SipHash-1-3 for string keys and a fast integer hash (splitmix64 finalizer) for numeric keys. Both are provided via the Hash interface, which keys must implement.

**3. Persistent Vector**

The same HAMT structure can power a persistent vector (indexed sequential collection) by using the integer index itself as the hash. Bits 0--4 select the slot in the leaf node, bits 5--9 select the next level up, and so on. The leaves are contiguous 32-element arrays, which is why persistent vectors have dramatically better cache behavior than linked lists --- you iterate through 32-element chunks sequentially in memory instead of chasing one pointer per element.

**3.1 API Surface**

> mod PersistentVector do
>
> fn empty() : PersistentVector(a)
>
> fn from\_list(xs : List(a)) : PersistentVector(a)
>
> fn get(v : PersistentVector(a), idx : Int) : a
>
> fn set(v : PersistentVector(a), idx : Int, val : a)
>
> : PersistentVector(a)
>
> fn push(v : PersistentVector(a), val : a)
>
> : PersistentVector(a)
>
> fn pop(v : PersistentVector(a))
>
> : (PersistentVector(a), a)
>
> fn length(v : PersistentVector(a)) : Int
>
> fn map(v : PersistentVector(a), f : a -\> b)
>
> : PersistentVector(b)
>
> fn fold\_left(acc : b, v : PersistentVector(a),
>
> f : (b, a) -\> b) : b
>
> fn to\_list(v : PersistentVector(a)) : List(a)
>
> end

**3.2 Tail Optimization**

Clojure's persistent vector uses a tail buffer: the rightmost leaf node is kept outside the tree as a mutable (or copy-on-write) array. Appending to the vector just writes into the tail buffer until it fills up (32 elements), at which point it gets pushed into the tree and a new tail starts. This makes sequential push operations amortized O(1) with no tree path copies at all for 31 out of every 32 appends.

March should adopt the same tail optimization. For the uniquely-owned case (RC = 1 or linear), the tail buffer can be mutated in place, making append a simple array write with no allocation.

**4. Interaction with Perceus and Linear Types**

This is where March's design becomes uniquely interesting. The combination of Perceus RC, FBIP, and linear types means HAMTs in March can achieve performance characteristics that HAMTs in other languages cannot.

**4.1 Perceus FBIP Path Reuse**

A persistent HAMT update copies the path from root to the modified leaf --- typically 1--7 nodes. In a language with tracing GC (like Clojure's JVM), the old path nodes become garbage that must be collected later. In March, Perceus tracks reference counts on each node.

When the HAMT is uniquely owned (RC = 1 on the root), the FBIP optimization kicks in: the old node's memory is reused in-place for the new node, because the old node's RC drops to 0 at exactly the point where the new node would be allocated. The result is that a "persistent update" on a uniquely-owned HAMT performs zero allocations --- it mutates the path nodes directly, then updates the leaf. From the language's perspective the operation is pure (old value is gone, new value is fresh). From the runtime's perspective it's an in-place mutation.

**4.2 Linear Types: Guaranteed In-Place**

Perceus FBIP is opportunistic --- it only fires when RC = 1 at runtime. Linear types upgrade this to a compile-time guarantee. If a Map or Vector is declared linear, the type system enforces unique ownership, which means:

-   The compiler can skip RC checks entirely --- the value is provably uniquely owned

-   FBIP is guaranteed to fire on every update, not just when RC happens to be 1

-   The persistent vector's tail buffer can be mutated without even a CAS or RC decrement

> \-- Persistent (shared): path copy on update
>
> let m = Map.insert(m, \"key\", 42)
>
> \-- Linear (unique): in-place mutation, zero copies
>
> linear let m = Map.empty()
>
> linear let m = Map.insert!(m, \"key\", 42)
>
> linear let m = Map.insert!(m, \"other\", 99)
>
> \-- m consumed and rebound each time; no allocation

**4.3 Performance Tiers**

  ------------------ ---------------------- ------------------------ ---------------------------------------
  **Ownership**      **Update Cost**        **Allocation**           **When to Use**
  Shared (RC \> 1)   Copy 1--7 path nodes   \~200 bytes per update   Shared state, undo history, snapshots
  Unique (RC = 1)    In-place via FBIP      Zero (runtime check)     Single-owner maps being built up
  Linear             In-place, guaranteed   Zero (compile-time)      Hot loops, bulk construction, actors
  ------------------ ---------------------- ------------------------ ---------------------------------------

This three-tier model is unique to March. Clojure only has the shared tier. Rust only has the owned-or-borrowed distinction without persistent semantics. March offers persistent API semantics with mutable-array performance when ownership allows it.

**5. Implementation Plan**

**5.1 Prerequisites**

The HAMT implementation depends on the Hash and Eq interfaces being available for key types. The remaining-work ranking identifies Standard Interfaces (item \#1) as the highest priority item, and the HAMT is sequenced after it. Specifically, we need Hash(Int), Hash(String), Hash(Bool), and Hash(Float) as builtins, plus the ability for users to derive Hash for their own types.

**5.2 Phased Delivery**

**Phase 1: Core HAMT Engine (5 days)**

Implement the HAMT data structure in C (runtime/march\_runtime.c) with March wrapper functions. The C implementation handles node allocation, bitmap manipulation, popcount indexing, and path copying. March wrapper provides the typed API.

1.  Node representation: tagged union of Leaf, Subtree, and Collision entries in a bitmap-indexed packed array

2.  Core operations: lookup, insert, remove, iteration (depth-first traversal of populated slots)

3.  Hash functions: SipHash-1-3 for strings, splitmix64 finalizer for integers

4.  Perceus integration: RC fields on each node, FBIP-aware path copy that reuses nodes when RC = 1

**Phase 2: Map and Set API (3 days)**

Wrap the HAMT engine with the Map(k, v) and Set(a) APIs as defined in the stdlib design spec. Set is implemented as Map(a, Unit) internally. Implement the full API surface: empty, singleton, from\_list, get, insert, remove, update, size, map\_values, filter, fold, merge, keys, values, to\_list for Map; add, remove, member, union, intersection, difference, is\_subset for Set.

**Phase 3: Persistent Vector (3 days)**

Extend the HAMT engine with index-based access (using integer bits instead of hash bits) and the Clojure-style tail optimization. The persistent vector uses the same node structure as the map but with integer indexing and a mutable tail buffer for amortized O(1) append.

**Phase 4: Linear Type Integration (2 days)**

Add the linear variants of Map and Vector operations (insert!, set!, push!) that consume and rebind the collection. Wire these into the type checker so the compiler enforces unique ownership and can skip RC operations. Ensure Perceus recognizes the linear qualification and elides all inc/dec on linear HAMT nodes.

**Phase 5: REPL JIT Support (1 day)**

Ensure HAMT operations work correctly in the REPL JIT. This means the C runtime functions for HAMT must be available as extern symbols in each JIT compilation unit, and the type environment must correctly resolve Map/Set/PersistentVector types for polymorphic operations.

**5.3 Testing Strategy**

  --------------------- ----------- --------------------------------------------------------------------------------
  **Test Category**     **Count**   **What It Covers**
  Unit tests (Map)      \~40        Insert, lookup, remove, collision handling, iteration order
  Unit tests (Set)      \~20        Union, intersection, difference, subset, membership
  Unit tests (Vector)   \~25        Get, set, push, pop, tail buffer transitions
  Property tests        \~15        Round-trip (insert then lookup), persistence (old version unchanged), ordering
  Stress tests          \~5         1M+ entries, collision-heavy workloads, sequential push to 10M
  REPL tests            \~10        Map/Set/Vector operations in JIT context, cross-line persistence
  Benchmark             3           Lookup throughput, insert throughput, iteration throughput vs List
  --------------------- ----------- --------------------------------------------------------------------------------

**6. Actor Integration**

March's actor model has a critical property for HAMT performance: actors own share-nothing heaps. A Map held by an actor is guaranteed to be in that actor's arena, with no cross-actor references. This means:

-   Actor-local Maps are always uniquely owned (RC = 1), so FBIP always fires. An actor maintaining a Map of sessions, connections, or cached values gets mutable-map performance with persistent-map semantics.

-   Sending a Map in a message transfers ownership via linear capability. The sender loses the reference; the receiver gets a uniquely-owned copy. No deep cloning required.

-   Per-actor bump allocation means HAMT node allocation is a pointer increment, not a malloc. Combined with FBIP reuse, most HAMT operations in an actor context allocate nothing.

This is the payoff of March's layered memory design: the HAMT doesn't need to be a special case. The same persistent data structure that provides safe sharing in the general case automatically becomes a zero-allocation mutable structure inside actors, purely from the ownership and memory model.

**7. Alternatives Considered**

**7.1 Red-Black Tree**

A balanced BST (red-black tree or AVL) gives O(log2 n) operations with simpler implementation. For a million entries, this means \~20 comparisons per lookup versus \~4 for a HAMT. The constant factors also differ: BST nodes are cache-unfriendly (2 pointers + key + value + color = \~48 bytes scattered across heap), while HAMT nodes pack 32 children into a contiguous array.

Red-black trees remain a viable fallback if HAMT implementation proves too complex. However, the HAMT also powers the persistent vector, which a BST cannot. Building the HAMT solves both Map and Vector needs.

**7.2 B-Tree**

Cache-oblivious B-trees offer excellent cache behavior but are designed for mutable, in-place data structures. Making them persistent requires full path copying of wide nodes, which is more expensive than HAMT path copies because B-tree nodes are larger and denser. HAMTs are the standard persistent wide-tree design for a reason.

**7.3 Ctrie (Concurrent Trie)**

Ctries extend HAMTs with compare-and-swap for lock-free concurrent access. March doesn't need this because actors provide concurrency isolation. A single-writer HAMT with Perceus RC is strictly simpler and faster than a Ctrie, and March's ownership model ensures there is always at most one writer.

**8. Risks and Mitigations**

  ----------------------------------------- ---------------------------- ---------------- ----------------------------------------------------------------------------
  **Risk**                                  **Impact**                   **Likelihood**   **Mitigation**
  HAMT complexity exceeds estimate          Schedule slip                Medium           Red-black tree as fallback for Map; Vector deferred
  Perceus FBIP doesn't fire on path nodes   Performance regression       Low              Explicit test: insert N times, measure allocations; tune Perceus analysis
  Hash collision rate too high              Degraded O(n) pockets        Low              SipHash-1-3 has strong distribution; monitor collision stats in benchmarks
  REPL JIT extern resolution fails          HAMT broken in REPL          Medium           Same pattern as existing stdlib; extern\_fns parameter already proven
  Linear HAMT type-checking edge cases      Type errors or unsoundness   Medium           Implement linear variants last (Phase 4); extensive property tests
  ----------------------------------------- ---------------------------- ---------------- ----------------------------------------------------------------------------

**9. Timeline**

  ----------- ------------------------------------------------ -------------- -----------------------------------
  **Phase**   **Work**                                         **Duration**   **Dependencies**
  Phase 1     Core HAMT engine (C runtime + March wrapper)     5 days         Hash/Eq interfaces
  Phase 2     Map(k, v) and Set(a) API                         3 days         Phase 1
  Phase 3     PersistentVector(a) with tail optimization       3 days         Phase 1
  Phase 4     Linear type integration (insert!, set!, push!)   2 days         Phase 2--3 + linear types working
  Phase 5     REPL JIT support                                 1 day          Phase 2--3
  Total                                                        14 days        
  ----------- ------------------------------------------------ -------------- -----------------------------------

Phases 2 and 3 can proceed in parallel after Phase 1 completes. Phase 5 can start as soon as either Phase 2 or 3 is done. The critical path is Phase 1 → Phase 2 → Phase 4 at 10 days.

**10. Success Criteria**

-   Map.get on 1M entries completes in under 200ns average (benchmark against Clojure's PersistentHashMap and OCaml's Hashtbl)

-   PersistentVector.push 10M elements completes without stack overflow or segfault, in both compiled and REPL modes

-   Linear Map.insert! on 1M entries allocates zero bytes (verified via allocation counter in runtime)

-   All existing 529+ tests continue to pass

-   Map, Set, and PersistentVector work identically in compiled mode, interpreter mode, and REPL JIT

-   The HAMT engine is pure C with no external dependencies, keeping the runtime minimal
