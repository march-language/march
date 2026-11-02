`[P1]` Refinement reflection, phase 1b: the rest of the design's phase 1, and the gaps phase 1a left.

Phase 1a (`specs/progress/2026-10-30-reflection-phase1a.md`) made reflection active. Its ruling R1
split the design's phase 1 (`specs/2026-10-29-refinement-reflection-design.md` §10) in two; this is
the second half, plus what 1a deliberately did not encode.

From the design's phase 1, not started:
- §7.1: the D17 hash lines (`--dump-impl-hashes` gains each reflected body's logic hash) and the
  core stored in the proof cache keyed by them; `sound_cache`'s second half (a body edit that only
  changes reflectability must change the D17 line).
- §7.2: LSP invalidation on a dependency's body edit, the `logic_hash` column; RED row
  `lsp_invalidate`.
- I9: the HCR refusal of a hot patch whose `logic_hash` changed; `sound_hcr`.
- §9.2: the parity net (`reflect-parity` group, `forge test --reflection-parity`); RED row `parity`.
- `lemma_in_body` (I2) needs `@[lemma]` (phase 2).

Encoder gaps phase 1a left (each sound, each loses proofs):
- R2 reads only the termination graph's own certificate, so a `metric`-certified function is not
  unfolded (the certificate is decided by the refinement walk, after the encoder is built). The
  design's `sound_domain` function `p` is therefore not reflected yet.
- R4: a division by a non-literal never passes (its `Division` obligation is filed after the check).
- Float and String: a function whose signature mentions either has no logic symbol (§2.3's opaque
  Float operators and distinct `$Str` literals are not built).
- Records and tuples as parameters or results, `let` patterns other than a variable, and a `match`
  in a non-tail value position: the body translator declines (the symbol stays uninterpreted).
- A function whose parameter refinement calls a reflected function is R8-blocked in the report
  (`pred_fn` does not know reflected names).
- The `refinement_unverified` hint text of a skip that stage 2 re-labels `reflect-fuel` /
  `reflect-budget` still names stage 1's reason (the ledger has the new one).
- `uses:` falls back to "every function of the frontier" when the core names no unfolding
  (congruence, I8), which over-approximates.
- A predicate's bare spelling resolves in the enclosing function's module only for obligations
  checked inside [visit_fn]; the propagation pre-pass resolves exact display names only.
- A constructor name two datatypes declare (a user `Some`/`None`) makes `term_of_body` decline every
  function matching on it, stdlib `Option` ones included; resolve constructors by the scrutinee's
  type instead (`review1a2/ctor2.march`).
