# Law coverage and law strength Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `march --check --law-coverage` lists which pure functions no admitted law covers, `--law-strength` adds the body edits every covering law still accepts, and `forge audit --laws` runs the same over a package.

**Architecture:** Two new refinecheck modules read what the refinement check already computed: the reflection verdicts (`Refine_reflect.analyze`, as `--reflect-report` uses them) and the admitted lemmas (`Refine_check.lemma_defs`). `Law_coverage` inverts "law → functions its theorem calls" and renders text and JSON. `Law_strength` makes single-function body edits and judges them in the witness interpreter on `Reflect_parity` inputs, reusing `Lemma_test`'s law evaluation. The driver wires both behind flags; forge shells out to them per source file.

**Tech Stack:** OCaml 5.5.1, dune, alcotest; z3 (only for the check that precedes the report; strength itself makes no z3 query).

**Spec:** `specs/2026-11-04-law-coverage-design.md` (read it with this plan; §-references below are to it).

## Global Constraints

- Neither report runs unless its flag is given; `--check` without the flags prints byte-for-byte what it prints today (§2 anti-goals).
- Pure = `Refine_reflect` verdict `Reflected _` only; `Specialised _` goes in the `higher-order (no laws possible yet)` group, outside the headline count; lemmas are never listed (§3).
- Covered = named by an **admitted** law's theorem (proved, or trusted from `stdlib/lemmas.verified`); unproved laws are listed apart and never counted (§2, §3).
- Theorem calls come from walking the theorem AST, not `Lemma_source.calls` (§3).
- Strength: at most **20** edits per function, deterministic; an equivalent edit is dropped; an edit with no decided input is undecided; a function with no generator prints `strength: not run (no input generator)`; none of these ever reads as zero survivors (§5).
- Strength budget: `MARCH_LAW_STRENGTH_MS`, default **5000** ms per function, across all its edits; on reaching it print `strength: partial (budget), N of M edits judged` (§5).
- `forge audit --laws` runs only the law report, needs no `forge.caps.lock`, exits 0 unless a check fails; `forge audit` without `--laws` is unchanged (§4).
- Build and test from the worktree with `--root .` or `scripts/run-tests.sh`; never `eval $(opam env)`; stage files by name; no Co-Authored-By lines.
- Same commit as the feature: `specs/progress/` note, CHANGELOG `### Added` bullet, `specs/lang/lemmas.md` section then `python3 scripts/gen-lang-docs.py` (Task 6).

## Review Focus

1. **A module with no lemmas at all**: every pure function is uncovered, the summary reads `0 of N`, nothing crashes on the empty law table. Test in Task 1 (`no_lemmas`).
2. **A lemma whose theorem calls a function only by a qualified name from another module** (`List.append` in a user lemma): it covers the stdlib function, but the report for the user file lists only the user file's functions. Test in Task 1 (`qualified_stdlib_call`).
3. **A recursive function edited to drop its recursive call**: the edited copy must call itself (edited), not the original, or every such edit is judged wrongly. Test in Task 4 (`recursive_edit_calls_itself`).
4. **The witness state after strength**: running strength must leave `Witness.current_module` as the real module so later output in the same run (e.g. `--lemma-test`) is unaffected. Test in Task 4 (`strength_then_lemma_test`).
5. **A warm CAS cache**: `--law-coverage` on a second run of the same source must still print the report (the driver's cache bypass list, `bin/main.ml` ~3500). Test in Task 1 (`warm_cache`).

---

### Task 1: Coverage for top-level functions, text report, flag

**Files:**
- Create: `lib/refinecheck/law_coverage.ml`, `lib/refinecheck/law_coverage.mli`
- Modify: `lib/refinecheck/dune` (add `law_coverage` to `modules`)
- Modify: `bin/flags.ml` (`let law_coverage = ref false`), `bin/main.ml` (arg `--law-coverage`; a `print_law_coverage` call next to both `print_reflect_report` sites, ~2771 and ~4082; add `!law_coverage` to the cache-bypass disjunction ~3500)
- Modify: `bin/main.ml` `print_reflect_report`: split out `reflect_rows ~filename ~user_files ~type_map ~recheck m : Refine_reflect.row list` (the body up to `RR.analyze`), used by both reports. Pure refactor; `--reflect-report` output unchanged.
- Create: `test/test_refine_law_coverage.ml` (group `law-coverage`); Modify: `test/dune` (add module to the `test_refinecheck` modules list, line ~1359), `test/test_refinecheck.ml` (register `("law-coverage", Test_refine_law_coverage.tests)` beside `reflect-stdlib-list`, ~29045)

**Interfaces:**
- Produces (in `law_coverage.mli`):
  ```ocaml
  type status = Uncovered | Unproved_only of string list | Covered of string list | Higher_order
  type entry = { e_module : string; e_name : string; e_public : bool; e_span : March_ast.Ast.span; e_status : status }
  val theorem_calls : March_ast.Ast.fn_def -> string list          (* resolved qualified names, deduplicated, in first-occurrence order *)
  val entries : rows:Refine_reflect.row list -> lemmas:(string * March_ast.Ast.fn_def * bool) list
                -> decls:March_ast.Ast.decl list -> is_user:(March_ast.Ast.span -> bool) -> entry list
  val report_lines : entry list -> string list
  ```
  `lemmas` is `!Refine_check.lemma_defs` (qualified name, def, admitted). `decls` gives visibility (`fn` vs `pfn`) and module paths.
- Consumes: `Refine_check.lemma_post` (the theorem), `Refine_reflect.row`.

Report format (exact; one module block per module with a user pure function, modules in source order, two-space separators):
```
law coverage: M: 1 of 3 pure functions have a law (1 more only by unproved laws)
  uncovered (public)  f  m.march:3
  uncovered (private)  g  m.march:7
  unproved only  h  m.march:9  (h_law)
  covered  k  m.march:12  (k_law, k_law2)
  higher-order (no laws possible yet)  map2  m.march:20
```
Groups in that order, functions in source order within a group; the parenthetical omitted when `0 more`. Names are bare within their module's block; the module is the innermost `mod` path (`Outer.Inner`).

Name resolution for `theorem_calls`: resolve each call head the way the checker resolves a predicate call (`Refine_resolve.resolve_call_gen`, `lib/refinecheck/refine_resolve.ml` ~140, with the lemma's module path as context); a head that resolves to nothing reflected is dropped.

- [ ] **Step 1: Write the failing tests** in `test/test_refine_law_coverage.ml`, each through `Test_refine_unfold.run ~args:"--check --law-coverage"`, z3-gated with `U.gated`:
  - `covered_uncovered`: `Test_refine_lemma.defs4_6 ^ Test_refine_lemma.cat_nil` in `mod M`: output contains a `covered  cat  ` line ending `(cat_nil)`, a line starting `  uncovered (public)  rev  `, and a summary line starting `law coverage: M: `.
  - `unproved_only`: add a lemma the checker does not admit, `@[lemma] fn bad(xs : List(a)) : {Unit | rev(xs) == xs} do () end` (false, so refuted; any non-admitted valid lemma counts the same), with `rev` otherwise uncovered: a line `  unproved only  rev  ` ending `(bad)`, and the summary contains `(1 more only by unproved laws)`.
  - `private_fn`: a `pfn` helper with no law appears as `uncovered (private)`.
  - `proof_only_call`: `rev_cat` proved with `cat_assoc`/`cat_nil` calls in its body; a function called only in `rev_cat`'s proof body (add `pfn helper` used only there) is uncovered.
  - `lemmas_not_listed`: no line names `cat_nil` as a function.
  - `no_lemmas` (Review Focus 1): a module with two pure functions and no lemma: `0 of 2`.
  - `qualified_stdlib_call` (Review Focus 2): a user lemma calling `List.append` and a user `f`; the block lists `f` covered and no `append` line.
  - `warm_cache` (Review Focus 5): run the same source twice in the same directory; both outputs contain `law coverage: M:`.
  - `absent_without_flag`: plain `--check` output contains no `law coverage`.
- [ ] **Step 2: Run** `scripts/run-tests.sh refinecheck` filtered to the group (`./_build/default/test/test_refinecheck.exe test law-coverage` after `dune build --root . test/test_refinecheck.exe`). Expected: FAIL (unknown flag / missing text).
- [ ] **Step 3: Implement** `Law_coverage` per the interface, the `reflect_rows` split, and `print_law_coverage ~filename ~user_files ~type_map ~recheck m` in `bin/main.ml` printing `report_lines` to stderr (as `--reflect-report` does).
- [ ] **Step 4: Run** the group and `./_build/default/test/test_refinecheck.exe test reflect` (reflect-report unchanged). Expected: PASS.
- [ ] **Step 5: Commit** `law coverage: --law-coverage reports pure functions no admitted law covers`.

### Task 2: Impl methods and JSON

**Files:**
- Modify: `lib/refinecheck/law_coverage.ml/.mli`, `bin/flags.ml` (`law_coverage_json`), `bin/main.ml` (arg `--law-coverage-json`, implies `--law-coverage`; prints JSON lines to **stdout**)
- Test: `test/test_refine_law_coverage.ml`

**Interfaces:**
- Produces: `status` gains `Impl_method of string * string` (interface, impl type) carried alongside coverage, i.e. `entry` gains `e_impl : (string * string) option`; `val json_lines : entry list -> string list`.
- Consumes: `Refine_scope.law_method_display` to map a generated copy `__law_<m>__<Iface>_<T>` back to `<m>`, and the generated lemma name `<law>__<Iface>_<T>` to `<law> (via <Iface>)`.

Impl method rows go after `covered`, before `higher-order`, as `  impl <Iface> for <T>: <m>  <file:line>  (<law> (via <Iface>), ...)`, using the method's span in the impl. Only impls of interfaces that declare laws appear; they are not in the headline count.

JSON: one object per entry, keys in this order: `{"kind":"law-coverage","module":..,"fn":..,"public":bool,"file":..,"line":int,"status":"uncovered|unproved-only|covered|higher-order|impl-method","covered_by":[..],"unproved_by":[..],"impl":null|{"interface":..,"type":..}}` (plus `"strength"` from Task 4).

- [ ] **Step 1: Failing tests:** `impl_method_covered` (an interface with one `@[lemma]` law, e.g. the fixture in `test/test_refine_lemma.ml`'s `iface_law_lemma_test`, and one impl): a line `impl <Iface> for <T>: <m>` with `(via <Iface>)`; `impl_without_laws` (an interface with no laws and an impl): no `impl` line; `json_shape`: `--law-coverage-json` stdout lines parse with `Yojson.Safe.from_string` and the `covered_uncovered` fixture yields `status` `covered` for `cat` with `covered_by` `["cat_nil"]`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the group, expect PASS.**
- [ ] **Step 5: Commit** `law coverage: impl methods via interface laws, --law-coverage-json`.

### Task 3: Edit generation

**Files:**
- Create: `lib/refinecheck/law_strength.ml`, `lib/refinecheck/law_strength.mli`; Modify `lib/refinecheck/dune`
- Test: `test/test_refine_law_coverage.ml` (direct OCaml unit tests on parsed source; parse with `March_parser.Parse.module_` as other unit tests do)

**Interfaces:**
- Produces:
  ```ocaml
  type edit = { ed_desc : string; ed_span : March_ast.Ast.span; ed_fn : March_ast.Ast.fn_def }   (* the whole edited definition *)
  val edits : March_ast.Ast.fn_def -> edit list      (* <= 20, deterministic *)
  ```
- Kinds and their exact `ed_desc` wording, generated in this order, each in source (pre-order) position order, the list truncated to the first 20:
  1. `return `<p>` unchanged` — body replaced by parameter `p`, for each parameter whose declared type equals the declared return type (textual equality of `Fmt.fmt_ty`).
  2. `swap the arguments of `<f>`` — `f(a, b, ...)` with its first two arguments swapped (all calls, user or builtin; non-identical argument expressions only).
  3. `swap the fields of `<C>`` — constructor application's first two arguments swapped.
  4. `change <n> to <n'>` — Int literal `0`↔`1`, any other `n` → `n + 1`.
  5. `swap the results of two match arms` — adjacent arms of one `match`, results swapped.
  6. `drop the recursive call` — a self-call `f(..., t, ...)` replaced by its first argument that is a pattern-bound variable from the enclosing match (the structurally smaller one), e.g. `Cons(h, f(t))` → `Cons(h, t)`.
  7. `change <op> to <op'>` — `<`↔`<=`, `>`↔`>=`, `==`↔`!=`.
  Type correctness is checked in Task 4, not here.

- [ ] **Step 1: Failing tests:** `edits_reverse` on `rev` from `defs4_6`: descriptions include ``return `xs` unchanged`` and `drop the recursive call`; `edits_deterministic`: two calls give equal `ed_desc` lists; `edits_cap`: a function with 30 Int literals yields exactly 20 edits; `edits_no_self`: every `ed_fn` differs from the input (`<>` on the AST).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement `edits`.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `law strength: single-function body edits`.

### Task 4: Judging edits, `--law-strength`

**Files:**
- Modify: `lib/refinecheck/law_strength.ml/.mli`, `lib/refinecheck/lemma_test.ml/.mli` (expose `render : Eval_types.value -> string` and a law evaluator, below), `lib/refinecheck/law_coverage.ml` (strength lines, JSON `strength`), `bin/flags.ml` (`law_strength`), `bin/main.ml` (arg `--law-strength`, implies `--law-coverage`; add to the cache bypass)
- Test: `test/test_refine_law_coverage.ml`

**Interfaces:**
- Consumes: `edits` (Task 3); `Lemma_test.test_lemma` (refactor its body into `val law_holds : file:string -> string * A.fn_def * bool -> [ `Killed of string | `Held | `Undecided ]` evaluating under the current `Witness` module, and keep `test_lemma` on top of it); `Witness.set_module`, `Witness.eval_classified`; `Reflect_parity.inputs`.
- Produces:
  ```ocaml
  type verdict = { v_total : int; v_survivors : edit list; v_undecided : int; v_partial : (int * int) option; v_no_gen : bool }
  val judge : module_:March_ast.Ast.module_ -> laws:(string * March_ast.Ast.fn_def * bool) list
              -> typecheck:(March_ast.Ast.module_ -> bool) -> March_ast.Ast.fn_def -> verdict
  ```
  `typecheck` is supplied by the driver (re-run the typechecker the driver uses on the edited module; `true` when it has no errors); an edit that fails it is discarded uncounted. Per edit: build the edited module (replace the `DFn` whose name span equals the original's, recursing into `DMod`), `Witness.set_module` it, (1) compare `f(args)` against the original's results on `Reflect_parity.inputs` for `f`'s parameter sorts by `Lemma_test.render` text — no decided input: undecided; all equal: dropped; (2) else evaluate each law with `law_holds`: any `Killed` kills it, all `Held` survives, otherwise undecided. Restore `Witness.set_module module_` before returning, also on exception. For an `impl` row, edit and judge the generated copy `__law_<m>__<Iface>_<T>` (the function the generated laws call), and print its survivors under the impl row at the method's span. `v_total` counts the edits that changed behaviour and were decided. Budget per §Global Constraints, measured with `Unix.gettimeofday`.

Lines under a `covered` or `impl` row (four-space indent):
```
    strength: 4 of 11 edits survive (1 undecided)
    survives: return `xs` unchanged  m.march:8
    strength: not run (no input generator)
    strength: partial (budget), 5 of 11 edits judged
```
`(N undecided)` omitted when 0; `partial` replaces the first line and survivors so far still follow.

- [ ] **Step 1: Failing tests** (all `--check --law-strength`):
  - `weak_reverse`: `defs4_6` with only a `len_rev` length lemma (`{Unit | len(rev(xs)) == len(xs)}`, proved by induction like `cat_nil`): a `survives: return `xs` unchanged` line under `rev`.
  - `still_weak_with_rev_rev`: adding `rev_cat`, `cat_assoc`, `cat_nil`, `rev_rev ~asserts:false`: `return `xs` unchanged` still survives for `rev` (rev_rev holds for identity).
  - `killed_by_rev_cat`: with `len_rev` and `rev_cat` (and its helpers): no `survives: return `xs` unchanged` under `rev`.
  - `equivalent_dropped`: `fn add2(a : Int, b : Int) : Int do a + b end` with a lemma `add2(a, b) == a + b`: no line mentions `swap the arguments of `+``.
  - `no_generator`: a covered function over a parameter type with no generator (a function-typed or opaque `String` parameter: pick one `Reflect_parity.inputs` returns `None` for): `strength: not run (no input generator)` and no `0 of`.
  - `budget_partial`: `MARCH_LAW_STRENGTH_MS=1` on `weak_reverse`: `strength: partial (budget)`.
  - `recursive_edit_calls_itself` (Review Focus 3): `fn count(xs : List(a)) : Int` = `0`/`1 + count(t)` with lemma `count(Cons(x, xs)) == 1 + count(xs)`: the edit `change 1 to 2` is reported killed (absent from survivors), which only holds if the edited copy recurses into itself.
  - `strength_then_lemma_test` (Review Focus 4): `--check --law-strength --lemma-test` on `weak_reverse`: the `lemma-test` lines equal those of `--check --lemma-test` alone.
  - `deterministic`: two runs, identical output.
  - JSON: `--law-coverage-json --law-strength` gives `"strength":{"total":..,"survivors":[{"desc":..,"line":..}],"undecided":..,"partial":null|{"judged":..,"of":..},"no_generator":bool}` on covered entries, `null` otherwise.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `law_holds` refactor (run `./_build/default/test/test_refinecheck.exe test reflect-lemma` after it: unchanged), then `judge`, then the driver and report lines.
- [ ] **Step 4: Run the group and `reflect-lemma`, expect PASS.**
- [ ] **Step 5: Commit** `law strength: judge edits by the covering laws, --law-strength`.

### Task 5: `forge audit --laws`

**Files:**
- Modify: `forge/lib/cmd_audit.ml` (`val run_laws : strength:bool -> unit -> (int, string) result`), `forge/bin/main.ml` (the `audit` command gains `--laws` and `--strength`; `--strength` without `--laws` is an error "--strength only applies with --laws"; man page paragraph `LAW COVERAGE`)
- Test: `forge/test/test_audit.ml`

**Interfaces:**
- Consumes: `Cmd_test.project_sources` (the package's `lib/` and `src/` files) and the `lib_path_env` construction `forge test` uses for lemma tests (`Cmd_test.run_lemma_tests`); `march --check --law-coverage [--law-strength] FILE`.
- Behaviour: per source file, in `project_sources` order, print `law coverage: <file>` then the march output's `law coverage` block lines verbatim (stderr of the run). Laws pool across the package because every run loads the whole package through `MARCH_LIB_PATH`. Exit 0; a run that exits nonzero prints its output and makes the command return `Error "law coverage: the check failed in <files>"`.

- [ ] **Step 1: Failing tests:** `audit_laws_report` (a temp package with `src/a.march` holding `cat`/`rev` and `src/b.march` holding a lemma about `cat`): output shows `covered  cat` with the law from `b.march`; `audit_laws_no_lock`: works with no `forge.caps.lock`; `audit_unchanged`: `forge audit` without `--laws` on the same package prints no `law coverage`; `strength_needs_laws`: `forge audit --strength` fails with the message above. Gate on z3 like the lemma tests in `forge/test/test_build_check.ml` (~827).
- [ ] **Step 2: Run** `dune build --root . forge/test/test_audit.exe && ./_build/default/forge/test/test_audit.exe`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `forge audit --laws: law coverage for a package`.

### Task 6: Docs, stdlib run, wrap-up

**Files:**
- Modify: `specs/lang/lemmas.md` (section "Law coverage": what pure and covered mean, the three flags, `forge audit --laws`, one sample block), then run `python3 scripts/gen-lang-docs.py` (regenerates `docs/lemmas.md`)
- Modify: `CHANGELOG.md` (`### Added` under `## [Unreleased]`: one bullet naming the flags and `forge audit --laws`)
- Create: `specs/progress/2026-11-04-law-coverage.md` (what landed, the rulings marked *my call* in the design, and the result of running on the stdlib)
- Modify: `specs/todos/2026-11-02-lemma-uses-beyond-refinement.md` only if it lists coverage (it does not today; leave it)

- [ ] **Step 1:** Run `march --check --law-coverage --law-strength stdlib/list.march` (and `option.march`, `result.march`); paste the summary lines and the strength survivors per function into the progress note; check the run finishes in minutes (§5 target) and note the time.
- [ ] **Step 2:** Write the docs, CHANGELOG and progress note; run `python3 scripts/gen-lang-docs.py`.
- [ ] **Step 3:** Run `scripts/check-docs.sh` (doc-lint) and `scripts/affected.sh --run --no-oracles`. Expected: all pass.
- [ ] **Step 4: Commit** `law coverage: docs, changelog, progress note`.
