# Which compiler files to decompose, and in what order

**Date:** 2026-08-25
**Feeds:** `specs/plans/2026-08-19-compiler-file-decomposition.md`
**Supersedes:** the file-size column of `specs/features/compiler-pipeline.md`'s
Implementation Status Summary, which was stale by 3–7× and has been removed in
favour of this document.

> ## Status, 2026-08-27 — most of this has since been done
>
> This document selected the targets; the work then happened. Read the findings
> below as **the reasoning that drove it**, not as open recommendations. What
> changed:
>
> | File | At analysis | Now |
> |---|---:|---:|
> | `typecheck.ml` | 14,958 | 8,272 |
> | `eval.ml` | 12,265 | 4,304 |
> | `analysis.ml` | 8,133 | 5,201 |
> | `llvm_emit.ml` | 5,720 | 2,271 (`emit_expr` 4,319 → 1,394) |
> | `bin/main.ml` | 5,403 | 4,198 |
>
> - **Finding 4 is closed.** "Only 2 of 31 files over 800 lines have an `.mli`" —
>   it is now 22 of 34. Two interface passes curated ~680 inferred values to ~380.
> - **Finding 5 is closed, with a better answer than either side had.** `bin/main.ml`
>   was re-examined: the 579-line TIR pass sequence *is* the linear driver code
>   Phase 5 defended and stays; the build plumbing beside it went. 49% of six months'
>   hunks land inside `compile`.
> - **Finding 1 is closed.** Phase 6 was re-scoped from "cold data only" to nine
>   tasks and executed.
> - **Finding 3 is partly open.** `lower.ml`, `desugar.ml` and `perceus.ml` still
>   have no decomposition phase, though all three now have interfaces.
> - **Finding 2 stands** as a method result: concentration without churn is not
>   worth fixing. `llvm_case.ml` remains untouched, correctly.
>
> Remaining work lives in `specs/plans/2026-08-27-remaining-decomposition-targets.md`.
> Outcomes are recorded in `specs/progress/2026-08-26-compiler-file-decomposition-complete.md`.

## Why this exists

The decomposition plan picked its targets in August 2026 from sizes that were
already wrong, and `compiler-pipeline.md` carried a *different* set of wrong
sizes (it claimed `typecheck.ml` was 2,006 lines in one table and ~7,700 in a
section header; it is 14,958). Neither document ranked by how often anyone
actually has to work in these files. This is a measurement pass, so target
selection rests on numbers that were true when written and are cheap to
re-derive.

## Method

Three axes, measured 2026-08-25 at `1e5bafcf`:

- **Size** — total lines. Proxy for how much you must hold in context.
- **Concentration** — lines in the file's single largest top-level definition,
  as a share of the file. A 1,000-line function is unworkable regardless of its
  file's size.
- **Churn** — commits touching the file in the last six months. This is the one
  the earlier passes omitted, and it is the one that decides payoff:
  decomposing a file nobody edits buys nothing.

Reproduce with `git log --oneline --since="6 months ago" -- <file> | wc -l` and
the line/concentration scan in the appendix.

> **Correction, 2026-08-26 — the concentration metric undercounts recursion groups.**
> The scan below measures the largest *top-level definition*, treating a col-0 `and`
> as a boundary. In OCaml a `let rec f … and g … and h …` group is a single unit that
> must move together, so the metric stops at the first `and` and reports less than the
> real figure. Found while writing the Phase 6 plan: `typecheck.ml`'s `infer_expr`
> chain is **2,217 lines across 14 mutually recursive functions** (`:5724–7941`), not
> the 1,500 first reported here — a 48% undercount, and it is the number a
> decomposition actually faces. Re-checked against the other large files: `lower.ml`
> is understated by 6% (896 → 949) and `perceus.ml`, `mono.ml` and `desugar.ml` are
> exact, so `typecheck.ml` is the only row this materially changed. The appendix
> command still measures per-definition; measure the enclosing group before planning
> any extraction.

> **Second correction, 2026-08-27 — the scan also *over*counts around `class`.**
> The metric treats only `let`/`type`/`module`/`external` at column 0 as boundaries,
> so an OCaml `class` is invisible to it. In `lsp/lib/server.ml` that made
> `semantic_tokens_data` (really **123** lines, `:245–368`) appear to absorb
> everything to EOF and report **1,313 lines / 84%** — the worst concentration in
> the original table, and an artefact. The real largest unit is
> `dispatch_by_method` at 644 lines (41%). Found while planning the remaining
> targets. Combined with the `let rec … and` undercount noted above, this metric
> has now erred in **both** directions: it splits recursion groups that must move
> together, and merges anything separated by a construct it does not recognise.
> Treat its output as a shortlist to verify, never as a measurement to plan from.

A fourth, qualitative axis matters for *risk*, not priority: whether the large
definition is **logic** or a **data table**. `eval.ml`'s `base_env` (5,290
lines) and `llvm_builtins.ml`'s `builtins` (893) are tables — long, simple, and
nearly free to move. `emit_expr`, `check_call`, `infer_expr` and `compile` are
logic, where extraction can change behaviour.

## The measurements

| File | Lines | Largest definition | Conc. | Commits/6mo | Pain score |
|---|---:|---|---:|---:|---:|
| `lib/typecheck/typecheck.ml` | 14,958 | `infer_expr` group **2,217** [see note] | 15% | **387** | **5,789** |
| `lib/eval/eval.ml` | 12,265 | `base_env` 5,290 *(table)* | 43% | 262 | 3,214 |
| `bin/main.ml` | 5,403 | `compile` 2,510 | 46% | **337** | 1,820 |
| `lib/tir/llvm_emit.ml` | 5,720 | `emit_expr` 4,319 | **76%** | 299 | 1,710 |
| `lsp/lib/analysis.ml` | 8,133 | `ast_code_actions` 1,089 | 13% | 129 | 1,049 |
| `lib/refinecheck/refine_check.ml` | 7,417 | `check_call` 1,361 | 18% | 82 | 608 |
| `lib/tir/lower.ml` | 2,001 | `lower_module` 896 | 45% | 134 | 268 |
| `lib/desugar/desugar.ml` | 3,321 | `derive_impl` 942 | 28% | 76 | 252 |
| `lib/repl/repl.ml` | 2,290 | `run_tui` 1,109 | 48% | 71 | 163 |
| `lib/tir/perceus.ml` | 1,998 | `insert_rc_expr` 856 | 43% | 66 | 132 |
| `lib/tir/llvm_builtins.ml` | 1,851 | `builtins` 893 *(table)* | 48% | 54 | 100 |
| `lsp/lib/server.ml` | 1,557 | `dispatch_by_method` **644** [see note] | 41% | 33 | 51 |
| `lib/tir/mono.ml` | 1,327 | `rewrite_calls` 675 | 51% | 34 | 45 |
| `lib/tir/llvm_toplevel.ml` | 1,521 | `emit_module` 787 | 52% | 24 | 36 |
| `lib/tir/llvm_case.ml` | 1,093 | `emit_case` 1,040 | **95%** | 11 | 12 |

Pain score is `commits × KLoC` — a crude "how much oversized code does someone
have to navigate per unit of work". It is a sorting aid, not a target.

## Findings

**1. The plan's priority order is close to inverted at the top.**
`typecheck.ml` scores highest by a factor of nearly two over the next file, and
it is the plan's *most downscoped* phase (Phase 6, "cold data only" — extract
`builtin_cap_table` and stop). It is simultaneously the largest file in the
compiler and the most frequently edited, at 387 commits in six months. That
combination is the definition of the problem this project exists to solve.

The reason for the downscoping is real: at 10% concentration there is no single
clean seam, and type inference is mutually recursive, so the extraction is
genuinely harder than `eval.ml`'s. But "hard" is an argument about sequencing
and technique, not about value. Phase 6 should be re-scoped from "cold data
only" to a real plan, and it should not be last.

**2. Concentration without churn is not worth fixing.** `llvm_case.ml` is 95%
one function — the worst ratio in the tree — and would top any concentration-
ranked list. It changed 11 times in six months. Nobody is suffering there.
Ranking by concentration alone, as the earlier pass effectively did, promotes
cold code and hides `typecheck.ml`, whose diffuse 10% conceals the highest
actual cost in the repository.

**3. Three sizeable, actively-edited files are absent from the plan entirely.**

| File | Lines | Commits/6mo | Note |
|---|---:|---:|---|
| `lib/tir/lower.ml` | 2,001 | 134 | more churn than `refine_check.ml`, which gets a whole phase |
| `lib/desugar/desugar.ml` | 3,321 | 76 | fourth-largest `lib/` file |
| `lib/tir/perceus.ml` | 1,998 | 66 | 43% in `insert_rc_expr`; RC bugs are historically expensive here |

**4. Only 2 of 31 files over 800 lines have an `.mli`** — `repl.ml` and
`repl_jit.ml`. Everything else exports its entire contents. This is both a
cause of the growth and the cheapest partial remedy available: an interface file
declares a boundary, makes accidental coupling a compile error, and shrinks the
surface a reader must consider, without moving a single line of code. Several
targets below would get most of the benefit of decomposition from an `.mli`
alone, at a fraction of the risk. The decomposition plan does not mention `.mli`
files except for `refine_check.mli` in its Phase 3.

**5. `bin/main.ml` deserves re-examination.** Phase 5 declines to split it, on
the grounds that "linear driver code is the friendliest shape to work in". At
337 commits in six months — second-highest in the tree — and a 2,510-line
`compile` function, that argument is worth re-testing against the evidence. This
session alone hit three separate defects inside that function.

## Recommended order

Ranked by payoff, with the plan's current sequencing noted:

| # | Target | Approach | vs. plan today |
|---|---|---|---|
| 1 | `typecheck.ml` | Re-scope Phase 6 into a real decomposition. Start with an `.mli` and the cold tables, then peel off self-contained checkers (exhaustiveness, capability/`needs`, linearity) which are not part of the inference recursion. | **Promote** from last/downscoped |
| 2 | `eval.ml` | As planned: `base_env` is a table, so Phase 1 is high-value and low-risk. Keep the interpreter-perf control the plan now carries. | Unchanged (Phase 1) |
| 3 | `llvm_emit.ml` | As planned: 76% concentration in `emit_expr` with a natural split by construct. | Unchanged (Phase 2) |
| 4 | `bin/main.ml` | Re-open the "do not split" decision for `compile` specifically. | **Re-examine** Phase 5 |
| 5 | `lower.ml`, `desugar.ml`, `perceus.ml` | Add as a phase. Each has one dominant function and a clear seam. | **Add** — currently absent |
| 6 | `analysis.ml`, `refine_check.ml` | As planned. | Unchanged (Phases 3–4) |
| — | `llvm_case.ml`, `llvm_toplevel.ml`, `server.ml`, `mono.ml` | Leave. Cold enough that the churn does not justify the risk. | Not in plan; correctly so |

**Do first, independent of all of the above:** add `.mli` files to the
highest-churn targets (`typecheck.ml`, `llvm_emit.ml`, `lower.ml`,
`desugar.ml`). It is the only item here that buys a real boundary without
moving code, and it makes every later extraction safer by making the current
surface explicit.

## Appendix — re-deriving the table

```bash
# size + concentration + .mli presence, for every file over 800 lines
python3 - <<'PY'
import os,re
for root,dirs,files in os.walk('.'):
    if any(s in root for s in ('_build','.git','.superpowers','.march')): continue
    if not root.startswith(('./lib','./bin','./lsp','./forge')): continue
    for f in files:
        if not f.endswith(('.ml','.mll','.mly')): continue
        p=os.path.join(root,f); lines=open(p,errors='ignore').read().split('\n')
        if len(lines)<800: continue
        starts=[i for i,l in enumerate(lines) if re.match(r'^(let|and|type|module|external)\s',l)]
        big=max((b-a,lines[a][:46]) for a,b in zip(starts,starts[1:]+[len(lines)]))
        print(f"{len(lines):6} {big[0]:6} {100*big[0]//len(lines):3}% "
              f"{'mli' if os.path.exists(p[:-3]+'.mli') else '---'}  {p}  {big[1]}")
PY

# churn
git log --oneline --since="6 months ago" -- <file> | wc -l
```
