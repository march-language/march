# Stdlib laws, second pass: Tuple, Duration, Queue, Deque (2026-11-16)

Landed on `claude/stdlib-laws-wave2` (built on the laws pass, #1273, and the Math Float laws).

## Why

A `--law-coverage` sweep of all 140 stdlib modules found laws in four: `List`, `Math`,
`Session.Theory` and `Actor.Theory`. Every other module was at 0. This pass takes the small value
types and data structures whose laws are both provable today and useful to callers.

## What

23 proved lemmas, admitted from `stdlib/lemmas.verified` (128):

- `Tuple` (6): `swap_swap`, `first_swap`, `second_swap`, `first_second_make`, `len_to_list`,
  `len_zip`.
- `Duration` (7): `to_milliseconds_add`, `add_comm`, `add_assoc`, `subtract_add`, `unit_steps`,
  `compare_antisym`, `compare_zero`.
- `Queue` (7): `size_to_list`, `size_push_back`, `size_push_front`, `is_empty_size`, and the
  helper lemmas `len_rev`, `list_len_len`, `len_list_append` over its private loops.
- `Deque` (3): `size_push_front`, `size_push_back`, `is_empty_size`.

Each module checks cold with 0 skipped obligations and 0 unenforced refinements. No function body
changed.

## Tests

`test/test_refine_stdlib_list.ml`, group `reflect-stdlib-wave2-laws` (3): `Queue.size_push_back`
gives a caller the size fact and the caller does not get it without the call; `Deque` and
`Duration` laws are accepted at a caller.

## Not done

- `Deque.singleton`'s size: `singleton` is predicate vocabulary, so the function never reflects
  (checker-gaps todo, item 11).
- `Tuple.len_zip` at a caller: a list of tuples does not translate at a call site (item 12).
- Order laws for `Queue`/`Deque` (`to_list(push_front(q, x))`): stated with a `Cons` literal they
  draw `predicate_eq_structural`, and `Deque.to_list` calls `List`, which the coverage audit
  counts as unenforced in a theorem (item 6).
- `Enum` and `Sort`: their uncovered functions loop in nested helpers (nested-loop todo).
