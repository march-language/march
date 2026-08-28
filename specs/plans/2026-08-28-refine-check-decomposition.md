# Decomposing `lib/refinecheck/refine_check.ml`

> **For agentic workers:** every task is a *behaviour-preserving band move*. There is no
> new behaviour to test, so the TDD cycle is replaced by: record an oracle baseline,
> prove the oracle goes **RED** on a deliberate perturbation, then require **GREEN** plus
> a byte-identical splice check. Steps use `- [ ]` syntax.

**Goal:** `refine_check.ml` is the largest file in the compiler — **7,583 lines, 83
commits in six months** — and it *grew* during the decomposition project (7,416 → 7,583)
while every other target shrank. It is the one file the project named and never touched.

**Architecture:** the file is a **strictly linear pipeline**. Measured on
comment-stripped code, all seven candidate bands have **zero forward dependencies** and
between 0 and 49 backward ones. So it decomposes by peeling from the top, each new module
`include`-ing the one below it, and `refine_check.ml` keeping a single `include` of the
current top of the chain. Ordering is not a preference here — see "Why top-down is
forced" below.

**Tech stack:** OCaml 5.3.0, dune, opam switch `march`.

## Global Constraints

- Never `git stash` in a march worktree (shared stash stack). Use a temporary WIP commit.
- `git add` explicit paths only — never `-A`, `.`, `-a`, `*`.
- No `Co-Authored-By` trailers. Never prefix a command with `eval $(opam env …)`.
- Build with `dune build --root . <targets>`; a targetless `dune build --root .` wedges.
- Judge every command by its exit code, never by tail output, never through a pipe.
- Run oracles under a **private `HOME`**, and suffix every `/tmp` path with a worktree
  slug — `/tmp` and `~/.cache/march` are shared across every worktree on this box.
- `lib/refinecheck/dune` has an explicit `(modules …)` list. **Every new module must be
  added to it**, or the build fails with `Unbound module`. (`lib/desugar` has no such
  list, which is why the finding-3 work needed no dune change there — do not generalise
  from that.)
- Update `specs/todos/` → `specs/progress/` in the same commit. Skip `CHANGELOG.md`:
  these are internal refactors with no observable behaviour change.

## The oracle situation — read this before writing any verification step

**`scripts/ir-oracle.sh` proves NOTHING here, and its green is actively misleading.**
`refine_check.ml` affects *diagnostics*, not emitted code: a checker that stopped
checking emits byte-identical IR. `scripts/refine-oracle.sh` says so in its own header.
Do not run ir-oracle for these tasks and do not cite it.

The real stack, and what each part can and cannot see:

| Check | Corpus | Catches | Blind to |
|---|---|---|---|
| `scripts/refine-oracle.sh` | `test/native/*.march` + `stdlib/*.march` — **all accepting** | a *changed* diagnostic | a check that silently **stopped firing** |
| `dune build @types-check --force` | `specs/lang/types/reject/` — **157 fixtures, 45 refinement-bearing** | a **dropped** check | — |
| `scripts/types-oracle.sh` | 601 fixtures, two tiers | core-AST + diagnostic **text** | — |
| `scripts/run-tests.sh` | 3,177 tests | regressions in behaviour | dune-rule tests (see below) |

**The reject corpus is the one that matters** and it is the one that is easiest to skip:
`@types-check` is **CI-only** — `scripts/run-tests.sh` does not run it — and **without
`--force` it is vacuous**: it exits 0 with a zero-byte log. Assert on the log's contents,
never on the exit code. This is not hypothetical for this file: the capability walks in
this pass have had `| _ -> ()` holes **five times**, and every one of them was invisible
to accepting programs and caught only by a reject witness.

**Two caches produce vacuous green** and `refine-oracle.sh` clears both once, before its
sweep: `.march/cas/artifacts-v2` (a compile-path CAS hit short-circuits before
`--refine-report` prints) and `.march/cas/vc` (verification conditions are reused, so a
checker that stopped checking still "proves"). Never clear them *between* fixtures.

## Why top-down is forced

Band `R4` (`check_call`, 1,874 lines) has **zero forward deps but 39 backward deps**. If
it were extracted first, `refine_call.ml` would need 39 names that still live in
`refine_check.ml`, while `refine_check.ml` includes `refine_call.ml` — a dune cycle. The
same holds for every band below the first. So the layers must come out **in order**, each
`include`-ing its predecessor, and the last one extracted is the one `refine_check.ml`
includes.

## The 20 mutable cells — the hazard that outranks everything else here

`refine_check.ml` holds **20 top-level mutable cells**, and they are **defined in early
layers and mutated from late ones**:

| Cell | Defined | Mutated |
|---|---|---|
| `registered_measures` | `:491` (R1) | `:6763`, `:7504` (R7) |
| `withdrawals` | `:605` (R1) | `:7487`, `:7490` (R7) |
| `ret_ctr` | `:2669` (R3) | `:7528` (R7) — a counter, so **determinism** |
| `strict_verified` | `:3007` (R4) | `:6643`, `:7480` (R7) |
| `unverified_hinted` | `:3021` (R4) | `:6648` (R7) |
| `trusted_fn` | `:3027` (R4) | `:6605` (R7) |

…plus 14 more registries in R1 (`adt_ctors`, `axiom_measures`, `measure_preamble`, …).

`include M` re-exports **the same ref cell**, so the chain preserves identity and all of
this keeps working. The failure mode is re-*declaring* a cell in the new module instead of
including it: the reset in a late layer then clears a **different ref** than the one the
early layer's readers see. That is silent, and the accepting corpus will not show it.

**Assert after every task** — on comment-stripped code, because prose in the module
headers will name these and a plain `grep` will match itself (this exact mistake was made
during finding 3, on `install_lower_expr`, which reported 2/2 until the comments were
stripped):

```bash
for n in registered_measures withdrawals ret_ctr strict_verified unverified_hinted \
         trusted_fn adt_ctors axiom_measures measure_preamble ctor_field_sorts; do
  c=$(for f in lib/refinecheck/refine_*.ml; do python3 scripts/strip-comments.py "$f"; done \
      | grep -cE "^let $n( :|=| =)")
  [ "$c" = 1 ] || echo "FAIL: $n defined $c times (must be exactly 1)"
done
```

## The layers

**Use the file's own section map, not hand-drawn bands.** `refine_check.ml` opens with a
23-entry table of contents (`§1`…`§23`) and each section header appears verbatim in the
body as `   §N  <title>`. Those headers are the anchors: they are stable across edits,
they are what the author already grouped by, and they survive the line-number drift that
every task introduces. An earlier draft of this plan drew boundaries by eye and split
`§12` in half.

Measured at `5abb3604`, comment-stripped. "exports" = band names referenced from outside
the band; `include` re-exports them all automatically.

| # | New module | Sections | Band | Lines | code | backward | fwd | exports |
|---|---|---|---|---:|---:|---:|---:|---:|
| R1 | `refine_encode.ml` | §1–§6 | `:53–1429` | 1,377 | 711 | **0** | 0 | 64 |
| R2 | `refine_scope.ml` | §7–§11 | `:1430–2454` | 1,025 | 520 | 23 | 0 | 28 |
| R3 | `refine_resolve.ml` | §12–§13 | `:2455–2983` | 529 | 262 | 10 | 0 | 15 |
| R4 | `refine_call.ml` | §14–§15 | `:2984–4857` | 1,874 | 940 | 39 | 0 | 4 |
| R5 | `refine_post.ml` | §16–§18 | `:4858–5770` | 913 | 575 | 49 | 0 | 2 |
| R6 *(optional)* | `refine_visit.ml` | §19–§20 | `:5771–6576` | 806 | 439 | 24 | 0 | 4 |
| R7 *(optional)* | `refine_decls.ml` | §21–§23 | `:6577–7583` | 1,007 | 503 | 46 | 0 | 0 |

Lines 1–52 are the module doc comment and the table of contents; they stay.

**After R1–R5: `refine_check.ml` ≈ 1,866 lines** (from 7,583). After R1–R7 it is ≈ 53 — a
composition root holding only its doc comment and one `include`.

**Stop after R5 unless the review budget is clearly there.** R5 already removes 75% of the
file. R6/R7 move the visitor and, more importantly, **every mutation site** for the shared
cells (see below), which is where the risk concentrates.

What each layer is, so boundaries are not guesswork:

- **R1 `refine_encode`** — §1 refined parameters and base-type classification; §2 SMT
  sorts (strings, scalars, measures, well-sortedness); §3 predicate scope and parameter
  substitution; §4 function signatures, measures, stdlib-provided names; §5 the ADT/record
  sort registry and SMT preamble builders; §6 AST traversal helpers and measure gating.
  **16 of the 20 mutable registries live here.**
- **R2 `refine_scope`** — §7 reflection of March expressions into SMT terms; §8 rendering
  (predicates, models, counterexamples); §9 the refined-bindings scope; §10 the other
  fact channels (path, launder, recenv, cbenv); §11 signature extraction and definition
  collection.
- **R3 `refine_resolve`** — §12 name resolution (module paths, aliases, call targets);
  §13 reflecting actual arguments (fields, records, scalars).
- **R4 `refine_call`** — §14 verdict state and withdrawal diagnostics; §15 `check_call`
  itself, 1,361 lines and the single largest thing in the file.
- **R5 `refine_post`** — §16 postcondition checking; §17 postconditions by induction;
  §18 function-level postcondition entry points and gating.
- **R6 `refine_visit`** — §19 the `visit` traversal; §20 refinement-placement warnings.
- **R7 `refine_decls`** — §21 the declaration walk; §22 registration and stdlib-shape
  validation; §23 the `check_module` entry point.

---

### Task R1: extract the encoding / sort-discipline layer

**Files:**
- Create: `lib/refinecheck/refine_encode.ml` (sections §1–§6, `:53–1429`)
- Modify: `lib/refinecheck/refine_check.ml` (remove `:53–1429`, insert one `include`),
  `lib/refinecheck/dune` (add `refine_encode` to `(modules …)`)

**Interfaces:**
- Produces: 64 names re-exported through `include Refine_encode`, including the 16
  mutable registries (`registered_measures`, `withdrawals`, `adt_ctors`,
  `axiom_measures`, `measure_preamble`, `ctor_field_sorts`, `ctor_field_names`,
  `type_preamble`, `measure_preamble_sorts`, `measure_base_cases`,
  `measure_scalar_field_dep`, `measure_nonneg`, `stdlib_source_files`,
  `list_length_is_stdlib`, `string_byte_size_is_stdlib`,
  `string_byte_length_is_builtin`).
- Consumes: nothing. This band has **zero** backward dependencies — it is the bottom of
  the pipeline.

- [ ] **Step 0: land the comment stripper** (R1 only — later tasks depend on it)

Steps 6 and 7 of every task need a nesting- and string-literal-aware OCaml comment
stripper. Finding 3 used a throwaway copy in `/tmp`; that breaks on a fresh worktree and
makes the plan unreproducible. Land it as `scripts/strip-comments.py` — reading a file
path, printing non-blank code lines with comments removed, handling nested `(* … *)` and
`"…"` (including `\\` escapes) — and commit it as part of this task.

- [ ] **Step 1: record the baseline** (before any edit)

```bash
export HOME=/tmp/march-home-refine-R1; mkdir -p "$HOME/.cache"
dune build --root . bin/main.exe
scripts/refine-oracle.sh baseline /tmp/refine-base-R1
scripts/types-oracle.sh   baseline /tmp/ty-base-R1
dune build --root . @types-check --force 2>&1 | tee /tmp/types-check-base-R1.log
wc -l /tmp/types-check-base-R1.log    # MUST be non-zero; a 0-byte log means vacuous
```

- [ ] **Step 2: prove the apparatus goes RED — in the REJECT direction**

An accepting-corpus oracle cannot see a dropped check, so the perturbation must make the
checker **accept something it must reject**. `measure_gate_errors` (§6, around `:1363`)
returns the list of `@[measure]` soundness violations; an empty list means "sound". Force
it to accept everything:

```bash
L=$(grep -n '^let measure_gate_errors' lib/refinecheck/refine_check.ml | cut -d: -f1)
perl -i -pe "s/^(let measure_gate_errors .*: string list) =/\$1 = ignore fd; []  (* RED PROBE *) or/ if \$. == $L" \
  lib/refinecheck/refine_check.ml
# simpler and less fragile: edit that one function by hand to `= []`
dune build --root . bin/main.exe          # must exit 0
dune build --root . @types-check --force 2>&1 | tee /tmp/types-check-red-R1.log
diff /tmp/types-check-base-R1.log /tmp/types-check-red-R1.log   # MUST differ
scripts/refine-oracle.sh check /tmp/refine-base-R1              # SHOULD also differ
git checkout -- lib/refinecheck/refine_check.ml
dune build --root . bin/main.exe          # restore the clean binary before continuing
```

If `@types-check`'s log is **unchanged**, stop: either the probe is inert or the reject
corpus does not reach this code, and nothing below proves anything. Pick another gate and
repeat until one goes RED.

This is not a formality. During finding 3, **three consecutive "obvious" perturbations of
`derive_impl` were inert** — renaming the generated `to_json`, renaming the derived `eq`,
and reversing `impl_methods` — because those names are all discarded downstream. Each
returned IDENTICAL on a corpus that genuinely contains `derive Json` and `derive Eq`
programs. Taking the first green as proof would have "verified" that task against nothing.
Assume every probe is inert until it demonstrates otherwise.

- [ ] **Step 3: move the band verbatim**

```bash
F=lib/refinecheck/refine_check.ml
sed -n '53,1429p' $F > /tmp/band-R1.ml
head -52 $F > /tmp/R1-part1
tail -n +1430 $F > /tmp/R1-part3
```

Write `lib/refinecheck/refine_encode.ml` as: a module doc comment, the same
`module`/`open` header lines `refine_check.ml` uses above `:53` (copy them; do not invent
them), then `/tmp/band-R1.ml` appended unchanged. Then rebuild `refine_check.ml` as
`part1` + this block + `part3`:

```ocaml
(* ── Encoding + sort discipline (moved to [Refine_encode]) ────────────────
   The String/Bool/Float sort encoding, the measure machinery and the M-b
   soundness gate moved VERBATIM into [Refine_encode].  [include], not
   aliases: refine_check.mli exports these names, and — more importantly —
   the 16 mutable registries in that band are RESET from the bottom of this
   file (registered_measures at :6763/:7504, withdrawals at :7487).  An
   include re-exports the same ref cell; re-declaring one would silently
   create a second. *)
include Refine_encode
```

- [ ] **Step 4: add the module to dune**

```bash
perl -i -pe 's/\(modules refine_check /(modules refine_check refine_encode /' lib/refinecheck/dune
```

- [ ] **Step 5: build**

Run: `dune build --root . bin/main.exe lsp/bin/main.exe`
Expected: exit 0. `Unbound module Refine_encode` means Step 4 was skipped. An
`unused value` warning means the name is used only by the band and should **move**, not be
kept as a dead re-export — that is what happened to four aliases in `lower.ml`.

- [ ] **Step 6: assert the mutable cells are still single-definition**

Run the loop from "The 20 mutable cells" above. Every cell must report exactly 1.

- [ ] **Step 7: splice check — prove the move was verbatim**

Comment-stripped code, with `include Refine_encode` replaced by the new module's code
(minus the header you authored), must reproduce the original **in order**:

```bash
git show HEAD:lib/refinecheck/refine_check.ml > /tmp/R1-orig.ml
python3 scripts/strip-comments.py /tmp/R1-orig.ml > /tmp/R1-base.code
# splice and diff; expected: empty, or only lines you can name and justify
```

- [ ] **Step 8: oracles GREEN**

```bash
scripts/refine-oracle.sh check /tmp/refine-base-R1     # IDENTICAL
scripts/types-oracle.sh   check /tmp/ty-base-R1        # Tier 1 + Tier 2 IDENTICAL
dune build --root . @types-check --force 2>&1 | tee /tmp/types-check-R1.log
diff /tmp/types-check-base-R1.log /tmp/types-check-R1.log   # empty
```

- [ ] **Step 9: full suite** — `scripts/run-tests.sh`, exit 0, 3,177 tests.

- [ ] **Step 10: commit**

```bash
git add lib/refinecheck/refine_check.ml lib/refinecheck/refine_encode.ml lib/refinecheck/dune
git commit -m "refactor(refinecheck): move the encoding/sort layer to refine_encode.ml"
```

---

### Tasks R2–R5

Identical in shape to R1. Only these four values change per task:

| Task | Module | Sections | Includes at its top | dune insert after |
|---|---|---|---|---|
| R2 | `refine_scope.ml` | §7–§11 | `include Refine_encode` | `refine_encode` |
| R3 | `refine_resolve.ml` | §12–§13 | `include Refine_scope` | `refine_scope` |
| R4 | `refine_call.ml` | §14–§15 | `include Refine_resolve` | `refine_resolve` |
| R5 | `refine_post.ml` | §16–§18 | `include Refine_call` | `refine_call` |

**Line numbers shift after every task.** Re-derive each band by its section banner at the
moment of use — never trust the numbers in this table after R1 has landed. The banners
are stable anchors:

Re-derive a band at the moment of use, from the section headers:

```bash
# start of §N .. line before the start of §M
grep -n '^   §7  ' lib/refinecheck/refine_check.ml   # band start
grep -n '^   §12 ' lib/refinecheck/refine_check.ml   # band end + 1
```

Note the table of contents at the top of the file also matches `§N`; take the SECOND
match (the body header), or anchor on the three-space indent as shown.

After each task, `refine_check.ml`'s single `include` line changes to name the new top of
the chain — there is never more than one `include Refine_*` in `refine_check.ml`.

Each task repeats R1 Steps 1–10 with its own `-R<N>` baseline suffixes, **including its
own RED proof** — a perturbation that went RED for R1 says nothing about whether the
corpus reaches R4's code.

---

## Closing out

- [ ] File `specs/progress/2026-08-2X-refine-check-decomposition.md` recording: final line
      counts, which layers were taken and which declined, the RED probe that worked for
      each task (future maintainers should not have to rediscover the inert ones), and the
      single-definition assertion for the 20 mutable cells.
- [ ] Update `specs/2026-08-25-file-decomposition-analysis.md`: `refine_check.ml` was the
      one target the project named and never executed, and it **grew** 7,416 → 7,583 while
      everything else shrank. Record the corrected figure.
- [ ] Update the `lib/refinecheck/` line in `CLAUDE.md`'s project layout.
- [ ] `scripts/check-docs.sh` must pass.
