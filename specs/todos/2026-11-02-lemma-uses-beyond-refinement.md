`[P3]` Uses of `@[lemma]` beyond discharging refinements. A lemma is a law about the code: the
compiler checks it and erases it before anything runs (`specs/2026-10-29-refinement-reflection-design.md`
§4; phase 2 builds the mechanism, see `specs/plans/2026-11-02-reflection-phase2-lemmas-plan.md`).
Once phase 2 lands, the same pieces serve uses outside the refinement checker. Those pieces are the
attribute, the admitted/proved status, the reflected (executable) functions a lemma mentions, and
erasure.

This file records the ideas so none is lost. Split one into its own todo when it is picked up.

Done on 2026-11-03 (`specs/progress/2026-11-03-lemma-tests-laws-search.md`): idea 1 (an
unproved lemma becomes a property test in `forge test`), idea 2 (admitted lemmas re-checked in
the interpreter and a compiled program), idea 3 without status marks, idea 4 at the text level,
and idea 10 (guidance); idea 5 for the open file's lemmas
(`specs/progress/2026-11-03-lemma-refutation-and-rewrites.md`). What remains of them:

3. **Laws in the docs: status marks.** `forge doc` lists the laws about each function
   (march_doc), but not whether each is proved, tested or unproved. That needs the
   `--reflect-deps` lemma rows (or `--lemma-test` lines) per file during `forge doc`, which
   means a z3 check of every documented file.
4. **Searching by law: shapes.** `forge search --law` matches theorem text and the functions
   a theorem calls. Matching a law's shape (`f(f(x)) == x` finds every involution) is not
   done.
5. **Proof-backed rewrites: other files' lemmas.** The LSP rewrite
   (`specs/progress/2026-11-03-lemma-refutation-and-rewrites.md`) uses the open file's lemmas
   only. The stdlib's (phase 3) and dependencies' need their admitted status too.

The open ideas:

6. **Interface laws.** `interface Monoid` declares `combine_assoc` and `empty_left` as lemmas
   that every `impl` must discharge, as proofs or at least as idea 1's tests. A derived impl
   could carry generated proofs. This is blocked by D7 (a hand-written `eq` is opaque) for laws
   over `Eq`.
7. **Versioning by behaviour.** A package's lemmas are part of its public interface:
   `forge publish` checks that the new version still proves the previous version's lemmas, so
   breaking a published law is flagged as a breaking change. Related:
   `2026-11-01-fn-needs-bounds-tooling-semver.md`.
8. **Hot reload, judged by laws.** Today a patch to a reflected body is refused when a proof in
   the build unfolded it. Instead, admit the patch when the new body still proves every lemma
   the old one did. Related: `2026-11-01-fn-needs-bounds-hot-reload.md`.
9. **Proved rewrite rules for the optimizer.** These work like GHC `RULES`, but each one is
   justified by an admitted lemma: map fusion, `append(xs, Nil)`, `reverse(reverse(xs))`. This
   is **unsafe until the Int-overflow phase** (spec §10 phase 6, D8), because the logic's `Int`
   is unbounded.

Out of reach until later phases:

- **Laws for higher-order functions** (`map` composition, `filter` idempotence) need function
  values (phase 5, D10).
- **Encode/decode round-trips** over String or Bytes need D9 (both opaque) lifted. Encoders to
  an algebraic type, such as a token list, work today.
