# Widening Slice 1 — Interfaces & Impls (declaration checking) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development to execute this plan task-by-task.

**Goal:** Widen the Core March references past the core fragment to cover **user-defined `interface`/`impl` declaration checking** — the typing rules for declaring interfaces and impls (method-signature validation, missing/extra-method rejection, superclass/`requires` bounds, `derive`/`satisfy`), the operational method-dispatch semantics, and the coherence/overlap story — each cited to live source and backed by conformance-corpus programs. This is the roadmap's stated "natural next widening slice" after constraint-discharge (`core-march-types.md` §6).

**Architecture:** Two existing references get NEW sections (not rewrites): `specs/lang/core-march-types.md` gains the interface/impl DECLARATION typing rules (it already has §2.1a constraint-*discharge*); `specs/lang/core-march.md` gains the method-DISPATCH operational rules + the coherence divergence. The existing `specs/lang/types/{accept,reject}/` corpus grows with interface/impl programs. Two real gaps the survey found — the **no-coherence-check interp-vs-compiled divergence** and the **`derive X for UnknownType` silent no-op** — are documented as known divergences/gaps AND filed as `specs/todos.md` items (fixing them is out of scope; this is a documentation slice).

**Tech Stack:** Markdown; `lib/typecheck/typecheck.ml` (declaration checking) + `lib/eval/eval.ml` + `lib/tir/lower.ml` (dispatch) are the sources of truth; the pre-built `_build/default/bin/main.exe --check` is the conformance oracle; the survey `.superpowers/sdd/interface-impl-survey.md` is the authoritative catalog (8 accept / 12 reject / 3 divergence / 1 no-op cases, with live-captured messages + line cites).

## Global Constraints

- **Base = current `origin/main`** (fetch + `git pull --ff-only`; rebase if it moved — docs-mostly, expect clean). Branch: `docs/core-march-types-skeleton`.
- **The survey is the catalog, but RE-VERIFY every citation + message live.** `.superpowers/sdd/interface-impl-survey.md` has the line cites + captured messages, but source lines DRIFT and the tree moves — `grep -n` the construct in the CURRENT `typecheck.ml`/`eval.ml`/`lower.ml` and cite the live line; re-run each reject program through `_build/default/bin/main.exe --check` and pin the CURRENT message (capture-not-guess). Never propagate a message/line from the survey on faith.
- **Environment:** the pre-built binary is fresh; use it directly. Do NOT run `dune build` unless truly needed (the daemon has been contended intermittently — if a build hangs >2 min, kill it, use the binary). `scripts/check-docs.sh` is the shell doc gate.
- **Documentation slice — no compiler changes.** Only `specs/lang/core-march-types.md`, `specs/lang/core-march.md`, `specs/lang/types/**`, `specs/lang/index.md`, `specs/todos.md`/`specs/progress.md`, and CI wiring if the corpus lane needs it. ZERO `lib/`/`bin/`/`runtime/`/`stdlib/` changes. A gap that would need a compiler change is a FILED finding (the widening flywheel), NOT an edit — notably the coherence divergence and the derive-no-op are documented + filed, never fixed here.
- **Corpus — capture-not-guess, and mind the divergences.** New `accept/` programs (a valid interface+impl) must `--check` exit 0; new `reject/` programs pin the CURRENT live parse/type error substring (first line `-- EXPECT-ERROR:`). The **coherence-overlap case is a DIVERGENCE, not a clean accept/reject** — both backends accept it but disagree at runtime — so it CANNOT be a corpus accept/reject (a `--check` program can't witness an interp-vs-compiled runtime split). Document it in prose as a known divergence (mirroring how `core-march.md` §4.2.1 handled the `ERecordUpdate` divergence) and file it; do NOT force it into the harness.
- **Corpus location:** reuse `specs/lang/types/{accept,reject}/` (continue the `tNN_` numbering — the interface/impl programs are typing conformance). Verified current highest: `accept/` = **t22**, `reject/` = **t17** — so new `accept/` programs start at **t23**, new `reject/` at **t18** (re-confirm with `ls` before writing, in case a concurrent commit added more).
- **Faithfulness caveat preserved.** Both references keep their existing §4/§6 faithfulness caveats; add findings to the appropriate findings section.
- **Process:** no `git stash`; explicit `git add <path>` by name; no Co-Authored-By. Commit per task.

---

## Task 1: Interface & impl declaration typing rules (the core)

**Files:** `specs/lang/core-march-types.md` (new section, e.g. §2.3 "Interface & impl declarations"); `specs/lang/types/{accept,reject}/*.march`.

**Deliverable:**
- Document **`DInterface` checking** (re-grep `DInterface`/`interface_decl`/`method_sig` + `prebind_interface_decl` — survey said `typecheck.ml:7045–7073` + `:5050–5087`): interface declaration is pure REGISTRATION — records the interface into `env.interfaces` and binds each method as a `∀a [CInterface(iface,a)]. ty` scheme under bare + qualified (`Iface.method`) names. State that almost nothing is rejectable at the interface declaration itself. Name the `prebind_interface_decl` + `register_impl_shape` (re-grep, ~:4994) pre-passes and their shared reason (cross-module declaration ordering) in one sentence.
- Document **default methods** (`md_default`): an interface method may carry a default body (`interface Foo do fn bar(self) : Int do 42 end end`); an impl that OMITS such a method is NOT a missing-method error (the default runs). Verify live and add a corpus `accept/` witnessing it (declare an interface with a defaulted method, an impl that omits it, call the method, confirm the default value).
- Document **`DImpl` checking** as a rule **(T-Impl)** with the ordered checks (re-grep `DImpl`/`register_impl`, survey said `typecheck.ml:7075–7210`): instantiate the impl head → register into `env.impls` → (superclass/when discharge — Task 2) → verify the interface exists → **no missing required method** → **no extra undeclared method** → **each method body's type matches the interface signature instantiated at the impl type** (name the `impl_matches_ty` judgment). Capture the LIVE error text for: interface-doesn't-exist, missing-method, extra-method, signature-mismatch (write tiny programs, `--check`, pin each).
- **Corpus:** ≥2 `accept/` (a valid `interface Speak do fn speak(self) : String end` + `impl Speak(Dog)` that typechecks; a generic-ish valid impl); ≥4 `reject/` — missing method, extra method, method signature mismatch, impl of a non-existent interface — each pinning the captured live message.

**Verify:** `MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/types/check_types.sh` all-pass; `scripts/check-docs.sh` 0; every cited line re-grepped; every reject message reproduced live.

**Commit:** `docs(spec): widen typing reference — interface/impl declaration checking`.

---

## Task 2: Superclass/`requires` bounds, `when`-clause impls, impl-head generality

**Files:** `specs/lang/core-march-types.md` (extend §2.3); corpus.

**Deliverable:**
- Document how the `DImpl` check discharges **superclass/`requires` constraints** and any **`when`-clause** on the impl (re-grep the discharge steps in the DImpl arm), cross-referencing §2.1a's `discharge_constraints`. Superclass bounds ARE enforced (confirmed live during plan review: an `impl Greet(Dog)` requiring `Speak(Dog)` with no `Speak(Dog)` impl is rejected — `` Cannot implement `Greet(Dog)`: required superclass `Speak(Dog)` is not satisfied ``). So this is a MANDATORY reject case (capture the current message live), not a conditional finding.
- Document the **impl-head generality** and name the **`impl_matches_ty` judgment as a rule (T-ImplMatch)** (re-grep, ~:4968): how the impl-head type (concrete `impl Iface(Dog)` vs generic `impl Iface(a)`) is matched/instantiated against a use site. This judgment is the crux of BOTH "generic impls work" AND "coherence doesn't exist" (cross-ref Task 4), so give it its own named rule, not a passing mention. Note no specificity resolution exists.
- **Corpus:** ≥1 `accept/` (an impl with a satisfied superclass/`when` bound) and **≥1 mandatory `reject/`** (unsatisfied superclass — pin the live `required superclass … is not satisfied` message). Capture live.

**Verify:** harness all-pass; check-docs 0; superclass-enforcement behavior verified live (accept-or-finding).

**Commit:** `docs(spec): widen typing reference — impl superclass/when bounds + head generality`.

---

## Task 3: Method dispatch — operational rules

**Files:** `specs/lang/core-march.md` (new section, method dispatch); corpus (value-witnessing where possible).

**Deliverable:**
- Document the **operational method-dispatch** semantics (re-grep `impl_tbl`/`is_type_dispatched_method`/`is_type_dispatched_iface` in `eval.ml`, survey said `:270–289`, `:8324`): the built-in type-directed interfaces (`Show`/`eq`/`Eq`/`compare`-`Ord`/`Hash`) dispatch via `impl_tbl` keyed `(iface, type_name)`; **user-defined interfaces get NO runtime dispatch table** — a user method call resolves by ordinary lexical `env` binding. State this clearly (it's why overlap for user interfaces is "just shadowing", the Task 4 story). Cross-ref §2.1a (typing-side discharge) as the static counterpart.
- Note the recent `impl_tbl` dispatch-key-collision fix (the `Eq`-default-`neq` recursion bug — verify the guard is present/stable at the cited line; it's context, not a rule).
- **Corpus:** ≥2 `accept/` value-witnessing a dispatched call (a user `impl Speak(Dog)` then `speak(d)` returning the expected string; a built-in-dispatched `show` on a user type via `derive`), run to confirm the value.

**Verify:** harness all-pass; the dispatch witnesses run to the expected value (pre-built binary); check-docs 0; eval.ml citations live.

**Commit:** `docs(spec): widen operational reference — method dispatch (impl_tbl + lexical)`.

---

## Task 4: Coherence / overlap — the divergence (document + FILE)

**Files:** `specs/lang/core-march.md` (known-divergence subsection) + `specs/lang/core-march-types.md` (a note that overlap is NOT rejected at typecheck); `specs/todos.md` (file the bug).

**Deliverable:**
- Document the **no-coherence-check fact + the interp-vs-compiled divergence** (RE-VERIFY live before writing): two `impl Speak(Dog)` blocks both typecheck; the interpreter picks the LAST-registered impl (`Hashtbl.replace impl_tbl`, re-grep `eval.ml` ~:8324) while compiled picks the FIRST-registered (`List.mem_assoc`, re-grep `lib/tir/lower.ml` ~:1010–1014). Reproduce BOTH backends' behavior on the SAME overlap program (interpret vs `--compile` + run) and pin the exact divergent outputs. Note it holds for plain, generic-vs-specific, and derive-vs-manual overlap. **Frame it as an OPEN, deliberately-left-unfixed divergence** — NOT like `core-march.md` §4.2.1's `ERecordUpdate` case (which was investigated, adjudicated, and CONVERGED — its todos entry is `✅` closed). The correct precedent is the codebase's genuinely-open filed divergences: `test/test_oracle.ml`'s `known_divergence` list and the open `- [ ]` `specs/todos.md` entries of the same shape (e.g. the `hash()` cross-backend-algorithm divergence, the `to_string`-on-container compiled breakage). Cite THAT precedent; explicitly note this is unlike §4.2.1 in that it stays open pending a language-design decision.
- **This is a KNOWN DIVERGENCE — it does NOT become a corpus accept/reject** (a `--check` program can't witness a runtime interp/compiled split; both accept). Explain why in the doc (cross-ref the golden corpus's "a divergence can't be a golden MATCH" limitation).
- **FILE it** in `specs/todos.md` as a real bug (P1/P2): overlapping impls silently accepted + interp/compiled disagree on selection, with the minimal repro and the two cited selection sites. Note that FIXING it (add a coherence check, or define a deterministic selection policy both backends share) is a language-design decision, deferred.

**Verify:** the divergence reproduced live on BOTH backends (paste the two outputs in the report); check-docs 0; the todos entry has a working repro.

**Commit:** `docs(spec): document impl-coherence gap + interp/compiled overlap divergence; file the bug`.

---

## Task 5: `derive` & `satisfy`

**Files:** `specs/lang/core-march-types.md` + `specs/lang/core-march.md` (derive/satisfy — declaration + generated behavior); corpus; `specs/todos.md` (file the derive no-op).

**Deliverable:**
- Document **`derive`** (re-grep `derive`/`expand_derive` in `desugar.ml`): the closed set of five derivable interfaces (`Eq, Show, Hash, Ord, Json`), hardcoded string-match, unknown-target rejected; `Json` special-cased via `JsonTo`/`JsonFrom` pseudo-interfaces that skip normal validation. **FILE the gap:** `derive X for UnknownType` silently no-ops (exit 0, no diagnostic — reproduced live in review: `derive Eq for Ghost` on an undefined type both `--check`s and RUNS at exit 0 with no message). Re-verify live, and file in `specs/todos.md` with the minimal repro AND the cited `desugar.ml` derive-expansion site (re-grep `expand_derive`/the derive-target match, ~:1659), matching Task 4's filing concreteness.
- Document **`satisfy`** (re-grep `satisfy` in `desugar.ml` ~:1673–1716): wires existing top-level functions to an interface by name match; unknown-interface and missing-function both rejected (capture live); all-or-nothing per interface+type.
- Note the dead `iface_assoc_types`/`impl_assoc_types` AST surface (parsed as `[]` — associated types not a real feature; a one-line "not yet a feature" note).
- **Corpus:** ≥2 `accept/` (`derive(Eq, Show)` on a user type used via `==`/`show`; a `satisfy` wiring); ≥2 `reject/` (`derive(BogusIface)` unknown target; `satisfy` with a missing function) — capture live.

**Verify:** harness all-pass; check-docs 0; derive/satisfy citations live; the derive-no-op filed with a repro.

**Commit:** `docs(spec): widen references — derive & satisfy; file derive-unknown-type no-op`.

---

## Task 6: Consolidate + corpus/CI + closeout

**Files:** both references (finalize the new sections + findings); `specs/lang/types/INDEX.md`; `specs/lang/index.md`; `specs/progress.md`, `specs/todos.md`.

**Deliverable:**
- Finalize both references' new sections: coherent reads, cross-references between the typing declaration rules and the operational dispatch rules resolve, the new findings (coherence divergence, derive no-op, any superclass-non-enforcement) are collected in each reference's findings section with `specs/todos.md` cross-refs.
- Update `specs/lang/types/INDEX.md` with all the new `tNN` interface/impl programs. Confirm `check_types.sh` (the `types-check` CI lane) still green with the additions — no new CI wiring needed (the interface/impl corpus rides the existing `types/` lane); confirm the count.
- **Reconcile the existing `specs/lang/interfaces.md` tutorial chapter** (the consolidation-era canonical user-facing interfaces doc). The plan-review found two problems: (a) a **stale "Known issue" callout** (~lines 39–44) claiming a user `interface Eq(a)` with a default `neq` calling `eq` "hangs/stack-overflows" — reproduced live during review and it does NOT hang (typechecks + prints correctly on both backends; the `impl_tbl` dispatch-key-collision bug it referred to was FIXED). Remove/correct that stale callout. (b) Its "Interface Dispatch" section (~line 336) claims dispatch is "resolved at compile time… no vtables or runtime type lookups," which is in tension with what Task 3 formally documents (built-in interfaces dispatch via a runtime `impl_tbl` hashtable; user interfaces via lexical shadowing). Add a cross-reference from `interfaces.md` to the new dispatch section (`core-march.md`) and soften/correct the over-strong "no runtime lookups" claim so the two canonical docs don't disagree. (If `interfaces.md` turns out to be actively edited by a concurrent session, file the reconciliation as a `specs/todos.md` doc-freshness item instead of edit-conflicting.)
- **Bookkeeping:** `specs/progress.md` — append the widening-slice-1 milestone (interfaces/impls declaration checking documented in both references, N new corpus programs, the flywheel findings filed). `specs/todos.md` — Done entry for the slice; confirm the coherence + derive-no-op findings remain OPEN `- [ ]` items (they're filed bugs, not completed work); note the next widening slice (modules or actors) as the queued follow-up.

**Verify:** `check_types.sh` all-pass with the full new corpus; `scripts/check-docs.sh` 0; both references read coherently; the filed findings are open `- [ ]`.

**Commit:** `docs(spec): widening-slice-1 closeout — interfaces/impls declaration checking`.

---

## Self-review checklist (run before executing)

1. **Divergence handling:** the coherence-overlap case is documented as a known divergence + filed, NOT forced into a corpus accept/reject (it can't witness an interp/compiled split via `--check`).
2. **Findings filed, not fixed:** coherence divergence, derive-unknown-type no-op, and any superclass-non-enforcement are FILED in `specs/todos.md` as open items — no compiler code changed.
3. **Capture-not-guess:** every reject substring re-captured from the LIVE compiler; every citation re-grepped live (survey lines are a starting point, not truth).
4. **Both tracks:** declaration rules land in the typing reference; dispatch + the divergence land in the operational reference; they cross-reference each other.
5. **Corpus numbering:** new programs continue the existing `specs/lang/types/` `tNN` sequence with no collisions.
