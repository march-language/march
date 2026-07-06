# Widening Slice 2 — Modules, Imports & Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development to execute this plan task-by-task.

**Goal:** Widen the Core March references to cover **modules, imports, and visibility** — module declaration/nesting, bare-vs-qualified name resolution, `use`/`import`/`alias`, and visibility (`pfn`/`ptype`) — with operational + typing rules and a conformance corpus. **Unlike slice 1 (docs-only), this slice INCLUDES a compiler fix:** the cross-file visibility gap (private `pfn`/`ptype` callable from anywhere) is a precisely-located bug, and the user chose to fix it in-slice.

**Architecture:** `specs/lang/core-march.md` (operational) gains module declaration/nesting/name-resolution/export semantics; `specs/lang/core-march-types.md` (typing) gains visibility-as-a-typecheck-concept, the no-per-module-type-namespace design point, and qualified-type-path unification. The `specs/lang/types/{accept,reject}/` corpus grows. **Task 1 fixes the visibility bug** (`load_module_into_env`'s missing `ex_public` gate) + a diagnostic-quality fix, gated on the full test suite; the documentation (Tasks 2-4) then describes the CORRECTED behavior.

**Tech Stack:** OCaml (`lib/typecheck/typecheck.ml` for the fix) + Markdown; `typecheck.ml`/`eval.ml`/`desugar.ml`/`resolver.ml` are the sources of truth; `_build/default/bin/main.exe` (rebuilt after the fix) is the conformance oracle; the survey `.superpowers/sdd/modules-survey.md` is the authoritative catalog.

## Global Constraints

- **Base = current `origin/main`** (fetch + `git pull --ff-only`; rebase if it moved). Branch: `docs/core-march-types-skeleton`.
- **MIXED slice.** Task 1 is a COMPILER change (`lib/typecheck/typecheck.ml`) — it rebuilds and runs the FULL test suite. Tasks 2-5 are docs + corpus (no compiler changes; a gap needing a compiler change beyond Task 1's scope is a FILED finding). The daemon has been free recently — building is OK; if a build/test hangs >3 min, kill it and report.
- **The survey is the catalog, RE-VERIFY every citation + message live.** `.superpowers/sdd/modules-survey.md` has the line cites (e.g. `load_module_into_env` `:657–692`, `ExCtor` gate `:687`, `DMod` typecheck `:6793–6935`, eval `:8168–8283`, `resolver.ml`) + captured messages. Lines DRIFT — `grep -n` the construct live and cite the live line; re-run each reject through `--check` and pin the CURRENT message.
- **Corpus:** reuse `specs/lang/types/{accept,reject}/` (continue `tNN` — verify current highest with `ls`; after slice 1 it was accept t30 / reject t24, so new accept start **t31**, reject **t25**; re-confirm). Capture-not-guess. The visibility-REJECT programs depend on Task 1's fix being in place (that's why Task 1 is first).
- **Value-witness** operational claims where a program's output proves the rule (a qualified cross-module call returning a known value; a `use`-imported name resolving).
- **Findings filed, not fixed (beyond Task 1's scope).** Task 1 fixes the visibility gate + the diagnostic. Any OTHER gap found (e.g. the no-per-module-type-namespace collision — that's a documented design point, NOT a bug to fix; `MARCH_LIB_PATH` edge cases) is documented and/or filed, not fixed.
- **Faithfulness caveats preserved** in both references; findings to the appropriate section.
- **Process:** no `git stash`; explicit `git add <path>` by name; no Co-Authored-By. Commit per task.

---

## Task 1: Fix cross-file visibility enforcement (compiler) + diagnostic quality

**Files:** `lib/typecheck/typecheck.ml` (the fix); `test/test_compiler.ml` (or the right suite — grep for existing visibility tests); `specs/lang/types/reject/*.march` (the now-rejected private-access cases).

**The bug (verified in survey):** `load_module_into_env` (`typecheck.ml` ~:657–692) loads `ExFn`/`ExValue`/`ExType`/`ExRecord` export entries UNCONDITIONALLY — it never checks `entry.ex_public`, so a private `pfn`/`ptype` from another module (e.g. `Array.lst_rev`, a real `pfn` in `stdlib/array.march`) is callable from unrelated code. The `ExCtor` arm right beside it (~:687) DOES check `ex_public` and correctly rejects (`` Function `TrieNode` is private to module `Array`. ``). RE-GREP for the live lines.

**Deliverable:**
- **The fix — GATE `ExFn`/`ExValue` ONLY, NOT `ExType` (design decision, pre-resolved by plan review):** add the `entry.ex_public` gate to the `ExFn` and `ExValue` arms of `load_module_into_env`, mirroring the `ExCtor` arm's existing check + message shape (`` … is private to module `X`. ``). **Do NOT gate `ExType`'s bare type name** — March uses the **opaque-type pattern**: a private `ptype`'s NAME stays nominally referenceable while its CONSTRUCTOR is hidden (already enforced by the `ExCtor` gate at ~:687). Gating `ExType` would BREAK live, tested stdlib code — confirmed by review: `stdlib/consistent_hash.march`'s private `ptype HashRing(a)` is referenced as `ring : ConsistentHash.HashRing(String)` on a PUBLIC parameter in `stdlib/work_dispatch.march` (both auto-loaded, both tested). So `ExType` stays ungated by design. For `ExRecord`: only gate if a record can itself be `pfn`/`ptype`-private in a way distinct from its type name — verify live; if unsure or it risks the same opaque-type breakage, leave it ungated and note it. The core bug being fixed is **private FUNCTIONS/VALUES callable cross-module**; the type-name visibility is intentionally the opaque-type behavior, documented (not "fixed") in Task 3.
- **The diagnostic-quality fix:** same-file access to a private nested module currently reports the misleading `` Unknown module `A` `` (because a module with no public surface never gets an outer `env.vars` key). Improve this to a private-access message where feasible (re-grep the same-file resolution path; if the fix is large/risky, document the improvement as a smaller change or file it — the cross-file gate is the priority).
- **RUN THE FULL SUITE — the critical gate:** `dune build --root . bin/main.exe` then `scripts/run-tests.sh` (full). The fix rejects programs that call cross-module privates. **If the stdlib or any test relies on cross-module private access, the suite goes red — INVESTIGATE:** is the caller legitimately reaching into another module's internals (then it's a real dependency the fix exposes — STOP and report, this may be a bigger finding about stdlib structure), or a test that should be updated? Do NOT weaken the gate to make a test pass without understanding why. Report the exact before/after pass counts.
- **Corpus:** add `reject/` programs pinning the now-correct rejections — a cross-file private `pfn` access (`Array.lst_rev(...)` → captured `… is private to module `Array`.`), and a private `ptype`/`pfn` in a same-compilation-unit `mod` accessed from outside. Capture live AFTER the fix. Also confirm the ACCEPT side still works: a PUBLIC cross-module call still typechecks + runs.

**Verify:** `dune build` succeeds; `scripts/run-tests.sh` full → all green vs baseline (report counts); `check_types.sh` passes with the new rejects; the private-access rejects reproduce their messages live; a public cross-module call still accepts.

**Commit:** `fix(typecheck): enforce module visibility for private functions/values across modules (ExFn/ExValue; type names stay opaque-referenceable per ExCtor pattern)`.

---

## Task 2: Module operational rules — declaration, nesting, resolution, export

**Files:** `specs/lang/core-march.md` (new section); corpus.

**Deliverable:** Document the OPERATIONAL semantics (re-grep `DMod` in `eval.ml` ~:8168–8283):
- Module declaration `mod Name do … end` and nesting; how a module contributes names — it exports its declared names as `"Mod.name"` into the outer scope (eval gates on `own_names`; note visibility is a TYPECHECK concept — Task 3 — so eval exports all own names). Cite the export mechanism.
- Bare vs qualified name resolution: a bare `f()` never auto-resolves into a sibling nested module (`` I cannot find `f` ``); qualified `A.f()` resolves to A's public `f`. The lexical-scoping nuance: a `pfn` nested lexically inside `A` IS callable bare from a module nested inside `A` (correct lexical scope).
- The one-mod-per-file rule (file-wrapper; cross-ref the grammar reference + the `` A file may have only one top-level `mod` `` message).
- **Corpus:** ≥2 `accept/` value-witnessing: a qualified cross-module call `A.f()` returning a known value; a nested-module lexical-resolution case. Run to confirm.

**Verify:** `check_types.sh` all-pass; check-docs 0; witnesses run to value; eval.ml citations live.

**Commit:** `docs(spec): widen operational reference — module declaration, nesting, name resolution`.

---

## Task 3: Module typing rules — visibility, no-per-module-type-namespace, qualified-type unification

**Files:** `specs/lang/core-march-types.md` (new section); corpus.

**Deliverable:** Document the TYPING semantics (re-grep `DMod` in `typecheck.ml` ~:6793–6935, `load_module_into_env` ~:657–692 — now with Task 1's `ex_public` gate):
- **Visibility as a typecheck concept, WITH the opaque-type asymmetry:** module typecheck exports only `pub_set`-filtered names as `"Mod.name"`; `load_module_into_env` now gates cross-module FUNCTION/VALUE imports on `ex_public` (Task 1's fix) — a private `pfn`/private value is NOT callable cross-module (cite the now-correct rejection). **BUT** a private `ptype`'s bare TYPE NAME stays nominally referenceable across modules (only its CONSTRUCTOR is hidden, via the `ExCtor` gate) — the **opaque-type pattern**. Document this asymmetry EXPLICITLY as intentional (not a bug): `pfn`/value = hidden; `ptype` = opaque (name usable in type annotations like `ConsistentHash.HashRing(String)`, constructor private). This is the design decision the plan review pre-resolved; it's WHY `stdlib/work_dispatch.march` can annotate a param with another module's private `ptype`. Cross-ref Task 1 + `docs/modules.md`'s opaque-type documentation.
- **The no-per-module-type-namespace design point:** types export/resolve by BARE NAME only (`take_a(x : A.Foo)` accepts a `B.Foo` value with no error — two sibling modules' same-named types silently collide). This is the FLIP SIDE of the qualified-type-path unification (`9001e4c0`, works both directions). Spec it as ONE design point: March has no per-module type namespace; qualified type paths are sugar that unify with the bare name. (This is a documented design fact, NOT a bug to fix — cross-ref the memory-flagged app-type-namespace collision.)
- **Qualified-type-path unification** (`9001e4c0`): a value of type `A.Foo` unifies with `Foo`; `x : A.Foo` annotations work. Verify live, cite.
- **Corpus:** ≥1 `accept/` (a public cross-module type/value used with a qualified annotation, e.g. the opaque-`ptype` pattern — a cross-module private `ptype` name in a param annotation still accepting, witnessing the asymmetry). The private-FUNCTION rejects are already in Task 1's corpus (cross-ref, don't duplicate). **Re-verify the survey's A10 record-field case LIVE** (don't assume the gap — confirm current behavior, since Task 1's ExFn/ExValue gate may have shifted it), and add a program pinning whatever the current behavior actually is.

**Verify:** `check_types.sh` all-pass; check-docs 0; the qualified-type-unification + no-namespace behaviors verified live; typecheck.ml citations live.

**Commit:** `docs(spec): widen typing reference — module visibility (post-fix) + no-per-module-type-namespace + qualified-type unification`.

---

## Task 4: `use` / `import` / `alias` — selectors, the resolver pre-pass, MARCH_LIB_PATH boundary

**Files:** `specs/lang/core-march.md` (+ maybe `core-march-types.md`); corpus.

**Deliverable:** Document import forms (re-grep `DUse`/`use_`/`alias` in `desugar.ml`/`parser.mly`, and `lib/resolver/resolver.ml`):
- `use A` and Elixir-style `import A` both desugar to the same `DUse` node (`parser.mly` ~:647–700). Selector forms: `use A only (f, g)` / `except (…)`. What each brings into scope.
- **The file-based resolver pre-pass** (`resolver.ml`): `use`/`import` are resolved by a SEPARATE pre-pass that looks for an actual `.march` FILE — so `use A.*` against an IN-FILE nested `mod A` fails (`` Module `A` not found (looked for `a.march`…) ``), while `use` of a real stdlib module works; selective `use X.{name}` of a non-exported name rejects (`` Module `Array` does not export `lst_rev`. `` — verify this is now consistent with Task 1's visibility fix). Document this file-vs-in-file distinction precisely (it's a real, surprising behavior).
- **Scope boundary:** `MARCH_LIB_PATH` multi-file discovery mechanics are BUILD-TOOLING — note them as out of the language-semantics scope (a one-paragraph pointer), don't spec the discovery walk.
- **Corpus:** ≥2 `accept/` (a `use` of a real stdlib module bringing a name into scope, used + run; a selector form); ≥1 `reject/` (a `use` selector of a non-exported/private name, or `use` of a non-existent module — capture live).

**Verify:** `check_types.sh` all-pass; check-docs 0; the selector + resolver behaviors verified live (incl. that private-name selective-use rejects consistently with Task 1); citations live.

**Commit:** `docs(spec): widen references — use/import/alias selectors + resolver pre-pass`.

---

## Task 5: Consolidate + corpus/INDEX + closeout

**Files:** both references (finalize); `specs/lang/types/INDEX.md`; `specs/lang/index.md`; `specs/progress.md`, `specs/todos.md`.

**Deliverable:**
- Finalize both references' new module sections: coherent reads, cross-references between the operational (resolution/export) and typing (visibility/namespace) sections resolve; any findings collected + `specs/todos.md`-linked.
- Reconcile the existing `specs/lang/modules.md` tutorial chapter (from consolidation): verify its claims against the CORRECTED visibility behavior (Task 1) — if it says private access "works" or is silent on enforcement, update it; add a cross-ref to the new operational/typing module sections. (If actively edited by a concurrent session, file a doc-freshness item instead.)
- Update `specs/lang/types/INDEX.md` with all new `tNN` module programs; confirm `check_types.sh`/`types-check` lane green.
- **Bookkeeping:** `specs/progress.md` — the slice-2 milestone (modules/imports/visibility documented in both references, the visibility bug FIXED, N new corpus programs, findings). `specs/todos.md` — Done entry; the visibility bug moves to Done (it's FIXED this slice, with the commit); the no-per-module-type-namespace is a documented design point (not a todo); note the next widening slice (actors) as queued.

**Verify:** `check_types.sh` all-pass; `scripts/check-docs.sh` 0; both references coherent; the visibility fix's Done entry cites Task 1's commit; `modules.md` reconciled.

**Commit:** `docs(spec): widening-slice-2 closeout — modules/imports/visibility`.

---

## Self-review checklist (run before executing)

1. **Task 1 is a real compiler fix gated on the FULL suite** — if the stdlib relies on cross-module private access, that's a STOP-and-report finding, not a force-through.
2. **Docs describe POST-FIX behavior** — Tasks 2-4 document visibility as enforced (Task 1's corrected state), not the old gap.
3. **No-per-module-type-namespace is a DESIGN POINT, not a bug** — documented, not fixed/filed-as-bug.
4. **Capture-not-guess** — every reject re-captured live AFTER Task 1's fix; every citation re-grepped live.
5. **Corpus numbering** continues `specs/lang/types/` `tNN` with no collisions; the visibility rejects live in Task 1 (depend on the fix), not duplicated later.
6. **Scope boundary:** single-compilation-unit modules + resolution + use/import/alias + visibility IN; `MARCH_LIB_PATH` discovery + `sig` conformance + capability `needs` OUT (noted, not specced).
