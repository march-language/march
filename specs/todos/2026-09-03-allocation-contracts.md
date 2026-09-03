`[P2]` - [ ] **Allocation contracts: `@[no_alloc]` checked on the final TIR.**

Filed 2026-09-03. Design: `specs/2026-09-03-allocation-contracts-design.md`.

A per-function attribute, in `no_alloc` / `no_alloc(warn)` / `no_alloc(assume)`
forms, checked after Perceus and escape analysis so FBIP reuse and stack
promotion pass. Transitive by fixpoint over the monomorphised module (no
callee annotations); `ECallPtr` and externs fail unless `assume`. `--no-opt`
downgrades to a warning; a TRMC-eligible failure with TRMC off gets a
`--trmc` hint. `Tagged(_, NoAlloc)` / `Realtime` delegate to the same checker.
`cap no_alloc` is untouched (separate todo to unify).

Also in scope: the LSP diagnostic, `✓ no_alloc` code lens, and "Add
`@[no_alloc]`" quick fix; `march --compile --report-contracts` plus
`forge fix --contracts` to insert the attribute on verified functions (default
scope: functions with `EReuse` / tokened `EAllocHole` / `EStackAlloc`; opt-in
globs via `[contracts] no_alloc = [...]` in `forge.toml`).

Prerequisite refactor: extract the post-lower pipeline tail into one
`lib/tir` function shared by `bin/main.ml` and the LSP so both see the same
TIR. Must be IR-oracle green.

Origin: item 1 of the OxCaml review (type kinds, portable closures, borrow
regions, unboxed Float layout are the other four; each gets its own spec).
