# `--check-json` never prints `no_alloc` contract diagnostics

Found 2026-11-10 (ocap phase 3). `bin/main.ml`'s `--check-json` arm prints the front end's
diagnostics and exits 0 before `contract_diags` (the lowered-TIR `no_alloc` / `cap portable`
verdicts that `--check` prints) is ever forced. So `forge fix`, which reads `--check-json`,
never sees them, and a program `--check` rejects on a contract looks clean to it. Phase 3 adds the
TIR capability diagnostics to `--check-json`; the contract ones should follow the same path.
