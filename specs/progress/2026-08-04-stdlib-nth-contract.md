# 2026-08-04 — `List.nth` carries a bounds contract

Task 6 of the "remaining seven" refinement batch. Unlike its siblings
`head`/`tail`/`last`/`unwrap`/`expect`, `List.nth` panicked on an out-of-range
index while carrying **no** refinement contract at all, so a *provably*
out-of-range index compiled in silence.

```march
-- stdlib/list.march
fn nth(xs : List(a), n : {Int | _ >= 0 && _ < len(xs)}) : a do
```

This is the first stdlib contract that is **cross-parameter**: the bound on `n`
mentions a measure of another parameter, `xs`. The shape was verified working
end to end before the task was planned (a user-written `fn at(xs : List(Int),
n : {Int | _ >= 0 && _ < len(xs)})` proved and violated correctly), so the risk
here was never feasibility — it was blast radius. `List.nth` is public API and
every call site in the stdlib and the ecosystem becomes an obligation.

## The measurement gate

The change was gated on a sweep taken **before** anything was committed: a
scratch stdlib with the contract applied, A/B'd against the unmodified stdlib
on the same compiler, caches (`.march/cas/artifacts-v2`, `.march/cas/vc`)
cleared once before each side.

**Stdlib — all 112 modules, `--check --refine-report` each:**

| | proved | violated | skipped |
|---|---|---|---|
| baseline | 1895 | **0** | 2785 |
| with contract | 1895 | **0** | 5783 |

Every module gained exactly 27 skips (24 for `list.march` itself, which sees
its own recursive `nth(t, n - 1)`; 40 for `stats.march`) and **not one
violation**. `proved` is unchanged, which is the expected reading: no stdlib
call site passes a literal index the solver can bound, so every new obligation
lands as a skip.

**Ecosystem.** The blast surface is exactly the set of files that call `nth`,
and it is small — a grep over `forgepm`, `conduit`, `depot` and `bastion`
(3772 `.march` files) found **two** distinct call sites: `forgepm`'s
`lib/forgepm/accounts/totp.march` (14 calls in its SHA-1 core) and `bastion`'s
`lib/forge/routes.march` (1). `conduit` and `depot` call only `nth_opt`.

| entry | violated (base → contract) | skipped (base → contract) |
|---|---|---|
| `forgepm/…/totp.march` (user code) | 0 → **0** | 2 → 16 |
| `bastion/lib/forge/routes.march` (user code) | 0 → **0** | 3 → 4 |
| `conduit/lib/conduit.march` | — → **0** | |
| `depot/lib/depot.march` | — → **0** | |

Every `totp.march` SHA-1 index (`List.nth(w, i - 3)`, `List.nth(hs, off + 3)`,
…) is bounded by loop arithmetic the checker cannot see, so all 14 became
skips reported as HINTs. That is the definite-failure stance working, not a
weakness: reporting them would have been a false positive, and a false positive
in the stdlib is the worst possible outcome for this feature's adoption.

**Decision: proceed.** Zero new violations, no genuine bug to fix, no false
positive to report.

### `proved 1895 → 1895` is not a verdict on the contract

That number says the stdlib's `nth` call sites are all loop arithmetic the
solver cannot see. It says nothing about the contract's power, and reading it
as "the contract is decorative" would be wrong. Independently confirmed during
review: the obligation is discharged by a runtime guard
(`if i >= 0 && i < List.length(xs) do List.nth(xs, i) …`), by a `match` arm
that narrows the index, and by caller-side contract composition — the same
three mechanisms that discharge `{List(a) | len(_) > 0}`. Twelve adversarial
shapes were probed for false positives; none fired.

### `cap verified` is the one mode where this is not silent

In the default mode an unbounded index is skipped and silent. Under
`cap verified` — whose entire premise is that every obligation is discharged —
it is now a hard **error** where it compiled clean before:

```
`cap verified` module: cannot verify precondition `_ >= 0 && _ < len(xs)`
on `List.nth` (solver-undecided: ...)
```

No stdlib module and none of the four sampled projects declare `cap verified`,
and all 13 pre-existing contracts behave identically in that mode, so this is
in-kind rather than novel. Worth stating anyway: the day anyone adds
`cap verified` to forgepm's `totp.march`, its SHA-1 core produces 14 such
errors at once.

## Witnesses

- `test/test_refinecheck.ml`, suite `stdlib-nth-contract` — in-range **proves**
  (`proved >= 1`, not merely "no error": silence is what an absent contract
  produces too, so only the ledger can tell a proof from a vacuum);
  `List.nth([1,2,3], 7)` and `List.nth([1,2,3], -1)` are violations; and an
  **unknown** index is silent *because the obligation was raised and then
  SKIPPED* (`skipped >= 1`), not because no obligation exists. That fourth case
  is the false-positive guard and is the assertion that matters most — and
  asserting only silence would have let it stay green if `List.nth`'s
  obligation vanished entirely, the precise regression the definite-failure
  stance exists to prevent. The fixtures restate the `nth` signature
  inline as a nested `mod List`, because this harness checks a single parsed
  string and — unlike `bin/main.ml` — does not prepend the stdlib; a bare
  `List.nth(…)` would resolve to nothing and all four cases would pass
  vacuously.
- `specs/lang/types/accept/t141_refine_nth_in_range.march` — in-range plus the
  unknown-index silence case, against the REAL stdlib.
- `specs/lang/types/reject/t142_refine_nth_out_of_range.march` — the
  load-bearing half; an accept-only witness cannot distinguish an enforced
  contract from an absent one.

## Load-bearing, by mutation

Reverting the parameter to a bare `n : Int`:

- in `test/test_refinecheck.ml`'s fixture → **all four** cases go red. The two
  violation controls fail on the verdict; the in-range and unknown-index cases
  fail on the ledger (`proved >= 1`, `skipped >= 1`). Those two ledger
  assertions were added after review: as first written they asserted only
  silence, which an absent contract satisfies just as well, so they could not
  fail at all.
- in `stdlib/list.march` → `reject/t142` exits **0 with zero bytes of
  diagnostic output**, i.e. the corpus witness dies.

## Verification

- `test_refinecheck.exe -e`: 474 tests, 0 failures (baseline 470).
- `specs/lang/types/check_types.sh`: **244 / 244** (123 accept, 121 reject).
  Baseline on this branch was 240 passed / 2 failed; the two failures were the
  known capability-subsystem bug that emits garbage bytes in a capability name,
  which is memory-layout sensitive and stopped reproducing here. It is
  unrelated to this change and remains recorded.
- `run_compiler` 675, `run_eval` 256, `run_codegen` 544, `run_stdlib -e` 782 —
  all green except the known-environmental
  `adversarial-regressions #40 MARCH_SANITIZE` (host-wide ASAN breakage; a
  trivial unrelated `clang -fsanitize=address` C program hangs identically).
