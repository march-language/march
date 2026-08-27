# Target A — `bin/main.ml` decomposition, tasks A1–A4 (2026-08-27)

Executes `specs/plans/2026-08-27-remaining-decomposition-targets.md`, **Target A,
tasks A1–A4**. Task A5 (`emit_native.ml`) is deliberately **not** attempted — see
"Why A5 was not started" below.

## Result

| | Before | After | |
|---|---:|---:|---|
| `bin/main.ml` | 5,429 | **4,198** | −1,231 (−23%) |
| `compile` | 2,431 | **2,232** | −199 (−8%) |

Four new modules, 1,318 lines total:

| Module | Lines | Contents |
|---|---:|---|
| `bin/toolchain.ml` | 865 | diagnostics + prelude-collision check; exe/stdlib/runtime discovery and the stdlib AST cache; clang link flags, cross-compile sysroots, `ensure_runtime_so` |
| `bin/flags.ml` | 81 | the 38 command-line flag cells |
| `bin/schema_migration.ml` | 216 | the `--check-migration` tool (helpers + arm) |
| `bin/emit_core_ast.ml` | 156 | the `--emit-core-ast` JSON writer |

`bin/` is an `(executable (name main))` with no `modules` field, so sibling
`bin/*.ml` files join the executable automatically — `bin/dune` needed no edit.
`open`, not `include`, at every seam: nothing outside the executable consumes
`Main`, so re-export is not needed and every call site is unchanged.

## Verification

Every task, against baselines recorded first, under a private `HOME`:

- `scripts/ir-oracle.sh check` — **IR IDENTICAL across 240 programs**, after
  every one of the four tasks and at the end. **Never once non-identical.**
- `scripts/types-oracle.sh check` — **TIER1 + TIER2 IDENTICAL (600 fixtures,
  7,252 report lines)**, same cadence. Tier 1 *is* `--emit-core-ast`, so it
  covers task A4's band directly.
- `dune build --root . bin/main.exe` — exit 0 after each task.
- `dune build --root . @check` — **17 errors before and 17 after, the same 17
  files** (15 under `forge/test/`, 2 under `js/`), all pre-existing.
- `scripts/run-tests.sh` (full, not `-q`) — 3,161 tests / 11 suites / exit 0,
  matching the pre-task baseline.

### Verbatim proofs — machine-checked, never asserted

For each task the moved region was read back **out of the destination file**,
inverse-substituted at its original call site, and required to be byte-for-byte
identical to the pre-extraction file. Each moved band was separately asserted
comment-balanced outside string literals.

| Task | Proof |
|---|---|
| A1 | 282,152 bytes reproduced exactly; five regions asserted to be a strict partition |
| A2 | 240,595 bytes; six blocks re-interleaved at recorded positions |
| A3 | 236,440 bytes; helper band + arm body restored |
| A4 | 227,122 bytes; body restored with the single `~rejected` edit undone |

Exactly **two** non-motion edits exist across A1–A4, both machine-asserted to be
what they claim:

1. **A2** — six flag cells initialised `ref []` / `ref None` needed explicit
   types once they became a module's interface (a weak type variable can no
   longer be resolved by a later use in the same compilation unit). The proof
   normalises exactly six such annotations away and asserts the count. Each was
   verified *by the compiler*, not by inspection: a wrong annotation fails at the
   use site.
2. **A4** — the four `has_*_errors` booleans collapse into one `~rejected`,
   computed at the call site exactly as `verdict` computed it. The proof undoes
   that one line and asserts it is the only line mentioning `rejected`.

A2 additionally machine-checks that the six moved blocks contain *nothing but*
flag declarations and their comments: comments are blanked by a
balance-tracking scanner and every surviving non-blank line must match the flag
pattern — 38 of them, no more, no less.

### The plan was wrong twice, and both were caught by re-deriving

Consistent with the Phase 0–7 record ("the plan was wrong more often than the
code was"):

- **A1's band boundaries.** The plan gives B2 as `258–520`; `load_stdlib`
  actually ends at **549**, and the gap that stays is `550–769`, not `521–781`.
  Caught by an anchor assertion on the first run, before any code moved.
- **A3's signature.** The plan specifies `Schema_migration.run ~filename
  ~desugared`. `filename` appears **zero** times in the arm (asserted by the
  extraction script). The real second input is `src`, needed by
  `Errors.render_diagnostic ~src` on the violation path.
- **A4's input list is incomplete.** The plan omits `typecheck_env`, which the
  band reads three times (`inst_witnesses`, `scheme_witnesses`, `module_caps`).
  A missing input is an unbound-value error, so a clean build is a sound
  completeness check for this list.

### `--check-migration` has no oracle and no test — so one was built

`grep -rn 'check-migration' test/ scripts/` returns nothing; the only consumer is
`forge/lib/cmd_deploy_hot.ml:804`, which shells out. Rather than review by
reading alone, A3 ships a purpose-built end-to-end differential: a
capability-clean actor fixture with a `migrate_state`, plus prior / new /
violating schema files, driven through all five reachable paths —

| path | exit |
|---|---|
| `--new-schema` omitted | 2 |
| `--prior-schema` omitted | 2 |
| sound migration | 0 |
| invariant the migration cannot establish | 1, + 18 lines of SMT diagnostics |
| new-schema file absent | 0 |

Compilers built from the pre-A3 and post-A3 trees (file-copy swap, never `git
stash`) produce **byte-identical output over all five**. The exit-1 case carrying
real diagnostics is what makes it non-vacuous.

The first fixture attempted was `demo/hcr_actor_demo/counter_v2.march`, which
**fails typecheck** (`main` performs IO with no grant) and so never reaches the
arm at all — a silently vacuous test if it had not been checked.

## Why A5 was not started

`bin/emit_native.ml` (LLVM emit, clang, linker, CAS store) is the largest
remaining extraction and the only one no oracle watches.
`scripts/ir-oracle.sh:4–9` documents that `--emit-llvm` exits in the `else`
branch *before* the arm containing clang, deliberately, so a warm CAS cannot
short-circuit the oracle — which means the oracle reaches 58 of the band's 945
lines and never the 887-line `if !do_compile` arm. That arm holds the CAS cache
key, whose historic failure mode is a correct-looking binary carrying yesterday's
answer, and its only automatic coverage is `Slow`-tagged. It needs its own
session with the purpose-built cold/warm CAS check the plan specifies.

## Also landed here

Two filed bugs living in this same file, as separate commits after the
extractions so they review on their own:

- `specs/progress/2026-08-27-stdlib-cache-mkdir-not-recursive.md`
- `specs/progress/2026-08-27-effects-ml-docstring-claims-a-call-path-that-does-not-exist.md`

## A trap worth carrying forward

Verifying the `~/.cache/march` fix by the obvious method — fresh `HOME`, run
twice, compare — is **vacuous**, and three consecutive attempts at it produced
confidently wrong readings in both directions. The worktree-local `.march/cas`
(`vc` especially) short-circuits the stdlib path entirely on any run after the
first, so a second invocation costs ~0.08s and writes nothing whether or not the
fix is present; and the only run that exercises the path at all is the first
after a rebuild. A valid probe must clear `.march/cas/vc` and
`.march/cas/artifacts-v2` **and** use a fresh `HOME` with no `.cache`. Detail in
that fix's own progress entry.

Separately: the shared scratchpad is genuinely shared — a generically-named
helper script written there was overwritten mid-session by a concurrent agent's
file of the same name. Name scratch scripts with the agent slug.
