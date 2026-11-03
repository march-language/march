Finishes the cheap halves of §X3 and §X4 and lands §X7 of
`specs/plans/2026-11-02-diagnostics-depth-plan.md`.

§X4, a machine fix must fix:
- `test/run_errors.ml` fails a case whose fixes leave the program rejected, unless its source ends
  with `-- EXPECT-FIX-PARTIAL: <reason>`; a stale marker (fixes now succeed, or no fix) fails too.
- Triage of the 17 cases whose fix didn't fix: 15 are partial (the fix is right, the program has
  a second, independent error) and carry the marker with the reason; 2 were real bugs:
  - `unused_binding` reported a parameter that only a refinement names
    (`fn f(t : {Tree | size(t) < 1})`), and its `_t` rename broke the predicate. Names in any
    parameter's refinement now count as uses.
  - `unused_binding` beside `linear_never_used` for the same binder: the `_r` rename does not
    satisfy linearity; the warning is now dropped (cascade rule).
- "Did you mean" for an unbound name no longer suggests an operator (`y` → `%`).
- Hint stacking outside `type_mismatch`: none found in the corpus (the one diagnostic with three
  notes uses them as what / why / fix).

§X3, more rules in `Errors.suppress_cascades`, from a review of the 45 corpus cases with more
than one error (the rest have independent errors):
- exact duplicates go; `type_mismatch`es on one span merge (notes and labels united);
- `unbound_variable` for a name an `or_pattern_binding` error names;
- `session_state_mismatch` "expected a channel endpoint but got `a`" after another session error;
- `mint_cap_invalid` inside a `proof_cap_mint_private` / `proof_cap_return`;
- while a protocol definition is invalid (`role_needs_invalid`, `protocol_invalid`,
  `endpoints_label_invalid`), its consequences: type, constructor, linearity and session errors
  (type_mismatch_13 went from 31 errors to its one protocol error);
- an error with no position (line 0) beside a positioned one;
- `cap_ceiling:X` beside `import_cap_missing` for `X`, with the ceiling's `needs X` fix moved
  onto the import error (the corpus caught the first version dropping the only fix).
- The LSP runs the same pass on its compiler diagnostics (`lsp/lib/analysis.ml`).

§X7, reach chains as traces:
- `cap_grant_exceeded` points at the use (the builtin call needing the capability), with a label on
  each call from `main` to it and on `main`'s grant (`Typecheck.cap_chain_trace`). It keeps the
  prose chain when a hop or the use is outside `main`'s file or goes through a function value.
- The `cap_needs` "reached from `main`" HINT is folded into the error it repeats, as a note
  (`bin/toolchain.ml` `dedupe_cap_hints`).
- Not done: role grants (`role_grant_exceeded`, rooted at a synthetic lambda key), `no_panic`,
  `pure`, `deterministic`, `no_alloc` chains.
- 5 internals-allowlist entries remain (generated actor/protocol names; F2/F3).
