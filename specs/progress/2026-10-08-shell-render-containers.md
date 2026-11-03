# Shell: render the remaining stdlib containers by their elements

Logged 2026-10-08. Follows `2026-10-07-shell-render.md`, which left "other
stdlib containers (`HashMap`, `Deque`, `OrderedMap`, ...) are opaque and
print through `to_string`".

## What was wrong

Observed on the shell test node (`test/native/shell_node.march`):

| input | printed |
|---|---|
| a HashMap | `HamtHashMap(HBranch(4128, [HLeaf(100790693, "b", 2), ...]))` |
| an OrderedMap | `{ cmp: <fn>, tree: Node(Node(Leaf, 1, "a", Leaf, 1), ...) }` |
| a SortedSet | `{ cmp: <fn>, tree: AvlNode(...) }` |
| a Deque | `Deque(3, [1], [3, 2])` (its two internal lists) |
| a Queue | `Queue([], [100, 99, 98, … 98 more])` (back list, reversed) |
| an RRB.Vec | `Vec(PVec(2, 0, TrieEmpty, [...]))` |
| a NativeArray | `#<tag:-6>` |

## What the shell does now

`stdlib/shell_render.march` gains one combinator per container. Each goes
through the container's public `to_list`, with the same rules as `list` and
`map`: at most `limit` elements then `… n more`, the limit passed down, and
`limit <= 0` meaning no limit.

| type | combinator | notation |
|---|---|---|
| `HashMap(k, v)` | `hash_map` | `HashMap{k => v, …}` (hash order) |
| OrderedMap (`{cmp, tree: Tree(k, v)}`) | `ordered_map` | `OrderedMap{k => v, …}` (key order) |
| SortedSet (`{cmp, tree: AvlTree(a)}`) | `sorted_set` | `SortedSet{a, …}` |
| `Deque(a)` | `deque` | `Deque[a, …]` (front to back) |
| `Queue(a)` | `queue` | `Queue[a, …]` (front to back) |
| `RRB.Vec(a)` | `rrb_vec` | `RRB.Vec[a, …]` |
| `NativeIntArr` / `NativeFloatArr` / `NativeF32Arr` / `NativeI32Arr` / `NativeU8Arr` | `native_array` (given `NativeArray.to_list_*`) | `NativeArray[x, …]` |

`bin/shell_render_gen.ml` emits these calls by static type.

**Not covered:**
- RingBuf and LinearMap are `always_linear`, and their `to_list` consumes
  the value, so rendering would use it up. They keep `to_string`.
- `TypedArray`, `RRB.Slice`, Seq/Flow (lazy), Hamt and the CRDT and
  ConsistentHash types are internal or not collections.
- `Range` already renders as its record `{ start, stop, step }`.

**Telling the stdlib's type from a program's.** The typechecker's type names
are bare, so a program's own `Deque` or `Vec` would unify with the stdlib's.
Rendering it through `Deque.to_list` would then read it as the wrong type.
`stdlib_type` accepts a name only if nothing else is named so:
- every visible constructor of a type of that name is the stdlib module's;
- the session's type table has no `<OtherModule>.<name>`;
- for a stdlib `ptype` (HashMap, Deque, RRB.Vec), whose constructors are
  hidden and whose name the table does not list, not even the bare name.
  Checked by hand: a node whose program declares `ptype Vec(a)` and
  `type Deque` prints both its own values and the stdlib's through
  `to_string`.

OrderedMap and SortedSet are structural records, so they are recognised by
shape: fields exactly `cmp` and `tree`, with `tree` OrderedMap's `Tree(k, v)`
or SortedSet's `AvlTree(a)`.

## Tests

- `test/stdlib/test_shell_render.march`: 9 new cases (30 in all). They cover
  each combinator, cuts, `limit 0`, an empty Deque and a nested limit. With
  `stdlib/shell_render.march` taken from origin/main by file copy, 9/30 fail.
- `test/shell/session.txt`: 9 new inputs. `test/native/shell_session.expected`
  gains their lines. With `bin/shell_render_gen.ml` taken from origin/main by
  file copy, all 9 lines differ (the internals in the table above).
- The node program is unchanged, so the refine audit baseline is unaffected.
