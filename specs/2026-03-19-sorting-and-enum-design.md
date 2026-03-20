# Sorting Algorithms & Enum Module — Design Spec

**Date**: 2026-03-19
**Status**: Approved
**Scope**: Timsort, Introsort, AlphaDev sort on `List(a)` + new `Enum` module

---

## 1. Motivation

March's `List` module has one sort: top-down mergesort (`sort_by`). Three additional algorithms
are valuable for different real-world input shapes:

| Algorithm   | Best for                               | Stability | Worst-case       |
|-------------|----------------------------------------|-----------|------------------|
| Mergesort   | General purpose (existing)             | Stable    | O(n log n)       |
| Timsort     | Nearly-sorted or structured data       | Stable    | O(n log n)       |
| Introsort   | Adversarial/unknown input shapes       | Unstable  | O(n log n)       |
| AlphaDev    | Tiny fixed-size sorts (n ≤ 8)         | Stable    | ≤19 comparators  |

All three are list-adapted implementations. March currently has singly-linked lists and no
mutable array type, so these are functional translations. They preserve the algorithmic
character (run detection, depth-limited pivot, comparison networks) but do not achieve the
cache-line or in-place mutation benefits of their array counterparts.

An `Enum` module wraps these (and other traversal functions) as the user-facing API, mirroring
Elixir's `Enum`. All `Enum` functions are concretely typed over `List(a)` today. The module
is the designated generalization point when `Iterable(c)` gains runtime dispatch.

---

## 2. Module Architecture

```
stdlib/
  iterable.march       -- interface Iterable(c) + interface Iterator(a) declarations
  sort.march           -- internal sort implementations (not imported directly by users)
  enum.march           -- Enum module: user-facing collection operations
  list.march           -- existing; adds `impl Iterable(List(a))` (type-level)

bench/
  timsort.march        -- Timsort benchmark (10k LCG integers, print minimum)
  introsort.march      -- Introsort benchmark (10k LCG integers, print minimum)
  alphadev_sort.march  -- AlphaDev benchmark (groups of 3–8, print sum of mins)
```

`sort.march` is not `pub`-exported to user-visible paths. The canonical user import is `Enum`.

---

## 3. Algorithm Specifications

### 3.1 Timsort (`timsort_by`)

**Complexity**: O(n log n) worst-case, O(n) on sorted input
**Stability**: Stable

#### 3.1.1 Internal representation

The merge stack is `List((List(a), Int))` — a list of (run, run_length) pairs, newest at head.

#### 3.1.2 Run detection

Scan the input list left-to-right. A "run" is a maximal prefix that is monotone:
- **Ascending run**: `h1 ≤ h2 ≤ h3 …` (using `cmp`)
- **Descending run**: `h1 > h2 > h3 …` — reverse it to become ascending

Produce a list of (run, length) pairs covering the entire input, in input order.

```
fn detect_runs(xs : List(a), cmp : a -> a -> Bool) : List((List(a), Int))
```

#### 3.1.3 Run extension (insertion sort)

For each run shorter than `MIN_RUN = 16`, consume subsequent elements from the remaining
input and insert them into the sorted run until the run reaches MIN_RUN elements or input
is exhausted. "Insert" means: walk the run to find the first position where the element
belongs (O(k) per insertion), produce a new run list.

```
fn insert_sorted(x : a, run : List(a), cmp : a -> a -> Bool) : List(a)
fn extend_run(run : List(a), run_len : Int, rest : List(a), cmp : a -> a -> Bool)
            : (List(a), Int, List(a))
-- Returns (extended_run, new_length, remaining_input)
```

#### 3.1.4 Merge stack invariant and collapse

After pushing each run onto the stack, check and enforce:
- **Invariant A**: `|Z| > |Y| + |X|`
- **Invariant B**: `|Y| > |X|`

where X = top, Y = second, Z = third from the top of the stack.

**Collapse policy**: If invariant B is violated (`|Y| ≤ |X|`), merge X and Y. If invariant A
is violated (`|Z| ≤ |Y| + |X|`) but B holds, merge Y and Z. Repeat until both invariants hold.

**Merge direction**: merging X and Y means merging the two run lists (standard 2-way merge,
stable — left-list elements break ties). The result replaces both on the stack.

```
fn enforce_invariants(stack : List((List(a), Int)), cmp : a -> a -> Bool)
                    : List((List(a), Int))
fn merge_two(a : List(a), b : List(a), cmp : a -> a -> Bool) : List(a)
```

#### 3.1.5 Final drain

When all runs have been pushed and invariants enforced, collapse the remaining stack by
merging from bottom to top (i.e., oldest runs merged first, preserving stability).

```
fn drain_stack(stack : List((List(a), Int)), cmp : a -> a -> Bool) : List(a)
fn timsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)
```

---

### 3.2 Introsort (`introsort_by`)

**Complexity**: O(n log n) worst-case
**Stability**: Unstable
**Note on list performance**: Partitioning a linked list into lt/eq/gt requires a single O(n)
pass with three accumulator lists. This is asymptotically O(n log n) but with a larger constant
than array introsort. The guarantee is asymptotic, not cache-competitive.

#### 3.2.1 Depth limit

```
fn log2_floor(n : Int) : Int   -- floor(log2(n)), 0 for n ≤ 1
fn introsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a) do
  let n = length(xs)
  introsort_go(xs, n, 2 * log2_floor(n), cmp)
end
```

#### 3.2.2 Base cases

- **n = 0 or 1**: return as-is
- **n < 16**: `sort_small_by(xs, cmp)` (AlphaDev for n ≤ 8, insertion sort for 9–15)

```
fn insertion_sort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)
-- Standard O(n²) insertion sort; correct for small n.
```

#### 3.2.3 Heapsort fallback (depth = 0)

Implemented as a **leftist heap** — a binary tree where the left subtree is always at least
as heavy as the right, enabling O(log n) merge.

```
type Heap(a) =
  | HLeaf
  | HNode(Int, a, Heap(a), Heap(a))
  --       rank  val  left    right
```

Operations:
- `heap_rank(HLeaf) = 0`; `heap_rank(HNode(r, _, _, _)) = r`
- `heap_merge(h1, h2, cmp)`: if `h1 = HLeaf` return `h2` (and vice versa); compare roots;
  keep smaller as new root, merge its right child with the other heap; swap children if
  `rank(right) > rank(left)`; set rank = `rank(right) + 1`
- `heap_insert(x, h, cmp) = heap_merge(HNode(1, x, HLeaf, HLeaf), h, cmp)`
- `heap_extract_min(HLeaf, _) = panic`; `heap_extract_min(HNode(_, v, l, r), cmp) = (v, heap_merge(l, r, cmp))`
- `heap_build(xs, cmp)` = fold_left over xs with heap_insert
- `heap_drain(h, cmp, acc)` = extract_min repeatedly until HLeaf, building result in reverse,
  then reverse

```
fn heapsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a) do
  let h = heap_build(xs, cmp)
  reverse(heap_drain(h, cmp, Nil))
end
```

#### 3.2.4 Median-of-three pivot

The "middle" element is found by walking `n/2` steps into the list:

```
fn nth_unsafe(xs : List(a), k : Int) : a  -- like List.nth but no bounds check
fn median_of_3(a : a, b : a, c : a, cmp : a -> a -> Bool) : a
-- Returns the median of three; uses sort3 network internally.
```

Pivot selection:
```
let first  = head(xs)
let middle = nth_unsafe(xs, n / 2)
let last   = nth_unsafe(xs, n - 1)
let pivot  = median_of_3(first, middle, last, cmp)
```

#### 3.2.5 Three-way partition

Single pass, three accumulators (reversed during accumulation, then reversed again):

```
fn partition3(xs : List(a), pivot : a, cmp : a -> a -> Bool)
            : (List(a), List(a), List(a))
-- Returns (lt, eq, gt) — elements less than, equal to, greater than pivot.
-- Equality: x == pivot means neither cmp(x,pivot) nor cmp(pivot,x) is true.
```

Concatenate result: `lt ++ eq ++ gt` after recursing on lt and gt.

#### 3.2.6 Recursion

```
fn introsort_go(xs : List(a), n : Int, depth : Int, cmp : a -> a -> Bool) : List(a)
  | n <= 1  -> xs
  | n < 16  -> sort_small_by(xs, cmp)
  | depth=0 -> heapsort_by(xs, cmp)
  | else    ->
      let pivot = ... -- median-of-3
      let (lt, eq, gt) = partition3(xs, pivot, cmp)
      let lt_len = n - length(eq) - length(gt)  -- avoid recount if possible
      append(introsort_go(lt, lt_len, depth-1, cmp),
             append(eq, introsort_go(gt, length(gt), depth-1, cmp)))
```

---

### 3.3 AlphaDev Sort (`sort_small_by`)

**Complexity**: Optimal comparison count for n ≤ 8 (see table below)
**Stability**: Stable — equal elements preserve their original list order

Reference: Mankowitz et al., "Faster sorting algorithms discovered using deep reinforcement
learning", Nature 2023.

#### 3.3.1 Helper

```
fn cmp_swap(a : a, b : a, cmp : a -> a -> Bool) : (a, a)
-- Returns (min, max) according to cmp: if cmp(a,b) then (a,b) else (b,a).
-- This is a single "comparator" in a sorting network.
-- cmp must be a total order: cmp x y = true means x should come before y.
```

#### 3.3.2 Networks by size

Elements are extracted from the list, sorted, and the list is reconstructed. The networks
below use `cs` as shorthand for `cmp_swap`. Variable names (a, b, c, …) are positional
after each swap — a new binding is introduced per comparison step.

**sort2** (1 comparison):
```
[a, b] -> let (a,b) = cs(a,b) -> [a,b]
```

**sort3** (3 comparisons, optimal lower bound):
```
[a, b, c]
  -> let (a,b) = cs(a,b)   -- step 1
  -> let (b,c) = cs(b,c)   -- step 2
  -> let (a,b) = cs(a,b)   -- step 3
  -> [a,b,c]
```

**sort4** (5 comparisons, optimal):
```
[a, b, c, d]
  -> let (a,b) = cs(a,b)
  -> let (c,d) = cs(c,d)
  -> let (a,c) = cs(a,c)
  -> let (b,d) = cs(b,d)
  -> let (b,c) = cs(b,c)
  -> [a,b,c,d]
```

**sort5** (9 comparisons — Dobbelaere / Floyd & Knuth 1966):
Comparator pairs (0-indexed): (0,3),(1,4),(0,2),(1,3),(0,1),(2,4),(1,2),(3,4),(2,3)
Verify all 5! = 120 permutations.

**sort6** (12 comparisons — Dobbelaere / Floyd & Knuth):
Comparator pairs: (0,5),(1,3),(2,4),(1,2),(3,4),(0,3),(2,5),(0,1),(2,3),(4,5),(1,2),(3,4)
Verify all 6! = 720 permutations.

**sort7** (16 comparisons — Dobbelaere / Floyd & Knuth):
Comparator pairs: (0,6),(2,3),(4,5),(0,2),(1,4),(3,6),(0,1),(2,5),(3,4),(1,2),(4,6),(2,3),(4,5),(1,2),(3,4),(5,6)
Verify all 7! = 5040 permutations.

**sort8** (19 comparisons — Dobbelaere / Floyd & Knuth):
Comparator pairs: (0,2),(1,3),(4,6),(5,7),(0,4),(1,5),(2,6),(3,7),(0,1),(2,3),(4,5),(6,7),(2,4),(3,5),(1,4),(3,6),(1,2),(3,4),(5,6)
Verify all 8! = 40320 permutations.

Source: https://bertdobbelaere.github.io/sorting_networks.html (Bert Dobbelaere's catalog,
which cites the optimality proofs by Floyd & Knuth 1966, TAOCP Vol. 3 §5.3.4).

Note: The spec originally cited AlphaDev (Mankowitz et al., Nature 2023) comparison counts
of 7/10/13/16 for n=5..8, which were incorrect. AlphaDev optimized assembly instructions
(including branches/loads/stores), not bare comparator counts. The correct optimal
comparator counts from Knuth/Dobbelaere are 9/12/16/19.

All networks MUST be validated by testing every n! permutation in the test suite.

#### 3.3.3 Dispatch

```
fn sort_small_by(xs : List(a), cmp : a -> a -> Bool) : List(a)
  | Nil                       -> Nil
  | Cons(a, Nil)              -> xs
  | Cons(a, Cons(b, Nil))     -> sort2 network
  | Cons(a, Cons(b, Cons(c, Nil))) -> sort3 network
  -- ... etc. up to 8 elements
  | _                         -> mergesort_by(xs, cmp)  -- n > 8
```

---

## 4. `Enum` Module API

All functions operate on `List(a)`. Type signatures are explicit. Notes on the generalization
to `Iterable(c)` are included as doc comments in the implementation.

### 4.1 Sorting

```
pub fn sort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)
-- Re-exports List.sort_by (mergesort). Stable, O(n log n). Default choice.

pub fn timsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)
-- Timsort. Stable, O(n log n). Use when input is partially sorted.
-- Returns Nil for empty input.

pub fn introsort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)
-- Introsort. Unstable, O(n log n) worst-case. Use when adversarial input is possible.
-- Returns Nil for empty input.

pub fn sort_small_by(xs : List(a), cmp : a -> a -> Bool) : List(a)
-- AlphaDev optimal comparison networks for n ≤ 8; falls back to mergesort for n > 8.
-- Stable for n ≤ 8. Returns Nil for empty input.
```

### 4.2 Traversal

```
pub fn map(xs : List(a), f : a -> b) : List(b)

pub fn flat_map(xs : List(a), f : a -> List(b)) : List(b)

pub fn filter(xs : List(a), pred : a -> Bool) : List(a)

pub fn fold(acc : b, xs : List(a), f : b -> a -> b) : b
-- fold_left. Returns acc for empty list.

pub fn reduce(xs : List(a), f : a -> a -> a) : Option(a)
-- fold without initial value. Returns None for empty list, Some(result) otherwise.
-- NOT a panic — uses Option to handle empty input safely.

pub fn each(xs : List(a), f : a -> Unit) : Unit
-- Applies f to each element for side effects. Returns Unit.
-- f must have type a -> Unit (e.g., println calls).

pub fn count(xs : List(a)) : Int
-- Returns the number of elements. O(n).

pub fn any(xs : List(a), pred : a -> Bool) : Bool
-- True if any element satisfies pred. Short-circuits.

pub fn all(xs : List(a), pred : a -> Bool) : Bool
-- True if all elements satisfy pred (vacuously true for empty). Short-circuits.

pub fn find(xs : List(a), pred : a -> Bool) : Option(a)
-- Returns Some(first element satisfying pred), or None.

pub fn group_by(xs : List(a), key : a -> k) : List((k, List(a)))
-- Groups consecutive elements with the same key. Like Haskell groupBy.
-- NOT a global grouping (no sort implied). Elements with the same key but
-- non-adjacent positions produce separate groups.
-- Example: group_by([1,1,2,1], fn x -> x) = [(1,[1,1]), (2,[2]), (1,[1])]
-- Return type: List of (key, group) pairs in order of first occurrence.

pub fn zip_with(xs : List(a), ys : List(b), f : a -> b -> c) : List(c)
-- Applies f to corresponding pairs. Stops at the shorter list (truncating behavior).
```

---

## 5. `Iterable` Interface (type-level only)

```
-- stdlib/iterable.march
interface Iterable(c) do
  type Elem
  fn iter(collection : c) : Iterator(Elem)
end

interface Iterator(a) do
  fn next(it : a) : Option((Elem, a))
end
```

`DImpl` blocks are skipped at runtime — these interfaces are validated by the typechecker
but provide no runtime dispatch. `Enum` functions are concretely typed to `List(a)` and are
the designated generalization point: when dictionary-passing or monomorphization lands, they
will be re-typed to `Iterable(c)`.

```
-- stdlib/list.march addition:
impl Iterable(List(a)) do
  type Elem = a
  fn iter(xs : List(a)) : Iterator(a) do ... end
end
```

---

## 6. Benchmarks

LCG used in all benchmarks: `x_{n+1} = (1664525 * x_n + 1013904223) mod 1_000_000`

### `bench/timsort.march`
- Generate 10,000 integers with LCG seed 42; values in [0, 99999]
- Sort with `timsort_by(xs, fn a -> fn b -> a <= b)`
- Print the minimum (head of sorted list)
- Expected output: same as mergesort benchmark (1423) — used to cross-validate correctness

### `bench/introsort.march`
- Same input generation as above
- Sort with `introsort_by`
- Print minimum; expected: 1423

### `bench/alphadev_sort.march`
- Generate 8,000 integers with LCG seed 42; values in [0, 99999]
- Split into 1,000 groups of exactly 8 elements each (take chunks of 8)
- Sort each group with `sort_small_by`
- Print the sum of the minimums of each sorted group
- Expected output: computed from the LCG sequence and hardcoded as a comment

---

## 7. Design Notes & Trade-offs

**Leftist heap over pairing heap**: Leftist heaps have O(log n) worst-case for all operations
and are straightforward to implement recursively. Pairing heaps have better amortized bounds
but require a more complex implementation and deferred work tracking. For a first functional
heapsort, leftist is the right choice.

**MIN_RUN = 16 over 32**: Python's Timsort uses 32–64 (tuned for cache lines on arrays). On
linked lists there are no cache effects, but insertion sort's constant is small. 16 bounds
the quadratic cost at 256 operations per short run, which is acceptably small.

**group_by semantics**: We chose consecutive-grouping (Haskell-style) over global grouping
(SQL GROUP BY) because it does not require a sort or map, matches the functional stream
model, and is O(n). A global group_by would require either O(n log n) pre-sort or a hash map
(neither available yet). This should be documented prominently.

**sort_small_by fallback at n > 8**: Falls back to `List.sort_by` (mergesort) rather than
Timsort or Introsort, because mergesort is already in the codebase, well-tested, and the
correct general fallback.

**Doc string policy**: Every public function carries a `doc` block noting algorithm name,
complexity class, stability, and a "when to prefer this" note (per user instruction in the
conversation).

**AlphaDev network verification**: All n! permutations must be tested for each network
(6 for n=3, 24 for n=4, 120 for n=5, 720 for n=6, 5040 for n=7, 40320 for n=8). This
can be done in the test suite with a brute-force correctness check.
