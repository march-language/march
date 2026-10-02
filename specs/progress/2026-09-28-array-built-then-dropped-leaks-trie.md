# An `Array` built, updated and dropped no longer leaks its trie (fixed 2026-10-01)

Filed 2026-09-28 from the ASAN check of the stable sorts. `Array.from_list` and
`Array.push` leaked the whole trie when the vector was dropped.

## The defect, measured

Compiled `--opt 2`, `live_allocs()` per build/drop on origin/main
(`test/native/array_trie_drop_leak_probe.march`):

| leg | objects leaked |
|---|---|
| `from_list` 5 (tail only) | 2 |
| `from_list` 33 / 40 (one leaf) | 72 |
| `from_list` 1,100 (two levels) | 2,224 |
| `from_list` 40,000 (three levels) | 81,118 |
| `push` 40 | 0 |
| `push` 1,100 | 1,229 |
| `set` at depth 2, `pop` at depth 2, String elements | leak per call |

The todo's guess (`__drop$PVec` does not recurse) was wrong: the generated drop
helpers are correct. Seven defects stacked up, none of them in the drop code:

1. **A forwarded capture was never released** (the `Seq` fix in
   `specs/progress/2026-09-30-seq-constructors-leak-their-closure.md`). Every
   nested `fn` in `array.march` that tail-calls a captured closure leaked it:
   `push` leaked 34 objects per leaf by itself.
2. **Frame tuples of nested polymorphic closures leaked** (`push_leaf`'s
   `ascend`/`descend`, `trie_update`, `pop_leaf`). A local `fn` is lifted to a
   closure that stays polymorphic in the element type, so the frame tuple
   `(children, slot)` it destructures has a type with a variable in it and gets
   only a shallow release; its field references (the old subtree) were never
   dropped. Growing the trie one level leaked all of it. Fixed in the stdlib:
   `trie_update_*`, `insert_*` and `pop_*` are private top-level functions, which
   are monomorphised per element type. The compiler gap is filed as
   `specs/todos/2026-10-01-polymorphic-local-closure-aggregate-drop.md`.
3. **`let (a, b) = f(..)` leaked the pair** (`lib/tir/lower_expr.ml`,
   `lib/tir/perceus_core.ml`). The tuple temp was marked `Lin`, which exempts it
   from Perceus's scope-end aggregate drop, and that drop refused any scope whose
   value it could not type: a scope ending in an `if`/`match`, an infix builtin
   (`+`), or a tuple literal read as "type unknown". `from_list`'s
   `let (front, tail) = lst_split(..)` and every `pop` leaked a cell and the
   references it held. The temp is now `Unr`, `tir_expr_ty` types those tails,
   and the drop is emitted per tail by `drop_agg_at_tails`.
4. **A tail call stays a tail call.** Typing more scopes would have pushed the
   self-call of every loop that destructures a tuple out of tail position (a
   50M-iteration loop overflowed the stack in the first version of this change).
   `drop_agg_at_tails` puts the release in FRONT of a tail call when no argument is
   a borrowed projection of the aggregate, and keeps the post-call release only
   when one is. Checked by hand, not by a fixture: 50M-iteration loops that
   destructure a tuple (top-level, nested `fn`, and a list walk) ran to
   completion with the same output as origin/main, and
   `bench/tree_transform`/`list_ops` were compared.
5. **A nested pattern with a default arm leaked** (`Cons(root, Nil) -> .. | _ ->
   ..`, `Cons(h, Nil)`/`Cons(_, t)` in `lst_last`/`lst_init`,
   `TrieBranch(Cons(c, Nil)) -> .. | _ -> ..` in `pop`). The default arm becomes a
   join-point closure allocated at the head of the matching arm and dropped
   unused and shallowly, leaking what it captured (`from_list` leaked every level
   of nodes it built; every `pop` leaked a list). `from_list`'s `up`,
   `lst_init`, `lst_last` and `pop`'s root collapse are rewritten without a
   default arm. The compiler half is
   `specs/todos/2026-10-01-dead-join-point-closure-leaks-captures.md`.
6. **An `Option(TrieNode)` tuple field got a shallow release** (niche-encoded:
   `Some(x)` is `x`, `None` is null, and `Drop.may_be_non_heap` falls back to a
   bare `dec_rc` for such a field). `pop_leaf` returned `(Option(TrieNode),
   List(a))`, so every pop that crossed a leaf leaked the subtree. It now returns
   the `TrieEmpty` sentinel for "absent". Filed as
   `specs/todos/2026-10-01-niche-option-field-shallow-drop.md`.
7. The trie-root collapse after a pop re-used the matched node whole in one arm,
   which made Perceus dup it up front and never release the dup in the arm that
   took it apart; it is now `has_single_child`/`only_child`.

## Verification

`test/native/array_trie_drop_leak_probe.march` (dune rule, `--opt 2`): `from_list`
at 5, 40, 1,100 and 40,000 elements (tail only, one leaf, past one and past two
trie levels), `push` at 40, 1,100 and 33,000, `set` and `pop` at depth 2, a
String-element vector pushed and popped, and `sort_by_key` building a second
Array. Every leg except `push 40` reads `flat: false` on origin/main; all read
`flat: true` now.

## Still open

See the three todos above. The stdlib restructuring removes every instance in
`array.march`; other nested polymorphic closures and nested patterns with
default arms still leak the same way.
