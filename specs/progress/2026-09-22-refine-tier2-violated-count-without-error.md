# `[P3]` Refinement: a true postcondition is counted `violated` with no error

**DONE 2026-09-22.**

**Root cause (two layers).**

1. *The encoding.* Tier 2 (`check_post_induction`, `lib/refinecheck/refine_post.ml`)
   builds one VC per return tail from the arm's pattern equation
   (`xs = Cons(h, t)`), and it treats every name in the tail as that one binder. `copy2`'s
   inner `Cons(h2, t)` rebinds `t`, so the tail's `t` was read as the equation's
   `t`. With the IH `len(rec) == len(t)`, the true goal became
   `2 + len(t) == 1 + len(t)`, and its negation was valid. The same conflation
   also PROVED a false contract: `drop1` (same shape, `Cons(h2, t) -> Cons(h, drop1(t))`,
   inner `Nil -> Cons(h, t)`) was counted `1 proved`, even though `drop1([1, 2]) == [1]`.
2. *The verdict.* Any refuted tail was recorded `Violated`, but Tier 2 emits no
   diagnostic, so the report counted a violation the user never saw. This also
   happened for genuinely false contracts: `grow` (`len(_) == len(xs) + 1`, with
   `Nil -> Nil`) got `1 violated` and exit 0.

**Fix.**
- `tails_bound` (new; `tails` is now a projection of it) returns the names bound on the
  way down to each tail (inner match patterns, block `let`s). In Shape 2, a tail
  that mentions a name rebound there which is also a parameter or one of the arm's own pattern
  binders is not checked. It gets an `unreflectable-subject` skip instead.
- A Tier 2 refutation is now a CANDIDATE. `settle_refutation` tries to reproduce it
  through `Witness`: first the decoded positive-query model of each refuted tail
  (`confirm_post`), then the small-value battery (`confirm_enumerative`). If one of them
  reproduces it, the verdict is `Violated` AND an error is emitted
  (`` `grow` does not satisfy … but grow([]) returns [].``). If neither does, it is the new skip reason
  `Refuted_unconfirmed` (`refuted-unconfirmed`). Only the recording pass does this.
- `Witness.eval_operand` can now evaluate a user `@[measure]` application
  (`size(_)`) by running its definition through `call_fn`, which uses the same
  harness, fuel and effect veto. Without this, no Tree-measure violation could ever be confirmed.
  Set-valued measures (`tree_elts`, `member`/`union`) have no meaning in the interpreter, so their
  refutations stay unconfirmed skips.

**Existing tests whose expectations moved (intended).**
- `tier2-induction` "a false relational postcondition does not propagate": `ins2`
  used to be asserted error-free. It now gets exactly ONE error, the definition's
  confirmed violation. Propagation is still absent, because a call-site error would
  make it two.
- `module-qualified-measure-and-sort` "...and refutes a literal that is not a member"
  and `avl-induction` "a false insert contract is refuted" (both set measures) went from
  `1 violated` to `1 skipped`. Each now also asserts that the skip is `Refuted_unconfirmed`,
  so "refuted" is still distinguishable from "merely skipping", and neither is ever a proof.
  Follow-up opportunity: give the witness a set semantics, which would let these
  be confirmed and reported.

**Other checks.** Full `test_refinecheck.exe` passes, 946 tests in three chunks
(321 + 255 + 370) with z3. `scripts/run-tests.sh -q compiler` passes (1098 tests).
`--check` on all 124 `stdlib/*.march` files is byte-identical between the pre- and post-change
compilers (separate private HOMEs). `refine-oracle` baseline (pre) vs check (post) is IDENTICAL:
7292 lines over 371 fixtures. The same oracle goes RED (1487 differing lines) when a Tier 2
Shape-2 `Proved` verdict is perturbed to `Skipped`, so the green result is not vacuous. The corpus has
no Tier 2 refutation, which is why the fix itself moves nothing there.

**Verified.** New suite `tier2-ledger-agrees` in `test/test_refinecheck.ml` asserts
both the ledger and the error flag: copy2 (0 violated, no error), drop1 (not proved),
grow (1 violated + error) and dup (1 violated + error, refuted only in the Cons arm).
Red control on origin/main's `lib/refinecheck`: all 4 FAIL for the expected reasons
(copy2 `violated` Expected 0 Received 1; drop1 `proved` Expected 0 Received 1;
grow and dup `an error is reported` Expected true Received false). All 4 pass after the fix.

---

Filed 2026-09-21, found while fixing
`specs/progress/2026-09-21-structural-components-trusted-by-name.md`.

```march
fn copy2(xs : List(Int)) : {List(Int) | len(_) == len(xs)} do
  match xs do
  Nil -> Nil
  Cons(h, t) ->
    match t do
    Nil -> Cons(h, Nil)
    Cons(h2, t) -> Cons(h, Cons(h2, copy2(t)))
    end
  end
end
```

The claim is true (two elements consumed, two produced, plus the induction
hypothesis on the inner tail). `--refine-report` counts it `1 violated`, yet
no error is printed and the exit code is 0 — so the ledger and the
diagnostics disagree. Behaves identically on `main` before the name fix.

Likely a tail Tier 2 cannot discharge (it needs two unfoldings of `len`)
recorded as a refutation rather than a skip. Find where the verdict is
recorded; a tail with no confirmed counterexample must be a skip, never a
violation, or `cap verified` and the report both mislead.
