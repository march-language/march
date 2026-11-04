# Reflection phase 6: Int overflow — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** a reflected function's definition is true of the program at every input where the
program returns, including the 63-bit edges. Close the one place where it is not.

**Spec:** `specs/2026-10-29-refinement-reflection-design.md` §9.1 "Int overflow", §9.3, §10
"Phase 6" (decision D8); todo `specs/todos/2026-10-29-reflection-int-overflow.md`.

**Base:** branch `claude/reflection-phase6-overflow`, cut from `origin/main`. Independent of
phase 5 (PR for phase 5 is separate).

## The ruling: keep `Int` mathematical, and encode the one operator that wraps exactly

The spec offered two models, written before 0.7.0 (#1042) made `+ - *` and negation panic
on overflow:

- **(a) a 63-bit wrap encoding** (bit-vectors or `mod 2^63`) for reflected arithmetic.
  Rejected: the program no longer wraps, so a wrap encoding would describe a program that
  does not exist (`inc(max) == min` in the logic, a panic at run time) and would lose every
  linear-arithmetic proof to bit-vector reasoning.
- **(b) an overflow obligation at every reflected `+ - *`**, with the function unreflected
  when it is not proved. Rejected: it buys no soundness and costs most of reflection.
  Since the trap, an operation either returns its mathematical value or stops the program,
  so `f$r(x) = body(x)` holds at every input where `f` returns, and a fact the checker
  derives about a value the program holds is about a value that really exists. A panic
  never gives the logic a wrong value; it gives the program no value. Cost of (b): every
  function with unguarded arithmetic (`inc(n) = n + 1`, `length`-style counters) would
  leave the logic, a proved→skipped move across the stdlib and the corpus. Proving that
  no overflow happens is already offered where it is wanted, by `cap no_panic`
  (`Overflow_safety`).
- **(c), chosen:** the logic's `Int` stays mathematical (D8's first sentence, unchanged).
  What the trap does not cover is an operator that still wraps. Of the operators the
  logic knows (§2.3: `+ - * negate`, comparisons, `/` and `%`), exactly one does:
  **`/` at `-2^62 / -1`**, which returns `-2^62` in both backends
  (`specs/lang/type-system.md`, "Int width and overflow"). `%` does not (`-2^62 % -1 == 0`,
  the mathematical value). `int_abs`, `int_pow`, `int_shl`, `int_div` and the
  `int_wrapping_*` forms also wrap, but none is in the R6 table or the predicate
  vocabulary, so a function calling one is not reflected and a predicate cannot name one.

  So `/` is encoded exactly: `a / d` is
  `ite(a == -2^62 && d == -1, -2^62, trunc(a, d))`, for a literal `-1` divisor and for a
  term divisor. This is `Refine_scope.truncating_division`, the one encoding shared by
  predicates, path conditions, `let` facts and reflected bodies (`Refine_reflect.builtin`),
  so the program's `/` means the same everywhere.

**Found while planning (a false proof on main):**
```march
fn negm(x : Int) : Int do x / -1 end
fn need_pos(y : {Int | _ > 0}) : Int do y end
fn t(x : {Int | _ < 0}) : Int do need_pos(negm(x)) end   -- PROVED on main; x = -2^62 breaks it
```

**Cost:** a query with a non-literal divisor carries one more `ite`; a literal divisor other
than `-1` is unchanged. Measured by the refine oracle (below).

**What D8's "overflow obligations come later" becomes:** for reflection, nothing: none is
needed for soundness. A user who wants proof that no overflow happens has `cap no_panic`.
R4 says in words that an overflow panic is allowed in a reflected function, and why.

## Tasks

### Task 1: the exact `/`

- `truncating_division ~op:"/"` wraps the result in the `ite` above. The `%` encoding is
  unchanged.
- The parity net's logic evaluator (`Reflect_parity.euclid`) raises `Logic_overflow` on
  `-2^62 / -1` instead of computing OCaml's wrapped quotient, so the evaluator models the
  unbounded logic it claims to.
- Tests (group `reflect-overflow`, `test/test_refine_overflow.ml`):
  - `div_min_neg1_reflected`: the program above, `t` not proved;
  - `div_min_neg1_direct`: `need_pos(x / -1)` with `x < 0`, and the same with a `d == -1`
    parameter: not proved; `need_pos(x / -1)` with `x > -5`: proved (the edge is the only
    gap);
  - `div_other_literal`: `x / 2` and `x / -2` proofs unchanged;
  - `parity_div`: `negm` agrees under the parity net, boundary inputs included;
  - RED control: `MARCH_REFLECT_PERTURB=div-wrap-off` restores the old encoding and `t`
    proves.

### Task 2: the `known_overflow` test flips on purpose

- `known_overflow` (`test/test_refine_lemma.ml`) pinned `{Unit | inc(n) > n}` as PROVED and
  "a known gap". It stays proved, and is now labelled sound: the test also runs `inc` at
  the largest `Int` in the interpreter and asserts it panics with `attempt to add with
  overflow` (the compiled trap has its own parity tests, from #1042), so no run returns a
  value that breaks the lemma.
- The parity net's `overflow?` status stays (an input where the program panics compares
  nothing); its description changes from "the logic's Int is unbounded" to "the program
  panics there".

### Task 3: docs, oracles, review

- Reference: the "`Int` is mathematical" paragraph, R4, the parity paragraph; the design
  spec's §9.1 row, §9.3 and §10 phase 6; close the todo into `specs/progress/`.
- Full refinecheck suite, `-q compiler`, `oracle-base.sh refine ir` (IR identical: no
  code generation changes).
- A fresh soundness review: every place the checker gives `Int` arithmetic a meaning,
  checked against both backends at the 63-bit edges.
