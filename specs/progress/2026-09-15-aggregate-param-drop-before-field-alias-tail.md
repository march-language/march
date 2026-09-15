# Owned aggregate param dropped before a tail that borrows its field

Shipped 2026-09-15.

## Symptom

```march
mod T3 do
  needs IO
  fn icmp(a : Int, b : Int) : Int do a - b end
  fn main(cap : Cap(IO)) do
    let s = SortedSet.add(SortedSet.add(SortedSet.add(SortedSet.new(icmp), 5), 3), 9)
    println(int_to_string(SortedSet.size(s)))
  end
end
```

Compiled (any `--opt`): `panic: non-exhaustive pattern match`. Interpreted: `3`.
`SortedSet.size(SortedSet.new(icmp))` alone was enough. Adding
`SortedSet.to_list(s)` / `SortedSet.member(s, 7)` after the `size` call "fixed"
it, which made it look like a mono/defun/DCE reachability bug. It wasn't.
Those later uses of `s` made `main` pass `s` to `size` with an `inc_rc`, so
`size`'s early release no longer took the refcount to zero.

## Root cause

`Perceus.insert_owned_aggregate_param_drops` (`lib/tir/perceus.ml`) releases
an owned record/tuple parameter by pushing `dec_rc p` ahead of every tail
expression, so a self tail call stays a tail call. It rebound the tail first
(`let tmp = tail in dec_rc p; tmp`) only when the tail mentioned `p` itself.
`SortedSet.size` lowers to

```
let $t = s.tree in SortedSet.tree_size($t)
```

`$t` is a borrowed-field var: it points into `s` and owns no reference. Perceus
dups one only at a consuming use, and `tree_size` only matches on its argument,
so it is inferred borrowing and `$t` got no dup. The pass produced

```
let $t = s.tree in dec_rc s; tree_size($t)
```

With `s` unique, the drop (`__drop$R2_cmp$Fn_tree$Tree_Int`) freed the tree, and
`tree_size` then read a freed `Leaf`/`Node` tag. `member`/`to_list` were already
safe: their callees consume the field, so Perceus emitted `inc_rc $t` before
the drop.

## Fix

`push` now carries the set of heap values on the current path that alias into
a candidate parameter without owning a reference:

- a `needs_rc` let bound to a projection of a candidate or alias (also
  through a nested let/seq RHS)
- an atom alias of one
- the `needs_rc` pattern vars of an `ECase` whose scrutinee is a candidate
  or alias

An `inc_rc`/`atomic_inc_rc` of an alias on the path removes it, since it is
independently owned again. A tail that mentions a remaining alias is rebound
before the drop, the same as a tail that reads the parameter. Non-RC
projections (`s.n : Int`) are never aliases, so `loop(s.n - 1)`-style tail
calls keep their drop-before-call shape.

Effect on the stdlib: `SortedSet.size` becomes
`let r = tree_size($t) in dec_rc s; r`. `member`/`to_list` are unchanged. The
TIR snapshot corpus is unchanged.

## Test

`test/native/aggregate_param_field_alias.march` (dune rule
`native_aggregate_param_field_alias`, with `(source_tree ../stdlib)`) covers:

- `SortedSet.size` on uniquely-held sets
- the three user-code alias shapes: a direct field alias, a pattern var bound
  from one, and a projection of a projection, each passed to a borrowing
  `count`

Each shape panics with the pre-fix compiler when isolated in its own program,
and passes after. Note that a helper that *consumes* the field (e.g. one that
conses it into a worklist) is inferred owning and gets a dup, so it does not
reproduce.
