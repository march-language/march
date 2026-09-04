`[P2]` - [x] **Allocation contracts: `@[no_alloc]` checked on the final TIR.**

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

---

**Landed 2026-09-03.** `lib/tir/alloc_contract.ml` (attribute collection,
allocation classifier, transitive fixpoint, diagnostics) plus
`lib/tir/contract_pipeline.ml`, the post-lower pass sequence extracted from
`bin/main.ml` and shared with the LSP. The extraction was proven to move no IR
with `scripts/ir-oracle.sh` over 242 programs, after first proving the oracle
goes RED on a deliberate perturbation (a build that skips `Known_call`: 484
differing manifest lines).

Two things the design did not anticipate, both confirmed against emitted LLVM
IR rather than assumed:

- **A nullary constructor is not always free.** For an all-nullary enum and for
  a niche-shaped `Option`, codegen emits an immediate, so it costs nothing; for
  a variant that also has payload-carrying cases (`List.Nil`), it emits a real
  16-byte `march_alloc` cell. The checker reports that case, so a list producer
  that returns a fresh `Nil` cannot satisfy the contract today. A function that
  returns the matched empty list instead of building one does satisfy it.
- **`panic_` and `march_decrc_freed` had to be classified as non-allocating.**
  `lower_match` gives every `match` a `panic_` fall-through and `Drop.run` puts
  `march_decrc_freed` in every generated `__drop` helper, so without those two
  entries every `match` and every owned drop failed its contract.

Also: an @[no_alloc(warn)] contract produces a successful binary, so the early
CAS artifact lookup silently swallowed the warning on every run after the
first (measured: printed once, then never). `--report-contracts` and any
source mentioning `no_alloc` now suppress that early exit, the same rule
`--refine-report` already used.

**Found while landing this (2026-09-03):** `forge fix --contracts` could not
run on a library at all. `march --compile` of a module with no `main` charges
that module with the prelude's own `IO.Console` and fails the default
capability ceiling, so the report was empty for exactly the code the feature
targets. CI's Linux leg caught it; it reproduces on macOS too. The command
passes `--no-cap-strict` (it writes no binary, and the real build still checks
the ceiling); the underlying false positive is filed as
`specs/todos/2026-09-03-cap-ceiling-charges-prelude-io-to-mainless-module.md`.
