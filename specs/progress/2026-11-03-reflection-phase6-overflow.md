`[P3]` Reflected arithmetic is over mathematical integers; runtime `Int` is 63-bit and its overflow is not ruled out.

Decision D8 and fact F18 of `specs/2026-10-29-refinement-reflection-design.md` (§9.1 "Int overflow",
§9.3, and phase 6 in §10).

- The checker's `Int` is unbounded; the runtime normalises to 63 bits. A reflected `inc(n) = n + 1`
  makes `{Unit | inc(n) > n}` true in the logic and false at the maximum `Int`.
- D8 keeps the logic mathematical and says so in the reference; the overflow obligations come later.
  From phase 2 the `known_overflow` test pins the lemma as PROVED, labelled a known gap, so this phase
  has to flip it on purpose.
- Phase 6 decides the model for reflected bodies: a 63-bit wrap encoding (bit-vectors or `mod`
  arithmetic) for reflected arithmetic only, or an overflow obligation at every reflected `+ - *`.
  Bit operations (`int_and`, `int_shl`, …) can then join the R6 table (§2.3).
- The D16 parity net marks a boundary-input mismatch `overflow?` rather than a mismatch (§9.2); that
  mark is what this phase retires.

**Update 2026-10-30.** #1042 made `+ - *` and negation panic on overflow (both backends), with
`int_wrapping_add/sub/mul` for intended wrap-around. A proved fact about a reflected function is now
true wherever the program gets past the call, so the open part of this item is narrower: a reflected
function is counted as unable to fail (R4) although its arithmetic can panic. Phase 6 adds the
overflow obligation; the reference's "`Int` is mathematical" paragraph says this.

---

# Done: refinement reflection, phase 6: Int overflow (2026-11-03)

Design: `specs/2026-10-29-refinement-reflection-design.md` §9.1, §9.3, §10 "Phase 6" (D8).
Plan, with the ruling and its cost: `specs/plans/2026-11-03-reflection-phase6-overflow-plan.md`.
The open item above is closed by this note (moved from `specs/todos/`).

## The ruling

Neither model the spec offered. Both predate 0.7.0 (#1042), which made `+ - *` and negation
panic on overflow:
- a 63-bit wrap encoding would describe a program that no longer exists;
- an overflow obligation at every reflected `+ - *` would buy no soundness (an overflow is a
  panic, never a wrong value) and would take every function with unguarded arithmetic out of
  the logic.

So the logic's `Int` stays mathematical, and the one operator of the R6 table and predicate
vocabulary that still wraps is encoded exactly: `/` on `-2^62` by `-1`, which returns `-2^62`
in both backends. `%` gives `0` there, the mathematical value. `int_abs`, `int_pow`,
`int_shl`, `int_div` and `int_wrapping_*` also wrap, but none is in the R6 table or the
predicate vocabulary.

## What landed

- **`Refine_scope.truncating_division`** (the one `/` encoding for predicates, path
  conditions, `let` facts and reflected bodies): `a / d` is
  `ite(a == -2^62 && d == -1, -2^62, trunc(a, d))`. A non-negative dividend (the fast path)
  and a literal divisor other than `-1` are unchanged.
- **A false proof on main, closed:** with `fn negm(x : Int) : Int do x / -1 end`,
  `need_pos(negm(x))` under `x < 0` was PROVED; at `x = -2^62` `need_pos` gets `-2^62`.
- **Parity evaluator:** `euclid` raises `Logic_overflow` on `-2^62 / -1` instead of computing
  OCaml's wrapped quotient, so it models the unbounded logic it claims to.
- **`known_overflow` flipped on purpose:** it stays PROVED, and is now labelled sound; the test
  also runs `inc` at the largest `Int` in the interpreter and asserts the panic (`attempt to add
  with overflow`) and no wrapped value.
- **Reference:** the "`Int` is mathematical" paragraph says why overflow does not unsettle a
  proof, names the `/` exception, and points at `cap no_panic`; R4 says an overflow is allowed;
  the parity paragraph says what `overflow?` means now.

## Tests (group `reflect-overflow`, `test/test_refine_overflow.ml`; 4 cases)

- `div_min_neg1`: `need_pos(negm(x))`, `need_pos(x / -1)` and `need_pos(x / d)` with `d == -1`,
  each under `x < 0`: not proved. RED control `MARCH_REFLECT_PERTURB=div-wrap-off` (the old
  encoding) proves the first.
- `div_away_from_the_edge`: `x > -5` still proves `x / -1 > 0`; `x / -2` from `x <= 0` still
  proves `>= 0`.
- `div_min_neg1 really wraps`: pins the run-time fact the encoding rests on.
- `parity_div`: `negm` agrees with the interpreter, boundary inputs included.

## Soundness review, round 1 (fresh reviewer, 2026-11-03)

The `/` encoding was checked against the interpreter, compiled code at `--opt 0/2/3` and the TIR
constant folder for every sign combination, with literal and variable divisors. It is correct, and
no `/` bypasses `truncating_division`. The review also found that a second false proof on main is
now closed: `x <= 0, d < 0 ⊢ x / d >= 0` was proved, and it is false at `x = -2^62, d = -1`.
The identity `(x/d)*d + x%d == x` no longer proves for an unconstrained `d`. That is correct:
at that edge it is false in the logic, and the program panics.

It found **one more false proof, already on main**, which is fixed here:
- **What was wrong.** `Refine_encode.fold_const_body` (zero-argument functions read as constants
  in predicates) folded `+ - *` and negation with OCaml's wrapping arithmetic. So
  `fn k3() = max * 3` folded to `max - 2`, and `need_gt(max)` under `_ > k3()` was proved.
  `-lo()` with `lo() = min` folded to `min`, so the lemma `k2() < 0` was proved. At run time
  both calls panic.
- **Fix.** The fold uses the same overflow tests as `lib/tir/fold.ml`. A body whose arithmetic
  overflows is not a constant ("overflows Int, so calling it panics").
- **Test.** `const_fold_overflow`.

Recorded, not changed:
- The parity net never compares `x / k` at `-2^62` for `k ≠ -1`. Its evaluator negates `-2^62`
  on the truncation branch and marks the input undecided, so a wrong encoding at exactly that
  edge would get past the net. The reviewer's backend comparison covered that edge by hand.

## Verification

| Check | Result |
|---|---|
| `reflect-overflow` | 5 cases pass; `div-wrap-off` turns `div_min_neg1` RED |
| refinecheck suite (z3 4.16) | 2192 tests pass (after the review fix) |
| ir-oracle vs `0a2077574` | IDENTICAL |
| refine-oracle vs `0a2077574` | IDENTICAL: no corpus fixture divides the smallest Int by a possible -1, or folds an overflowing constant |
