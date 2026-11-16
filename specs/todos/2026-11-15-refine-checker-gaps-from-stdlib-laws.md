`[P3]` Refinement checker gaps found by the stdlib laws pass (2026-11-15)

Found while adding laws to `Option`, `Result`, `Math` and `List`
(`progress/2026-11-15-stdlib-laws-pass.md`). Each is a shape the checker skips although the
fact is simple; none makes it wrong, so they are P3.

1. **A Bool-valued reflected call as an argument is `unreflectable-subject` from user code.**
   `need_eqb(true, List.is_empty(xs))` and `need_eqb(a, Option.is_some(o))` with
   `need_eqb(a : Bool, b : {Bool | _ == a})` are skipped, while `List`- and `Int`-valued stdlib
   calls in the same position translate. So a caller cannot use `Option.zip_is_some` or
   `Option.is_none_not_some` in a Bool contract; it has to go through a tag test on the
   `Option` (`{Option(T) | is_Some(_)}`).
2. **A nested call in an argument is `unreflectable-subject` where the same call through a
   `let` is not.** `need_eq(xs, List.drop_last(List.append(xs, Cons(x, Nil))))` is skipped;
   `let ys = List.append(xs, Cons(x, Nil))` then `need_eq(xs, List.drop_last(ys))` is proved.
3. **A lemma's postcondition at the end of a `with fuel(f, N) do … end` block does not see the
   facts proved inside it.** `drop_last_snoc` with its steps inside the block proved every
   `assert`, including the theorem itself as the last line, and the postcondition was still a
   `reflect-fuel` skip. Worked around with a helper lemma (`List.reverse_onto_single`).
4. **A result-type refinement that tests a generic parameter's constructor is
   `unreflectable-predicate`**: `fn is_some(opt : Option(a)) : {Bool | _ == is_Some(opt)}`.
   Tag tests work on `_` and on concrete types (`{Option(Int) | is_Some(_)}`).
5. **`if` inside a predicate is `unreflectable-predicate`**:
   `{Unit | len(to_list(opt)) == (if is_some(opt) do 1 else 0 end)}`.

6. **A lemma whose theorem calls another module is an unenforced refinement to the coverage
   audit.** `Math.checked_div_is_some : {Unit | Option.is_some(checked_div(a, b)) == (b != 0)}`
   is proved, but `--refine-audit` reports "declared here, but no occurrence with the same
   enclosing name and predicate text survives desugaring" (the qualified call prints as
   `<predicate>`), so `audit-baseline`'s `corpus_unenforced_ceiling = 0` fails. Six such laws
   were dropped from the laws pass for this alone.
7. **A tag test on a reflected call's result is `unreflectable-subject` inside a lemma**:
   `{Unit | is_Some(checked_div(a, b)) == (b != 0)}` and `is_None(Range.first(r))` do not
   prove, while the same fact through `Option.is_some(...)` does.
8. **`unwrap_or(opt, d) == d` over a generic element type is unchecked** (`unwrap_or` "is not a
   measure or known predicate") in the `reflect-stdlib-sweep` check of `stdlib/option.march` and
   `stdlib/result.march`, although a single-file `--check` of the same file reported the lemma
   proved; the same law over `Option(Int)` in user code proves. That disagreement between the
   two runs is itself worth a look.

9. **A return contract whose return expression is a builtin call is `unreflectable-subject`.**
   `fn abs(x : Float) : {Float | is_nan(x) || _ >= 0.0} do float_abs(x) end` and the same for
   `math_sqrt` do not check, although `float_abs`/`math_sqrt` reflect inside other functions
   (`fp.abs`/`fp.sqrt`). `Math.abs` and `Math.sqrt` state those facts as lemmas instead.
10. **`fp.sqrt` next to an uninterpreted function is `unknown` at any rlimit tried.**
    `sqrt(x) >= 0.0` for `x >= 0.0` is unsat in 0.2 s as a bare query, but the stage-2 form
    (`(= (sq x) (fp.sqrt RNE x))` with `sq` declared) stays `unknown` at 3M and 30M steps.
    `Math.sqrt_nonneg` was dropped for this; `sqrt_neg_nan` proves.

11. **A stdlib function named like predicate vocabulary is never reflected** (R11):
    `Deque.singleton` is set vocabulary, so `size(singleton(x)) == 1` cannot even be stated.
    The rule protects predicates from a user `singleton`; it should not stop a qualified
    stdlib function from reflecting.
12. **A call returning a list of tuples is `unreflectable-subject` at a call site**, directly
    or through a `let`: `Tuple.zip(xs, ys)` passed to `{List((Int, Int)) | len(_) <= n}`.
    `Tuple.len_zip` proves inside `Tuple` but gives a caller nothing yet.

Repro for 1 and 2: the probes `need_eqb(true, List.is_empty(xs))` and the nested
`drop_last(append(...))` above, checked with `march --check --refine-report-sites=all`.
