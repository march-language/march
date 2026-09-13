# Linearity holes: survey, specs, and order of work

**Status:** specced 2026-09-13. Nothing here is built. Each hole has its own
file in `specs/todos/` (one item per file); this plan is the map across them,
the measured matrix they all cite, and the order to build them in.

## Why this exists

Two linearity holes were open in `specs/todos/`, both found while designing
the choreography/endpoint line:

- [[2026-09-10-linear-lambda-parameter-not-must-use]]
- [[2026-09-10-linear-actor-state-field-retained-after-consume]]

Specifying them properly meant measuring their edges, and the edges were
wider than either file said. A 71-program probe sweep on `main` at
`8eb0d7ee` (compiler rebuilt in this worktree, private `HOME`, `march
--check`) found five more independent holes that silently accept a dropped
or duplicated `always_linear` value, and four older findings (L1, L3, L4,
L8) that are fixed but still documented as open.

## The measured matrix

All programs share this prelude unless stated:

```march
always_linear type S1 = S1(Int)
fn sink(s : S1) : Int do match s do S1(e) -> e end end
```

"acc" means `--check` exit 0 with no diagnostic. **Bold** = a hole.

### Binders: must-use (never used) and at-most-once (used twice)

| binder | never used | used twice | file |
|---|---|---|---|
| named `fn` param, annotated | rejected | rejected | — |
| `let`-bound | rejected | rejected | — |
| actor handler param, annotated | rejected | rejected | fixed 2026-09-12 |
| lambda param, check mode (`run(fn st -> …)`) | **acc** | rejected | lambda |
| lambda param, infer mode, annotated | **acc** | rejected | lambda |
| lambda param, `linear` keyword | **acc** | — | lambda |
| local `fn g(st : S1) … end` in a block | **acc** | rejected | lambda |
| lambda multi-param, second unused | **acc** | — | lambda |
| lambda param, infer mode, **unannotated** | **acc** | **acc** | unannotated |
| named `fn` param, unannotated, body fixes the type | — | **acc** | unannotated |
| actor handler param, unannotated | — | **acc** | unannotated |
| `let _ = S1(1)` | **acc** | — | wildcard |
| `fn _ -> 0` against `S1 -> Int` | **acc** | — | wildcard |
| `let (a, _) = (S1(1), S1(2))` | **acc** | — | wildcard |
| `match st do _ -> 0 end` on a linear param | **acc** | — | wildcard |

### Captures

| shape | result | file |
|---|---|---|
| infer-mode lambda capturing a linear `let` | rejected ("cannot be captured by a closure") | — |
| check-mode lambda capturing it, callee calls `k() + k()` | **acc** | capture |
| check-mode 1-arg lambda capturing it | **acc** | capture |
| local `fn g() … end` capturing it, called twice | **acc** | capture |

### Paths

| shape | result | file |
|---|---|---|
| linear consumed in `if` then-branch only (named fn, lambda, let) | **acc** | branch |
| same via `match` | **acc** | branch |
| same with `linear` keyword param | **acc** | branch |
| consumed in one branch, other branch `panic(…)` | acc (correct) | branch |
| linear param in scope across a `let?` that returns `Err` early | **acc** | branch |

### Records and actor state

| shape | result | file |
|---|---|---|
| actor: `sink(state.st)` then `{ state with n: … }` | **acc** | record |
| actor: `sink(state.st) + sink(state.st)` | **acc** | record |
| actor: `linear st : T` field, consume then retain | **acc**, not even a warning | record |
| actor: `linear st : T` field accessed twice (the `DActor` arm drops `fld_lin`) | **acc** | record |
| actor: `{ state with st: bump(state.st) }` | acc (correct) | record |
| actor: field untouched, `{ state with n: … }` | acc (correct) | record |
| actor: `let x = state.st`, `x` dropped | rejected (correct, `x` is let-bound) | — |
| let-bound record, `always_linear` field accessed twice | **acc** | record |
| let-bound record, `linear` field accessed twice | rejected | — |
| let-bound record, `linear` field consumed then record passed whole | **acc** | record |
| let-bound record, `always_linear` field consumed then `{ r with n: … }` | **acc** | record |
| param-bound record, same | **acc** | record |
| record holding an `always_linear` field dropped | **acc** | record |
| record holding an `always_linear` field passed whole twice | **acc** | record |

### Generic code and containers

| shape | result | file |
|---|---|---|
| `fn dup(x) do (x, x) end`, `dup(S1(1))` | **acc** | generics |
| `fn dup2(x : a) : (a, a)`, same | **acc** | generics |
| `fn drop_it(x) : Int do 0 end`, `drop_it(s)` | **acc** | generics |
| `let f = fn st -> print_line("…")`, `f(S1(1))` | **acc** | generics |
| `let xs = [s]`, `List.length(xs)` twice | **acc** | generics |
| `let p = (s, 1)`, destructured twice, both halves consumed | **acc** | generics |
| `let xs = [s, s]` | rejected (correct) | — |

### Findings documented as open that are fixed

| finding | doc claim | measured |
|---|---|---|
| L1 | `fn f(affine cap : T)` is a parse error | parses and checks |
| L3 | param-bound `linear` field double access is only a warning | error: "The linear value `r.st` is used more than once here." |
| L4 | a user type named `Handle` silently becomes linear | an ordinary type, bound and copied freely |
| L8 | `let h = open()` with `open : … -> linear T` is not tracked | error: "The linear value `h` was never used." |

## The files

| file | kind | priority |
|---|---|---|
| [[2026-09-10-linear-lambda-parameter-not-must-use]] | build-ready | P2 |
| [[2026-09-13-linear-wildcard-discards-a-linear-value]] | build-ready | P2 |
| [[2026-09-13-linear-capture-unchecked-outside-infer-mode-lambdas]] | build-ready | P2 |
| [[2026-09-13-linear-unannotated-parameter-never-promoted]] | build-ready | P2 |
| [[2026-09-10-linear-actor-state-field-retained-after-consume]] | build-ready, one decision to confirm | P2 |
| [[2026-09-13-linear-consumed-on-one-branch-only]] | decided: Option A (strict) | P2 |
| [[2026-09-13-linear-generic-code-and-containers]] | decided: Option B (opt-in); detailed design at build time | P2 |
| [[2026-09-13-linear-types-doc-cites-fixed-findings]] | docs | P3 |

## Order of work

1. **Docs** ([[2026-09-13-linear-types-doc-cites-fixed-findings]]). Trivial,
   and it stops the chapter telling readers to work around bugs that no
   longer exist.
2. **Lambda must-use.** Introduces the one shared helper the next three
   need: close a binder scope by checking the **entries it added** to
   `env.lin`, by physical identity, not by name (see that file for why name
   filtering is wrong once lambdas are involved).
3. **Wildcard discards.** Small, same binder sites.
4. **Capture outside infer mode.** Factors the capture snapshot out of the
   `ELam` infer arm into a helper used by three sites.
5. **Unannotated parameter promotion.** Extends the linear-entry record with
   a deferred mode. Builds on the step-2 helper, since the deferred decision
   is made at scope close.
6. **Record fields / actor state.** The largest build-ready item: field
   sentinels for `always_linear` fields, whole-use vs field-use interaction,
   and sentinels on the actor handler's `state`.
7. **Branches.** Option A. Must come after 2–6,
   because a stricter path rule multiplies the reach of every binder that
   step 2–6 newly tracks.
8. **Generic code and containers.** Option B; nothing in 1–7 depends on it.

Steps 2–6 each make the checker reject programs it accepts today. Land them
as separate PRs, so a corpus regression bisects to one rule.

## Shared test protocol

Every build-ready file lists its own witnesses. The common rules:

- **Prove every reject RED before the fix.** Every one in these files is
  accepted on `main` today; a reject witness that already fails before the
  change is testing something else.
- Corpus witnesses go in `specs/lang/types/{accept,reject}/`, numbered after
  the highest existing one at the time (today `accept/t197`), with rows in
  `specs/lang/types/INDEX.md`; run `dune build --root . @types-check --force`
  and read the log. Without `--force` the check is empty and exits 0.
- Unit cases go in `test/test_compiler.ml`'s `tag_and_typestate` group,
  where the 2026-09-12 handler-parameter fix put its own.
- **Measure the blast radius before and after.** Run
  `scripts/types-oracle.sh baseline <dir>` on the base commit and `check` on
  the change, under a private `HOME` (see CLAUDE.md, "Refactor oracles").
  Every changed line should be a new linearity diagnostic this item intends.
  Any other change is a false positive to fix, not to baseline.
- `scripts/run-tests.sh` (full), plus the session goldens
  (`test/session/*.march`). The generated `@[endpoints]` API is the heaviest
  in-repo user of `always_linear` values in callbacks, so it is the canary
  for steps 2, 4 and 5.
- Real-project gate: `~/code/bastion_todos` should still check clean.
- Affine and session-channel binders (`Chan(…)` parameters resolve to
  `TLin` and are tracked **affine**) must not start getting must-use errors.
  Every file below restricts new must-use checks to `Ast.Linear`.

## Relevant code

All in `lib/typecheck/typecheck.ml` unless noted; line numbers as of `8eb0d7ee`.

| what | where |
|---|---|
| `record_use` (double-use detection) | §3, ~l.110 |
| `bind_pattern_bindings` (`always_linear` promotion for pattern binds) | ~l.210 |
| `check_linear_all_consumed` (must-use, name-filtered) | l.273 |
| `ELam` infer arm (capture snapshot) | l.1776 |
| `ERecordUpdate` | l.1841 |
| `EField` (field sentinel use) | l.1881 |
| `check_expr` `ELam` peel (no capture check, no must-use) | l.2386 |
| `iter_paths_linear` (branch union) | ~l.2660 |
| `ELet` `auto_lin` | ~l.2840 |
| `ELetFn` in `infer_block` | l.2955 |
| `bind_lam_params` / `bind_lam_param` | l.3027 / l.3035 |
| `check_fn` param loop, must-use at close | ~l.3270 / l.3417 |
| actor handler binding, must-use at close | ~l.4300 / l.4331 |
| `bind_linear` | `typecheck_env.ml` l.1471 |
| `bind_linear_field_sentinels` (only `TLin` fields) | `typecheck_unify.ml` l.893 |
