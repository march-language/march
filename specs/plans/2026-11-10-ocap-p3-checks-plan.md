# Object capabilities, phase 3: compile-time checks in every mode. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every compile-time capability check `march --compile` runs today (the module
`needs` ceiling, function `needs` bounds, `main`'s grant, path scopes, host/method/path
scopes on `IO.NetConnect`) gives the same verdict, with the same diagnostic, under
`march --check`, `--check-json`, `--emit-core-ast`, `march check` (forge's entry), the
interpreter (`march file.march`, `march test`, `--jit`), the REPL and the LSP.

**Architecture:** The two checks that exist only on the compile path run on lowered TIR
(`Cap_attrib` + `Cap_ceiling` on pre-opt TIR; `Net_scope.check` on post-lower TIR). Rather
than re-implement them on the AST (the 2026-08-17 subset took four review rounds to get
*approximately* right, see `specs/progress/2026-08-17-cap-ceiling-under-check-landed.md`),
lift them out of `bin/main.ml` into one library module, `March_driver.Cap_static`, that
lowers on demand, the way `Contract_pipeline.check_contracts` already does for `no_alloc`.
Every mode calls it; the compile path calls its TIR-level entry points on the TIR it already
has, so compiled output is byte-identical. The typecheck-side subset ceiling stays as the
cheap first pass in every non-compile mode (it rejects before lowering is paid for). A
parity test runs one fixture set through every mode and fails on any disagreement; every
static `cap_*` code must be classified in it, which is how the narrow-capability scopes
(designed, not yet built) join when they land.

**Tech Stack:** OCaml 5.5.1, dune, alcotest; March stdlib; `scripts/types-oracle.sh`,
`scripts/ir-oracle.sh`, `scripts/oracle-base.sh`.

**Spec:** `specs/2026-11-10-object-capability-design.md` §4, §15, §17 (phase 3), §20, §21;
the superseded `specs/2026-11-09-dependency-grants-and-restrict-design.md` ("Every way of
running a program", "Caches"); today's behaviour in `specs/lang/capabilities.md`.

## Where things stand (measured 2026-11-10 on this branch, `aeac8a566`)

Probe programs (one violation each) run under each mode, private `HOME`, fresh cwd:

| Check (code) | `--check` | `--check-json` | `march check` | interp / `--jit` | REPL | `--compile` (native, JS) |
|---|---|---|---|---|---|---|
| body-scan `needs` (`cap_needs`) | yes | yes | yes | yes | yes | yes |
| module ceiling, stdlib-mediated (`cap_ceiling`) | subset (typecheck side) | subset | **no** | **no** | **no** | yes (TIR, complete) |
| function `needs` bound (`cap_bound*`) | yes | yes | yes | yes | **no** | yes |
| `main`'s grant (`cap_grant`, `cap_grant_exceeded`) | yes | yes | yes | yes | n/a (§21: full authority) | yes |
| path scope, literal path (`cap_scope_violation`) | yes | yes | yes | yes | not probed | yes |
| host/method/path scope (`cap_host_*`) | **no** | **no** | **no** | **no** | **no** | yes |
| narrow-capability scopes | not implemented anywhere (design approved 2026-11-09) |

Why: `cap_strict_ceiling` is set only for `--check`/`--check-json`/`--emit-core-ast`
(`bin/main.ml:4469`); `run_check_cmd` (`bin/main.ml:7771`), the LSP and the REPL never set it.
`check_main_grant`/`check_fn_bounds` run at the end of `check_module_full`
(`lib/typecheck/typecheck.ml:12286-12287`), which the REPL's per-declaration `check_decl`
never reaches. The TIR ceiling (`bin/main.ml:5266-5484`, a `before_opt` hook) and
`Net_scope.check` (`bin/main.ml:4908-5041`) are inline in the `compile_mode` branch.
`--check-json` exits at `bin/main.ml:4688`, before any TIR-stage diagnostic.

Cost of lowering on demand: on `bench/json_stream.march` (6,083 TIR functions with the
stdlib) lowering took ~1.0 s and reaching pre-opt ~1.6 s more than typecheck alone, at load
average 40-60 (re-measure quietly). An interpreted hello-world is ~2-3 s wall today.

Caches that can skip a check: the compile CAS key and the `--check` CAS key
(`bin/main.ml:4056`) both include the compiler identity, and `--check` caches only
diagnostic-free runs, so new checks are never skipped by them; the `~/.cache/march`
stdlib type-environment caches (`bin/main.ml:360`, `lib/repl/repl.ml:219`) are keyed on the
compiler build and hold no per-program verdict. forge's `check_all_cache_key`
(`forge/lib/cmd_build.ml:552`) is the one that does not key the compiler (Task 5). The
interpreter has no verdict cache today; Task 4 adds one.

Pre-existing gaps found while probing (not this phase's, filed in Task 1): an `impl` method
in a nested module is not charged to that module by either ceiling (accepted even by
`--compile`); a path scope on a nested module is not checked when the parent declares the
capability unscoped; a function of a module declared at the REPL fails to call under the JIT
(`Unknown_callee`); `--check-json` never prints `no_alloc` contract diagnostics.

## Global Constraints

- "The compile-time checks run under `march --check`, the interpreter and the REPL, not only
  `--compile`." (§15)
- Anti-goal: "A program restricted differently depending on how it runs (compiled,
  interpreter, REPL, JIT, JS)." (§2)
- "A module's `needs` limits the module's own operations only" and "A function's `needs`
  clause stays transitive"; "The compile-time checks are today's ceiling and
  per-function-bound checks." (§4) This phase moves checks; it changes no rule.
- The REPL "runs with the full authority of the person at the terminal" (§21): no grant
  check at the prompt; module ceilings, function bounds and scopes do apply.
- Out of scope: retiring the untraceable-call refusal under a narrow function bound (§4,
  §14) needs phase 4's run-time capture to stay sound; run-time guards (the
  `Net_scope.rewrite` redirect twins) in the interpreter are phase 4.
- Caches: nothing that can skip a check may survive a compiler change or a change to any
  checked source (§10's rule, applied now to the compiler identity; phase 6 adds grants).
- `--compile` output (IR and diagnostics) is unchanged: `scripts/oracle-base.sh ir` green.
- A lowering failure in a non-compile mode never rejects a program the mode can run: it is
  a warning `cap_unchecked` naming the reason, and the typecheck-side checks still apply.
- Repo rules: `dune build --root .`; `scripts/run-tests.sh`; stage by explicit path, never
  `git add -A`/`.`; never bare `git stash`; no attribution lines in commits; each commit
  updates `specs/todos/`/`specs/progress/`; user-visible changes get a `CHANGELOG.md`
  `[Unreleased]` bullet; edit `specs/lang/capabilities.md` and run
  `scripts/gen-lang-docs.py`, never `docs/`. No parser or lexer change (no tree-sitter work).

## Review Focus

1. **An interpreter-only program that cannot lower** (supervisor DSL; anything
   `Lower.lower_module` rejects with `Diagnostic_exn`/`Failure`) must still run, with one
   `cap_unchecked` warning, not exit 1 or crash. Test in Task 4.
2. **A warm cache from an older compiler** (`.forge/check-cache/*.clean`, the `--check`
   CAS entry, the new interpreter verdict entry) must not skip a check the new compiler
   adds. Today `check_all_cache_key` (`forge/lib/cmd_build.ml:552`) hashes only sources and
   `MARCH_LIB_PATH`, so a compiler upgrade keeps every `.clean` marker. Tests in Tasks 4, 5.
3. **A violation in a `MARCH_LIB_PATH` dependency module** (another file; its module span is
   not in the entry file's tree) renders without a fix and without reading the wrong file,
   in every mode, as the compile path does today. Fixture in Task 1.
4. **The same violation reported twice** (subset ceiling and TIR ceiling; LSP sync and
   background passes). The subset's errors reject before lowering, so TIR runs only on a
   front-end-clean program; the LSP merges by (code, span). Tests in Tasks 3, 7.
5. **Interpreter start-up cost on an unchanged program**: a repeat `march file.march` must
   not pay lowering again. Measured and bounded in Task 4.

---

## File structure

- Create `lib/driver/cap_static.ml`, `lib/driver/cap_static.mli`: the TIR-side capability
  checks and the on-demand lowering. Moves `cap_ceiling_module_spans`,
  `cap_ceiling_fix_indent`, `user_fn_names_of`, `tir_fn_stem`, `is_user_tir_fn`,
  `stdlib_module_names` and the two check blocks out of `bin/main.ml`.
- Modify `lib/driver/dune` (add `march_caps`), `bin/dune`, `lsp/lib/dune`, `lib/repl/dune`
  (add `march_driver`).
- Modify `lib/tir/contract_pipeline.ml`: `run_to_pre_opt`.
- Modify `bin/main.ml` (compile, check, check-json, emit-core-ast, interp/JIT, `march check`
  arms), `lib/repl/repl.ml`, `lsp/lib/analysis.ml`, `forge/lib/cmd_build.ml`,
  `lib/errors/code.ml` (+ explain page) for `cap_unchecked`.
- Create `test/test_cap_mode_parity.ml`, `test/cap_parity/*.march`,
  `test/cap_parity/known-gaps.txt`; register in `test/test_compiler.ml` next to
  `cap_ceiling` (line ~18448).
- New `test/errors/` cases via `scripts/seed-error-corpus.sh`.

---

### Task 1: Mode-parity harness that pins today's matrix

**Files:**
- Create: `test/test_cap_mode_parity.ml`, `test/cap_parity/` fixtures, `test/cap_parity/known-gaps.txt`
- Modify: `test/test_compiler.ml` (register `("cap_mode_parity", Test_cap_mode_parity.tests)`), `test/dune` (the `(modules ...)` list at line 14), `scripts/test-affected.sh`/`scripts/affected.sh` rule if a new directory needs one
- Create: four `specs/todos/2026-11-10-*.md` for the pre-existing gaps above

**Interfaces:**
- Produces: `Test_cap_mode_parity.modes : (string * (string -> int * string)) list`, one
  runner per mode: `compile`, `check`, `check_json`, `emit_core_ast`, `march_check`,
  `interp`, `jit`, `repl`. Each takes a fixture path, runs `_build/default/bin/main.exe`
  under a private `HOME` and a fresh cwd, stdin `/dev/null` (REPL: the fixture's body piped
  in, then `:quit`), and returns (exit code, combined output).
- Produces: `codes_of : string -> string list`, the sorted unique `[cap_*]` codes in text
  output, or `"code":"cap_*"` in JSON.
- Produces: fixture header `-- EXPECT-CAP: <code>` (or `-- EXPECT-CAP: none` for an accept
  twin) and optional `-- MODES: <mode,...>` when a mode does not apply (REPL for a `main`
  grant fixture, per §21).

- [ ] **Step 1: Write fixtures**, one reject and one accept twin each: `ceiling_stdlib`
  (Dep needs `IO.Console`, calls `File.read`), `ceiling_compile_only` (a reject fixture from
  `test/test_cap_ceiling.ml` that today's `--check` accepts: find it by running each of that
  file's reject programs under `--check` and keeping one that exits 0), `fn_bound`
  (`needs ()` over `println`), `main_grant` (`test/errors/cap_grant_exceeded_1.march`'s
  shape), `path_scope` (top-level `needs IO.FileRead("/srv/data/")`, reads `/etc/hostname`),
  `host_scope` (A `needs IO.NetConnect("example.com")`, `HttpTransport.simple_get("http://evil.test/" ++ q)`),
  `host_unproven` (URL from a parameter), `dep_module` (violation in a module loaded from
  `MARCH_LIB_PATH`; the runner sets it to `test/cap_parity/lib`).
- [ ] **Step 2: Write the test.** For each fixture and each applicable mode:
  `codes_of out` = the fixture's EXPECT-CAP set and `rc` = 1 for a reject, 0 for an accept
  (interp/jit accept fixtures must not need the network: use a host that fails fast and
  print the `Err`; the `host_scope` accept twin scopes and calls `127.0.0.1:9`, which refuses at once), unless `(fixture, mode)` is listed in `known-gaps.txt`. A listed pair
  that now agrees is a failure too ("remove it from known-gaps.txt"), so the file can only
  shrink. Second test: every code in `March_errors.Code` that starts with `cap_` is either
  the EXPECT-CAP of some fixture or listed in `not_static` in the test with a one-line reason
  (`cap_deserialize`, `cap_dict_*`, ...).
- [ ] **Step 3: Fill `known-gaps.txt` from the run** (it should match the table above: the
  ceiling under `march_check`/`interp`/`jit`/`repl`, `ceiling_compile_only` under `check`,
  `check_json`, `emit_core_ast`, fn bounds under `repl`, all host-scope fixtures outside
  `compile`). Run: `scripts/run-tests.sh compiler` (or
  `./_build/default/test/run_compiler.exe test cap_mode_parity`). Expected: PASS.
- [ ] **Step 4: Prove the harness goes RED**: delete one line from `known-gaps.txt`, run,
  expect FAIL naming that pair; restore.
- [ ] **Step 5: File the four todos** (nested-module impl not charged by the ceiling; nested
  path scope masked by an unscoped parent; REPL module call `Unknown_callee` under the JIT;
  `--check-json` omits contract diagnostics), each with its probe program.
- [ ] **Step 6: Commit**: `test: capability check mode-parity harness pinning today's gaps`.

### Task 2: Lift the TIR checks into `March_driver.Cap_static`; compile path unchanged

**Files:**
- Create: `lib/driver/cap_static.ml`, `lib/driver/cap_static.mli`
- Modify: `lib/driver/dune`, `bin/dune`, `bin/main.ml:4908-5041`, `bin/main.ml:5266-5484`,
  `lib/tir/contract_pipeline.ml`
- Test: `test/test_cap_ceiling.ml`, `test/test_cap_net_scope.ml` (existing, unchanged)

**Interfaces:**
- Produces:
  ```ocaml
  type input = {
    desugared : March_ast.Ast.module_;          (* whole program, stdlib prepended *)
    stdlib_decls : March_ast.Ast.decl list;
    tc_env : March_typecheck.Typecheck.env;
    type_map : (March_ast.Ast.span, March_typecheck.Typecheck.ty) Hashtbl.t;
    src : string; filename : string; read_file : string -> string;
    cap_strict : bool;                          (* false under --no-cap-strict: no ceiling *)
  }
  type finding =
    | Diag of March_errors.Errors.diagnostic
    | Bare of string        (* today's file-less "-- CAPABILITY --" block, kept verbatim *)
  val host_scope_findings : input -> March_tir.Tir.tir_module -> finding list  (* post-lower TIR *)
  val ceiling_findings : input -> pre_opt:March_tir.Tir.tir_module -> finding list
  val cap_attribution : input -> pre_opt:March_tir.Tir.tir_module -> (string * string) list
  type outcome = Checked of finding list | Unchecked of string  (* one-line reason *)
  val check_program : input -> outcome   (* lowers, runs to pre-opt, both checks *)
  ```
- Produces: `Contract_pipeline.run_to_pre_opt : ?iface_methods:_ -> Tir.tir_module -> Tir.tir_module`,
  the same passes `run` applies before its `before_opt` hook, no opt and no later pass.

- [ ] **Step 1: Baseline the oracle** before touching code:
  `scripts/oracle-base.sh ir` (records merge-base; expect green on the unmodified tree).
- [ ] **Step 2: Move the code.** `host_scope_findings` is `bin/main.ml:4916-5037` minus the
  printing and `exit`; `ceiling_findings` is `5328-5470` likewise; `cap_attribution` is the
  `Cap_attrib.attribute` call at `5275-5326`. The compile arm keeps its rendering, summary
  lines (`"%d host-scope violation(s)."`, `"%d capability ceiling violation(s). ..."`) and
  `exit 1`, and keeps calling `Net_scope.rewrite` itself. `check_program` lowers with
  `Lower.lower_module ~type_map`, catches what `Contract_pipeline.check_contracts` catches
  (`Diagnostic_exn`, `Failure`, other non-fatal exceptions; re-raise `Out_of_memory`,
  `Stack_overflow`), runs `host_scope_findings` on the post-lower TIR (only when
  `declared_net_scopes` has a non-empty scope, as now), then `run_to_pre_opt` and
  `ceiling_findings` (only when `input.cap_strict`).
- [ ] **Step 3: Unit test `check_program`** in `test/test_cap_ceiling.ml`:
  `test_check_program_matches_compile`: for `ceiling_stdlib` and `host_scope`,
  `check_program` returns `Checked` with exactly the codes `--compile` prints;
  `test_check_program_unchecked`: a program whose lowering raises returns `Unchecked _`.
- [ ] **Step 4: Verify the compile path moved nothing.**
  Run: `scripts/run-tests.sh compiler codegen` → PASS; `scripts/oracle-base.sh ir` → green;
  perturb (temporarily make `ceiling_findings` drop its first finding), confirm
  `test_cap_ceiling` goes RED, revert. Parity test unchanged.
- [ ] **Step 5: Commit**: `refactor(caps): lift TIR capability checks into Cap_static`.

### Task 3: `--check`, `--check-json` and `--emit-core-ast` run the full checks

**Files:**
- Modify: `bin/main.ml` (`contract_diags` at ~4697, `check_json` arm at ~4682, `do_check` arm
  at ~4833, `Emit_core_ast.run` call at ~4729), `lib/errors/code.ml` (`cap_unchecked`,
  warning), its explain page
- Test: `test/cap_parity/known-gaps.txt`, `test/errors/` (new cases), `test/test_check_cas_cap_strict.ml`

**Interfaces:**
- Consumes: `Cap_static.check_program`, `finding`.
- Produces: `cap_diags : March_errors.Errors.diagnostic list Lazy.t` in `bin/main.ml`, forced
  only on a front-end-clean program; `Bare` findings rendered as on the compile path;
  `Unchecked why` → one `cap_unchecked` warning at the entry module's name span:
  "The capability ceiling and host scopes were not checked: <why>. `march --compile` checks
  them."

- [ ] **Step 1: Seed error-corpus cases**: `cap_host_scope_1`, `cap_host_unproven_1`,
  `cap_ceiling_6` (the `ceiling_compile_only` fixture) with `scripts/seed-error-corpus.sh`;
  run `ERRORS_ONLY=cap_host,cap_ceiling_6 ./_build/default/test/run_errors.exe -e`.
  Expected: FAIL (today `--check` exits 0 on them).
- [ ] **Step 2: Implement.** `--check`: force `cap_diags` after `contract_diags`, print,
  `exit 1` on any error; they count as printed diagnostics for the check-CAS rule (only
  diagnostic-free runs are cached). `--check-json`: when no user error, append `cap_diags`
  (fixes verified by `Fix_verify.verify` like the rest). `--emit-core-ast`: fold into
  `~diags` and `~rejected`. Keep `cap_strict_ceiling` on in these modes (its errors reject
  before lowering, so nothing is reported twice).
- [ ] **Step 3: Regenerate and review**: `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e`,
  `git diff test/errors/`: only the three new cases change; each `.expected` shows the same
  message the compile path prints. Remove the `check`, `check_json`, `emit_core_ast` lines
  from `known-gaps.txt`. Run `scripts/run-tests.sh errors compiler` → PASS.
- [ ] **Step 4: Cache test** in `test/test_check_cas_cap_strict.ml` (it already pins the `capstrict` key):
  `test_check_cache_does_not_mask_host_scope`: in one fresh cwd, `--check` the accept twin
  (cached clean), then the reject file with identical bytes except the URL, expect rc 1; and
  run the reject file twice, rc 1 both times.
- [ ] **Step 5: Types oracle.** `scripts/oracle-base.sh types`. Expected: the only changed
  fixtures are ones with a scoped `needs IO.NetConnect(...)` or a ceiling violation the
  subset missed; list each in the commit message. Prove RED: none needed beyond the diff
  itself (it is the perturbation); if the diff is empty, the oracle missed the change:
  stop and find out why.
- [ ] **Step 6: Commit** with `specs/lang/capabilities.md` edits for these modes (§"What this
  does and does not guarantee", host scopes §"Limits") deferred to Task 8.
  `feat(caps): --check runs the full ceiling and host scopes`.

### Task 4: The interpreter, `march test` and `--jit` run the checks

**Files:**
- Modify: `bin/main.ml` (`cap_strict_ceiling` at 4469: also on when `interpreting` or
  `--jit`; the final interpret/JIT arm, after `frontend_rejected`), `lib/cas/` only if a
  helper is needed
- Test: `test/test_cap_ceiling.ml`, `known-gaps.txt`

**Interfaces:**
- Consumes: `Cap_static.check_program`.
- Produces: an interpreter verdict entry in the project CAS:
  `Cas.compilation_hash src_hash ~target:"capcheck" ~flags` with the same `flags` list the
  `--check` key uses (`bin/main.ml:4056`), registered through `register_depend_store` so a
  `MARCH_LIB_PATH` dependency's content is in it; stored only for `Checked []`; a hit skips
  lowering.

- [ ] **Step 1: Failing tests**: `test_interp_rejects_ceiling` (rc 1, `[cap_ceiling]`, the
  program's output absent), `test_interp_runs_unlowerable_program` (an interpreter-only
  program, e.g. the supervisor DSL fixture `Lower` rejects: rc 0, its output present, one
  `cap_unchecked` warning), `test_interp_verdict_cache_tracks_dependency` (clean run, edit
  the `MARCH_LIB_PATH` dependency to violate, rerun: rc 1). Run them: FAIL.
- [ ] **Step 2: Implement**: in interpreted and JIT runs, after the front end and before
  `run_module`/the JIT, look up the verdict entry; on a miss run `check_program`, print
  findings as `--check` does, `exit 1` on an error, store on `Checked []`. `march test`
  goes through the same arm (`do_test`); confirm with a test file containing a violation.
- [ ] **Step 3: Measure**: hello-world (`mod H do needs IO.Console ... end`) and
  `bench/json_stream.march` interpreted, five runs each, cold and warm CAS, before and after,
  on a quiet machine (load < 4). Record in the progress note. Budget: warm-cache runs within
  noise of today; cold runs within 1.5 s of today. If cold exceeds the budget, report the
  numbers instead of tuning in this task (owner question 1).
- [ ] **Step 4**: remove `interp`/`jit` lines from `known-gaps.txt`;
  `scripts/run-tests.sh compiler stdlib eval` → PASS.
- [ ] **Step 5: Commit**: `feat(caps): the interpreter and --jit run the capability checks`.

### Task 5: `march check`, and forge's check cache

**Files:**
- Modify: `bin/main.ml` `run_check_cmd` (7771), `forge/lib/cmd_build.ml:552`
  (`check_all_cache_key`)
- Test: `forge/test/test_build_check.ml`, `known-gaps.txt`

**Interfaces:**
- Produces: `check_all_cache_key ~lib_path_env ~compiler_id files`, where `compiler_id` is
  the `march` binary's identity (its digest, or `march --version` output plus its mtime if
  forge cannot digest it cheaply: builder's call, but it must change when the compiler is
  rebuilt).

- [ ] **Step 1: Failing tests**: `march check` on `ceiling_stdlib` and `host_scope` → rc 1;
  forge: a `.clean` marker written under one `compiler_id` is not honoured under another.
- [ ] **Step 2: Implement**: `run_check_cmd` sets `cap_strict_ceiling` (respecting
  `--no-cap-strict`) and, when its combined check is clean, runs `check_program` on the
  combined module (it already builds one, `bin/main.ml:~7906`) unless `emit_caps` mode;
  forge passes the identity into the key.
- [ ] **Step 3**: remove `march_check` lines; `scripts/run-tests.sh compiler` and the forge
  suite → PASS.
- [ ] **Step 4: Commit**: `feat(caps): march check runs the full checks; forge check cache keys the compiler`.

### Task 6: The REPL runs function bounds, the ceiling and scopes

**Files:**
- Modify: `lib/repl/repl.ml` (each `check_decl` site: 148, 426, 896, 908, 1306, 1483, 1493,
  2103 — factor one `check_decl_caps` helper), `lib/repl/dune`,
  `lib/typecheck/typecheck.ml`/`.mli` (expose a REPL entry if `check_fn_bounds` and
  `fn_capability_rows_tbl` are not exported)
- Test: a new `test/test_repl_caps.ml` beside `test/test_repl_cache.ml` (add it to `test/dune`'s `(modules ...)` and `test/test_compiler.ml`), `known-gaps.txt`

**Interfaces:**
- Produces: `Typecheck.check_repl_decl_caps : env -> Ast.decl -> unit`, running
  `check_fn_bounds` over the bound points the declaration added and, for a `DMod`, the
  subset ceiling for that module; never `check_main_grant` (§21).
- Consumes: `Cap_static.check_program` on a synthetic module = stdlib decls + every user
  declaration accepted so far in the session + the new one, run only when the new
  declaration is a `DMod` (a REPL top-level function has no module `needs` to exceed and no
  scope).

- [ ] **Step 1: Failing tests**: at the prompt, `mod Q do needs IO.Console fn f(s : String) : Unit needs () do println(s) end end`
  → a `[cap_bound]` error and `Q` is not added to the session; the same with a host-scope
  violation → `[cap_host_scope]`; with a stdlib-mediated ceiling violation → `[cap_ceiling]`;
  a clean `mod` is accepted and the next input sees it.
- [ ] **Step 2: Implement**: a declaration with a capability error is rejected like a type
  error (the session env is not updated). Lowering failure → `cap_unchecked` warning, the
  declaration is accepted.
- [ ] **Step 3: Measure** one `mod` declaration's added latency at the prompt (quiet machine);
  record it. If above 2 s, report (owner question 1).
- [ ] **Step 4**: remove `repl` lines; run the REPL suites and `scripts/run-tests.sh test_jit`
  → PASS.
- [ ] **Step 5: Commit**: `feat(caps): the REPL checks function bounds, ceilings and scopes`.

### Task 7: The LSP surfaces the checks

**Files:**
- Modify: `lsp/lib/analysis.ml` (sync analysis: set `cap_strict_ceiling` around its
  typecheck; `run_tir_pass` at 3445: add `Cap_static` findings from its own lowering, which
  it already does at ~3496), `lsp/lib/dune`
- Test: `lsp/test/test_lsp_analysis.ml` or `test_lsp_features.ml`

**Interfaces:**
- Consumes: `Cap_static.host_scope_findings` on the post-lower TIR `run_tir_pass` builds and
  `ceiling_findings` on `pipe.Contract_pipeline.pre_opt`; `Bare` findings are dropped (no
  span to publish).

- [ ] **Step 1: Failing tests**: `analyse` of `ceiling_stdlib` has a `cap_ceiling`
  diagnostic; `run_tir_pass` of `host_scope` has `cap_host_scope`; `run_tir_pass` of
  `ceiling_stdlib` does not publish `cap_ceiling` twice (merge by code and span).
- [ ] **Step 2: Implement**; the ceiling's `needs` fix is a code action like every other
  `FInsert`.
- [ ] **Step 3**: `scripts/run-tests.sh lsp jsonrpc` → PASS (from the repo root).
- [ ] **Step 4: Commit**: `feat(lsp): publish capability ceiling and host-scope diagnostics`.

### Task 8: Regression sweep, docs, and closing the phase

**Files:**
- Modify: `specs/lang/capabilities.md` (then `scripts/gen-lang-docs.py`), `CHANGELOG.md`,
  `specs/todos/2026-11-09-host-scope-phase-2.md` (drop "Under `--check` and the
  interpreter"), `specs/todos/2026-08-04-cap-ceiling-follow-ups.md` if it lists the same
  gap, programs the sweep finds
- Create: `specs/progress/2026-11-10-ocap-p3-checks.md`
- Delete: `test/cap_parity/known-gaps.txt` (empty by now) and its handling in the test

- [ ] **Step 1: Sweep** with the base compiler and this one: `--check` and interpreted runs
  (stdin `/dev/null`, 30 s cap, network-free where possible) over `examples/`,
  `test/stdlib/*.march`, `test/native/*.march`, `bench/*.march`, `specs/lang/types/accept/`,
  and the `code` blocks doctests extract from `stdlib/`. List every program whose verdict
  changes. Each is either a true violation (fix the program: add the `needs` line, or the
  scope) or a bug in this phase (stop and fix it). The stdlib's own modules are transparent
  to the ceiling and must not change; any that does is a bug.
- [ ] **Step 2: Docs.** `specs/lang/capabilities.md`: the "What this does and does not
  guarantee" bullets and the host-scope "Limits" paragraph now say every mode runs the
  checks, with `cap_unchecked` as the one exception; regenerate `docs/`. `CHANGELOG.md`
  `### Changed`: "`march --check`, `march check`, the interpreter, the REPL and the editor
  now run the full capability ceiling and host-scope checks, so a program they accepted can
  now be rejected the way `--compile` rejected it."
- [ ] **Step 3: Full verification**: `scripts/run-tests.sh` (full), `scripts/oracle-base.sh ir`
  (green: compile path unchanged), `scripts/oracle-base.sh types` (only the Task 3 diff),
  `scripts/check-docs.sh`. Parity test: no known gaps left.
- [ ] **Step 4: Commit** with the progress note (matrix before/after, timings, the sweep's
  list): `docs(caps): capability checks run in every mode (ocap phase 3)`.

---

## Questions for the owner

1. **Cost.** Lowering on demand adds about 1-1.6 s (measured under load) to a cold `--check`,
   interpreted run or REPL `mod` declaration of a real program; warm interpreted runs are
   cached. Acceptable, or must a sound skip (no lowering when the cheap checks prove
   nothing can fail) come first?
2. **Programs the compiler cannot lower** (interpreter-only features): this plan runs them
   with a `cap_unchecked` warning, which is a mode difference the anti-goal forbids in
   spirit. The strict alternative is to refuse them outside `--compile`-capable features.
   Which?
3. **Pre-existing gaps** (nested `impl` methods uncharged even by `--compile`; nested path
   scope masked by an unscoped parent): this plan files them as todos. Fixing them in
   phase 3 would newly reject programs in every mode, `--compile` included. Pull them in?
