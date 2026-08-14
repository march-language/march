# Capability UX Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make March's capability system the friendliest of any language by fixing the broken on-ramp (a scaffolded project that does not build, an auto-fix that can never fire), removing the one rule that forces capability threading, and quieting the diagnostics that fire on correct code.

**Architecture:** Capabilities stay **module-scoped**. `needs` is the manifest, the module ceiling enforces it, and `main`'s parameter is the whole-program grant. The one mechanism that pushed toward per-call-site threading — the per-function grant ceiling (R1 stage C, `check_fn_grants`) — is removed, because a `Cap(X)` parameter on a non-`main` function should be an authority marker at a module boundary, not an obligation to enumerate every capability the function transitively reaches. Everything else in this plan is diagnostic quality and tooling.

**Tech Stack:** OCaml 5.3.0, dune, menhir/ocamllex, alcotest. Compiler in `lib/`, build tool in `forge/`.

## Global Constraints

- Capabilities remain module-scoped. **No task may introduce a rule that requires passing a capability value to satisfy a check.** Adding a parameter must never be the only way to fix a capability diagnostic on a non-`main` function.
- Build with `dune build --root . bin/main.exe` and `dune build --root . forge/bin/main.exe`. Never use `eval $(opam env)`.
- Test with `scripts/run-tests.sh` (full, ~17s) or `scripts/run-tests.sh -q compiler` for the fast loop. Judge by `$?`, never by tail output, and never measure an exit code through a pipe.
- **Every task in this plan changes diagnostic text, so every task MUST run `dune build --root . @types-check` and check `$?` directly.** This is not covered by `scripts/run-tests.sh` (alcotest executables only) or by `scripts/check-docs.sh` (its count check passes vacuously when no files are added or removed). The type-conformance corpus under `specs/lang/types/{accept,reject}/` asserts diagnostic *text* via `EXPECT-ERROR` markers, so rewording or removing a diagnostic silently breaks it and only CI notices. Discovered the hard way in Task 3, where deleting a check left `reject/t174_fn_grant_violated_by_helper.march` expecting a message that no longer exists. When a corpus file must be deleted, its `specs/lang/types/INDEX.md` row **and** the two counts (`INDEX.md:242`, and the reject count near `:570`) must move in the same commit, or `check-docs.sh` Check C fails.
- Every task updates `CHANGELOG.md` under `## [Unreleased]` and files/moves the matching `specs/todos/` → `specs/progress/` entry **in the same commit** (see `CLAUDE.md`).
- Stage files explicitly by name. Never `git add -A`, `git add .`, or `git commit -am`.
- Doc edits to the language reference must be applied to **both** `specs/lang/capabilities.md` and the drifted copy under `docs/` if one exists for the same page (see `project_lang_reference_consolidated`). Run `scripts/check-docs.sh` before committing doc changes.
- When testing `forge` against a locally built compiler, the installed `~/.opam/march/bin/march` will shadow it. Use a shim: a `march` shell script on `PATH` that `exec`s the absolute path of `_build/default/bin/main.exe`, plus `MARCH_HOME=<empty dir>`. A bare symlink does **not** work — the compiler resolves its stdlib relative to the invoked path.

---

## File Structure

| File | Responsibility | Tasks |
|---|---|---|
| `forge/lib/cmd_fix.ml` | Collect + apply compiler auto-fixes | 1 |
| `forge/lib/scaffold.ml` | `forge new` project templates | 2 |
| `lib/typecheck/typecheck.ml` | All capability checks and diagnostics | 3, 4, 5, 6, 8 |
| `lib/caps/cap_lattice.ml` | Closed capability hierarchy; add name validation helper | 4 |
| `bin/main.ml` | Ceiling reporting, `--check` wiring | 7 |
| `test/test_compiler.ml` | Alcotest suite for all compiler-side behavior | 3–8 |
| `forge/test/test_cap_sandbox.ml` | forge-side cap tests | 1, 2 |

---

### Task 1: Make `forge fix` able to apply capability fixes

**Why:** Both capability errors print ``  `forge fix` can apply this. `` It never can. `collect_all_fixes` sets `has_errors` and `run` refuses. The condition is also *inverted*: `parse_fix_line` returns `None` for any diagnostic without a `fix`, so a diagnostic can only set `has_errors` if it **has** a machine-applicable fix. `forge fix` refuses precisely when it has safe work to do. An unfixable error does not block it at all.

**Files:**
- Modify: `forge/lib/cmd_fix.ml:49-68` (`collect_all_fixes`), `forge/lib/cmd_fix.ml:196-198` (the gate)
- Modify: `lib/typecheck/typecheck.ml:13176` (add a `code` to the grant error)
- Test: `forge/test/test_cap_sandbox.ml`

**Interfaces:**
- Consumes: `march --check-json` line format, already emitting `{"severity","file","message","code","fix"}`. Confirmed codes: `cap_needs:<Cap>` on missing-`needs` errors, `null` on the grant error, `unused_binding` on unused params.
- Produces: `code` = `"cap_grant"` on the missing-grant error. `collect_all_fixes : lib_path_env:string -> string list -> fix_item list` (the `bool` is dropped from the return type).

- [ ] **Step 1: Write the failing test**

Add to `forge/test/test_cap_sandbox.ml`:

```ocaml
let test_forge_fix_applies_capability_errors () =
  (* A capability-incorrect module must be repaired by `forge fix`, not
     refused.  Both fixes are error-severity: the missing grant on `main`
     and the missing `needs` line. *)
  let dir = Filename.concat (Filename.get_temp_dir_name ()) "forge_fix_caps" in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  ignore (Sys.command (Printf.sprintf "mkdir -p %s/lib" (Filename.quote dir)));
  let src = Filename.concat dir "lib/ffc.march" in
  let oc = open_out src in
  output_string oc "mod Ffc do\n  fn main() do\n    println(\"hi\")\n  end\nend\n";
  close_out oc;
  let toml = open_out (Filename.concat dir "forge.toml") in
  output_string toml "[package]\nname = \"ffc\"\nversion = \"0.1.0\"\ntype = \"app\"\n\n[deps]\n";
  close_out toml;
  let rc = Sys.command (Printf.sprintf "cd %s && forge fix > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "forge fix succeeds on capability errors" 0 rc;
  let ic = open_in src in
  let n = in_channel_length ic in
  let content = really_input_string ic n in
  close_in ic;
  Alcotest.(check bool) "needs line inserted" true
    (Astring.String.is_infix ~affix:"needs IO.Console" content);
  Alcotest.(check bool) "grant parameter inserted" true
    (Astring.String.is_infix ~affix:"Cap(IO.Console)" content)
```

Register it in the suite list at the bottom of the file:

```ocaml
  "forge fix applies capability errors", `Quick, test_forge_fix_applies_capability_errors;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dune build --root . forge/test/test_cap_sandbox.exe && ./_build/default/forge/test/test_cap_sandbox.exe -e
```

Expected: FAIL — `forge fix succeeds on capability errors` gets `1`, and the file is unchanged.

- [ ] **Step 3: Add a `code` to the grant diagnostic**

In `lib/typecheck/typecheck.ml`, the grant error at ~line 13176 calls `Err.error_with_fix`. Switch it to the code-carrying variant so tooling can identify it, matching how the `needs` error already emits `cap_needs:<Cap>`:

`Err.error_with_fix` already takes an optional `?code` (`lib/errors/errors.ml:73` — `error_with_fix ctx ~span ?code ~fix message`), so no new function is needed. Pass it:

```ocaml
         Err.error_with_fix env.errors ~span ~code:"cap_grant"
           ~fix:(Err.FReplace
                   { span = params_span; text = Printf.sprintf "(%s)" suggested })
```

- [ ] **Step 4: Remove the inverted gate**

In `forge/lib/cmd_fix.ml`, drop the `has_errors` tracking entirely:

```ocaml
let collect_all_fixes ~lib_path_env files : fix_item list =
  let all_items = ref [] in
  List.iter (fun file ->
    let cmd = Printf.sprintf "%smarch --check-json %s 2>/dev/null"
      lib_path_env (Filename.quote file) in
    let ic = Unix.open_process_in cmd in
    (try
      while true do
        let line = input_line ic in
        (match parse_fix_line line with
         | Some fi -> all_items := fi :: !all_items
         | None -> ())
      done
    with End_of_file -> ());
    ignore (Unix.close_process_in ic)
  ) files;
  !all_items
```

and at the call site (~line 196) replace the gate with a plain binding:

```ocaml
      let items = collect_all_fixes ~lib_path_env all_files in
      begin
```

Delete the now-unmatched `if has_errors then Error "..." else` and keep the `begin ... end` body that follows. A fix is only ever emitted alongside a diagnostic the compiler produced from a successfully parsed file, so a file that fails to parse contributes no fixes and nothing is applied to it — the gate protected nothing.

- [ ] **Step 5: Run the test to verify it passes**

```bash
dune build --root . forge/bin/main.exe forge/test/test_cap_sandbox.exe && ./_build/default/forge/test/test_cap_sandbox.exe -e
```

Expected: PASS.

- [ ] **Step 6: Verify the full suite still passes**

```bash
scripts/run-tests.sh
```

Expected: exit 0. Check `$?` directly.

- [ ] **Step 7: Update docs and changelog**

Add to `CHANGELOG.md` under `## [Unreleased]` → `### Fixed`:

```markdown
- `forge fix` now applies capability fixes. It previously refused to run whenever any
  error-severity diagnostic carried a machine-applicable fix — which is exactly what the
  missing-`needs` and missing-grant errors emit, so the fix those errors advertised could
  never be applied.
```

Create `specs/progress/2026-08-13-forge-fix-refused-capability-fixes.md` describing the inverted condition and the fix.

- [ ] **Step 8: Commit**

```bash
git add forge/lib/cmd_fix.ml lib/typecheck/typecheck.ml forge/test/test_cap_sandbox.ml CHANGELOG.md specs/progress/2026-08-13-forge-fix-refused-capability-fixes.md
git commit -m "fix(forge): apply capability fixes instead of refusing on them"
```

---

### Task 2: Make `forge new` scaffold a project that builds

**Why:** `forge new x && cd x && forge build` exits 1 with two capability errors. The first command a new user runs fails, on capabilities. The `app` and `tool` templates emit `fn main() do println(...) end` — no `needs`, no grant. The generated **test** file has the same problem.

**Files:**
- Modify: `forge/lib/scaffold.ml:20-31` (`lib_source`), `forge/lib/scaffold.ml:33-35` (`test_source`)
- Test: `forge/test/test_cap_sandbox.ml`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: templates that pass `march --check` unmodified. The `Lib` template stays pure (no `needs`, no `main`) and is unchanged.

- [ ] **Step 1: Write the failing test**

Add to `forge/test/test_cap_sandbox.ml`:

```ocaml
let test_scaffolded_app_builds_clean () =
  let dir = Filename.concat (Filename.get_temp_dir_name ()) "forge_new_clean" in
  ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote dir)));
  let rc_new = Sys.command
    (Printf.sprintf "cd %s && forge new %s > /dev/null 2>&1"
       (Filename.quote (Filename.get_temp_dir_name ())) "forge_new_clean") in
  Alcotest.(check int) "forge new succeeds" 0 rc_new;
  let rc_check = Sys.command
    (Printf.sprintf "cd %s && forge check > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app checks clean" 0 rc_check;
  let rc_build = Sys.command
    (Printf.sprintf "cd %s && forge build > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app builds" 0 rc_build;
  let rc_test = Sys.command
    (Printf.sprintf "cd %s && forge test > /dev/null 2>&1" (Filename.quote dir)) in
  Alcotest.(check int) "a freshly scaffolded app's tests run" 0 rc_test
```

Register it:

```ocaml
  "scaffolded app builds clean", `Quick, test_scaffolded_app_builds_clean;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dune build --root . forge/test/test_cap_sandbox.exe && ./_build/default/forge/test/test_cap_sandbox.exe -e
```

Expected: FAIL on `a freshly scaffolded app checks clean` (gets `1`).

- [ ] **Step 3: Fix the templates**

In `forge/lib/scaffold.ml`, replace `lib_source`'s `App` and `Tool` arms and `test_source`:

```ocaml
let lib_source name = function
  | Project.App ->
    Printf.sprintf
      "mod %s do\n\n  needs IO.Console\n\n  fn main(_cap : Cap(IO.Console)) do\n    println(\"Hello from %s!\")\n  end\n\nend\n"
      (snake_to_pascal name) name
  | Project.Lib ->
    Printf.sprintf "mod %s do\n\n  fn hello(name: String) : String do\n    \"Hello, \" ++ name ++ \"!\"\n  end\n\nend\n"
      (snake_to_pascal name)
  | Project.Tool ->
    Printf.sprintf
      "mod %s do\n\n  needs IO.Console\n\n  fn main(_cap : Cap(IO.Console)) do\n    println(\"Hello from %s!\")\n  end\n\nend\n"
      (snake_to_pascal name) name

let test_source name =
  Printf.sprintf
    "mod %sTest do\n\n  needs IO.Console\n\n  fn test_placeholder() : Bool do\n    true\n  end\n\n  fn main(_cap : Cap(IO.Console)) do\n    let result = test_placeholder()\n    if result do println(\"All tests passed.\") else println(\"Tests failed.\") end\n  end\n\nend\n"
    (snake_to_pascal name)
```

The parameter is named `_cap`, not `cap`, so the unused-variable warning does not fire on generated code even before Task 6 lands.

- [ ] **Step 4: Run the test to verify it passes**

```bash
dune build --root . forge/bin/main.exe forge/test/test_cap_sandbox.exe && ./_build/default/forge/test/test_cap_sandbox.exe -e
```

Expected: PASS.

- [ ] **Step 5: Verify the templates by hand**

```bash
cd /tmp && rm -rf scaffold_check && forge new scaffold_check && cd scaffold_check && forge build && forge run
```

Expected: `Hello from scaffold_check!` and exit 0.

- [ ] **Step 6: Update docs and changelog**

Add to `CHANGELOG.md` under `## [Unreleased]` → `### Fixed`:

```markdown
- `forge new` now scaffolds capability-correct projects. The generated `app`/`tool` entry
  point and test module declared no `needs` and took no grant, so a freshly created project
  failed `forge build` with two capability errors.
```

Create `specs/progress/2026-08-13-forge-new-scaffold-not-cap-correct.md`.

- [ ] **Step 7: Commit**

```bash
git add forge/lib/scaffold.ml forge/test/test_cap_sandbox.ml CHANGELOG.md specs/progress/2026-08-13-forge-new-scaffold-not-cap-correct.md
git commit -m "fix(forge): scaffold capability-correct projects in forge new"
```

---

### Task 3: Remove the per-function grant ceiling (no capability threading)

**Why:** This is the plan's central decision. Today a `Cap(X)` parameter on **any** function becomes a ceiling on everything that function transitively reaches:

```march
fn handle(c : Cap(IO.FileWrite), name : String) : () do
  println("handling")   -- ERROR: granted Cap(IO.FileWrite), reaches IO.Console
```

The only fix is to add a second parameter, then a third, propagating up every caller. Functions that take **no** capability parameter carry no such obligation — module `needs` covers them. So the language makes explicit capability passing strictly more painful than not passing anything, and the pain grows with the call graph. Capabilities are module-scoped by design; this rule is the one place that contradicts that.

**What is deliberately given up:** a narrow `Cap` parameter on a library function stops being a per-function bound. A library never linked into a `main` is then governed by its module `needs` ceiling alone. That is the module-scoped guarantee this design intends — but it is a real reduction, so it is called out here rather than buried.

**What is kept:** `main`'s grant (`check_main_grant`), the whole-program ceiling, the per-module ceiling, Check 1 (`Cap(X)` in a signature requires `needs X`), and Check 4 (demand-driven import propagation). None of these require threading.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:13388-13473` (`check_fn_grants`), `lib/typecheck/typecheck.ml:13784` (its call site)
- Modify: `lib/typecheck/typecheck.ml:13778-13781` (the `~with_rows` computation that exists only to feed it)
- Modify: `test/test_compiler.ml:10168-10520` (the stage C block)
- Modify: `specs/lang/capabilities.md`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `check_fn_grants` is deleted. `env.fn_grant_points` remains populated (`typecheck.ml:9184`) — it is left in place because `~with_rows` and future work read it — but nothing checks it. `check_main_grant` is unchanged and remains the only grant discharge point.

- [ ] **Step 1: Write the failing test**

Add to `test/test_compiler.ml`, next to the existing stage C block:

```ocaml
let test_cap_param_does_not_force_threading () =
  (* A capability parameter marks authority at a module boundary. It does NOT
     oblige the function to enumerate every capability it reaches: that is what
     the module's `needs` and the program's grant are for. Requiring a second
     parameter here is exactly the threading the module-scoped design rejects. *)
  let ctx = typecheck {|mod NoThread do
    needs IO.Console
    needs IO.FileWrite
    fn handle(c : Cap(IO.FileWrite), msg : String) : () do
      println("handling")
      match file_write("/tmp/no_thread", msg) do
        Ok(_) -> ()
        Err(_) -> ()
      end
    end
    fn main(cap : Cap(IO)) : () do
      handle(cap_narrow(cap), "x")
    end
  end|} in
  Alcotest.(check bool)
    "a Cap parameter does not impose a per-function ceiling"
    false (has_errors ctx)

let test_main_grant_still_bounds_the_program () =
  (* Removing the per-function ceiling must not weaken the program grant. *)
  let ctx = typecheck {|mod StillBounded do
    needs IO.Console
    needs IO.FileWrite
    fn handle(c : Cap(IO.FileWrite), msg : String) : () do
      match file_write("/tmp/still_bounded", msg) do
        Ok(_) -> ()
        Err(_) -> ()
      end
    end
    fn main(cap : Cap(IO.Console)) : () do
      handle(cap_narrow(cap), "x")
    end
  end|} in
  Alcotest.(check bool) "the program grant still rejects IO.FileWrite"
    true (has_error_with ctx "granted `Cap(IO.Console)`")
```

Register both in the compiler suite list:

```ocaml
  "cap param does not force threading", `Quick, test_cap_param_does_not_force_threading;
  "main grant still bounds the program", `Quick, test_main_grant_still_bounds_the_program;
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: `cap param does not force threading` FAILS (an error is present: ``  `handle` is granted `Cap(IO.FileWrite)`, but reaches `IO.Console` ``). `main grant still bounds the program` should already PASS.

- [ ] **Step 3: Delete `check_fn_grants` and its call site**

In `lib/typecheck/typecheck.ml`, delete the whole `let check_fn_grants ?rows (env : env) : unit = ...` definition (from `let check_fn_grants` through the closing `end` before `let check_module_core`).

**Keep `cap_reach_chain`** even though this deletion makes it temporarily unused — Task 8 needs it to attribute grant violations to the user's call chain. If the build errors on an unused binding, add `let _ = cap_reach_chain` next to it with a comment pointing at Task 8, or land Task 8 first.

Keep `dump_cap_rows`; move its single call out of the deleted function into `check_module_core` right before `check_main_grant`, so `MARCH_DUMP_CAP_ROWS=1` keeps working:

```ocaml
  dump_cap_rows final_env;
  check_main_grant ~rows:cap_rows final_env m.Ast.mod_decls;
```

Then delete the call site at ~line 13784:

```ocaml
  (* R1 stage C: and each Cap-parameter function's row under its own grant. *)
  check_fn_grants ~rows:cap_rows final_env;
```

- [ ] **Step 4: Simplify the row solve**

`~with_rows` exists only because `check_fn_grants` read `deps`/`unknown`. `check_main_grant` deliberately does not consult them. Replace the block at ~13778:

```ocaml
  let cap_rows = fn_capability_rows_tbl final_env in
  dump_cap_rows final_env;
  check_main_grant ~rows:cap_rows final_env m.Ast.mod_decls;
```

- [ ] **Step 5: Retire the stage C tests**

The block at `test/test_compiler.ml:10168-10520` pins the removed behavior. For each `test_fn_grant_*` test:

- Delete the ones that assert a per-function violation is an error: `test_fn_grant_narrow_rejects_filewrite`, `test_fn_grant_violation_through_helper`, `test_fn_grant_multi_cap_params_union`, `test_fn_grant_supplier_is_charged_for_the_callback`, `test_fn_grant_refuses_untraceable_invocation`, `test_fn_grant_narrow_refuses_foreign`.
- Keep, unchanged, the ones that assert *no* error, since they must keep passing: `test_fn_grant_narrow_covers_console`, `test_fn_grant_polymorphic_cap_param_is_no_gate`, `test_fn_grant_invoking_a_parameter_still_certifies`, `test_fn_grant_full_io_accepts_untraceable_invocation`, `test_fn_grant_dead_code_is_not_charged`, `test_fn_grant_main_is_not_double_reported`.

- **Rewrite** `test_fn_grant_with_stdlib_prepended` and `test_fn_grant_with_prelude_flattened`. (Corrected 2026-08-13 during execution: an earlier draft of this plan listed these two as "keep unchanged", which was wrong — both assert a per-function grant violation is present, so neither can survive the removal untouched.) Do not delete them: they exist to guard the regression in `specs/progress/2026-08-09-cap-shadowing-false-positive.md`, where a capability fix's own unit tests passed green while shipping a regression because they used a bare parse-and-desugar helper instead of the real stdlib-prepended shape. The *shapes* are the load-bearing part. Keep each test's setup verbatim and change only the assertions: assert the per-function diagnostic is now absent (negative form, pinning the removed behavior as removed), and in the same test assert `main`'s grant still fires under that shape — otherwise the test would pass even if the capability pipeline silently stopped running under these shapes, which is the exact failure mode the incident was about. Rename to `test_module_scoped_caps_with_stdlib_prepended` / `..._with_prelude_flattened`.

- Do not trust these lists blindly. Read what each test actually asserts and let that decide; record any deviation and its reasoning in the report.

Remove each deleted test's entry from the suite list. Replace the block's header comment at line 10168 with:

```ocaml
(* ── R1 stage C: REMOVED (2026-08-13) ─────────────────────────────────────
   Per-function grants made any `Cap(X)` parameter a ceiling over everything
   the function transitively reached, so taking one capability parameter
   obliged a function to take parameters for all the others — capability
   threading, which March's module-scoped design rejects. `main`'s grant and
   the per-module ceiling remain. The tests below are the ones that assert
   NO error, kept to pin that a Cap parameter is not itself a gate. *)
```

Also check the two later references and update or delete them:

```bash
grep -n "stage C\|Stage C" test/test_compiler.ml
```

`test_compiler.ml:10603` and `:10659` mention stage C in comments; rewrite those comments to say the module ceiling covers the case.

- [ ] **Step 6: Run the tests**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS, including both new tests.

- [ ] **Step 7: Run the whole suite**

```bash
scripts/run-tests.sh
```

Expected: exit 0, checked via `$?`. If a stdlib `.march` test regresses, it is because a stdlib module relied on a per-function grant error; that cannot happen (the check only ever produced errors), so any failure here is unrelated and must be investigated before proceeding.

- [ ] **Step 8: Fix the reference**

`specs/lang/capabilities.md:465` and `:24` already claim per-function grants are "stage C and not built" — which was false while `check_fn_grants` shipped, and becomes true now. Replace the sentence at `:465`:

```markdown
The grant is `needs`' missing other half: `needs` says what a *module*
touches; the grant bounds what the *program* may. Sandbox ladder stages A/B/D
are shipped (`specs/2026-08-08-r1-no-ambient-io-design.md`). Per-function
grants (effect rows) are stage C and deliberately **not** built: making a
`Cap(X)` parameter a ceiling over everything a function reaches would force
every caller to thread capabilities it does not otherwise need, which is the
opposite of March's module-scoped design. A `Cap(X)` parameter is an authority
marker at a module boundary; the *checks* are `needs`, the module ceiling, and
`main`'s grant.
```

Update the parallel note at `:24` the same way. Apply the identical edit to the `docs/` copy of this page if one exists.

- [ ] **Step 9: Update changelog and specs**

Add to `CHANGELOG.md` under `## [Unreleased]` → `### Changed`:

```markdown
- A `Cap(X)` parameter on a non-`main` function is no longer a ceiling on everything that
  function transitively reaches. Taking one capability parameter used to oblige a function
  to take parameters for every other capability it reached, forcing callers to thread
  capabilities through the call graph. Capabilities are module-scoped: `needs`, the module
  ceiling, and `main`'s grant are the checks. `main`'s grant is unchanged.
```

Create `specs/progress/2026-08-13-remove-per-function-grant-ceiling.md` recording the decision, what was given up (a narrow `Cap` param is no longer a per-function bound for an unlinked library), and why.

- [ ] **Step 10: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/capabilities.md CHANGELOG.md specs/progress/2026-08-13-remove-per-function-grant-ceiling.md
git commit -m "feat(caps): remove per-function grant ceiling; capabilities stay module-scoped"
```

---

### Task 4: Reject unknown capability names with a suggestion

**Why:** `needs IO.Filesystem` (wrong case), `needs IO.FileWrit` (typo) and `needs Network` are all accepted. Each yields only *"declares `needs X` but no function requires it — help: remove the unused capability declaration"*, which points away from the real problem, while the genuine error surfaces elsewhere as an unrelated missing-`needs`. The lattice is closed, so this is checkable.

FFI capability roots (e.g. `LibC`) are intentionally *not* in the hierarchy and must stay legal. The rule: a path whose first segment is `IO` must be in the hierarchy; any other single-segment root is accepted as an FFI root **unless** its lowercased form matches a known capability's leaf (which catches `needs Network`).

**Files:**
- Modify: `lib/caps/cap_lattice.ml` (add `suggest_cap`), `lib/caps/cap_lattice.mli`
- Modify: `lib/typecheck/typecheck.ml:11089` (the `DNeeds` validation arm)
- Test: `test/test_compiler.ml`

**Interfaces:**
- Consumes: `March_caps.Cap_lattice.hierarchy : (string * string option) list`.
- Produces: `March_caps.Cap_lattice.suggest_cap : string -> string option` — `None` if `cap` is a legal capability path, `Some known` naming the closest known capability if it is not.

- [ ] **Step 1: Write the failing test**

Add to `test/test_compiler.ml`:

```ocaml
let test_unknown_capability_is_rejected_with_suggestion () =
  let ctx = typecheck {|mod BadCap do
    needs IO.FileWrit
    fn main() : () do
      ()
    end
  end|} in
  Alcotest.(check bool) "an unknown capability is an error"
    true (has_error_with ctx "IO.FileWrit");
  Alcotest.(check bool) "the closest known capability is suggested"
    true (has_error_with ctx "IO.FileWrite")

let test_wrong_case_capability_is_rejected () =
  let ctx = typecheck {|mod BadCase do
    needs IO.Filesystem
    fn main() : () do
      ()
    end
  end|} in
  Alcotest.(check bool) "wrong case is suggested against"
    true (has_error_with ctx "IO.FileSystem")

let test_bare_leaf_capability_is_rejected () =
  let ctx = typecheck {|mod BareLeaf do
    needs Network
    fn main() : () do
      ()
    end
  end|} in
  Alcotest.(check bool) "a bare leaf name suggests the full path"
    true (has_error_with ctx "IO.Network")

let test_ffi_capability_root_still_accepted () =
  (* FFI roots are deliberately outside the IO lattice and must stay legal. *)
  let ctx = typecheck {|mod FfiRoot do
    needs IO.Foreign
    extern "libc": Cap(LibC) do
      fn getpid() : Int
    end
    fn main() : () do
      ()
    end
  end|} in
  Alcotest.(check bool) "an FFI capability root is not reported unknown"
    false (has_error_with ctx "is not a known capability")
```

Register all four in the suite list.

- [ ] **Step 2: Run test to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: the first three FAIL (no error is produced at all).

- [ ] **Step 3: Add the suggestion helper**

Append to `lib/caps/cap_lattice.ml`:

```ocaml
(* Levenshtein distance, iterative two-row form. *)
let edit_distance a b =
  let la = String.length a and lb = String.length b in
  if la = 0 then lb else if lb = 0 then la
  else begin
    let prev = Array.init (lb + 1) (fun j -> j) in
    let cur  = Array.make (lb + 1) 0 in
    for i = 1 to la do
      cur.(0) <- i;
      for j = 1 to lb do
        let cost = if a.[i - 1] = b.[j - 1] then 0 else 1 in
        cur.(j) <- min (min (cur.(j - 1) + 1) (prev.(j) + 1)) (prev.(j - 1) + cost)
      done;
      Array.blit cur 0 prev 0 (lb + 1)
    done;
    prev.(lb)
  end

let known_caps = List.map fst hierarchy

let leaf c =
  match String.rindex_opt c '.' with
  | Some i -> String.sub c (i + 1) (String.length c - i - 1)
  | None -> c

(** [suggest_cap cap] is [None] when [cap] is a legal capability path, and
    [Some known] naming the closest known capability when it is not.

    A path rooted at [IO] must appear in [hierarchy] — that lattice is closed.
    Any other root is an FFI capability (see the header comment) and is legal,
    UNLESS its leaf matches a known capability's leaf case-insensitively, which
    is the `needs Network` case: a real capability written without its path. *)
let suggest_cap cap =
  if List.mem cap known_caps then None
  else begin
    let lower s = String.lowercase_ascii s in
    let is_io_rooted =
      cap = "IO" || (String.length cap > 3 && String.sub cap 0 3 = "IO.")
    in
    (* The leaf-collision rule catches `needs Network` — a real capability
       written without its path.  It must apply ONLY to single-segment names:
       a DOTTED non-IO path is an FFI/proof capability and is always legal, so
       `MyLib.Clock` and `Vendor.Random` must not be dragged in by their last
       segment.  (Corrected 2026-08-13 during execution: an earlier draft of
       this code computed the leaf match before this gate, which falsely
       rejected exactly those names and pointed the user at an unrelated IO
       capability.  `Db.Migrated` and `Db.P` in the existing corpus are the
       shape that must keep working.) *)
    let leaf_match =
      if String.contains cap '.' then None
      else List.find_opt (fun k -> lower (leaf k) = lower (leaf cap)) known_caps
    in
    match leaf_match with
    | Some k -> Some k
    | None ->
      if not is_io_rooted then None   (* an FFI root; legal *)
      else
        let scored =
          List.map (fun k -> (edit_distance (lower cap) (lower k), k)) known_caps
        in
        match List.sort compare scored with
        | (d, k) :: _ when d <= 3 -> Some k
        | _ -> Some "IO"
  end
```

Add to `lib/caps/cap_lattice.mli`:

```ocaml
val suggest_cap : string -> string option
(** [suggest_cap cap] is [None] when [cap] is a legal capability path, and
    [Some known] naming the closest known capability when it is not.  Paths
    rooted at [IO] must be in the closed lattice; other roots are FFI
    capabilities and are legal unless their leaf names a real capability. *)
```

- [ ] **Step 4: Report it in the `DNeeds` arm**

In `lib/typecheck/typecheck.ml`, in the `| Ast.DNeeds (caps, sp) ->` arm at ~11089 (the one that already checks `has_foreign`), add before the `has_foreign` check:

```ocaml
      List.iter (fun (path, _scope) ->
        let cap_path = String.concat "." (List.map (fun (n : Ast.name) -> n.Ast.txt) path) in
        match March_caps.Cap_lattice.suggest_cap cap_path with
        | None -> ()
        | Some known ->
          Err.error_with_fix errors ~span:sp
            ~fix:(Err.FReplace { span = sp; text = "needs " ^ known })
            (Printf.sprintf
               "`%s` is not a known capability.\n\
                help: did you mean `%s`?"
               cap_path known)
      ) caps;
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS, all four.

- [ ] **Step 6: Run the whole suite**

```bash
scripts/run-tests.sh
```

Expected: exit 0. If a stdlib module declares a capability outside the lattice, `suggest_cap` is wrong about it — widen the FFI-root rule rather than adding the name to `hierarchy`, unless it genuinely is an IO capability.

- [ ] **Step 7: Update docs and changelog**

Add to `CHANGELOG.md` under `## [Unreleased]` → `### Added`:

```markdown
- An unrecognized capability in `needs` is now an error with a did-you-mean suggestion
  (`needs IO.FileWrit` → `needs IO.FileWrite`). Typos previously produced only a misleading
  "declared but no function requires it — remove the unused declaration" warning.
```

Add a short subsection to `specs/lang/capabilities.md` under "Capability hierarchy" noting the lattice is closed and typos are rejected with a suggestion, while FFI roots stay free-form. Create `specs/progress/2026-08-13-unknown-capability-names-unvalidated.md`.

- [ ] **Step 8: Commit**

```bash
git add lib/caps/cap_lattice.ml lib/caps/cap_lattice.mli lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/capabilities.md CHANGELOG.md specs/progress/2026-08-13-unknown-capability-names-unvalidated.md
git commit -m "feat(caps): reject unknown capability names with a suggestion"
```

---

### Task 5: Aggregate the per-builtin `needs` errors into one diagnostic

**Why:** A `main` that prints, writes a file, reads the clock and calls the RNG with nothing declared produces **five** errors for one mistake: the grant error plus four separate missing-`needs` errors. The grant error already aggregates all four capabilities and prints a complete replacement signature; the `needs` errors do not. One aggregated `needs` error per module, carrying a single multi-line insert fix, keeps `forge fix` working (one fix per diagnostic) while cutting five diagnostics to two.

**Files:**
- Modify: `lib/typecheck/typecheck.ml` — the body-scan check that emits `function body calls a builtin that requires ...`
- Test: `test/test_compiler.ml`

**Interfaces:**
- Consumes: Task 1's `code` convention. The aggregated diagnostic keeps code `cap_needs:<Cap1>,<Cap2>,…` so tooling can still parse the set.
- Produces: at most one missing-`needs` diagnostic per module, with `fix` = `FInsert` whose `text` is all missing `needs` lines joined by `\n`.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_missing_needs_reported_once_per_module () =
  let ctx = typecheck {|mod ManyCaps do
    fn main(cap : Cap(IO)) : () do
      println("a")
      match file_write("/tmp/many", "d") do
        Ok(_) -> ()
        Err(_) -> ()
      end
    end
  end|} in
  Alcotest.(check int) "one aggregated missing-needs error, not one per builtin"
    1 (count_errors_with ctx "does not declare");
  Alcotest.(check bool) "every missing capability is named"
    true (has_error_with ctx "IO.Console" && has_error_with ctx "IO.FileWrite")
```

`count_errors_with` does not exist. Add it to `test/test_helpers.ml` immediately after `has_error_with` (`test/test_helpers.ml:1804`), mirroring its case-insensitive substring search exactly:

```ocaml
(** Counts error diagnostics whose message contains [sub] (case-insensitive). *)
let count_errors_with ctx sub =
  let sub_lo = String.lowercase_ascii sub in
  List.length (List.filter (fun d ->
    d.March_errors.Errors.severity = March_errors.Errors.Error &&
    let m = String.lowercase_ascii d.March_errors.Errors.message in
    let sub_len = String.length sub_lo in
    let m_len   = String.length m in
    let found   = ref false in
    for i = 0 to m_len - sub_len do
      if String.sub m i sub_len = sub_lo then found := true
    done;
    !found
  ) ctx.March_errors.Errors.diagnostics)
```

`has_errors`, `has_error_with`, `has_warning_with` and `has_hint_with` already exist in that file and need no changes.

- [ ] **Step 2: Run test to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: FAIL — gets `2`, expected `1`.

- [ ] **Step 3: Aggregate the diagnostic**

Locate the body-scan emitter:

```bash
grep -n "function body calls a builtin that requires" lib/typecheck/typecheck.ml
```

It currently emits inside a per-call-site `List.iter`. Restructure: accumulate `(cap, span)` pairs into a local list across the walk, then after the walk emit one diagnostic. Report it at the **first** offending call site's span so the excerpt still points at real code, and list the capabilities in sorted order:

```ocaml
  (* Accumulated during the body walk, emitted once per module: five errors
     for "declared nothing" is five fixes for one mistake, and the grant error
     already aggregates. *)
  match List.sort_uniq compare !missing_needs with
  | [] -> ()
  | ((_, first_span) :: _) as missing ->
    let caps = List.sort_uniq String.compare (List.map fst missing) in
    let show = String.concat ", " (List.map (fun c -> Printf.sprintf "`%s`" c) caps) in
    let lines =
      String.concat "\n" (List.map (fun c -> "  needs " ^ c) caps)
    in
    Err.error_with_fix env.errors ~span:first_span
      ~code:("cap_needs:" ^ String.concat "," caps)
      ~fix:(Err.FInsert { after_line = mod_header_line; text = lines })
      (Printf.sprintf
         "function bodies in `%s` call builtins that require %s, but `%s` \
          declares no matching `needs`.\n\
          help: add %s to the module body."
         mod_name show mod_name
         (String.concat " and " (List.map (fun c -> "`needs " ^ c ^ "`") caps)))
```

`mod_header_line` is the line the existing single-cap fix already inserts after — reuse the same expression rather than recomputing it.

- [ ] **Step 4: Run the test to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS.

- [ ] **Step 5: Verify `forge fix` still repairs a multi-capability module end to end**

```bash
cd /tmp && rm -rf aggfix && forge new aggfix && cd aggfix
cat > lib/aggfix.march <<'EOF'
mod Aggfix do
  fn main() do
    println("a")
    let _ = file_write("/tmp/aggfix.txt", "d")
    ()
  end
end
EOF
forge fix && forge build && forge run
```

Expected: `forge fix` inserts both `needs` lines and the grant parameter; `forge build` and `forge run` exit 0.

- [ ] **Step 6: Run the whole suite**

```bash
scripts/run-tests.sh
```

Expected: exit 0. Several existing tests assert the old singular wording ("function body calls a builtin that requires"); update their expected substrings to the new text. Find them with `grep -n "calls a builtin that requires" test/*.ml`.

- [ ] **Step 7: Update docs and changelog**

Update the two example transcripts in `specs/lang/capabilities.md` under "What the compiler tells you" to the new aggregated wording. Add to `CHANGELOG.md` under `### Changed`:

```markdown
- Missing `needs` declarations are now reported as one aggregated error per module listing
  every missing capability, with a single fix that inserts them all, instead of one error
  per offending call site.
```

Create `specs/progress/2026-08-13-aggregate-missing-needs-diagnostics.md`.

- [ ] **Step 8: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/capabilities.md CHANGELOG.md specs/progress/2026-08-13-aggregate-missing-needs-diagnostics.md
git commit -m "feat(caps): aggregate missing-needs errors into one diagnostic per module"
```

---

### Task 6: Stop nagging correct code

**Why:** Two diagnostics fire on code that is already right.

1. Every capability parameter warns *"Unused variable `cap`"*. Capability values are runtime-erased grant tokens; being unused is their normal state. `forge new`'s own template had to name the parameter `_cap` to dodge it.
2. `fn main(cap : Cap(IO))` emits *"consider narrowing... for least-privilege"* — while `specs/lang/capabilities.md` calls `Cap(IO)` "the established entry-point convention" and says `needs IO` in entry points "is fine". The compiler nags you for following the documented convention.

**Files:**
- Modify: `lib/typecheck/typecheck.ml:7650-7666` (`warn_unused_params`)
- Modify: `lib/typecheck/typecheck.ml:9627-9636` (the `Cap(IO)` narrowing hint)
- Test: `test/test_compiler.ml`

**Interfaces:**
- Consumes: `March_caps.Cap_surface_ty.caps_in_ty : Ast.ty -> string list`.
- Produces: no new public interface.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_unused_cap_param_is_not_warned () =
  let ctx = typecheck {|mod QuietCap do
    needs IO.Console
    fn main(cap : Cap(IO.Console)) : () do
      println("hi")
    end
  end|} in
  Alcotest.(check bool) "a capability parameter is not an unused variable"
    false (has_warning_with ctx "Unused variable `cap`")

let test_ordinary_unused_param_still_warned () =
  let ctx = typecheck {|mod StillWarns do
    fn f(x : Int) : Int do
      1
    end
  end|} in
  Alcotest.(check bool) "an ordinary unused parameter still warns"
    true (has_warning_with ctx "Unused variable `x`")

let test_main_is_not_nagged_about_root_cap () =
  let ctx = typecheck {|mod EntryPoint do
    needs IO
    fn main(cap : Cap(IO)) : () do
      println("hi")
    end
  end|} in
  Alcotest.(check bool) "main is not told to narrow the root capability"
    false (has_hint_with ctx "root capability")

let test_non_main_still_hinted_about_root_cap () =
  let ctx = typecheck {|mod NotEntry do
    needs IO
    fn helper(cap : Cap(IO)) : () do
      println("hi")
    end
    fn main(c : Cap(IO)) : () do
      helper(c)
    end
  end|} in
  Alcotest.(check bool) "a non-main function is still hinted"
    true (has_hint_with ctx "root capability")
```

`has_warning_with` (`test/test_helpers.ml:1789`) and `has_hint_with` (`:1825`) already exist. No helper changes are needed for this task.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: `test_unused_cap_param_is_not_warned` and `test_main_is_not_nagged_about_root_cap` FAIL.

- [ ] **Step 3: Exempt capability parameters from the unused warning**

In `warn_unused_params` (`typecheck.ml:7650`), skip any parameter whose declared type names a capability:

```ocaml
let warn_unused_params env (params : Ast.fn_param list) (body : Ast.expr) _fn_span =
  let used = free_vars_expr [] body in
  (* A capability value is a runtime-erased grant token: it is normal, and
     often correct, for it never to be mentioned in the body. Warning on it
     made the right code noisy and pushed users to spell every grant `_cap`. *)
  let is_cap_ty = function
    | Some ty -> March_caps.Cap_surface_ty.caps_in_ty ty <> []
    | None -> false
  in
  let check_name name span =
    if name <> "_" && not (String.length name > 0 && name.[0] = '_')
       && not (List.mem name used) then
      Err.warning_with_code_and_fix env.errors ~span ~code:"unused_binding"
        ~fix:(Err.FReplace { span; text = "_" ^ name })
        (Printf.sprintf "Unused variable `%s`.\n\
                         Use `_` to mark intentionally unused params." name)
  in
  List.iter (fun fp ->
    match fp with
    | Ast.FPNamed p ->
      if not (is_cap_ty p.param_ty) then check_name p.param_name.txt p.param_name.span
    | Ast.FPPat (Ast.PatVar n) -> check_name n.txt n.span
    | Ast.FPPat _ -> ()
    | Ast.FPDefault (p, _) ->
      if not (is_cap_ty p.param_ty) then check_name p.param_name.txt p.param_name.span
  ) params
```

`lib/typecheck/dune:3` already lists `march_caps`, and `Ast.param` already carries `param_ty : ty option` (`lib/ast/ast.ml:94-98`), so no build or AST changes are needed.

- [ ] **Step 4: Suppress the narrowing hint on `main`**

The hint at `typecheck.ml:9627` iterates `used_caps`, which are `(cap_path, span)` pairs with no function name. Thread the enclosing function's name through so `main` can be excluded — find where `used_caps` is built and carry the name alongside, then:

```ocaml
  (* Check 3 (hint): Cap(IO) root — suggest narrowing.  Not on `main`: the
     reference calls `fn main(cap : Cap(IO))` the entry-point convention, so
     hinting there tells users to stop following the documented advice. *)
  List.iter (fun (cap_path, fn_name, sp) ->
    if cap_path = "IO" && fn_name <> "main" then
      Err.hint env.errors ~span:sp
        (render_parts [
          MPText "this function takes "; cap "IO";
          MPText " (the root capability); consider narrowing to e.g. ";
          cap "IO.FileRead"; MPText " or "; cap "IO.Console";
          MPText " for least-privilege." ])
  ) used_caps;
```

If threading the name is invasive, the narrower alternative is to compare `sp` against the span recorded in `env.fn_grant_points` for the key `"main"` — but prefer the explicit name.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS, all four.

- [ ] **Step 6: Run the whole suite**

```bash
scripts/run-tests.sh
```

Expected: exit 0. Some tests count total warnings; update any that assumed a cap-param warning.

- [ ] **Step 7: Revert the scaffold workaround**

Task 2 named the template parameter `_cap` to dodge the warning. With the warning gone, rename it to `cap` in `forge/lib/scaffold.ml` so generated code reads naturally, and confirm `forge new` + `forge check` still exits 0.

- [ ] **Step 8: Update docs and changelog**

Add to `CHANGELOG.md` under `### Fixed`:

```markdown
- Capability parameters no longer trigger "Unused variable" warnings. A capability value is
  a runtime-erased grant token and is normally never referenced in the body.
- `fn main(cap : Cap(IO))` no longer emits the "narrow to least-privilege" hint. That is the
  documented entry-point convention; the hint still fires on non-`main` functions.
```

Create `specs/progress/2026-08-13-capability-diagnostics-nag-correct-code.md`.

- [ ] **Step 9: Commit**

```bash
git add lib/typecheck/typecheck.ml forge/lib/scaffold.ml test/test_compiler.ml CHANGELOG.md specs/progress/2026-08-13-capability-diagnostics-nag-correct-code.md
git commit -m "fix(caps): stop warning and hinting on correct capability code"
```

---

### Task 7: Give the capability ceiling a span, a fix, and a `--check` run

**Why:** The ceiling is the only check that catches a stdlib-routed capability (`File.read` rather than `file_read`) — the *idiomatic* way to do IO. Two problems:

1. Its diagnostic is second-class: no file, no line, no source excerpt, no machine-applicable fix. It is therefore invisible to the LSP and unusable by `forge fix`, unlike every other capability diagnostic.
2. It runs only on the compile path, so `march --check` exits 0 on a module whose `needs` manifest is provably false. Verified: a module declaring `needs IO.Console` that reads `/etc/passwd` via `File.read` passes `--check` silently, and only `--compile` reports it.

**Files:**
- Modify: `bin/main.ml:2911-2970` (ceiling reporting)
- Modify: `lib/caps/cap_ceiling.ml` / `.mli` (carry a span for each violation)
- Test: `test/test_compiler.ml`

**Interfaces:**
- Consumes: the existing per-module violation records from `Cap_ceiling`.
- Produces: each ceiling violation is reported through `Err.error_with_code_and_fix` with `code = "cap_ceiling:<Cap>"`, the declaring module's `needs`-block span (or the module header span when it declares none), and an `FInsert` fix adding the missing `needs` line.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_ceiling_violation_surfaces_under_check () =
  (* A stdlib-routed read is the idiomatic form. `--check` must not pass a
     module whose `needs` manifest is provably false. *)
  let ctx = typecheck {|mod StdlibRouted do
    needs IO.Console
    fn slurp(p : String) : String do
      match File.read(p) do
        Ok(s) -> s
        Err(_) -> ""
      end
    end
    fn main(cap : Cap(IO)) : () do
      println(slurp("/etc/passwd"))
    end
  end|} in
  Alcotest.(check bool) "the stdlib-routed capability is reported"
    true (has_error_with ctx "IO.FileRead");
  Alcotest.(check bool) "the offending module is named"
    true (has_error_with ctx "StdlibRouted")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: FAIL — `--check` produces no such error today.

- [ ] **Step 3: Carry a span on each violation**

In `lib/caps/cap_ceiling.ml`, extend the violation record from `(module_name, cap)` to `(module_name, cap, span)`. Populate the span at the point the violation is constructed: the module's first `DNeeds` span if it has one, otherwise the module header's span. Update `cap_ceiling.mli` to match.

- [ ] **Step 4: Report it as an ordinary diagnostic**

In `bin/main.ml`, replace the bespoke `-- CAPABILITY CEILING --` block at ~2959 with an `Err` emission per violation so it renders like every other diagnostic and carries a fix:

```ocaml
             Err.error_with_fix errs ~span
               ~code:("cap_ceiling:" ^ cap)
               ~fix:(Err.FInsert { after_line = mod_header_line; text = "  needs " ^ cap })
               (Printf.sprintf
                  "module `%s` uses `%s` but does not declare `needs %s`.\n\
                   help: add `needs %s` to the module body."
                  m cap cap cap)
```

Keep the trailing summary line ("N capability ceiling violation(s)…") and the `--no-cap-strict` escape hatch note, since both are useful.

- [ ] **Step 5: Run the ceiling on the `--check` path**

The ceiling analysis runs over emitted TIR, which `--check` does not produce. Rather than lowering under `--check`, run the same **attribution** the ceiling uses against the typecheck-time capability closure, which already resolves stdlib calls (that is how the grant check caught `File.read` in the verification above). In `check_module_core`, after `check_module_needs`, add a per-module comparison of each module's transitive closure against its declared `needs`, emitting the same `cap_ceiling:<Cap>` diagnostic. Reuse `own_cap_closures` and `cap_subsumes` — do not re-derive the closure.

If the closure available at typecheck time proves insufficient to attribute a stdlib-routed call to the calling module, stop and report that finding rather than approximating: an over-reporting ceiling on `--check` would break every existing project.

- [ ] **Step 6: Run the test to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS.

- [ ] **Step 7: Run the whole suite and a corpus sweep**

```bash
scripts/run-tests.sh
```

Expected: exit 0. Then verify no false positives across real code:

```bash
for f in bench/*.march stdlib/*.march; do
  ./_build/default/bin/main.exe --check "$f" > /dev/null 2>&1 || echo "FAIL $f"
done
```

Expected: no `FAIL` lines beyond any that already failed before this task. Capture the pre-change baseline first by running the same loop on a stashed-free checkout of the previous commit.

- [ ] **Step 8: Update docs and changelog**

`specs/lang/capabilities.md` states in several places that `--check` exits 0 on a stdlib-mediated call and that only `march --compile` catches it. Update every such passage — including the "What this does and does not guarantee" list, the "When *not* to use IO caps" paragraph, and the assurance-ladder table row — to say the ceiling now runs under `--check` too. Add to `CHANGELOG.md` under `### Changed`:

```markdown
- The capability ceiling now runs under `march --check`, not only on the compile path, so a
  module whose `needs` manifest is falsified by a stdlib-routed call (`File.read` rather than
  `file_read`) is caught before codegen. Ceiling violations are now reported as ordinary
  diagnostics with a source span and an applicable fix.
```

Create `specs/progress/2026-08-13-capability-ceiling-second-class-and-compile-only.md`.

- [ ] **Step 9: Commit**

```bash
git add lib/caps/cap_ceiling.ml lib/caps/cap_ceiling.mli bin/main.ml lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/capabilities.md CHANGELOG.md specs/progress/2026-08-13-capability-ceiling-second-class-and-compile-only.md
git commit -m "feat(caps): report ceiling violations with spans and run them under --check"
```

---

### Task 8: Attribute grant violations to the user's module, not the stdlib leaf

**Why:** A grant violation reached through the stdlib reports:

```
`main` is granted `Cap(IO.Console)`, but the program reaches `IO.FileRead` (reached in `File.read`).
```

`File.read` is the stdlib leaf — the least useful frame. The user has to hunt for which of *their* modules called it. The body-scan error already does this right, printing `main → log_error → log`, and `cap_reach_chain` exists to produce exactly that.

**Files:**
- Modify: `lib/typecheck/typecheck.ml` — `check_main_grant`'s attribution (the `reached in` text, ~13195-13230)
- Test: `test/test_compiler.ml`

**Interfaces:**
- Consumes: `cap_reach_chain env ~from:(string) ~cap:(string) : string list option`, defined in `lib/typecheck/typecheck.ml` just above the (now-deleted) `check_fn_grants`. Task 3 Step 3 explicitly preserves it for this task.
- Produces: no new public interface.

- [ ] **Step 1: Write the failing test**

```ocaml
let test_grant_violation_names_the_user_module () =
  let ctx = typecheck {|mod Attributed do
    needs IO
    fn helper(p : String) : String do
      match File.read(p) do
        Ok(s) -> s
        Err(_) -> ""
      end
    end
    fn main(cap : Cap(IO.Console)) : () do
      println(helper("/etc/passwd"))
    end
  end|} in
  Alcotest.(check bool) "the user's own function is named in the chain"
    true (has_error_with ctx "helper")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: FAIL — the message names only `File.read`.

- [ ] **Step 3: Report the chain instead of the leaf**

In `check_main_grant`'s violation branch, replace the single `reached in <holder>` phrasing with the chain from `main`, matching the body-scan error's format and its 4-frame elision:

```ocaml
             (match cap_reach_chain env ~from:"main" ~cap:c with
              | Some (_ :: _ as chain) ->
                let shown =
                  if List.length chain > 4 then
                    "… -> "
                    ^ String.concat " -> "
                        (List.filteri (fun i _ -> i >= List.length chain - 3) chain)
                  else String.concat " -> " chain
                in
                Printf.sprintf " (reached from `main`: %s)" shown
              | _ -> "")
```

The chain ends at the frame that directly holds the capability, so a stdlib leaf still appears — but preceded by the user's own frames, which is the information that was missing.

- [ ] **Step 4: Run the test to verify it passes**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e
```

Expected: PASS.

- [ ] **Step 5: Run the whole suite**

```bash
scripts/run-tests.sh
```

Expected: exit 0. Tests asserting the old `reached in` substring need their expected text updated — find them with `grep -n "reached in" test/*.ml`.

- [ ] **Step 6: Update docs and changelog**

Update the grant-error transcript in `specs/lang/capabilities.md` under "The grant" to show the chain form. Add to `CHANGELOG.md` under `### Changed`:

```markdown
- A grant violation now names the chain of the user's own functions that reaches the
  capability, instead of only the stdlib function that holds it.
```

Create `specs/progress/2026-08-13-grant-violation-attributed-to-stdlib-leaf.md`.

- [ ] **Step 7: Commit**

```bash
git add lib/typecheck/typecheck.ml test/test_compiler.ml specs/lang/capabilities.md CHANGELOG.md specs/progress/2026-08-13-grant-violation-attributed-to-stdlib-leaf.md
git commit -m "fix(caps): attribute grant violations to the user's call chain"
```

---

## Final verification

- [ ] **Run the full suite including Slow tests**

```bash
scripts/run-tests.sh
```

Expected: exit 0, checked via `$?`.

- [ ] **Run the doc freshness lint**

```bash
scripts/check-docs.sh
```

Expected: exit 0.

- [ ] **Walk the new-user path end to end**

```bash
cd /tmp && rm -rf finalcheck && forge new finalcheck && cd finalcheck && forge check && forge build && forge run && forge test
```

Expected: every command exits 0, no warnings, no hints.

- [ ] **Confirm the no-threading property holds**

```bash
cd /tmp && cat > nothread.march <<'EOF'
mod NoThread do
  needs IO.Console
  needs IO.FileWrite
  fn handle(c : Cap(IO.FileWrite), msg : String) : () do
    println("handling")
    match file_write("/tmp/nothread.txt", msg) do
      Ok(_) -> ()
      Err(_) -> ()
    end
  end
  fn main(cap : Cap(IO)) : () do
    handle(cap_narrow(cap), "x")
  end
end
EOF
march --check nothread.march
```

Expected: exit 0 with no diagnostics. A single capability parameter must never oblige a function to accept a second one.

---

## Deferred / not in scope

- **A capability-environment record as a language feature.** The reference describes one as a pattern for threading many capabilities. With Task 3 removing the pressure to thread at all, this is no longer urgent; revisit only if real code still hits parameter pressure.
- **`forge check`'s divergence from `march --check`.** Investigated during analysis and found to be a stale installed toolchain (`~/.opam/march/bin/march`, a week behind), not a product defect. No work needed, but note it in contributor docs if new contributors keep hitting it.
- **macOS `process-exec` not gated under `--cap-sandbox`.** Already tracked in `specs/todos/2026-08-12-cap-sandbox-macos-process-exec-not-gated.md`.
