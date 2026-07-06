# Spec Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development to execute this plan task-by-task.

**Goal:** Fold the ~21 scattered current-truth language-reference docs into ONE versioned, contradiction-free reference — a structured *set* under `specs/lang/`: an umbrella `index.md` over the two conformance-tested core references (`core-march.md`, `core-march-types.md`), a promoted `surface-syntax.md`, and one canonical chapter per language topic — by **organizing + canonicalizing + de-staling** (NOT rewriting), archiving superseded duplicates with redirect stubs, and keeping `scripts/check-docs.sh`'s lint scope in sync.

**Architecture:** For each topic there are today up to three docs at three "altitudes" (a formal `specs/lang/` ref, an engineering `specs/features/*.md`, a tutorial `docs/*.md`). This plan designates ONE canonical doc per topic (preferring whichever is most current — usually the `docs/` version per the survey), moves/keeps it as a `specs/lang/` chapter, fixes the known staleness bugs, and leaves redirect stubs at the superseded paths. Compiler-internal docs (bucket C) are grouped as a SEPARATE sibling "implementation reference," not merged into the language reference. No content is rewritten from scratch — this is curation, de-duplication, versioning, and de-staling.

**Tech Stack:** Markdown; `scripts/check-docs.sh` (doc-freshness lint — dead source-pointers + stale stdlib counts); git `mv` for moves; the survey catalog `.superpowers/sdd/spec-consolidation-survey.md` is the authoritative inventory.

## Global Constraints

- **The survey catalog is the inventory, but RE-VERIFY staleness per topic.** `.superpowers/sdd/spec-consolidation-survey.md` lists buckets, overlaps, and known staleness. Docs may have changed since the survey; before acting on a "X is stale / Y is more current" claim, open both and confirm against the live compiler (e.g. `pub`/`then`/`let?` claims: grep the actual doc + confirm current syntax with `bin/main.exe`). Never propagate a staleness fix you haven't reconfirmed.
- **This is CURATION, not rewriting.** Move/keep the canonical doc; fix outright errors (obsolete keywords, "not implemented" for shipped features, dead file pointers, stale line-counts); do NOT rewrite prose that is correct. A task that finds itself authoring a topic from scratch has exceeded scope — stop and flag.
- **No compiler-code changes.** Only `specs/`, `docs/`, root `*.md`, and `scripts/check-docs.sh` (lint allowlist). Zero `lib/`/`bin/`/`runtime/`/`stdlib/` changes.
- **Lint scope must stay in sync.** `scripts/check-docs.sh`'s `lint_docs()` is a HYBRID (verified): 5 explicitly-named files (`README.md`, `CLAUDE.md`, `syntax_reference.md`, `specs/perceus-invariants.md`, the SKILL) PLUS two directory globs (`find docs -name '*.md'`, `find specs/features -name '*.md'`). `specs/lang/` is covered by neither today. **Task 1 adds exactly ONE glob line — `find specs/lang -name '*.md' 2>/dev/null || true` — to `lint_docs()`**, which auto-covers every present and future `specs/lang/` chapter; NO later task needs to add `specs/lang/` names. Because `docs/` and `specs/features/` stay globbed, a superseded original left as a redirect stub REMAINS linted but stays clean (a stub has no compiler-source pointers or stdlib-count claims — the only two things the lint checks). NOTE: the lint does NOT validate markdown→markdown links, so a chapter pointing at a not-yet-created sibling never trips it — that risk is caught only by the per-task manual dead-link grep, which every task must run.
- **Redirect stubs required, no dead links.** A superseded doc's old path must not 404 for existing links: leave a 1-paragraph stub ("Moved — this topic is now `specs/lang/<chapter>.md`; see the reference umbrella `specs/lang/index.md`.") rather than deleting. After each task, grep the repo for links to any moved path and confirm none dangle.
- **Version the reference.** The umbrella `specs/lang/index.md` carries a version + date + status; each chapter gets a one-line status/provenance header (canonical-since, superseded-doc pointer).
- **Bucket boundaries (from the survey):** (A) normative language reference → chapters; (B) historical/design (`specs/plans/*`, dated `specs/*.md`, `specs/analysis/*`, `specs/bastion/*`, `specs/depot/*`) → LEAVE ALONE; (C) compiler-internal → sibling impl reference, referenced-not-merged; (D) tooling → out of scope, leave alone.
- **Process:** no `git stash` (shared stack across worktrees — forbidden); explicit `git add <path>` by name; no Co-Authored-By lines. Commit per task as specified.

---

## Target structure

```
specs/lang/
  index.md              # NEW — versioned umbrella: chapter map + status + canonical-source table + links to impl ref
  core-march.md         # existing — operational semantics reference v1 (unchanged)
  core-march-types.md   # existing — static-semantics/typing reference v1 (unchanged)
  surface-syntax.md     # promoted from root syntax_reference.md (incl. its "Semantics notes" appendix verbatim)
  modules.md            # canonical modules/imports/visibility chapter (de-staled: no pub/then)
  pattern-matching.md   # canonical
  interfaces.md         # canonical (standard interfaces / typeclasses)
  let-propagation.md    # canonical (de-staled: let? IS shipped)
  linear-types.md       refinement-types.md   session-types.md   capabilities.md
  memory-model.md       safety-by-construction.md
  actors.md             supervision.md   parallelism.md   clustering.md
  standard-library.md   # overview/pointer chapter (NOT the auto-gen API listing)
  golden/  types/        # existing conformance corpora (unchanged)
specs/impl/
  index.md              # NEW — sibling "implementation reference" umbrella over bucket (C)
                        #   points at (in place, NOT moved): docs/value-representation.md,
                        #   specs/perceus-invariants.md, specs/features/{tir-invariants,scheduler,
                        #   content-addressed-system,runtime,compiler-pipeline}.md
```

Redirect stubs remain at every old path (`syntax_reference.md`, `docs/<topic>.md`, `specs/features/<topic>.md`) pointing at the new chapter.

## Canonical-source decisions (RE-VERIFY each before acting)

| Topic | Canonical winner (per survey) | Superseded → redirect | Known staleness to FIX |
|---|---|---|---|
| surface syntax | `syntax_reference.md` → `specs/lang/surface-syntax.md` | — | none known (Wave-4 fixed if/then); keep Semantics-notes appendix |
| modules | `docs/modules.md` | `specs/features/module-system.md` | **`pub` keyword + `then` examples are WRONG** |
| let-propagation | `docs/` or the corrected feature doc | `specs/features/let-propagation.md` | **claims `let?` "not yet implemented" — it SHIPPED** |
| type-system (tutorial) | `docs/types.md` | `specs/features/type-system.md` | stale line-counts; defer formal content to `core-march-types.md` |
| pattern-matching | `docs/pattern-matching.md` | `specs/features/pattern-matching.md` | re-verify |
| interfaces | `docs/interfaces.md` | `specs/features/standard-interfaces.md` | re-verify |
| linear/refinement/session/capabilities/memory-model/safety | `docs/*.md` | (feature-doc dup if any) | re-verify per doc |
| actors/supervision/parallelism/clustering | `docs/*.md` (+ A-content from `specs/features/actor-system.md`) | feature-doc internals → impl ref | actor-system.md self-contradicts on compiled-scheduler status |
| CAS (impl ref) | `specs/features/content-addressed-system.md` | — (stays impl ref) | **`driver.ml` pointer is WRONG — CAS is wired in `bin/main.ml`** |

---

## Task 1: Scaffold — umbrella, surface-syntax chapter, lint scope, README redirect

**Files:** Create `specs/lang/index.md`; `git mv syntax_reference.md specs/lang/surface-syntax.md` + stub; Modify `scripts/check-docs.sh` (add the ONE glob line `find specs/lang -name '*.md' 2>/dev/null || true` to `lint_docs()`); Modify `CLAUDE.md` (its ~line 156 links to `syntax_reference.md` — repoint to `specs/lang/surface-syntax.md`); Modify `README.md` (redirect the dead `specs/design.md` pointer → `specs/lang/index.md`).

**Deliverable:**
- `specs/lang/index.md`: a versioned umbrella (`# March Language Reference` + version/date/status header). It states the reference's *structure* (the two core conformance-tested references + surface-syntax + the topic chapters), a **chapter map table** (each topic → chapter file → status: `canonical` / `stub-only (chapter lands in Task N)`), a pointer to the sibling `specs/impl/index.md`, and a short "how this reference is organized / how it's kept honest (conformance corpora + check-docs lint)" note. Chapters not yet migrated are listed with status `pending (Task N)` so the umbrella is coherent from the first commit.
- `syntax_reference.md` → `specs/lang/surface-syntax.md` via `git mv` (preserve its "Semantics notes" appendix verbatim); add a chapter-status header; leave a redirect stub at `syntax_reference.md`.
- `scripts/check-docs.sh`: add the single glob line `find specs/lang -name '*.md' 2>/dev/null || true` to `lint_docs()` (auto-covers `index.md`, `surface-syntax.md`, and every future chapter). The named `syntax_reference.md` lint entry can stay — it now points at the redirect stub, which is lint-clean (no source pointers/counts). Confirm `core-march.md`/`core-march-types.md` (now newly in scope via the glob) pass the lint — they were verified clean, so this is zero-risk.
- `CLAUDE.md`: repoint its `syntax_reference.md` link (~line 156, "See [syntax_reference.md](syntax_reference.md) …") to `specs/lang/surface-syntax.md`. CLAUDE.md is project-instructions AND itself lint-scoped — do NOT leave it pointing at the stub.
- `README.md`: redirect the stale `specs/design.md` reference to `specs/lang/index.md`.

**Verify:** `scripts/check-docs.sh` exits 0; `grep -rn "syntax_reference.md" --include=*.md .` shows only the stub + intended references (no dangling links to the old path in other docs — fix any); the umbrella renders coherently (every topic listed with a status).

**Commit:** `docs(spec): scaffold specs/lang reference umbrella + promote surface-syntax` staging `specs/lang/index.md specs/lang/surface-syntax.md syntax_reference.md scripts/check-docs.sh README.md`.

---

## Task 2: Core-semantics chapters + fix the SEVERE staleness bugs

**Files:** `git mv` `docs/{modules,pattern-matching,interfaces,types}.md` and `docs/`/`specs/features/let-propagation` → `specs/lang/{modules,pattern-matching,interfaces,type-system,let-propagation}.md`; redirect stubs at EVERY superseded path (both the `docs/` origin AND the `specs/features/` duplicate for each topic); update `specs/lang/index.md` chapter-map statuses. (No `check-docs.sh` edit needed — Task 1's `specs/lang/` glob already covers the new chapters, and the `docs/`/`specs/features/` globs keep the stubs linted.)

**Deliverable:** For EACH of modules, let-propagation, pattern-matching, interfaces, type-system-tutorial:
- Confirm the canonical doc against the table above (re-verify freshness live). Move it to `specs/lang/<chapter>.md` (git mv preferred to preserve history; if two docs must merge, keep the canonical and fold in any unique-and-correct content from the other, citing it).
- **FIX the confirmed staleness bugs:** `modules` — remove every `pub` keyword and `then` example, replace with current `fn`/`pfn`/`do…else…end` syntax (verify each corrected snippet parses with `bin/main.exe --check`); `let-propagation` — correct the "not yet implemented" claim to reflect that `let?` shipped (verify with a live `let?` program). For `type-system` (`git mv docs/types.md → specs/lang/type-system.md`): the FORMAL rules live in `core-march-types.md`, so this chapter is the tutorial-register companion — trim/cross-link the first ~half that restates core ground (defer to `core-march-types.md`), KEEP the distinct back-half (refinements, type-level nats); redirect `specs/features/type-system.md` here too, folding in only its unique-and-correct linearity/mono/interface sections; de-stale its line-counts.
- Add chapter-status headers; redirect stubs at EVERY superseded path (the `docs/` origin AND the `specs/features/` duplicate); update the umbrella chapter-map to `canonical`. (No `check-docs.sh` edit — Task 1's `specs/lang/` glob already covers new chapters; the `docs/`/`specs/features/` globs keep stubs linted.)

**Verify:** `scripts/check-docs.sh` exits 0; every corrected code snippet in the touched chapters parses (`bin/main.exe --check` on extracted snippets, or manual confirmation); `grep -rn` for links to moved paths — none dangle; no `pub`/`then` remains in `specs/lang/modules.md`; `let?`-shipped is stated correctly.

**Commit:** `docs(spec): canonicalize core-semantics chapters + fix module-system/let-propagation staleness`.

---

## Task 3: Advanced-feature chapters

**Files:** `specs/lang/{linear-types,refinement-types,session-types,capabilities,memory-model,safety-by-construction}.md` (canonical, from `docs/` per re-verification); redirect stubs at every superseded path — INCLUDING the `specs/features/session-types.md` duplicate, which must be merged/redirected (the survey's target structure calls for folding it with `docs/session-types.md`); umbrella statuses. (No `check-docs.sh` edit — Task 1's glob covers new chapters.)

**Deliverable:** For each topic: confirm canonical (re-verify freshness), `git mv` to `specs/lang/<chapter>.md`, de-stale any confirmed errors, add status header + redirect stub, update the umbrella. These are lower-contradiction than Task 2 — expect mostly clean moves + light de-staling. Where a topic has an existing `specs/features/` duplicate (notably `session-types`), redirect it; where only a `docs/` version exists, move + redirect.

**Verify:** `scripts/check-docs.sh` exits 0; no dangling links to moved paths; umbrella chapter-map updated to `canonical` for these topics; spot-check that any code snippets parse.

**Commit:** `docs(spec): canonicalize advanced-feature chapters (linear/refinement/session/capabilities/memory-model/safety)`.

---

## Task 4: Concurrency chapters + split actor-system A/C content

**Files:** `specs/lang/{actors,supervision,parallelism,clustering}.md`; redirect stubs at superseded paths; umbrella statuses. (No `check-docs.sh` edit — Task 1's glob covers new chapters.)

**Deliverable:**
- `actors.md`: the survey found `specs/features/actor-system.md` is HALF language-reference (spawn/send/kill syntax, mailbox semantics, capability model, linear-typed messages, MPST session-type syntax) and HALF compiler-internals (scheduler, lowering). Take the **A-content** as the `specs/lang/actors.md` chapter (prefer `docs/actors.md` where more current); the **C-content** (scheduler/lowering) goes to / stays in the impl reference (Task 5). Reconcile the self-contradiction the survey flagged (Overview says compiled actors run; Known-Limitations says pending) against the CURRENT runtime (`runtime/march_scheduler.c` exists — verify compiled-actor status live and state it once, correctly).
- `supervision`, `parallelism`, `clustering`: canonical from `docs/`, de-stale, move + redirect + lint + umbrella.

**Verify:** `scripts/check-docs.sh` exits 0; the actor chapter states compiled-actor status consistently (no self-contradiction); C-content is referenced in the impl ref, not duplicated in the language chapter; no dangling links.

**Commit:** `docs(spec): canonicalize concurrency chapters + split actor-system reference/internals`.

---

## Task 5: Implementation-reference sibling + standard-library chapter

**Files:** Create `specs/impl/index.md`, `specs/lang/standard-library.md`; redirect stub at `specs/features/standard-library.md`; umbrella. (No `check-docs.sh` edit — `specs/impl/` is indexed-in-place, files stay globbed where they are.)

**Deliverable:**
- `specs/impl/index.md`: a sibling "implementation reference" umbrella (versioned) that indexes ALL NINE bucket-(C) docs — `docs/value-representation.md`, `specs/perceus-invariants.md`, `specs/features/{tir-invariants,scheduler,content-addressed-system,runtime,compiler-pipeline,http-and-networking,debugger}.md` — IN PLACE (do NOT move these; just index + one-line describe each). **Fix the confirmed CAS error:** `specs/features/content-addressed-system.md`'s `driver.ml` pointer is wrong (CAS is wired in `bin/main.ml`) — correct that one pointer (grep-verify no `driver.ml` remains). Add a "line-counts are indicative, not linted" disclaimer for the stale per-file counts the survey flagged (fixing `typecheck.ml` 2006→8285 if cheap, but the disclaimer is the real fix).
- `specs/lang/standard-library.md`: a short overview/pointer chapter (the stdlib is documented by the auto-generated API reference + `docs/stdlib`; this chapter orients the reader and links out — it does NOT duplicate the 108-module listing). **Disposition of the pre-existing `specs/features/standard-library.md` (1278 lines):** leave a redirect stub pointing at `specs/lang/standard-library.md` + the API reference — do NOT let the old 1278-line doc sit un-superseded (it's glob-linted and would otherwise coexist confusingly with the new chapter).
- Link the impl reference from the language umbrella ("for compiler internals, see `specs/impl/index.md`").

**Verify:** `scripts/check-docs.sh` exits 0; the CAS `driver.ml` pointer is corrected (grep confirms no `driver.ml` reference remains in that doc); both umbrellas cross-link.

**Commit:** `docs(spec): add implementation-reference sibling + standard-library chapter; fix CAS driver.ml pointer`.

---

## Task 6: Closeout — umbrella review, link audit, bookkeeping

**Files:** `specs/lang/index.md` (finalize); `specs/progress.md`, `specs/todos.md`.

**Deliverable:**
- Finalize `specs/lang/index.md`: every chapter status is `canonical` (or explicitly `external` for the two conformance-tested core refs / the impl sibling); the version/date/status header reflects "v1 — core language reference consolidated"; the canonical-source table is complete.
- **Full link audit:** grep the whole repo for links to every moved path (`syntax_reference.md`, each moved `docs/`/`specs/features/` doc) and confirm each resolves (to a stub or the new chapter) — zero dangling links. List the audit result.
- **Bookkeeping:** `specs/progress.md` — append the consolidation milestone (the `specs/lang/` reference set exists, N chapters canonical, umbrella versioned, lint scope extended). `specs/todos.md` — mark the §4.6-consolidation roadmap item done (date 2026-07-05); record the resolved-surface-grammar as the NEXT queued spec item (with the survey's grammar-input notes: 59-vs-5 precedence conflicts, token_filter newline-glom, pipe/`let?` desugar gaps).

**Verify:** `scripts/check-docs.sh` exits 0; the link audit shows zero dangling links; the umbrella is internally consistent (every listed chapter file exists; every chapter's status matches reality).

**Commit:** `docs(spec): finalize language-reference umbrella + consolidation closeout`.

---

## Self-review checklist (run before executing)

1. **Coverage:** every bucket-(A) doc from the survey (21) is accounted for — moved to a chapter, redirected, or explicitly noted. Cross-check against `.superpowers/sdd/spec-consolidation-survey.md`'s A-list. EXPLICIT no-action item: README's "Language tour" section (lines ~311-434) stays in README as-is — the survey judged it low-value to merge; the umbrella links to it rather than absorbing it. (Recording it here so "all A-docs accounted for" is honest, not silently dropped.)
2. **Lint-allowlist invariant:** every task that moves a file updates `scripts/check-docs.sh` in the SAME commit. No task leaves a moved chapter unlinted or a stale entry pointing at a moved file.
3. **No dead links:** every task ends with a grep for links to the paths it moved.
4. **Staleness fixes are re-verified live**, never propagated from the survey on faith.
5. **No content rewritten** — moves + de-staling only; a task authoring from scratch has exceeded scope.
