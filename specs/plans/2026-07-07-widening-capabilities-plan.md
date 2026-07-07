# Widening Slice 5 — Capabilities / Effects (IO caps + behavioral caps + F2/F3 fixes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Fresh implementer subagent per task, task review after each, whole-slice review at the end. Steps use `- [ ]`.

**Goal:** Widen the Core March conformance-tested TYPING reference to cover the **capability / effect system** — the IO-permission-cap spine (`needs`/`Cap(X)`/subsumption/`cap_narrow`/transitive-`use`/extern-cap/effect-inference) AND the behavioral module caps (`cap no_panic`/`no_alloc`/`no_extern`/`pure`/`deterministic`) — and fold in the two soundness FIXES the survey found (F2: `cap pure`/`cap deterministic` ban stale/nonexistent builtin names; F3: `cap no_panic` misses non-exhaustive matches).

**Architecture:** The capability system is **purely compile-time / static** — `Cap(X)` is runtime-erased (`null`/`VUnit`), interp==compiled always (survey P6b), no golden corpus needed. Enforcement lives entirely in `--check` (typecheck + refinecheck passes). So this is a **`types/` accept-reject + prose** slice, PLUS two compiler fixes. IO caps (Checks 1/4/5/7/8) are current-correct → docs-only. Behavioral caps: `no_panic`(base)/`no_alloc`/`no_extern` are correct → docs; `pure`/`deterministic` (F2) and `no_panic`-non-exhaustive (F3) are UNSOUND → fix, then document the fixed behavior. Proof caps (F4) are DEFERRED to a later slice (filed).

**Tech Stack:** Markdown (`specs/lang/core-march-types.md`, `capabilities.md` tutorial); `lib/typecheck/typecheck.ml` (`check_module_needs` Checks 1–8, behavioral-cap enforcers, `builtin_cap_table`); `lib/caps/cap_lattice.ml` (hierarchy + subsumption); `lib/refinecheck/{cap_infer,no_alloc,division_safety}.ml`; `_build/default/bin/main.exe --check` (the oracle — accept/reject). Survey `.superpowers/sdd/capabilities-survey.md` is the authoritative catalog (mechanism cites, 51 probe transcripts, findings F1–F5, corpus starts).

## Global Constraints

- **Slice = docs + TWO compiler fixes (F2, F3).** IO-cap tasks (T1–T3) and the behavioral-cap DOC task (T4) touch ONLY `specs/`. The fix tasks (T5=F2, T6=F3) touch `lib/` + their regression tests + the reject-corpus witnesses their fix enables. Any gap needing a compiler change other than F2/F3 is a FILED finding, not a fix (esp. F1, F4, F5).
- **Each compiler-fix task (T5, T6) MUST pass the FULL suite** (`scripts/run-tests.sh`, six runners, `--root .`) before landing — they are the only tasks that can regress the compiler. Verify each fix with a VALUE-REVEALING probe: a program that currently `--check`s clean (unsound) must `--check` REJECT after the fix, with the exact new message captured.
- **⚠️ Corpus ORDERING — reject witnesses that need a fix come WITH the fix.** A `cap pure` + `file_write` program currently ACCEPTS (F2 unsound); its `reject/` witness can only be added AFTER T5's F2 fix makes it reject. A `cap no_panic` + non-exhaustive-`match` program currently ACCEPTS (F3); its `reject/` witness comes with T6's F3 fix. Do NOT add these reject witnesses in an earlier task — they would fail the harness (the program accepts pre-fix). T1–T4 add ONLY corpus programs that pass against CURRENT behavior.
- **⚠️ FAITHFULNESS — the reference must state the F1 truth, not the spec's overclaim.** The `capabilities.md` tutorial claims "the build fails" / "enforces `needs` as an error" — but body-scanned IO caps (calling `file_read` etc. without `needs`) are **WARNING-only, `--check` exits 0**; only `Cap(X)` in a *signature* is an ERROR (Check 1). The new typing-reference section MUST document this honestly (signature-position = error; body-position = warning-only), and T7 reconciles `capabilities.md`. Do NOT repeat the overclaim.
- **`requires` is NOT a capability keyword** — it is the interface-superclass constraint. Cap requirement is `needs` + `Cap(X)` params only. Do not conflate.
- **Compile-time / static → NO golden.** Every witness is a `march --check` exit-code + pinned-substring, in `specs/lang/types/{accept,reject}/`. Skip golden (the optional cap-erasure `g40` is a weak witness — do not add it).
- **Faithfulness discipline:** every rule cited to a live `typecheck.ml`/`cap_lattice.ml`/`refinecheck` line (RE-GREP — lines drift with concurrent commits); capture-not-guess every reject message from the live compiler.
- **Process rules (verbatim):** NEVER `git stash` in this worktree (shared stack); stage files EXPLICITLY BY NAME (never `git add -A`/`.`/`-am`); NO `Co-Authored-By`; `dune build --root .`; dune/ocaml on PATH at `/Users/80197052/.opam/march/bin` (never `eval $(opam env …)`); NEVER pipe `march --compile` (N/A here — this slice is `--check`-only except the full-suite gate); foreground.

**Corpus start numbers (verified live):** accept next = **`t45`**; reject next = **`t36`**; golden = none. The typing reference gets a NEW section (e.g. §2.8 "Capabilities and effects").

---

## Task 1: IO cap subsumption + `needs`/`Cap(X)` signature enforcement (Check 1)

**Files:** `specs/lang/core-march-types.md` (new §2.8, first subsections); `specs/lang/types/accept/t45–t48*.march`; `specs/lang/types/reject/t36–t38*.march`; `specs/lang/types/INDEX.md`.

**Deliverable:** Document (re-grep live):
- The capability HIERARCHY (18 entries, `lib/caps/cap_lattice.ml:15-34`) + subsumption `cap_subsumes` (`:50`) / `normalize` (`:56`); the typecheck alias (`typecheck.ml:1103`).
- `needs [IO.Network; …]` manifest (`DNeeds`, `ast.ml:159`; token `lexer.mll:50`).
- **Check 1** (`typecheck.ml:5561`): every `Cap(X)` **in a function/actor/extern SIGNATURE** must be covered by a declared `needs` via subsumption, else ERROR. Capture the exact message (`` `Cap(IO.Network)` used in module `X` but `IO.Network` is not declared in `needs` ``).
- **Corpus:** accept — bare `Cap(X)` param covered by matching `needs` (t45); broad `needs IO` covers `Cap(IO.Network)` (subsumption, t46); sibling-independence (t47); a second well-formed subsumption shape (t48). reject — uncovered `Cap(X)` (t36); narrow `needs IO.Network` does NOT cover `Cap(IO)` (t37); one more Check-1 violation (t38). Each captured live (accept exit 0; reject exit 1 + pinned substring). INDEX rows + ALL count sites.

**Verify:** `MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/types/check_types.sh` all-pass; `bash scripts/check-docs.sh` exit 0 (Check C guards the counts); every reject reproduced live; citations re-grepped.

**Commit:** `docs(spec): widen typing reference — IO capability subsumption + Cap(X) signature enforcement (§2.8, Check 1)`.

---

## Task 2: Transitive `use` + extern-implied caps (Checks 4, 1c, 5) + the F1 honesty

**Files:** `core-march-types.md` (extend §2.8); `types/accept/t49–t50*.march`, `reject/t39*.march`; INDEX; `specs/todos.md` (file F1).

**Deliverable:**
- **Check 4** (`typecheck.ml:5662`): a module `use`ing another must declare (cover) the used module's declared caps — ERROR if missing. **Check 5** (`:5685`): an extern's `Cap(X)` must be in `needs` — ERROR. **Check 1c** (`:5608`): an extern block implies `IO.Foreign` (+`.Blocking`) — WARNING.
- **DOCUMENT THE F1 TRUTH HONESTLY:** Check 1 (signature `Cap(X)`), Check 4 (transitive `use`), Check 5 (extern cap) are ERRORs; but **Check 1b** (`:5589`, a body call to a `builtin_cap_table` builtin without `needs`) and Check 1c are **WARNING-only — `--check` exits 0**. State plainly: absence of `needs` is a machine-verified guarantee ONLY when authors thread `Cap(X)` through signatures; a module that calls IO builtins directly in a body is warned, not rejected. **FILE F1** in `specs/todos.md` as an open `- [ ]` (spec-overclaim / enforcement-gap: body-scan is warning not error, `:5596` `Err.warning_with_fix`); note the tutorial `capabilities.md` overclaims and is reconciled in T7.
- **Corpus:** accept — importer declares the imported module's caps (t49); well-formed extern with `needs IO.Foreign` + specific cap (t50). reject — importer missing a transitively-required cap (Check 4, t39). Captured live. INDEX + counts.

**Verify:** `check_types.sh` all-pass; `check-docs.sh` 0; F1 filed OPEN; the WARNING-vs-ERROR distinction verified live (a body-scan program `--check`s exit 0 with a warning; a signature/transitive violation exits 1).

**Commit:** `docs(spec): widen typing reference — transitive-use + extern caps (Checks 4/1c/5) + honest body-vs-signature enforcement (F1 filed)`.

---

## Task 3: `cap_narrow` + capability threading + effect inference (Check 8) + realtime exclusion (Check 7)

**Files:** `core-march-types.md` (extend §2.8); `types/accept/t51–t53*.march`, `reject/t40–t41*.march`; INDEX.

**Deliverable:**
- `cap_narrow : Cap(IO) -> Cap(a)` (`typecheck.ml:1458`, polymorphic return) + `root_cap : Cap(IO)` (`:1457`) — compile-time capability narrowing/threading; note it's runtime-erased. (Note the polymorphic-return reality as context for the deferred F4 — do NOT try to fix F4 here.)
- **Check 8** (`:5798`): a `*_migrate_state` fn must be IO-free, checked via the `own_cap_closures` projection (`:5444`) so the module's handler-level `needs` doesn't false-blame a pure migrate. **Check 7** (`:5755`): a `Tagged(_, Realtime)` param cannot coexist with a `Cap(Alloc|IO|Panic)` param — ERROR.
- Effect inference: `record_fn_caps` (`:5435`) accumulates `cap_closures` (own + module-wide) and `own_cap_closures` (own only); document the two projections and why Check 8 uses the own-only one (the F-caveat mitigation — verified sound+precise, survey P8c/P8d).
- **Corpus:** accept — narrow `Cap(IO)`→sub-cap threaded to a stricter callee (t51); env-record narrowing or a second threading shape (t52); pure `*_migrate_state` in a `needs IO` module (the caveat-mitigation witness, t53). reject — `*_migrate_state` doing IO (Check 8, t40); `Tagged(_,Realtime)` + `Cap(IO)` param (Check 7, t41). Captured live. INDEX + counts.

**Verify:** `check_types.sh` all-pass; `check-docs.sh` 0; rejects reproduced live; the migrate own-caps-projection accept (t53) confirmed (a pure migrate in a `needs IO` module accepts).

**Commit:** `docs(spec): widen typing reference — cap_narrow/threading + effect inference (Check 8) + realtime exclusion (Check 7)`.

---

## Task 4: Behavioral module caps — documentation + file F2/F3/F5

**Files:** `core-march-types.md` (extend §2.8 with a behavioral-caps subsection); `types/accept/t54–t56*.march`, `reject/t42–t44*.march`; INDEX; `specs/todos.md` (file F2, F3, F5).

**Deliverable:** Document the five behavioral caps + their enforcement (re-grep). Corpus ONLY for the CURRENTLY-CORRECT behaviors (the F2/F3-broken cases get their reject witnesses in T5/T6, AFTER the fix):
- `cap no_panic` (`check_no_panic_module` `typecheck.ml:6489`): bans direct/transitive `panic_surface_*` calls (`:6408-6431`: `panic`/`unwrap`/`expect`/`head`/`tail`/`List.nth`/…) + unsafe integer division unless the divisor carries a `{v|v≠0}`/`v>0` refinement (Z3-discharged, `division_safety.ml`). **CORRECT** for explicit panic + division → corpus witnesses now. **NOTE the F3 gap** (non-exhaustive match slips through) in prose + file F3; its reject witness comes in T6.
- `cap no_alloc` (`refinecheck/no_alloc.ml`): per-fn syntactic scan — `ETuple(≥1)`/`ERecord`/`ECon(≥1 arg)`/`ELam` allocate → ERROR; nullary ctors + `()` safe. **CORRECT** → corpus witnesses now.
- `cap no_extern` (`check_no_extern_module` `:6604`): any `DExtern` or `needs IO.Foreign` → ERROR. **CORRECT** → witness now.
- `cap pure` (`check_pure_module` `:6581`) + `cap deterministic` (`:6641`): document the INTENDED semantics (pure = no side effects; deterministic = no clock/RNG). **FILE F2** (the `pure_banned` `:6570` / `deterministic_banned` `:6632` lists reference NONEXISTENT builtin names — `write_file`/`random_int`/`now_ms` — and MISS the real ones — `file_write`/`random_bytes`/`unix_time_ms` — so a `cap pure` module calling `file_write` typechecks clean; UNSOUND). Document `pure`/`deterministic` in prose but add NO accept/reject corpus for them yet (their correct-rejection witnesses arrive in T5 after the F2 fix; adding a `cap pure`+`file_write` reject now would fail because it currently accepts). You MAY add an accept witness for a genuinely-pure `cap pure` module (t54) that stays valid across the fix.
- **Corpus (current-correct only):** accept — a valid `cap no_alloc` fn (t55), a genuinely-pure `cap pure` module (t54). reject — `cap no_panic` + explicit `panic` (t42); `cap no_alloc` + tuple construction (t43); `cap no_extern` + extern (t44). Captured live. INDEX + counts.
- **FILE F2, F3, F5** in `specs/todos.md` as open `- [ ]` (F2/F3 headline unsound; F5 cosmetic `println` skips body-scan). Note F2/F3 are FIXED in T5/T6 of this slice (so they'll flip to Done there).

**Verify:** `check_types.sh` all-pass; `check-docs.sh` 0; the working rejects reproduced live; F2/F3/F5 filed OPEN.

**Commit:** `docs(spec): widen typing reference — behavioral caps (no_panic/no_alloc/no_extern/pure/deterministic) + file F2/F3/F5`.

---

## Task 5: FIX F2 — derive `pure`/`deterministic` banned builtins from the real cap table (COMPILER)

**Files:** `lib/typecheck/typecheck.ml` (`pure_banned` `:6570`, `deterministic_banned` `:6632`, `check_pure_module`/`check_deterministic_module`); `test/test_caps.ml` (regression); `specs/lang/types/reject/t45–t47*.march` (the now-rejecting witnesses); INDEX; `specs/todos.md` (F2 → Done).

**The bug (survey F2):** `pure_banned`/`deterministic_banned` are hand-maintained name lists that reference builtins that DO NOT EXIST (`write_file`, `random_int`, `now_ms`, …) while missing the REAL effectful builtins (`file_write`, `file_read`, `random_bytes`, `unix_time_ms`, `vault_set`, …). So `cap pure`/`cap deterministic` silently fail to reject the most common effectful builtins. The authoritative effect map is `builtin_cap_table` (`typecheck.ml:999-1097`, ≈90 builtins → cap).

**Deliverable:**
- Replace the hand-guessed `pure_banned`/`deterministic_banned` name lists with lists DERIVED from `builtin_cap_table`: `cap pure` bans every builtin the table maps to any non-empty IO/effect cap (i.e. anything that performs a side effect); `cap deterministic` bans the nondeterminism sources (clock + RNG — the builtins mapped to `IO.Clock`/`IO.Random`-family caps; determine the exact cap tags from the table). **Determine the precise intended semantics from the table + `capabilities.md` before coding** — `pure` is stricter (no effects at all) than `deterministic` (no clock/RNG but a deterministic file read might be allowed — confirm from the spec/table which caps each bans). Keep any INCIDENTAL correct entries; the point is to stop referencing nonexistent names and start catching the real ones.
- Verify with value-revealing probes: `cap pure` + `file_write`/`file_read`/`random_bytes` → now REJECT (was accept); `cap deterministic` + `unix_time_ms(())` → now REJECT; a genuinely-pure `cap pure` module (T4's t54) → still ACCEPT (no over-rejection); a genuinely-deterministic module → still accept. Capture the exact new reject messages.
- Add regression tests in `test/test_caps.ml` asserting the now-rejected programs reject and the pure ones still accept — RED pre-fix, GREEN after. **⚠️ (plan-review M3) Do NOT model on the existing `test_cap_pure_now_ms_error`/`_random_int_error` cases (`test_compiler.ml:~4071/4078/4099/4113`) — those pass for the WRONG reason (`now_ms`/`random_int` are nonexistent, so the program ALSO gets an "I cannot find `now_ms`" unbound ERROR that satisfies `has_errors` regardless of the cap ban; they stay green even under the fix, giving false confidence). Write NEW cases using REAL builtins (`file_write`/`random_bytes`/`unix_time_ms`) that reject ONLY via the cap ban. Optionally replace/augment the 4 stale ones + note in the commit that they pass via the unbound error.**
- **Corpus:** add `reject/t45–t47` — `cap pure` + `file_write` (t45); `cap pure` + `random_bytes` (t46); `cap deterministic` + `unix_time_ms` (t47), each with the pinned new message. **⚠️ (plan-review M2) Each F2 witness MUST be TYPE-CORRECT so the ONLY rejection is the cap violation, not an incidental type error: `file_write` returns `Result(Unit, r)`, NOT `Unit` — a naive `fn f() : Unit do file_write(...) end` exits 1 TODAY for a type mismatch (masking the F2 gap). Use a `Result`-returning signature (e.g. `: Result(Unit, String)`); verified live that `cap pure` + type-correct `file_write` exits 0 PRE-fix (the genuine gap) and the "has side effects" error does not fire.** (These are the F2 witnesses that were impossible pre-fix.) INDEX + counts.
- Move **F2 → Done** in `specs/todos.md` (fix locus + tests + witnesses).

**Verify:** the F2 probes reject after / accepted before; `cap pure` t54 (genuine-pure) still accepts (no false-positive over-rejection — check a realistic pure module, not a trivial one); `scripts/run-tests.sh` FULL six-runner GREEN, no regressions (esp. any existing `cap pure`/`deterministic` stdlib modules — if a real stdlib module is `cap pure` and now newly-rejected, that's a REAL bug the fix surfaced: investigate whether the module actually violates purity or the fix over-bans, and report); `check_types.sh` all-pass; `check-docs.sh` 0.

**Commit:** `fix(typecheck): derive cap pure/deterministic banned builtins from builtin_cap_table so real effectful builtins (file_write/random_bytes/unix_time_ms) are caught (F2) + reject corpus + tests`.

---

## Task 6: FIX F3 — `cap no_panic` treats a non-exhaustive match as a panic site (COMPILER)

**Files:** `lib/typecheck/typecheck.ml` (`check_no_panic_module` `:6489`, `panic_surface_*` `:6408-6431`) and/or wherever exhaustiveness is computed; `test/test_caps.ml`; `specs/lang/types/reject/t48*.march`; INDEX; `specs/todos.md` (F3 → Done).

**The bug (survey F3):** a `cap no_panic` module with a non-exhaustive `match` (which lowers to a runtime "no matching clause" panic) typechecks clean and then panics at runtime (P9c). `no_panic` covers named partial functions but NOT the match-non-exhaustiveness panic surface.

**⚠️ Fix-locus reality (plan-review I1 — do NOT follow the naive "reuse the verdict" instruction):** `check_no_panic_module` (`typecheck.ml:~6489`, re-grep) works PURELY from `calls_in_expr` (a `(name, span)` list) — it NEVER inspects `EMatch` nodes. `check_exhaustiveness` (`~:3279`) only EMITS a Warning into `env.errors` — it stores NO consumable verdict (no side-table). So there is no existing verdict to "reuse." You must WIRE ONE of two ways, both entirely inside `typecheck.ml`:
  - **(a) preferred — a side-table:** have `check_exhaustiveness` (or its `find_missing_mc` core) record the spans of non-exhaustive `EMatch`es into a new `env` field (e.g. `env.nonexhaustive_matches : span list ref` or a per-fn set), and have `check_no_panic_module` read it and error for any such span whose enclosing fn is in a `cap no_panic` module.
  - **(b) alternative — re-walk:** have `check_no_panic_module` walk the fn bodies for `EMatch` and re-invoke `find_missing_mc`/`check_exhaustiveness` per match — this needs the scrutinee TYPE (i.e. threading the `type_map`, which is NOT currently passed to `check_no_panic_module`), so it's more plumbing.
  Prefer (a). Either way it's localized to `typecheck.ml`, but it is NOT trivial wiring — budget for adding the side-table + read.

**Deliverable:**
- Implement option (a) (or (b) if cleaner in practice): in a `cap no_panic` module, a non-exhaustive `EMatch` becomes an ERROR (clear message, e.g. "a non-exhaustive `match` can panic at runtime; a `cap no_panic` module must handle every case or add a `_ ->` arm"). Do NOT re-implement exhaustiveness — reuse `find_missing_mc`/`check_exhaustiveness`.
- Verify: a `cap no_panic` module with a non-exhaustive match → now REJECT (was accept + only a warning); a `cap no_panic` module with an EXHAUSTIVE match → still ACCEPT (no over-rejection); the existing explicit-`panic`/division rejections still fire. Capture the new message.
- Add a regression test in `test/test_caps.ml` — RED pre-fix, GREEN after.
- **Corpus:** add `reject/t48` — `cap no_panic` + non-exhaustive match, pinned message. INDEX + counts.
- Move **F3 → Done** in `specs/todos.md`.

**Verify:** the non-exhaustive-match program rejects after / accepted before; an exhaustive `cap no_panic` module still accepts; **`accept/t14_nonexhaustive_match_still_typechecks` STILL ACCEPTS (exit 0)** — a PLAIN (non-cap) non-exhaustive match must remain a warning/accept; the fix must fire ONLY inside `cap no_panic` modules (this is the key regression guard — run `check_types.sh` and confirm t14 is green); `scripts/run-tests.sh` FULL six-runner GREEN (watch for any stdlib `cap no_panic` module that now newly-rejects — investigate as in T5); `check_types.sh` all-pass; `check-docs.sh` 0.

**Commit:** `fix(typecheck): cap no_panic rejects non-exhaustive matches (they panic at runtime) by consuming the exhaustiveness verdict (F3) + reject corpus + test`.

---

## Task 7: Consolidate + `capabilities.md` reconcile + closeout

**Files:** `core-march-types.md` (finalize §2.8); `capabilities.md` (reconcile); `types/INDEX.md`; `specs/lang/index.md`; `specs/progress.md`, `specs/todos.md`; pointer from `core-march.md` (erasure note).

**Deliverable:**
- Finalize §2.8: coherent read; the three enforcement tiers stated precisely (signature `Cap` + transitive-`use` + extern = ERROR; body-scan = WARNING, per F1); subsumption; effect inference; behavioral caps (with F2/F3 now FIXED); the runtime-erasure note (cross-ref `core-march.md`).
- **Reconcile `capabilities.md`** (692-line tutorial): fix the F1 overclaims ("the build fails" / "enforces `needs` as an error" / "no false positives") to state the honest signature-vs-body distinction; note the F2/F3 fixes (behavioral caps now catch the real effectful builtins + non-exhaustive matches); re-verify its code examples `--check` as claimed (fix any that don't, à la slices 3/4). If it documents the proof-cap mint idiom (F4), add a note that the documented idiom is being reconciled in a later slice (F4 filed).
- **Counts:** INDEX (all sites — Check C guards), the §3 illustrative-table note if touched; confirm `check_types.sh` all-pass at the final count. Add a `specs/lang/index.md` capabilities entry if the umbrella maps chapters.
- **Bookkeeping:** `specs/progress.md` — the slice-5 milestone (IO caps + behavioral caps in the typing reference, the F2/F3 soundness fixes, N accept + M reject programs, findings F1/F4/F5 open + F2/F3 fixed, static/compile-time property). `specs/todos.md` — Done entry for the slice; confirm F1/F4/F5 stay OPEN, F2/F3 Done; note the next slice (behavioral-cap deepening / proof caps / linear types) as queued.

**Verify:** `check_types.sh` + `check-docs.sh` (incl. Check C) all green; `capabilities.md` examples verified; findings roster correct (F2/F3 Done, F1/F4/F5 open).

**Commit:** `docs(spec): widening-slice-5 closeout — capabilities/effects (IO + behavioral) + F2/F3 fixed`.

---

## Self-review checklist (run before executing)

1. **Fix ordering:** F2/F3 reject witnesses are added IN their fix task (T5/T6), never earlier — a pre-fix program accepts, so its reject witness would fail the harness.
2. **Full-suite gate:** T5 and T6 each pass `scripts/run-tests.sh` before landing; verified with a value-revealing probe (a program that accepts pre-fix REJECTS post-fix).
3. **F1 honesty:** the reference states body-scan = WARNING, signature = ERROR — never repeats the tutorial's "build fails" overclaim; `capabilities.md` reconciled in T7.
4. **No golden:** the system is compile-time/static; every witness is `--check` accept/reject in `types/`. No `g40`.
5. **Findings:** F2/F3 fixed+Done; F1 (enforcement gap), F4 (proof-cap mint mismatch — DEFERRED), F5 (println cosmetic) filed OPEN. Proof caps out of scope this slice.
6. **Over-rejection watch:** the F2/F3 fixes must not newly-reject a *legitimate* `cap pure`/`no_panic` stdlib module — if the full suite surfaces one, determine whether it's a real violation (good — the fix caught it) or over-banning (fix the fix), and report.
7. **Capture-not-guess** every reject; **re-grep** every citation live (concurrent commits drift lines).
