# march-lean's differential oracle is out of sync with this repo's corpus

Filed 2026-08-10, while recording R1 stage C in the sandbox ladder
(`specs/2026-08-04-provable-sandbox-design.md` §R7). Not a bug in either
repo — a cross-repo drift that silently degrades what the oracle is evidence
for, and which nothing in THIS repo's CI can see.

## What's out of sync

`march-language/march-lean` re-implements March's error-level static checks in
Lean 4 and re-checks `--emit-core-ast` output over this repo's
`specs/lang/types/{accept,reject}` corpus
(`scripts/conformance-harness.sh --corpus-dir <march>/specs/lang/types`).

Two gaps, both pointing the same way:

1. **`MarchLean/CapCheck.lean` models no grant check.** 4400 lines mirroring
   March's capability checks, zero occurrences of "grant". R1 stage A/B
   (whole-program, 2026-08-09) and stage C (per-function, 2026-08-10) are both
   ERROR-level checks it cannot see.
2. **Its ledgers and its pinned march SHA predate R1.** On `main` the ledgers
   top out around `t140`. The unpushed branch
   `claude/calculus-proof-capabilities-0a1127` is much closer — re-baselined
   to 277 files, top fixture `t165` — but its CI pins march `6867c783`, which
   predates stages A/B, so `t166`/`t167` and `t170` are in neither ledger.

Predicted (NOT verified — no Lean toolchain was available when this was
filed, and the harness was not run): `reject/t166_grant_narrow_violated_by_
helper` and `reject/t170_fn_grant_violated_by_helper` are wrong-accepts for
the oracle — March rejects, march-lean accepts — which the harness classifies
as hard MISMATCH. Verify before acting on it.

## Why it matters more than a stale allowlist usually would

march-lean's own discipline is deliberately anti-rot: both ledgers are
enforced in BOTH directions, so a stale entry fails the run and the lists can
only shrink. That property is exactly what makes drift here dangerous — the
harness is trustworthy enough to be cited as evidence, and an out-of-sync
harness is either red for uninteresting reasons (so it gets ignored) or
quietly narrower than it looks.

It has already found real March bugs of the class our corpus structurally
cannot (`calls_in_expr` not total over `Ast.expr`, so a check silently never
fired — twice, in two same-named functions; march PR #136, march issue #82).
Keeping it in sync is protecting a working bug-finder, not bookkeeping.

## Fix shape

- march-lean side: extend `CapCheck.lean` with the grant check (the lattice
  half already exists — `CapLattice.capSubsumes`/`normalize` mirror
  `lib/caps/cap_lattice.ml`), and refresh both ledgers against the current
  corpus. Stage C additionally needs a row notion if the per-function check is
  to be modeled rather than skipped; skipping is a legitimate first step, but
  it must be a LEDGERED skip, not a mismatch.
- This repo's side, the durable half: **adding an ERROR-level check here is a
  change to two repos.** Nothing in this repo's CI notices when it isn't.
  Worth either a note in the capability-check contributor docs or, better, a
  scheduled cross-repo harness run whose failure is visible to whoever landed
  the check.
