# Law coverage and law strength (design, 2026-11-04)

Status: design, not built. Follows the `@[lemma]` tooling of
`specs/todos/2026-11-02-lemma-uses-beyond-refinement.md` (ideas 1-6, done) and phase 3's stdlib
`List` lemmas (`specs/progress/2026-11-03-reflection-phase3-stdlib-list.md`).

## 1. Intent

A lemma is a law about the code. Now that laws can be written, proved, tested, searched and shipped
in the stdlib, the next question for whoever maintains a library is **which pure functions have no
laws, and which have laws too weak to pin them down**.

The audience is the language designer and library authors (the stdlib first). The report is a
to-do list: the functions worth writing laws for next. It is not a quality gate and not a score
to optimise.

Two parts:

- **Coverage** (cheap, always available): which pure functions no admitted law mentions.
- **Strength** (opt-in, slower): for each covered pure function, small edits to its body that every
  law mentioning it still accepts. A surviving edit is behaviour the laws do not pin down.

## 2. Goals, non-goals, anti-goals

Goals:
- List every pure function of a module or package with no law, public ones first.
- For covered functions, list the laws that cover them, and with `--law-strength` the edits that
  survive them, each readable on one line.
- Run on the stdlib, so the Q2 rollout (`Option`, `Result`, `Map` after `List`; reflection design
  §11 Q2) has a concrete list.

Non-goals (this version):
- General mutation testing judged by unit tests, property tests or doctests. Mutation here is only
  within law coverage, judged only by laws. (The user ruled this out to keep scope.)
- Edits spanning several functions, or edits to a function's callees.
- Proving with z3 that an edit breaks a law; the judgement is by evaluation.
- Suggesting the missing law.
- `forge doc` marks for uncovered functions (a possible later addition).
- Impure, non-terminating or partial functions: they cannot have laws (D6), so they are left out,
  not reported as gaps.

Anti-goals (would make it a failure even if it ran):
- **A false "weak".** An edit that does not change behaviour (swapping the operands of `+`) must
  never be reported as surviving. A report full of those teaches the reader to ignore it.
- **Counting an unproved law as coverage.** An unproved lemma covers a function only on paper; it is
  shown separately, never folded into the covered count.
- **Cost leaking into ordinary checks.** Neither part runs unless asked for; `--check` without the
  flags is unchanged, byte for byte.
- **Changing what a lemma means or whether it is admitted.** Both parts only read verdicts.

## 3. Definitions

- **Pure function**: a function the checker reflects (reflection design D1/D6; terminates, no
  effects, cannot fail, every match covers every case). `--reflect-report`
  (`Refine_reflect.report_lines`, `lib/refinecheck/refine_reflect.ml`) already decides this per
  function; coverage uses the same verdict. Only the `Reflected` verdict counts. Lemmas themselves
  are excluded from the list.
- **Higher-order functions** (verdict `Specialised`: reflected per call site, phase 5, such as
  `List.map` and `List.filter`) are pure but cannot yet carry a law about the function itself,
  since a lemma's parameters cannot be functions. They are listed in their own group,
  `higher-order (no laws possible yet)`, and are **not** in the headline count. *(Builder-check
  ruling, my call.)*
- **Admitted law**: a lemma the checker proved, or one admitted as trusted from the stdlib manifest
  (`stdlib/lemmas.verified`). The same notion `--lemma-test` and the LSP rewrite use.
- **Covers**: a law covers a function when the law's **theorem** calls it, directly, as resolved by
  the checker (qualified names resolved, a local alias followed). Being unfolded inside the law's
  proof does not count: `len_append` covers `append` and `len`, not a helper its proof unfolds.
- **Impl methods**: the checker reflects an impl method only through the copies interface laws
  generate (`__law_<m>__<Iface>_<T>`, `lib/desugar/interface_laws.ml`). So impl methods are listed
  only for impls of interfaces that declare laws, one row per method, in an `impl methods` group
  under the impl (`Ord for Version: compare`), covered by the generated laws, named
  `<law> (via <Iface>)`. Their purity verdict is the copy's. Methods of interfaces with no laws
  are left out, like any function that cannot have a law. They are not in the headline count.
  Strength edits the method body, judged through the copy. *(Builder-check ruling, my call.)*
- **Which calls a theorem makes**: walk the theorem's AST (the lemma's `fn_ret_ty` refinement, as
  the checker holds it after resolution), not `Lemma_source.calls`, which is a text scanner and has
  no text for generated laws. Law search is unchanged; the two may differ slightly. *(My call.)*

## 4. Coverage

### What it reports

Per module, in source order within each group:

```
law coverage: List  31 of 58 pure functions have a law (2 more only by unproved laws)
  uncovered (public):   zip, unzip, last, init, intersperse, ...
  uncovered (private):  take_onto_rev, ...
  unproved only:        rotate (rotate_len, unproved)
  covered:              append (append_nil, append_assoc, len_append, reverse_append), ...
```

Each function line carries its `file:line`. The summary line is the only number, and it counts
admitted coverage only.

### Where it lives

- **Scope.** `march --check --law-coverage FILE` counts every admitted law the check loaded,
  including lemmas in other files on `MARCH_LIB_PATH` and the stdlib, and reports the entry
  file's functions. `forge audit --laws` reports every source file of the package's own `src/`/
  `lib/`, with laws from all of them pooled, so a law in `b.march` covers a function in
  `a.march`. Test files are not reported and their laws do not count. *(My call.)*
- `march --check --law-coverage FILE` prints the block for the entry file's modules
  (like `--reflect-report`: user spans only, unless the file is a stdlib file).
  `--law-coverage-json` gives one record per function: `{module, fn, public, file, line, covered_by:
  [..], unproved_by: [..]}` (plus a `strength` field, §5, when that ran).
- `forge audit --laws` runs it over the package's own sources (not its dependencies) and prints the
  same blocks. The user settled that it lives in `forge audit`. `--laws` runs **only** the law
  report: no capability audit, no `forge.caps.lock` needed, and it always exits 0 unless the check
  itself fails, because it is a to-do list, not a gate. `forge audit` without `--laws` is
  unchanged. *(Exit code and separation: my call.)*
- No change to `forge doc`, the LSP or any default output.

### How

After the refinement check, which already holds the reflection verdicts and the admitted-lemma
table (`lemma_rows`/`lemma_defs` in `lib/refinecheck/refine_check.ml`): for each admitted lemma,
resolve its theorem's calls; invert into function -> laws; list reflected, non-lemma functions with
none. No new z3 queries.

## 5. Strength (`--law-strength`)

### What it reports

Next to each covered function:

```
  reverse   4 of 11 edits survive its laws (len_reverse, reverse_reverse)
    survives: return `xs` unchanged                       list.march:212
    survives: swap the arguments of `reverse_onto`        list.march:213
    ...
  append    0 of 9 edits survive
```

An edit is described in words plus its location, never as a raw AST dump.

### The edits

One edit at a time, to the covered function's own body only, at most **20 per function**
(deterministic order and selection, so two runs agree):

| Kind | Example |
|---|---|
| return a parameter | the body becomes `xs` (one per parameter whose type is the result type) |
| swap call arguments | `f(a, b)` -> `f(b, a)` when both have the same type |
| swap constructor arguments | `Cons(h, t)` -> not applicable (types differ); `Pair(a, b)` -> `Pair(b, a)` |
| nudge an Int literal | `0` <-> `1`, `n` literal -> `n + 1` |
| swap two match arms' results | arms of the same match whose results have the same type |
| drop the recursive call | `f(t) + h` -> `h`, `Cons(h, f(t))` -> `Cons(h, t)` where types allow |
| flip a comparison | `<` <-> `<=`, `==` <-> `!=` |

Every edit must typecheck; one that does not is discarded silently (not counted).

### Judging an edit

For each edit, evaluated in the interpreter with the edited body in place, on the inputs
`--lemma-test` uses (`Reflect_parity.inputs`: boundary values, then `Reflect_parity.draws` random
draws from its fixed seed, `lib/refinecheck/reflect_parity.ml`):

1. **Did the edit change behaviour?** Run the original and the edited function on generated inputs
   for the function's own parameters. If some decided input gives a different result, the edit
   changed behaviour. If every decided input agrees, the edit is **dropped as equivalent** and not
   counted; this is the guard against the first anti-goal. If **no** input could be decided, the
   edit is **undecided**, not equivalent. If the function's parameters have no generator at all,
   the whole row reads `strength: not run (no input generator)`. Neither case may ever read as
   "0 survive", which would be a false "strong". *(Builder-check ruling, my call.)*
2. **Do the laws notice?** Evaluate every admitted law that covers the function, on its own inputs,
   exactly as `Lemma_test.test_lemma` does (`lib/refinecheck/lemma_test.ml`), with the edited
   function in place. If some law is false on some input the edit is **killed**. If every law holds
   on every decided input it **survives**. An edit under which no law could be decided on any input
   (fuel, panic, overflow everywhere) is **undecided** and reported as such, not as surviving.

The edited function is installed by evaluating a copy of the module with that one declaration
replaced (`Witness.set_module` resets the interpreter environment for a new module value;
`Witness.module_env` builds it). The builder may find a cheaper swap, such as rebinding only the
edited function in an environment built once, if it gives the same results. A recursive function
must call its edited self.

### Cost

Opt-in only. Edits x (equivalence inputs + laws x law inputs) interpreter evaluations per covered
function; no z3. The existing witness wall budget does **not** bound this: `eval_classified` is not
charged to it, and `set_module` resets it. So strength has its **own** budget: a wall-clock cap per
function (default 5 s, `MARCH_LAW_STRENGTH_MS`), counted across all its edits. A function that
reaches the cap prints `strength: partial (budget), N of M edits judged`, with its survivors so far.
Strength does not run in CI over the stdlib; its tests use small fixtures. The target is minutes
for the whole of `stdlib/list.march` on a laptop, not a hard limit. *(My call.)*

## 6. Tests

- A fixture with a covered, an uncovered, an unproved-only and a private function: exact coverage
  block and JSON.
- A theorem calling a function through an alias and a qualified name counts; a call only inside the
  proof does not.
- An interface law covers an impl's method, shown with `(via Iface)`.
- Strength: a function whose laws pin it (`append` with `append_nil` + `len_append` +
  `append_assoc`) has a known survivor count; a function with only a length law
  (`reverse` with `len_reverse` alone) has "return `xs` unchanged" surviving, and it still survives
  `reverse_reverse`. Adding `reverse_append` (`reverse(append(a, b)) == append(reverse(b),
  reverse(a))`) kills it.
- A higher-order function shows in its own group, not in the count; a function with no generator
  shows `strength: not run (no input generator)`; an edit with no decided input is undecided.
- An impl of an interface with laws shows its methods covered `via` the interface; an impl of an
  interface without laws shows no rows.
- The per-function budget: a fixture with a tiny `MARCH_LAW_STRENGTH_MS` prints `partial (budget)`.
- Equivalent edit: `a + b` -> `b + a` is dropped, never reported.
- Determinism: two runs give identical output.
- `--check` without the flags: output unchanged (an existing golden test covers it; add one that
  asserts the new flags print nothing when absent).
- `forge audit --laws` on a small package; `forge audit` without `--laws` unchanged.
- Run on `stdlib/list.march` and record the result in the progress note.

## 7. Settled, and left to the builder

Settled with the user:
- Audience: the language designer and library authors; purpose: find uncovered pure functions.
- Definitions of pure (reflected) and covered (named by an admitted law's theorem; unproved shown
  apart).
- The report's shape (§4), `march --check --law-coverage` plus `forge audit`.
- Strength is wanted in this version ("covered but weak"), judged by laws only, narrow scope.

Settled by me after the builder check (marked *my call* above): higher-order functions in their
own group; impl methods only for interfaces with laws; theorem calls from the AST; scope per entry
file vs package; `forge audit --laws` is report-only and exits 0; an undecided edit or a missing
generator never reads as zero survivors; strength's own per-function budget.

Left to the builder:
- Module layout (a new `lib/refinecheck/law_coverage.ml` and `law_strength.ml` is the obvious shape).
- The exact edit-description wording and the selection when more than 20 edits apply.
- Docs: a section in `specs/lang/lemmas.md` (then `scripts/gen-lang-docs.py`), the CHANGELOG, a
  progress note, and an `affected.sh` rule if a new test executable is added.
