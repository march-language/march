# `[P4]` Compiler Optimizations (Planned)

- [ ] **P1 Layer 2 — non-leading / interleaved common lets** — Today only the *first* let of each arm is peeled. Generalize to a common pure binding anywhere in an arm's leading let-chain whose RHS does not depend on arm-specific earlier bindings, with reordering. Medium. See `specs/optimizations.md` §P1.
- [ ] **P1 Layer 3 — general non-let-bound cross-arm CSE** — Hoist shared sub-expressions ANF did not already lift to a head let; gate on `Purity.is_pure`. Mostly subsumed by ANF, low marginal value. See `specs/optimizations.md` §P1.
- [ ] **P8 Layer 2 — delayed/non-immediate FBIP reuse** — Current cross-tag reuse only fires when destruction and reconstruction are adjacent; extend to reuse across intervening code. Medium-High. See `specs/optimizations.md` §P8.
