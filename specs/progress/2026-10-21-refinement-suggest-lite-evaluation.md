# Inference-lite evaluation run (Task 14)

Done 2026-10-21. This is the evaluation called for in design §6
(`specs/2026-10-20-refinement-suggest-lite-design.md`) and plan Task 14
(`specs/plans/2026-10-21-refinement-suggest-lite-plan.md`). It changes no product code; the
two bugs it found were fixed on the branch first, with RED tests (see "Bugs found" below). Per
D5, no stdlib annotation lands.

Every run was a dry run under a private `HOME`, with the staged stdlib checked against `stdlib/`
(`cmp _build/default/stdlib/list.march stdlib/list.march`). The compiler is the branch tip:
`march --check --refine-infer-json` per file; for files with a proposal,
`--refine-infer-apply --apply-public` on a copy.

## Corpus 1: `test/native/*.march` (416 files)

| Metric | Value |
|---|---|
| Files that check | 416 / 416 |
| User skips before → after (dry run) | 13 → 13 |
| User skips by reason | solver-undecided 10, partial-conjunct 1, unconstrained-subject 1, unreflectable-subject 1 (5 files) |
| Violations before → after | 0 → 0 |
| Accepted, by kind | 1 precondition (`array_trie_drop_leak_probe.march`: `set_n` `n : {Int \| _ <= j}`) |
| Rejected, by reason | not-true 3683 (return not proved 3099, element return not proved 391, accumulator base/step not proved 193) |
| Refused | 11, all caller-violation |
| Notes | scc-unsupported 16, vocabulary-truncated 2 |
| Probes | 11 778 in total; max rounds 2 |
| Wall time ÷ cold `--check` (fresh HOME for each run) | median 1.35×, p90 1.66×, aggregate 1.44× (709 s → 1024 s). Max 23.7× on `hcr_e2e_server.march`, whose plain check takes 0.1 s |
| Prediction mismatches (apply on a copy) | **0** of 1 applied, after the fix below. **1** of 1 before it |

No rejection's `detail` is a checker skip reason. They are all "not true" verdicts, so Step 3
files no per-rejection todos. The skip reasons above match the ones filed in phase 0 (R2, O1, C1,
G1) and the existing solver-undecided items.

**Quality finding.** The one accepted proposal does not express a real contract. `n <= j` makes
the `else` branch that calls `Array.set` dead. The refused `pop_n` `j == 0` has the same shape.
Admissibility (closes one, opens none, satisfiable) does not reject a precondition that closes a
site only by making the site unreachable. Filed:
`specs/todos/2026-10-21-refine-infer-vacuous-branch-preconditions.md`.

## Corpus 2: `~/code/depot` and `~/code/conduit` (`forge refine --infer --diff`)

| Project | Files | Result |
|---|---|---|
| depot | 31 | 30 checked, with 0 unsettled user obligations, so 0 probes and 0 proposals; tree untouched (`git status` identical). `lib/forge/cmd_depot.march` does not check standalone and is reported as "no inference — skipped, the program has errors" |
| conduit | 45 | None check against this compiler: `cap_ceiling` errors in `conduit/dashboard.march` (`IO.NetListen`) and `conduit/storage/postgres.march` (`IO.Clock`), with depot on `MARCH_LIB_PATH`; under forge with a private HOME the registry dep `depot 0.3.3` is not fetched either (`forge.lock` still pins 0.3.2). Every file is now reported as skipped; tree untouched |

Before the forge fix below, conduit printed nothing at all.

The depot run prints 966 `scc-unsupported` notes for SCCs that have nothing to infer, and the
JSON lists a refusal once per round. Filed:
`specs/todos/2026-10-21-refine-infer-notes-noise.md`.

## Corpus 3: the stdlib (`--refine-infer-stdlib` on a trivial entry)

| Metric | Value |
|---|---|
| Wall time | 2862 s (48 min), against 1 s for a cold `--check` of the same entry |
| Probes, rounds | 3000 (the whole default budget) in round 1 |
| Accepted / refused | 0 / 0 |
| Rejected | 2393, all not-true |
| Notes | budget-exhausted 1554 functions, scc-unsupported 51, vocabulary-truncated 20 |
| Skips before → after | not measurable from this run: the JSON summary counts user-code skips only, and with an entry file that holds no user obligations it reports 0 → 0 |

The run probes 90 modules in callees-first order and spends the global budget before most
functions get a turn. `List.pfilter` (5 rejections), `List.find_index` (8) and
`List.drop_while` (4) were probed and then budget-exhausted. `HashMap.filter`, `Seq.filter`,
`Flow.filter` and `Gen.filter` were never reached. A whole-stdlib dry run therefore cannot
answer the design's "expected stdlib outcomes" table at the default budget. Filed:
`specs/todos/2026-10-21-refine-infer-stdlib-sweep-too-slow.md`. The table needs per-function
fixtures or a per-module budget.

## Rediscovery (design §6 table)

The unit tests pin the hand-written rows (`infer-abstract`: `filter`, `find`, `take_while`,
`partition` with both halves, `Option.filter`; `infer-elements` and `infer-fixpoint` for K4/K5
and the demand chains). All of them rediscover the stripped annotation exactly.

| Row | Outcome |
|---|---|
| `List.filter` / `find` / `take_while` / `partition` / `Option.filter` | rediscovered (unit tests, `infer-abstract`) |
| `Deque.filter` (moved here from Task 8) | not rediscovered. The v1 K6 grammar (List, Option, 2-tuples of lists) has no `Within`-field container, and the **checker** does not prove the hand-annotated version either: the element fact is lost through `Deque.to_list` (`parametric-source-unproved`). Filed: `specs/todos/2026-10-21-refine-deque-to-list-element-fact.md` |
| `List.pfilter`, `find_index`, `drop_while` | probed in the stdlib run, then budget-exhausted, with no proposal (Corpus 3) |
| `HashMap.filter`, `Seq`, `Flow`, `Gen`, the `hamt` index skips | not reached within the stdlib run's 3000-probe budget (Corpus 3) |

Hit rate on the rows the checker proves by hand: 5/5. `Deque.filter` falls outside that target,
since the checker cannot prove it by hand.

## Bugs found and fixed on the branch

1. **Prediction mismatch** (`array_trie_drop_leak_probe.march`, exit 3, edits reverted).
   `Precond_infer.walk_ledger` ran `Division_safety.check_module` on the pruned probe tree, and
   that call re-registers the tree as the witness executor's module. Every later witness run,
   the one that promotes a skip to a demonstrated violation by executing the enclosing function,
   then ran without the stdlib and failed. So a probe predicted a skip where the applied
   program's re-check finds a violation. The walk now calls `check_decls` and starts each walk
   with the witness's full module budget. RED test: `infer-apply`, "a caller's caller makes the
   requirement concrete".
2. **`forge refine --infer` printed nothing** when the compiler lacks `--refine-infer` or a file
   does not check: stderr was discarded and every exit code except 3 was ignored. Each such file
   now gets a "no inference — <reason>" line, and the summary counts them. Tests:
   `forge/test/test_forge.ml`, group "refine --infer" (4 cases).

## Checker gaps filed

- `specs/todos/2026-10-21-refine-infer-vacuous-branch-preconditions.md` (P2)
- `specs/todos/2026-10-21-refine-deque-to-list-element-fact.md` (P3)
- `specs/todos/2026-10-21-refine-infer-stdlib-sweep-too-slow.md` (P3)
- `specs/todos/2026-10-21-refine-infer-notes-noise.md` (P4)
