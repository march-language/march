`[P3]` Uses of `@[lemma]` beyond discharging refinements. A lemma is a law about the code: the
compiler checks it and erases it before anything runs (`specs/2026-10-29-refinement-reflection-design.md`
§4; phase 2 builds the mechanism, see `specs/plans/2026-11-02-reflection-phase2-lemmas-plan.md`).
Once phase 2 lands, the same pieces serve uses outside the refinement checker. Those pieces are the
attribute, the admitted/proved status, the reflected (executable) functions a lemma mentions, and
erasure.

This file records the ideas so none is lost. Split one into its own todo when it is picked up.

The ideas, cheapest and most valuable first:

1. **An unproved lemma becomes a property test.** Every function a lemma mentions is reflected,
   so it can run, and the statement `P` can be evaluated on concrete inputs. When z3 skips a
   lemma, `forge test` could evaluate `P` over generated inputs. It would reuse the §9.2 parity
   net's generators and its fixed, recorded seed. The result is a counterexample, or "tested,
   not proved". It runs only under `forge test`; erasure still removes lemmas from every
   production path. Today an unproved lemma is only a `lemma_unproved` warning.
2. **Catching miscompiles.** A proved lemma whose `P` is false in compiled code can only be a
   compiler or runtime bug. Evaluating proved laws on a few inputs through both the interpreter
   and the compiled backend gives a cheap differential test. It complements `scripts/triage.sh`.
3. **Laws in the docs.** `forge doc` renders the lemmas about a function as a "Laws" section on
   its API page, marked proved, tested or unproved. This pairs with phase 3's stdlib `List`
   lemmas.
4. **Searching by law.** `forge search` finds functions by what is proved about them, such as
   `f(f(x)) == x` or "preserves length", alongside search by type signature.
5. **Proof-backed refactors in the LSP.** A code action offers a rewrite such as `reverse(reverse(xs))`
   → `xs` only when an admitted lemma justifies it, and names that lemma.
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
10. **Specs for code written by agents.** A set of lemmas is a machine-checked contract that an
    agent's refactor must keep proving. That is stronger than "the tests pass" and cheaper than a
    review round.

Out of reach until later phases:

- **Laws for higher-order functions** (`map` composition, `filter` idempotence) need function
  values (phase 5, D10).
- **Encode/decode round-trips** over String or Bytes need D9 (both opaque) lifted. Encoders to
  an algebraic type, such as a token list, work today.
