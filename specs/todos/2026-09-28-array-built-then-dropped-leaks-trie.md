# An `Array` built with `from_list` or `push` and then dropped leaks its trie (OPEN, 2026-09-28)

**Filed:** 2026-09-28, found while ASAN-checking the new stable sorts
(specs/progress/2026-09-28-array-sort-by-stable.md). Related to, but not the same
as, `specs/todos/2026-09-06-closure-capture-release-widening.md` (which is about
`Array.set`'s update path).

## Measurement

Linux container (arm64), `MARCH_SANITIZE=1`, `ASAN_OPTIONS=detect_leaks=1`. A
loop that k times builds `Array.from_list(xs)` from the same 1,000-element list
of `(Int, String)` pairs and keeps only its length. The leak that grows with k
is the per-build leak:

| stdlib | k = 1 | k = 5 | per build |
|---|---:|---:|---:|
| origin/main (`from_list` = n pushes) | 3,626 allocs | 10,194 allocs | ~1,642 allocs (~1.6 per element, ~50 KB) |
| bulk `from_list` (2026-09-28) | 4,128 allocs | 12,604 allocs | ~2,119 allocs (~2.1 per element, ~67 KB) |

LSan's allocation sites are the trie itself: `Array.push` / `push_leaf` /
`descend` / `insert` on origin/main; `from_list` / `up` / `chunk` (the bulk
builder's leaf and branch lists and its `(front, tail)` / `(root, shift)` pairs)
with the bulk builder. So the dropped `PVec` does not release its root, leaves or
tail; the bulk builder only leaks a different mix of the same structure. There
is no memory error (0 ASAN errors in both), and the sort builtins
(`list_stable_sort_by`, `list_sort_by_int_key`) add no leak of their own beyond
the second `Array` a sort builds.

## Next step

Find why dropping a `PVec(a)` (a `ptype` holding `TrieNode(a)` and `List(a)`)
does not recurse: check the generated `__drop$PVec_…` / `__drop$TrieNode_…` in
`--dump-tir`, and whether the `let (a, b) = pfn(...)` destructuring in the
builders drops the pair. Witness with the loop above (leak per build must reach 0).
