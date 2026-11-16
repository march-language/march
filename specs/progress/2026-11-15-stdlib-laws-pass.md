# Stdlib laws pass: List accessors, Option, Result, Math (2026-11-15)

Landed 2026-11-15 on `claude/stdlib-laws-pass`.

## Why

`march --check --law-coverage` on the pure stdlib modules showed most of their pure functions
had no law at all: `Option` 0 of 6, `Result` 0 of 5, `Math` 0 of 13, `Range` 0 of 4, and
`List` 12 of 24 (all of them about `append`/`reverse`/`take`/`drop`/`sum`/`product`). A law
lets a caller's contract be proved where one unfolding is not enough, and `forge doc` lists it
on the function's page.

## What

16 new `@[lemma]`s, all proved on a cold check (fresh `HOME`, no VC cache) and admitted from
`stdlib/lemmas.verified` (100 lemmas now):

- `List`: `is_empty_len`, `head_opt_nth_opt`, `head_opt_append`, `reverse_onto_single`,
  `drop_last_snoc` (`drop_last(append(xs, [x])) == xs`), `len_drop_last`.
- `Option`: `is_none_not_some`, `zip_is_some`, `len_to_list`, `to_list_is_some`.
- `Result`: `is_err_not_ok`.
- `Math`: `min_int_comm`, `max_int_comm`, `min_plus_max`, `clamp_int_within`, `clamp_int_idem`.

Coverage after (`--law-coverage`): `List` 15 of 24, `Option` 4 of 6, `Result` 2 of 5, `Math` 3 of
13 (the rest are Float functions and constants). No function body changed; lemmas are erased
before compilation, so nothing runs differently. Each changed module checks with 0 skipped
obligations and 0 unenforced refinements (`--refine-report --refine-audit`).

## Tests

`test/test_refine_stdlib_list.ml`, group `reflect-stdlib-laws` (5 cases): a caller gets
`drop_last_snoc`, `len_drop_last` and `zip_is_some`'s facts with the lemma call and not
without it; `len_to_list`'s and `clamp_int_idem`'s calls are accepted at a caller (those facts
also hold by unfolding there). The manifest-admission case in `reflect-stdlib-list` now lists the six new
`List` lemmas. `scripts/gen-lemma-manifest.sh --check` is fresh.

## Not done, and why

- **Result-type refinements instead of lemmas** (`is_some : {Bool | _ == is_Some(opt)}`,
  `to_list : {List(a) | len(_) <= 1}`, …) were tried first. None is in the checker's
  fragment for a generic `Option`/`Result` parameter (`unreflectable-predicate` /
  `unreflectable-subject`), and `Option`/`Result` are `cap verified`, so they were reverted.
  Filed as `todos/2026-11-15-refine-checker-gaps-from-stdlib-laws.md`.
- **Higher-order functions** (`map`, `filter`, `fold_left`, `Option.map`, …): a lemma cannot take
  a function parameter yet.
- **`zip`, `unzip`, `enumerate`, `concat`, `split_at`** loop in a nested `go`, which a lemma
  cannot name; each needs its loop lifted to a top-level `pfn` first, as `take_onto` was.
  Filed as `todos/2026-11-15-stdlib-laws-nested-loop-functions.md`.
- **Eight laws written and then dropped.** `Option.unwrap_or_none` and `Result.unwrap_or_err`
  (the generic `unwrap_or(x, d) == d` shape) fail the `cap verified` stdlib sweep, although a
  single-file check had reported them proved. `Result.to_option_is_some`, `Result.to_option_to_result`,
  `Math.checked_div_is_some`, `Math.checked_mod_is_some`, `Range.is_empty_first` and
  `Range.first_last_some` prove only when the theorem calls another module (`Option.is_some`,
  `Option.to_result`), and the refinement coverage audit then reports each as an unenforced
  declared refinement, which the audit baseline's zero ceiling forbids; restated with a tag test
  (`is_Some(checked_div(a, b))`) they do not prove. Both are in the checker-gaps todo.
- **A `List` law stated with `==` on an `Option` built from a constructor literal**
  (`tail_opt(xs) == Some(drop(xs, 1))`) draws `predicate_eq_structural`; dropped rather than
  ship a warning.
