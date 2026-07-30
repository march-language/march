# Core March widening slice 7 — linear/affine types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Widen the conformance-tested core references (`specs/lang/core-march-types.md`, `specs/lang/core-march.md`) to cover the linear/affine type system, with one in-slice compiler fix (the `TLin`/constraint-resolution leak), a types-corpus expansion with pinned diagnostics, one golden witness, a findings ledger, and reconciliation of the `linear-types.md` tutorial.

**Architecture:** Follows the widening-slice template of slices 1–6 (survey → in-slice fix where a witness is blocked → reference sections → corpus → findings → tutorial reconcile → closeout). Linearity is enforced purely statically (`env.lin` tracker in `lib/typecheck/typecheck.ml`; the interpreter and runtime never re-check), so this is primarily a `types/` accept/reject slice like slice 5 (capabilities), plus ONE golden (linear-annotated program runs byte-identical on both backends).

**Tech Stack:** OCaml 5.3 (typechecker), March conformance corpora (`specs/lang/types/`, `specs/lang/golden/`), alcotest.

## Global Constraints

- Build: `export PATH="/Users/80197052/.opam/march/bin:$PATH"`; `dune build --root . bin/main.exe`. NEVER `eval $(opam env ...)`.
- Test gate for the compiler-fix task (Task 1): full six-runner suite `bash scripts/run-tests.sh`, judged by exit code. Docs-only tasks: `bash specs/lang/types/check_types.sh`, `bash specs/lang/golden/verify.sh`, `bash scripts/check-docs.sh`, all exit 0.
- Never pipe `march --compile` output; redirect to a file, judge by `$?`.
- Git: stage files explicitly by name; NO `Co-Authored-By`; never `git stash`; one commit per task; update `specs/todos.md` + `specs/progress.md` in the closeout commit.
- Corpus numbering: types corpus is currently **120 = 63 accept + 57 reject**; new accepts start at `t64`, new rejects at `t58`. Golden corpus is currently **40**; the new golden is `g41`. Update `specs/lang/types/INDEX.md` and `specs/lang/golden/INDEX.md` counts (check-docs Check C enforces consistency).
- Diagnostic strings in EXPECT-ERROR lines must be substrings of the REAL emitted text (verified live in the survey; quoted verbatim in each task below).

## Survey ground truth (2026-07-10, all live-verified against `_build/default/bin/main.exe --check`)

Verified accepts: `linear` param single-use; `linear let` single-use; `c : affine Cap` param (type-modifier form) dropped; linear-field single access; **`send(pid, Ctor(linear_value))` typechecks — send is a consuming use**.
Verified rejects (exact messages):
- Drop: `The linear value `X` was never used.` + `Linear values must be consumed exactly once — did you mean to pass it somewhere?` (fires for `linear` params AND `linear let`)
- Double-use: `The linear value `X` is used more than once here.` + `Linear values must be consumed exactly once — they cannot be copied or ignored.` (params, lets, match-then-reuse)
- Affine double-use: `The affine value `X` is used more than once here.` + `Affine values may be used at most once.`
- Closure capture: `The linear value `X` cannot be captured by a closure.`
- Let-bound linear-field double access: `The linear value `p#data` is used more than once here.` (note the internal `#` sentinel leaking — finding L5)
- `always_linear type` value drop: same never-used message.

New findings (L1–L6), full statements in Task 4:
- **L1** `affine` in PARAM position is a PARSE error (`I got stuck here`) — only `LINEAR` has a param production (`parser.mly:417-418`); `AFFINE` exists only as a `ty_atom` modifier (`:938-939`). The tutorial's `fn maybe_connect(affine cap : NetworkCap)` (`linear-types.md:78`) does not parse. Working form: `cap : affine NetworkCap`.
- **L2 (the in-slice fix)** `linear Int` fails `Num`/`Ord`/interface constraint discharge — `p.data + 1` (a SINGLE use) rejects with `` `linear Int` does not implement Num. `` The constraint-discharge loop (`typecheck.ml:5504-5522` CNum/COrd arm, `:5524` CInterface arm) does `repr` but never strips `TLin`, so the wrapper falls to the catch-all rejection, despite `impl_matches_ty` already stripping it (`:5375`) and unification coercing transparently (`:2414-2417`).
- **L3** Linear FIELD tracking silently degrades for fn-param-bound records: only a WARNING (`linearity tracking is not available for `p``) — sentinels are registered only at let-binding sites (`bind_linear_field_sentinels`, `:2777-2788`). Enforcement holds only for locally-let-bound records. Also: the existing unit test `test_linear_field_double_access_error` (`test/test_compiler.ml:918`) passes VACUOUSLY on the L2 error, not on double-use — Task 1 must rewrite it.
- **L4** `always_linear_types` is NAME-KEYED GLOBALLY (`:7959-7973` registers bare + qualified names): a user `type Handle = H(Int)` silently inherits linearity from stdlib's `always_linear type Handle` (`stdlib/handle.march`) — a zero-`linear`-keyword program gets hard linear errors — and the constructor-namespace cross-talk corrupts exhaustiveness (`missing case: Handle(_)` for a match on the user's `H`).
- **L5** The internal `var#field` sentinel name leaks into the user-facing double-use diagnostic (`p#data`).
- **L6** Tutorial claims 13 and 14 CONTRADICT each other (`linear-types.md:117-122` ownership-transfer send vs `:127-129` "cannot be sent directly"); reality: send is allowed and consumes (claim 14 is FALSE).
- Pre-existing **F7** (session-channel linearity: parameter reuse + unclosed-drop slip through) reconfirmed at the code level: `record_use` fires only via `le_used` on let-bound names; `Chan.send` re-reads a parameter's declared session type (`:3733`) without consuming the binding.

Probe corpus (verified sources to adapt): session scratchpad `linprobe/` — c1–c9, p4, p7, p9, p14–p17.

---

### Task 1: COMPILER FIX — strip `TLin` in constraint discharge (L2) + de-vacuate the field test + sentinel message cleanup (L5)

**Files:**
- Modify: `lib/typecheck/typecheck.ml` (constraint-discharge loop ~`:5490-5560`; double-use message site ~`:2807-2815`)
- Modify: `test/test_compiler.ml` (rewrite `test_linear_field_double_access_error` ~`:918`; add 3 new tests)

**Interfaces:**
- Consumes: `TLin of Ast.linearity * ty` (`typecheck.ml:92`), `repr`, the existing strip precedent `impl_matches_ty`'s `TLin` arm (`:5375`).
- Produces: constraint discharge treats `linear T`/`affine T` identically to `T` for `Num`/`Ord`/`CInterface`. Later tasks' corpus programs `t64`/`t67` depend on this.

- [ ] **Step 1: Write the failing tests**

In `test/test_compiler.ml`, next to the existing H6 linear-field tests (~line 915):

```ocaml
let test_linear_field_arith_single_use_ok () =
  (* L2: a single arithmetic use of a linear Int field must typecheck —
     constraint discharge must strip the TLin wrapper (like impl_matches_ty
     already does) instead of rejecting `linear Int` as not-Num. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn ok2(p: Packet) : Int do
      p.data + 1
    end
  end|} in
  Alcotest.(check bool) "linear Int field arithmetic: no error" false (has_errors ctx)

let test_linear_let_arith_ok () =
  (* Same leak, linear-let surface: linear let n : Int used once in arithmetic. *)
  let ctx = typecheck {|mod Test do
    fn f() : Int do
      linear let n : Int = 1
      n + 1
    end
  end|} in
  Alcotest.(check bool) "linear let Int arithmetic: no error" false (has_errors ctx)
```

- [ ] **Step 2: Run to verify they fail**

Run: `dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e 2>&1 | tail -5`
Expected: the two new tests FAIL (current behavior emits `` `linear Int` does not implement Num. ``).

- [ ] **Step 3: Implement the fix**

In the constraint-discharge loop (`typecheck.ml`, the `List.iter (fun c -> ...)` starting ~`:5491`), add a strip helper and apply it at all three `repr` sites — the dedup key (`:5495`), the `CNum/COrd` arm (`:5506`), and the `CInterface` arm (`:5524`):

```ocaml
(* Linearity is transparent to interface/constraint discharge: `linear T`
   satisfies exactly the constraints `T` satisfies. impl_matches_ty already
   strips TLin (see its TLin arm); unification coerces TLin transparently.
   Without this, a single arithmetic use of a `linear Int` field rejects
   with "`linear Int` does not implement Num" before the linearity tracker
   ever runs. *)
let rec strip_lin t = match repr t with
  | TLin (_, inner) -> strip_lin inner
  | t' -> t'
in
```
then replace `let rt = repr t` / `let ty = repr t` with `let rt = strip_lin t` / `let ty = strip_lin t` in those three places. Do NOT touch `repr` itself (TLin must survive for the tracker and pp).

Sentinel cleanup (L5): at the double-use/never-used message construction (`:2807-2815`, `:2887-2889`), prettify names containing `#`:

```ocaml
let display_name n =
  match String.index_opt n '#' with
  | Some i -> Printf.sprintf "%s.%s (linear field)"
                (String.sub n 0 i) (String.sub n (i+1) (String.length n - i - 1))
  | None -> n
in
```
and use `display_name name` in the four message format strings. (Message BODY text otherwise unchanged — the corpus pins substrings that avoid the name.)

- [ ] **Step 4: Rewrite the vacuous test + add the L3 pin**

The existing `test_linear_field_double_access_error` (param-bound record) passed only because of the L2 error; after Step 3 it would go green with NO error (param-bound field tracking is warning-only — L3). Replace it:

```ocaml
let test_linear_field_double_access_error () =
  (* Double access must be caught for a LET-BOUND record (the sentinel path).
     NOTE: for a fn-PARAM-bound record, tracking degrades to a warning (L3,
     filed) — that shape is pinned by test_linear_field_param_warning_only. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn mk() : Packet do
      { data: 1, size: 2 }
    end
    fn bad() : Int do
      let p = mk()
      let x = p.data
      let y = p.data
      x + y
    end
  end|} in
  Alcotest.(check bool) "linear field let-bound double-access: error" true (has_errors ctx)

let test_linear_field_param_warning_only () =
  (* L3 pin: param-bound linear-field double access is NOT an error today
     (sentinels are only registered at let sites). If this starts erroring,
     L3 got fixed — update the finding and flip this expectation. *)
  let ctx = typecheck {|mod Test do
    type Packet = { linear data: Int, size: Int }
    fn bad(p: Packet) : Int do
      let x = p.data
      let y = p.data
      x + y
    end
  end|} in
  Alcotest.(check bool) "param-bound linear field: warning-only (L3)" false (has_errors ctx)
```

Register all four tests in the suite lists (~`:7257-7266`).

- [ ] **Step 5: Verify green + no regressions**

Run: `bash scripts/run-tests.sh` — full six-runner suite, exit 0. Also re-run the live probe: `./_build/default/bin/main.exe --check <scratchpad>/linprobe/c7c_field_arith_once.march` → exit 0, and `c7d_field_double_let.march` → exit 1 with the prettified name (no bare `p#data`).

- [ ] **Step 6: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml
git commit -m "fix: strip TLin in constraint discharge; de-vacuate linear-field test; prettify sentinel diagnostics"
```

---

### Task 2: Typing reference §2.9 — linearity (core-march-types.md) + accept corpus

**Files:**
- Modify: `specs/lang/core-march-types.md` (new §2.9 after §2.8; findings roster §4.1 gets L1–L6 stubs pointing at todos)
- Create: `specs/lang/types/accept/t64_linear_let_single_use.march`, `t65_linear_param_single_use.march`, `t66_affine_ty_param_drop.march`, `t67_linear_field_arith_single.march`, `t68_linear_send_consumes.march`
- Modify: `specs/lang/types/INDEX.md`

**Interfaces:**
- Consumes: Task 1's fix (t67 needs it). Rule-numbering convention from §2.3–§2.8.
- Produces: rule names (T-LinMark), (T-LinUse), (T-LinDrop), (T-AffDrop), (T-LinClosure), (T-LinField), (T-LinMatch), (T-LinCoerce), (T-AlwaysLin) — Task 3/4/6 cite these.

- [ ] **Step 1: Write §2.9** covering, with `typecheck.ml` citations: the five marking surfaces (`linear` param `parser.mly:417-418`; `linear let` `:1000-1001` — NO `affine let` production; `linear`/`affine` ty-modifiers `:938-939`; `linear` record fields `:977-978`; `always_linear type` auto-promotion `:7959-7973` + `bind_fn_param` `:4926-4937`); the tracker (`lin_entry`, `le_used : bool ref`, `:400-405`); check sites (`record_use` at every `EVar` `:3618`, `check_linear_all_consumed` at fn/let-scope close `:5266`/`:4854`, closure-capture snapshot `:4234-4259`, field sentinels `:2777-2788`/`:4398`); transparency (unify coercion `:2414-2417`, `impl_matches_ty` strip `:5375`, constraint-discharge strip from Task 1); the honest caveats — L3 (param-bound field tracking is warning-only), L4 (name-keyed always_linear registration), F7 (session-parameter reuse invisible). State the affine rule precisely: droppable (filtered out of `check_linear_all_consumed`, `:2883`), not duplicable.
- [ ] **Step 2: Write the five accept programs.** Adapt verified probes c3, c4, p14, c7c (post-fix), c9 respectively — each a self-contained `mod Main` with a `-- EXPECT-OK` header per corpus convention (copy an existing accept file's header format exactly). t68 is probe c9 verbatim (send consumes the linear value).
- [ ] **Step 3: Verify + commit.** `bash specs/lang/types/check_types.sh` → 125/125 exit 0. Update INDEX.md (rows + counts). `git add` the six files; commit `docs: core-march-types §2.9 linearity + accept corpus t64-t68`.

---

### Task 3: Reject corpus — pinned linearity diagnostics

**Files:**
- Create: `specs/lang/types/reject/t58_linear_param_drop.march`, `t59_linear_let_drop.march`, `t60_linear_param_double_use.march` *(numbering: continue from the current highest reject index — re-check `ls specs/lang/types/reject/` first; if t58+ are taken, shift accordingly and fix INDEX)*, `t61_linear_match_then_reuse.march`, `t62_linear_closure_capture.march`, `t63_linear_field_double_let.march`, `t64_affine_double_use.march`, `t65_always_linear_drop.march`, `t66_linear_use_after_send.march`
- Modify: `specs/lang/types/INDEX.md`

**Interfaces:** Consumes Task 2's rule names for INDEX cross-refs.

- [ ] **Step 1: Write the nine programs**, adapting verified probes (c1, p4, p15, c6, c5, c7d, p17, p7) plus one new shape: `t66` = probe c9 with `let _ = take(r)` added AFTER the `send` — expected `is used more than once`. EXPECT-ERROR pins (substrings of live output):
  - drop shapes: `was never used`
  - double-use shapes: `is used more than once here`
  - closure: `cannot be captured by a closure`
  - affine: `The affine value` + `used more than once`
  Use non-colliding type names (NEVER `Handle` — L4) and non-colliding ctors (NEVER `Put`).
- [ ] **Step 2: Verify each rejects for the RIGHT reason** — run each with `--check`, confirm exit 1 AND the pinned substring is present (the survey's lesson: exit-1-for-the-wrong-reason is the trap).
- [ ] **Step 3: Verify + commit.** `check_types.sh` → 134/134 exit 0; INDEX updated; commit `docs: linearity reject corpus with pinned diagnostics`.

---

### Task 4: Findings ledger (specs/todos.md)

**Files:** Modify: `specs/todos.md` (new section header `### Compiler: Linearity (found during Core March widening slice 7)`)

- [ ] **Step 1: File L1, L3, L4, L6 as OPEN `- [ ]` entries** with the full statements from the survey section above, each with repro, file:line loci, and the tutorial lines they contradict. L6 is filed as a resolved-contradiction NOTE (behavior is fine; the tutorial must be fixed in Task 6 — cross-ref). Add a cross-ref line under the existing F7 entry pointing to §2.9's honest-caveats paragraph.
- [ ] **Step 2: File L2 + L5 as ✅ Done entries** citing Task 1's commit, including the vacuous-test discovery (test asserted `has_errors` only and passed on the wrong error — the standing lesson for corpus/test authorship).
- [ ] **Step 3: Commit** `docs: file linearity findings L1-L6 (slice 7)`.

---

### Task 5: Operational note (core-march.md) + golden g41

**Files:**
- Modify: `specs/lang/core-march.md` (short §4.12 "Linearity at runtime")
- Create: `specs/lang/golden/g41_linear_annotations_erased.march` + expected-output registration per `golden/INDEX.md` convention
- Modify: `specs/lang/golden/INDEX.md`

- [ ] **Step 1: Write §4.12** (short): linearity is compile-time-erased — the interpreter performs no use-accounting (`eval.ml` handles `DAlwaysLinearType` identically to `DType`, `:8412-8423`; `chan_send` passes endpoints through, `:2686-2692`); the compiled backend uses `v_lin = Lin` only for optimization (`march_send_linear` zero-copy move, `llvm_emit.ml:1576-1593`; FBIP `$actor` param, `lower_actor.ml:92-94`); actor crash-cleanup drop-handlers (`eval.ml:1827-1837`) are resource management, not enforcement. Cross-ref §2.9 and F7.
- [ ] **Step 2: Write g41** — a program using `linear let` + a linear param + an affine ty-modifier binding, printing derived values (e.g. `println(int_to_string(take(r)))`), asserting byte-identical interp vs compiled output (the "annotations are erased" witness). Verify with `bash specs/lang/golden/verify.sh` → 41/41.
- [ ] **Step 3: Commit** `docs: core-march §4.12 linearity-at-runtime + golden g41`.

---

### Task 6: Tutorial reconcile (linear-types.md) + closeout

**Files:**
- Modify: `specs/lang/linear-types.md`, `specs/lang/index.md` (if the chapter row needs a cross-ref), `specs/todos.md` (move slice items to Done), `specs/progress.md` (Current State entry; corpus counts 120→134 types, 40→41 golden)

- [ ] **Step 1: Fix the tutorial against verified reality:**
  - `:78-87` affine param example → rewrite to the type-modifier form (`cap : affine NetworkCap`) with a note that `affine` has no param-keyword production (L1).
  - `:44-48`/`:52-57` flagship error texts → the real messages (`was never used` / `is used more than once here`).
  - `:117-129` claims 13/14 contradiction → one consistent account: send is a consuming use (typechecks; use-after-send rejects); zero-copy move is a compiled-backend optimization.
  - Linear-fields section → add the L3 caveat (enforcement only for let-bound records) and note post-L2 arithmetic works.
  - Add an `always_linear type` section (currently absent from the "canonical" chapter) with a pointer to `surface-syntax.md:234-262` and the L4 name-collision warning.
  - Session-channel section (`:146-177`) → align with F7's honest scope ("let-threaded continuations in the same scope"), cross-ref §2.7.8.
  - Every code example in the chapter must be re-verified live (`--check`, and run where it claims output) after editing — the slice-2/3 precedent.
- [ ] **Step 2: Run all gates:** `check_types.sh`, `verify.sh`, `scripts/check-docs.sh`, `bash scripts/run-tests.sh` — all exit 0.
- [ ] **Step 3: Commit** `docs: reconcile linear-types.md + slice 7 closeout (todos/progress/counts)`.

---

## Self-review notes

- Spec coverage: all six findings have a home (L2/L5 fixed in T1; L1/L3/L4/L6 filed in T4; F7 cross-referenced in T2/T6). Every tutorial claim from the survey is either witnessed (T2/T3/T5) or corrected (T6).
- The reject-corpus numbering in Task 3 carries an explicit re-check instruction because accept and reject sequences are independent and the survey counted 57 rejects (→ next is t58) — verify against `ls` before creating files.
- Type/name hygiene: every corpus program must avoid `Handle` (L4) and stdlib-colliding constructors (`Put`, `Ping`, …) — this bit the survey probes twice.
- t67 (accept) depends on Task 1 landing first; the task order enforces this.
