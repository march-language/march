# Wave 3 Chunk 1: Shared Modules + Perceus Restructure

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kill the cross-pass drift class (magic strings, duplicated predicates, name-sniffing) and restructure perceus.ml around an explicit environment — the structural fixes for the two highest fix-density files per `specs/analysis/2026-07-01-pipeline-deep-review.md` §7 (perceus.ml/borrow.ml: 89% fix-commits).

**Architecture:** Behavior-preserving refactors only. Two new shared modules (`tir_names.ml`, `rc_types.ml`), a `fn_kind` field on `Tir.fn_def` replacing name-sniffing, then perceus.ml's six mutable globals replaced by a threaded env record, then the file split into `perceus_*.ml` units. llvm_emit/lower splits are Chunk 2 (separate plan).

**Tech Stack:** OCaml 5.3 / dune. New files join the existing `lib/tir` library as flat `lib/tir/*.ml` modules (no subdirectory — avoids new dune library plumbing and keeps `open`-free qualified access cheap).

## Global Constraints — REFACTOR DISCIPLINE (these define the wave)

- **Behavior-identical, provably.** Every commit must show: six runners exit 0 (isolated HOME) AND **zero TIR snapshot churn** (`run_snapshots.exe` green with NO `.expected` changes) AND the four compiled benchmarks (`--compile --opt 2`: tree_transform, list_ops, binary_trees, mutual_recursion) matching `specs/benchmarks.md` outputs with timings within noise (±10%). Exception: Task 3's printer caveat, documented there.
- **Find a bug while moving code → do NOT fix it.** Preserve the behavior bit-for-bit, file a specs/todos.md entry describing it, note it in your report. Mixing fixes into moves destroys bisectability — the whole point of this wave.
- **One commit per task.** Env-threading and file-splitting are SEPARATE tasks/commits by design.
- **Worktree:** ONLY /Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3 (branch claude/hopeful-kapitsa-9f49f3, base c00bcb6c == main == origin/main). Controller handles main at chunk end.
- **Build/test recipe:** `dune build --root .` (REQUIRED); six runners `dune build --root . test/run_compiler.exe test/run_eval.exe test/run_codegen.exe test/run_stdlib.exe test/test_stdlib_march.exe test/run_snapshots.exe` then each `HOME=$PWD/.w3home ./_build/default/test/<t>.exe -e` (mkdir -p .w3home first), judged by EXIT CODE. scripts/run-tests.sh does NOT work from worktrees. NEVER `eval $(opam env ...)`.
- **Process rules:** foreground only; wedge rule (runner >4 min wall → kill, retry once isolated-HOME, else BLOCKED naming the wedge); no `git stash` (file copies); never pipe `march --compile` output (redirect to files); explicit staging; no Co-Authored-By.
- **deciduous:** action node before edits linked from goal 1599; outcome `--commit HEAD` after.
- **Do not touch:** test/test_properties.ml; runtime/; bin/ (except if a moved module forces a reference update — flag it).
- **Known pre-existing failures (NOT yours):** bench/heapsort.march RC underflow (separate confirmed bug); examples/supervision_linear_drop.march race; mono "Monomorphization limit reached" (documented skip).
- **Reference:** the target inventory below comes from `specs/analysis/2026-07-01-pipeline-deep-review.md` §7.1–7.3 and the wave-1/2 fix history. Line numbers there are stale — locate by grepping, always.

---

### Task 1: `lib/tir/tir_names.ml` — one home for every cross-pass name contract

**Files:**
- Create: `lib/tir/tir_names.ml`
- Modify (consumers): `lib/tir/lower.ml`, `lib/tir/defun.ml`, `lib/tir/join_points.ml`, `lib/tir/borrow.ml`, `lib/tir/perceus.ml`, `lib/tir/llvm_emit.ml`, `lib/tir/js_emit.ml`, `lib/tir/mono.ml` (whichever of these actually contain the strings — grep-verify each)
- Test: `test/test_codegen.ml` or a small `test/test_tir_names.ml` (unit tests for parse/mangle round-trips)

**Interfaces (produced — later tasks consume):** a module of pure functions/constants. Suggested surface (adapt names to what the code actually needs; keep flat and boring):
`tuple_tag : int -> string` (`"$Tuple%d"`), `fv_field : int -> string` (`"$fv%d"`), `is_tuple_tag`, `try_call_name`/`try_call_val_name` + `is_try_call`, `apply_fn_name`/`is_apply_fn` (replaces the two drifted copies in perceus.ml and llvm_emit.ml — diff them first; if they differ, preserve EACH caller's exact behavior and expose the difference as two named predicates with a comment, do NOT silently unify), `clo_struct_prefix`/`is_clo_struct` (`"$Clo_"`), `iface_mangle : iface:string -> ty:string -> meth:string -> string` + `is_iface_mangled` (the `$`-before-last-`.` predicate from the W2 guard — llvm_emit's `fail_if_unresolved_iface_method` and the `unqualified_fns` exclusion both consume it), `default_arg_mangle`/`parse_default_arg` (`base$N`, `f$N`), actor suffixes (`_Msg/_Actor/_State/_dispatch/_spawn`) and the `$d_/$e_/$f_` field-sort prefixes (docstring MUST state the C-runtime word-index coupling: runtime reads a[2]/a[3]/a[4] — see lower.ml's comment), `bool_tag : bool -> string` (document the True/true/string_of_bool triple-spelling mess and pick the canonical producer — but ONLY centralize the producers; llvm_emit's capitalize-tolerant decoder stays as-is this chunk), `test_fn_name : int -> string`/`setup_fn_name`, `runtime_prefix`/`has_runtime_prefix` (the `march_` 0-6 check, 4 aligned sites in llvm_emit).

- [ ] **Step 1: Inventory.** Grep each magic string across lib/tir + lib/desugar; build a table (report artifact) of string → producing sites → consuming sites. Anything the analysis doc lists that no longer exists: note and skip.
- [ ] **Step 2: Write tir_names.ml** with doc comments per entry naming producers/consumers and any cross-system coupling (C runtime, JS emitter).
- [ ] **Step 3: RED (unit tests):** round-trip tests (e.g. `parse_default_arg (default_arg_mangle f 2) = Some (f, 2)`), `is_iface_mangled` positive/negative cases including `List.map$Int` (must be FALSE — the $ is after the last dot) and a user fn named with dots. Run them against the new module.
- [ ] **Step 4: Convert consumers site-by-site** — each replaced literal/predicate must produce byte-identical strings. NO behavior tweaks. Where two copies of a predicate exist and differ (the is_apply_fn pair!), preserve per-caller behavior exactly.
- [ ] **Step 5: Full gate:** build, six runners, ZERO snapshot churn, four benchmarks. If any snapshot churns, a "pure move" wasn't — diff it, find the string you changed, fix the move.
- [ ] **Step 6: Commit** `refactor(tir): Tir_names — single home for cross-pass name contracts (W3.1)`.

---

### Task 2: `lib/tir/rc_types.ml` — one canonical needs_rc

**Files:**
- Create: `lib/tir/rc_types.ml`
- Modify: `lib/tir/perceus.ml`, `lib/tir/borrow.ml`
- Test: unit tests alongside Task 1's (a `needs_rc`/`borrow_eligible` divergence table test)

**Interfaces:** `needs_rc : Tir.ty -> bool` (perceus's semantics — the RC-op emission question) and `borrow_eligible : Tir.ty -> bool` (borrow.ml's semantics — the inference-eligibility question). They intentionally diverge on `TFn _`/bare `TVar _` (perceus true, borrow false) — the analysis doc flagged this as an undocumented landmine. The module's doc comment states WHY each answers differently and what breaks if either changes (closure-FV fix history: a705cc95, d2cf09e, fd520110).

- [ ] **Step 1:** Diff the two current copies line-by-line (borrow.ml ~:152-163 vs perceus.ml ~:203-237 — stale line refs, grep). Enumerate every type constructor's answer in both. Any divergence beyond the documented TFn/TVar pair: STOP and report BLOCKED with the table (it may be an undiscovered bug — do not pick a side).
- [ ] **Step 2:** Write rc_types.ml with both predicates + the divergence table as a doc comment; a unit test asserts the divergence is exactly {TFn, TVar} and nothing else (table-driven over representative types).
- [ ] **Step 3:** Point perceus.ml at `Rc_types.needs_rc`, borrow.ml at `Rc_types.borrow_eligible`; delete the local copies (borrow.ml's "duplicated to avoid cyclic dependency" comment goes away — rc_types has no deps on either).
- [ ] **Step 4: Full gate** (six runners, zero snapshot churn — post-perceus snapshots are the sharp check here, benchmarks).
- [ ] **Step 5: Commit** `refactor(tir): Rc_types — canonical needs_rc + borrow_eligible with documented divergence (W3.2)`.

---

### Task 3: `fn_kind` role flags on `Tir.fn_def` — retire name-sniffing

**Files:**
- Modify: `lib/tir/tir.ml` (add `fn_kind` variant + field), synthesis sites (`lib/tir/defun.ml` lambdas + apply fns; `lib/tir/join_points.ml`; wherever `__try_call*` fns are synthesized — grep Tir_names.try_call producers), consumers (`lib/tir/borrow.ml` `$Clo_`/`__try_call` checks; `lib/tir/perceus.ml` is_apply_fn/`$clo`; `lib/tir/llvm_emit.ml` is_apply_fn), `lib/tir/pp.ml` (see printer caveat)
- Test: extend Task 1's unit tests; snapshot gate

**Interfaces:** `type fn_kind = FnNormal | FnLambda | FnJoinPoint | FnApply | FnTryThunk` (adapt to what synthesis sites actually distinguish); every `fn_def` constructor site sets it (default `FnNormal` for parsed user fns).

- [ ] **Step 1:** Enumerate every `fn_def` record construction (the compiler finds them once the field is added — add it and follow the errors). At each synthesis site set the honest kind.
- [ ] **Step 2:** Convert consumers to check the flag. TRANSITION SAFETY: for one commit, each converted consumer ASSERTS flag-vs-name-sniff agreement (`assert (new_answer = old_sniff_answer)` behind a debug conditional or plainly — cheap) so a missed synthesis site fails loudly in the suite rather than silently changing RC behavior. The assertions come out in Chunk 2.
- [ ] **Step 3: PRINTER CAVEAT:** if `pp.ml`/show fns print fn_def fields positionally or exhaustively, printing fn_kind churns every snapshot. Do NOT print fn_kind this chunk — keep the printer's output byte-identical (add the field to the record but omit from the printer, with a comment referencing this plan). Zero snapshot churn stays the gate.
- [ ] **Step 4: Full gate + benchmarks.**
- [ ] **Step 5: Commit** `refactor(tir): fn_kind role flags on fn_def; consumers assert against legacy name-sniffing (W3.3)`.

---

### Task 4: Perceus env-record threading (IN PLACE — no file split yet)

**Files:**
- Modify: `lib/tir/perceus.ml` only
- Test: snapshot gate is the primary net; six runners

**Interfaces:** an `env` record (immutable, threaded as a parameter through `insert_rc_expr` and its helpers) replacing the module-level mutable refs — grep for `ref` at module level (the analysis doc named `_borrowed_field_vars`, `_var_ctx`, `_closure_fvs`, `_actor_sent` + others; W2-era fixes may have added/removed some — inventory first).

- [ ] **Step 1: Inventory the globals** and every save/restore site (the hand-rolled `let prev = !r in ... r := prev` dances). Map each to env semantics: a saved-and-restored ref IS a value scoped to a subtree — exactly a field of an env passed downward. A ref mutated WITHOUT restore (accumulator semantics) is NOT env-shaped — leave any such ref alone and document why (or thread it as an explicit accumulator return — only if the transformation is obviously mechanical).
- [ ] **Step 2: Thread the env** top-down through `insert_rc_expr`'s call tree. The transformation per site: `r := x; f (); r := prev` becomes `f { env with field = x }`. Where the OLD code had a restore-gap bug-shape (mutation escaping a scope non-lexically), the env version is NOT equivalent — if you find such a site, STOP: preserve the old behavior exactly (even if it looks wrong) and file a todos entry describing the suspicious site.
- [ ] **Step 3: Full gate — zero snapshot churn is the theorem prover here.** Also run `MARCH_DEBUG_PERCEUS=1` on `test/snapshots/src/scrutinee_borrowed_conservatism.march` (and 2 more corpus programs) before/after: inc/dec/free counts must be identical.
- [ ] **Step 4: Benchmarks** (env allocation on hot paths — if tree_transform regresses >10%, the env is being allocated per-node somewhere gratuitous; restructure to pass unchanged env by reference, not rebuild).
- [ ] **Step 5: Commit** `refactor(perceus): thread explicit env through insert_rc_expr; retire module-level mutable state (W3.4)`.

---

### Task 5: Perceus file split (pure moves)

**Files:**
- Create: `lib/tir/perceus_liveness.ml` (live_before, name_free_in, vars_of_atom(s) — already self-contained), `lib/tir/perceus_elide.ml` (elide_cancel_pairs), `lib/tir/perceus_fbip.ml` (try_fbip_sink, fbip_expr, same_arity + `$fbip$` machinery), `lib/tir/perceus_scrut.ml` (preprocess_scrut_escape / Phase-0.5)
- Modify: `lib/tir/perceus.ml` (keeps env type, insert_rc_expr core, and the public entry point — the pass orchestrator), any external references (`bin/main.ml`, `lib/jit/` — grep `Perceus.`)
- Test: snapshot gate; six runners

- [ ] **Step 1:** Move function bodies VERBATIM (cut-paste; only module-qualification edits). The public API (`Perceus.run`/whatever bin/main.ml calls) stays on perceus.ml so external callers don't change.
- [ ] **Step 2:** Document the pass-ordering contract at the top of perceus.ml (preprocess_scrut → insert_rc → elide → fbip; runs after Known_call/Join_points, before Escape — verify against bin/main.ml and cite it).
- [ ] **Step 3: Full gate + benchmarks.** `git diff --stat` sanity: perceus.ml shrinks by ≈ the sum of the new files; use `git log --follow`-friendly moves (whole-function granularity).
- [ ] **Step 4: Commit** `refactor(perceus): split liveness/elide/fbip/scrut-escape into focused modules (W3.5)`.

---

### Task 6: Bookkeeping

- [ ] Six runners for final counts; `scripts/check-docs.sh` green (the compiler-rc skill + CLAUDE.md reference perceus.ml paths — check the doc-lint catches any dead pointers from the split; fix pointers).
- [ ] specs/progress.md: Wave 3 chunk 1 entry (what moved where, the zero-churn evidence). specs/todos.md: mark the §7.1/§7.2 items progressed; list anything Tasks 1–5 filed.
- [ ] Commit `docs(specs): record Wave 3 chunk 1 (shared modules + perceus restructure)`.
