# Stdlib lemma sweep, phase S2: the accumulator loops lifted (2026-11-06)

Design: `specs/2026-11-04-stdlib-lemma-sweep-design.md` §3 "S2". Phase S1 is
`specs/progress/2026-11-04-stdlib-lemma-sweep-s1.md`. The open phase S3 is
`specs/todos/2026-11-04-stdlib-lemma-sweep-s3.md`.

## What shipped

- **The loops of `List.length`, `sum_int`, `product_int`, `minimum_int` and `maximum_int` are
  top-level `pfn`s:** `length_onto`, `sum_onto`, `product_onto`, `min_onto`, `max_onto`. Each
  replaces a local `go` and computes the same thing.
- **`List.length : {Int | _ == len(xs)}`**, proved through the lemma `len_length_onto`
  (`length_onto(xs, acc) == len(xs) + acc`), which `length` calls.
- **Eleven lemmas in `stdlib/list.march`, admitted by `stdlib/lemmas.verified` (now 28 entries):**
  - `len_length_onto`;
  - `sum_onto_shift`: `sum_onto(xs, acc) == sum_onto(xs, 0) + acc`;
  - `sum_onto_append`: `sum_onto(append(xs, ys), acc) == sum_onto(ys, sum_onto(xs, acc))`;
  - `sum_onto_reverse_onto`: `sum_onto(reverse_onto(xs, rest), acc) == sum_onto(xs, sum_onto(rest, acc))`;
  - `sum_int_append`: `sum_int(append(xs, ys)) == sum_int(xs) + sum_int(ys)`;
  - `sum_int_reverse`: `sum_int(reverse(xs)) == sum_int(xs)`;
  - `product_onto_shift`, `product_onto_append`, `product_onto_reverse_onto`,
    `product_int_append` and `product_int_reverse`: the same five for products, with `*` and 1.

## Rulings

1. **`length`'s result type is proved through a lemma, not on `length_onto`.** The plan was
   `pfn length_onto(...) : {Int | _ == len(lst) + acc}`. That is `solver-undecided`: a scalar
   return of a self-call gets no induction hypothesis
   (`specs/todos/2026-10-18-refine-scalar-accumulator-recursion.md`; even
   `fn cnt(lst) : {Int | _ == len(lst)}` with `1 + cnt(t)` does not prove). A `Unit` lemma does
   get one, so `len_length_onto` states the law and `length` calls it. The call is erased; the
   IR of `length` is the same as without it.
2. **`minimum_int` and `maximum_int` are lifted with no law.** The todo listed them with the
   others. Their natural laws (`minimum_int(xs) <= x` for each element of `xs`) need a
   quantifier. They are lifted so the five loops look alike and a later law can name them.
3. **`product_onto_reverse_onto` spells out its step with two `assert`s.** Its step is
   `p * (acc * h) == (p * acc) * h` under a call to `product_onto`, which is nonlinear. Without
   the asserts its postcondition is a `reflect-fuel` skip; with them it proves. The `sum`
   version needs no help.
4. **`List.length` already proved at a caller.** `List.length(xs) == len(xs)` was already proved
   through the measure alias (`list_length_is_stdlib`). The sweep case for the result type pins
   that, and is not RED before the change. The other four law cases are.
5. **The lift is not IR-neutral, as in phase 3.** ir-oracle: 175 of 520 programs changed.
   - 71 are identical after normalising line numbers (the `.fnt` table, panic and overflow
     locations: `list.march` grew three lines above most functions).
   - The other 104 replace the static closure `$Clo_go$0_List_length_…` (100 programs) or
     `$Clo_go$0_List_sum_int` (4) with a direct call to `List.length_onto` or `List.sum_onto`.
     Every one was checked by script: a `go` closure of one of the five functions in the base,
     its `_onto` function in the new IR, and no `go` closure of the five left.
   - The old `go` took its accumulator as a boxed `ptr`; `length_onto` and `sum_onto` take an
     unboxed `i64`.

6. **Two tests pinned the old shape; both now accept the new one, and neither was weakened past
   its property.**
   - `run_eval` perceus 14 (`List.length` then `List.nth`) asserted an `EIncRC` in the caller,
     because the old `go` closure owned the list (6 RC ops). `List.length_onto` borrows it
     (0 RC ops), so the caller needs no inc (`check` goes from 2 RC ops to 1). The test now
     accepts either "the caller incs" or "`List.length` and its loop release nothing". The
     program prints `pass` compiled at `--opt 0` and `--opt 2` under `MARCH_SANITIZE=1`, and
     interpreted.
   - `reflect-unfold` 48 (`two_stage_identical`) asserted every reflection-off query is sent
     byte for byte by the reflection-on run. `List.pmap_n`'s `let n = length(xs)` now carries
     `n == len(xs)` in the on run only: with `MARCH_REFLECT=0`, `length`'s postcondition is an
     `unreflectable-subject` skip, since it rests on a lemma. The on query is the off query
     plus `(declare-const len$xs Int)`, `(assert (= n len$xs))` and `(assert (>= len$xs 0))`.
     The test now also accepts an on query that has every line of the off query, in order, plus
     only `declare-const` / `assert` lines (`only_adds_facts`); dropped or rewritten text still
     fails.
7. **The erased lemma call leaves `()` in `length`'s body.** `--dump-phases` marks `List.length`
   "not inline-eligible (side-effects)" because of that `ESeq`; the real inliner still inlines it
   (the final TIR of a caller has `length_onto` called directly), and ir-oracle shows no codegen
   change beyond the lift. Left as is.

## Verification

| Check | Result |
|---|---|
| `reflect-stdlib-sweep`, 7 new cases (each law with and without its lemma, `length`'s type at a caller, a REJECT control asserting a false sum after `sum_int_append`, manifest admission of the 11 lemmas) | 15/15 |
| RED: the new cases before the stdlib change | the four law cases and manifest admission fail; `length` (ruling 4) and the REJECT control pass |
| The new lemmas proved from scratch (`MARCH_LEMMA_MANIFEST=/dev/null`) | all `proved` |
| refine-oracle vs main `8a4065e02` | 571 of 574 programs: `+1 proved, +11 trusted` in `user + stdlib` (`length`'s result type, the lemmas). No `user code` total moved except `stdlib_list` (58/7 → 77/9). The other two: `native_entry_module_named_list` (+6 proved, +11 trusted, −5 skipped) and `native_owned_call_drop_fusion` (+3 proved, +10 trusted), the same two that differed in phase 3 |
| `audit-baseline`, regenerated | +12 enforced on every `user + stdlib` slice (240 → 252); `stdlib_list`'s `user code` 55 → 67 |
| CI `conformance` skip ceiling (`--check --stdlib-source --refine-report stdlib/list.march`) | 167 proved / 47 skipped → 186 / 49. The two new skip rows are `sum_int_reverse` and `product_int_reverse` (`unreflectable-predicate`: checked as user code, `reverse` is ambiguous, as for `len_reverse` and `take_drop`). Ceiling raised 47 → 49 in `ci.yml`, attributed in its comment |
| `run_eval`, `run_compiler`, `run_codegen`, `run_stdlib`, `test_stdlib_march` (full, incl. Slow) | all pass after ruling 6 (perceus 14 failed before it) |
| refinecheck groups `reflect-stdlib-list`, `reflect-stdlib-sweep`, `law-coverage`, `reflect-infer-lemma`, `reflect-lemma`, `reflect-fuel`, `reflect-unfold` | 219 pass after ruling 6 (`reflect-unfold` 48 failed before it) |
| `scripts/gen-lemma-manifest.sh --check` | fresh |
| `@types-check` conformance corpus | 492 passed, 0 failed |
| doc-lint | passes |
| TIR golden snapshots (`run_snapshots`), regenerated | 5 programs change at both stages (`trmc_modulo_cons`, `trmc_computed_arg_nested`, `nested_cons_ctor_heap`, `tuple_param_borrowed_destruct`, `record_field_tail_projection`): the `$Clo_go$0_List_*` closures go and the `_onto` functions appear, called directly. `trmc_modulo_cons`'s metrics: allocations 15 → 11 and decrements 55 → 24 after Perceus. Increments rise 2 → 8, all `inc_rc` on Int binders the snapshot still types `'_` (a no-op once types are known) |
| `bench/list_ops.march`, `--opt 2` | same output, same binary size (270936), times within noise (0.02–0.04 s both) |
| A micro-benchmark of `length`, `sum_int`, `product_int` and `maximum_int` over a 100 000-element list, 300 rounds, `--opt 2` | same output; base 0.31–0.43 s, new 0.21–0.37 s (load average 15) |
