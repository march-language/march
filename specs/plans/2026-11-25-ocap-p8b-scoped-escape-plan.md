# Object capabilities, phase 8b: scoped handles and escape checking — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A handle that a function hands to a callback and closes afterwards (`File.with_open`'s
`h`) cannot leave that callback, by itself or inside a closure or a data value. Letting it leave
is a build error in every mode. Nothing else is newly rejected.

**Architecture:** A callback parameter is marked `scoped` in the signature of the function that
takes the callback. The capture pass (8a, `lib/typecheck/capture.ml`) gives each use of such a
function a fresh *tracked name*, puts it in the set of the handle the callback receives, and
lets the existing constraint solver carry it wherever the handle flows. After solving, a
tracked name found in an *escape position* (the callback's result, a table, a message, a
detached task or actor, a registry, or code the pass cannot follow) is the error
`capture_escape`. The pass runs inside the typechecker, only for functions that refer to a
function with a `scoped` parameter, so every mode gets the error and a program that uses no
scoped open pays nothing.

**Tech stack:** OCaml 5.5.1 (`lib/lexer`, `lib/parser`, `lib/ast`, `lib/caps`, `lib/typecheck`,
`lib/errors`), `tree-sitter-march/grammar.js`, three stdlib signatures. No TIR, codegen,
runtime C or interpreter change.

**Spec:** `specs/2026-11-11-ocap-capture-checking-design.md` ("the design"; `§n` is a section of
it): §3 (tracked names), §4.4, §7, §8.1 rule 1, §11.2, §11.5, §15, §16 row 8b, §18 "Escape" and
"Every mode". Groundwork: `specs/progress/2026-11-24-ocap-p8a-capture-sets.md`,
`specs/todos/2026-11-24-ocap-capture-pass-always-on-prerequisites.md`.

## Global Constraints

- The only new error is `capture_escape`. Every program accepted before 8b is still accepted
  unless it lets a scoped handle leave its callback (§15). `scripts/oracle-base.sh all` must
  report the types and refine oracles identical to the merge-base apart from fixtures and
  stdlib lines this branch changes, and the IR oracle byte-identical (§10.3, §10.4).
- No set is ever smaller than the truth. No set covers a tracked name except one that holds it:
  not `IO`, and narrowing (clause, `restrict`, grant) never removes a tracked name (§3, §6.1).
- A tracked name prints as its source name (`h`); when the callback is not a lambda, as the
  parameter name of the function passed. No internal name appears in a message (§11.5).
- The pass adds no run-time code or data. Capture sets stay erased before lowering.
- 8a's goldens (`test/captures/*.expected`) do not change: a handle with no tracked name prints
  as before.
- Repo rules: no attribution lines; stage files by name; `dune build --root .`; never skip or
  quarantine a test; a rewritten test is shown red first; merge `origin/main`, never rebase;
  log to deciduous; `specs/todos`, `specs/progress`, `CHANGELOG.md` (`### Added`) in the same
  PR; `specs/lang/` is edited, `docs/` is regenerated with `scripts/gen-lang-docs.py`.

## Questions for the owner

My recommendation is first in each, and the plan is written to it.

- **Q1. Is a public function's handle parameter checked at the function's definition in 8b?**
  The design (§7.2) says a bare handle parameter in a public signature *borrows*, and a
  function that keeps it must write `(BufReader needs h)` on its result.
  - *Recommended:* not in 8b. Every function, public or private, has its handle parameters
    inferred, and the error is reported where the scoped callback lets the handle out (through
    whatever it called). The written form `(T needs h)` and the definition-site rule move to
    8c with the other public-signature rules. Reason: the definition-site rule rejects any
    existing public function that wraps a handle it was given (`fn reader(h : File.Handle) :
    Reader`), which is not an escape, and §15 promises 8b adds no such error. It also means 8b
    needs one new piece of syntax (`scoped`) instead of two.
  - *Alternative:* do it now, as §18's test list has it. More code breaks in 8b, and 8b also
    has to parse `needs` inside a type.
- **Q2. When does the pass run?**
  - *Recommended:* inside the typechecker, for each function that refers to a function with a
    `scoped` parameter (by name, as a call or as a value), and for what those functions need.
    A program with no such reference does not run the pass. A crash in the pass is an internal
    compiler error with the usual report, never a silent accept.
  - *Alternative:* over every function of every build. 8a measured that at 0.1% to 2.8% of a
    check. It finds nothing more in 8b, since a tracked name only starts at a scoped use.
- **Q3. What if a scoped handle is passed into code the pass cannot follow** (a function value
  of unknown origin, a construct listed as "not tracked")?
  - *Recommended:* an error, with its own second line: "and is passed to `f`, which the
    compiler cannot follow (line N)". Anything else would let a handle out unseen. Builtins
    that take a handle and keep nothing (`file_read_line`, `socket_recv`, …) are followed, so
    ordinary reads and writes are not affected.
  - *Alternative:* accept it. No false alarm is possible, but the check has a hole.
- **Q4. Which stdlib functions get `scoped`?**
  - *Recommended:* `File.with_open`, `File.with_open_write`, `Socket.with_connection`: the
    three that hand a handle to a callback and close it. `HttpClient.with_connection` hands a
    *function* that holds the socket, which the design's `scoped` does not cover; it gets a
    todo. `File.with_lines` and `File.with_chunks` hand data, not a handle.
- **Q5. Is `scoped` a reserved word?** It is used as an ordinary name today
  (`stdlib/authority.march:187`, two test fixtures).
  - *Recommended:* contextual. It is the marker only in a type, directly before the parameter
    type of an arrow, on the same line. Everywhere else it stays a name.
  - *Alternative:* reserve it and rename the existing uses. Any user program with a `scoped`
    name stops parsing.

## Builder's calls

1. **A table store is always an escape**, even into a table created inside the callback: a
   named table outlives the callback. §7.1 says "a `Vault` made outside"; the pass does not
   know where a table was made.
2. **`Task.async` inside the callback is allowed and the task carries the name** (§9.2); a
   detached spawn, `spawn` of an actor and `send` are escapes.
3. **The name starts where the scoped function is referred to**, not only where it is called,
   so `let w = File.with_open` followed by `w(p, fn h -> h)` is still caught.
4. **A `mock` handler is not treated as an escape route.** No stdlib file or socket operation
   calls a mock handler with a handle. The Vault imprecision from phase 7 (every function that
   opens a table is `?`) does not block 8b under Q3's rule, because `?` alone holds no tracked
   name; it stays in the precision todo.
5. **The soundness proof for escape is a pair per route** (Task 6): the checker rejects the
   program, and with the check switched off by a test-only variable the same program runs and
   observes the closed handle. That shows every rejection is a real escape. The whole existing
   suite staying green shows no correct program is rejected.

## Review Focus

1. A scoped callback that is a named function (`File.with_open(p, helper)`), not a lambda:
   expected to be checked exactly like a lambda.
2. A handle that leaves two calls deep (`fn h -> keep(wrap(h))` where `wrap` builds a record and
   `keep` stores it): expected `capture_escape`, naming the store.
3. A callback that returns data read from the handle (`fn h -> File.read_line(h)`), or a
   `Result` or tuple of such data: expected accepted.
4. Nested scoped callbacks (`with_open` inside `with_open`), inner handle returned to the outer
   callback and used there: expected `capture_escape` for the inner handle only.
5. A program with `scoped` as a variable, parameter or function name: expected to parse and
   run as before.

---

### Task 1: `scoped` in the grammar and the typechecker's table

**Files:**
- Modify: `lib/ast/ast.ml` (`ty`, `show_ty`), `lib/parser/parser.mly` (`ty`),
  `lib/parser/parse.ml` (token filter, if the contextual form needs it), `lib/lexer/lexer.mll`
  (only if a token is added), `lib/typecheck/typecheck_types.ml` (env field),
  `lib/typecheck/typecheck.ml` (signature conversion), every exhaustive match on `Ast.ty` the
  compiler flags, `tree-sitter-march/grammar.js`, `specs/lang/surface-syntax.md`
- Test: `test/test_captures.ml`, `test/errors/` (one new slug via `scripts/seed-error-corpus.sh`)

**Interfaces:**
- Produces: `Ast.TyScoped of ty` (only ever the domain of a `TyArrow`); `show_ty` prints
  `scoped T -> r`. `env.scoped_params : (string, int list) Hashtbl.t`: function key (as in
  `fn_refs`) to the 0-based indices of its parameters whose type is an arrow with a scoped
  domain. Unification sees `TyScoped t` as `t`.

- [ ] **Step 1: failing tests.** In `test/test_captures.ml`:
  `test_scoped_parses` (`fn w(p : String, f : scoped File.Handle -> a) : a do ... end` checks
  clean, and `--dump-captures`-level API reports `scoped_params` = `[1]` for `w`);
  `test_scoped_is_still_a_name` (`fn scoped(scoped : Bool) : Bool do scoped end` and
  `let scoped = 1` check clean and run). A `test/errors` case `scoped_misplaced_1.march`:
  `fn f(x : scoped Int) : Int` → error "`scoped` marks the handle a callback receives; write
  it before the parameter type of a function type, as in `scoped File.Handle -> r`."
- [ ] **Step 2: run them red.** `scripts/run-tests.sh captures errors`. Expected: the three fail
  (parse error on `scoped File.Handle`).
- [ ] **Step 3: implement.** Contextual per Q5. `TyScoped` anywhere but an arrow domain is the
  `scoped_misplaced` error, reported by the typechecker's signature conversion. Menhir conflict
  count must not rise (record before and after in the commit message).
- [ ] **Step 4: tree-sitter.** Extend `grammar.js`; `scripts/check-tree-sitter.sh` passes with
  no new line in `known-failures.txt`.
- [ ] **Step 5: green.** `scripts/run-tests.sh captures errors compiler`; `scripts/check-docs.sh`.
- [ ] **Step 6: commit** (files by name).

### Task 2: tracked names in `Capture_set`

**Files:**
- Modify: `lib/caps/capture_set.ml`, `lib/caps/capture_set.mli`
- Test: `test/test_capture_set.ml`

**Interfaces:**
- Produces:
  ```ocaml
  type name = { label : string; id : int }   (* id: unique per scoped use *)
  val of_name : name -> t
  val names : t -> name list                 (* sorted by id; [] for unknown *)
  val without_names : t -> t
  ```
  `union` unions names. `covers ~sup x` is false when `x` has a name `sup` lacks, for every
  `sup` including `full` and `unknown`'s scope part (`unknown` still covers scopes).
  `narrow x ~by` keeps every name of `x`. `to_string` prints scopes, then name labels.
  `is_empty` is false for a set with a name.

- [ ] **Step 1: failing tests**: `full_does_not_cover_a_name`, `narrow_keeps_names`,
  `union_merges_names`, `prints_scopes_then_names` (`"IO.FileRead, h"`),
  `two_uses_same_label_are_distinct` (ids 1 and 2, label `h`: neither covers the other).
- [ ] **Step 2: red.** `scripts/run-tests.sh captures`. Expected: compile failure, `of_name` unbound.
- [ ] **Step 3: implement.**
- [ ] **Step 4: green**, and the existing `test_capture_set` cases unchanged.
- [ ] **Step 5: commit.**

### Task 3: handles carry a set

**Files:**
- Modify: `lib/typecheck/capture_ty.ml`, `lib/typecheck/capture.ml` (`builtin_flows`,
  `call_builtin`)
- Test: `test/test_captures.ml`, `test/captures/*.expected` (must not change)

**Interfaces:**
- Consumes: Task 2.
- Produces: `Capture_ty.handle_types : string list` = `File.Handle`, `Socket`, `Listener`,
  `Process`, `File.Dir` (§4.4; the builder adds any other builtin handle type the scoped opens
  of Q4 hand out). A value of one of these is `Con (k, [], Some sv)` instead of `Plain`, and a
  declared type that holds one gets a set by the rule 8a uses for arrows (§4.2).
  `Capture.retaining_builtins : (string * route) list` with
  `type route = Result | Table | Message | Detached | Actor | Registry | Untracked`: the
  builtins that keep an argument (table writes, `send`, detached spawns, actor spawn, the
  registries the precision todo lists). Every other builtin that takes a handle keeps nothing
  and returns `Plain` data.

- [ ] **Step 1: failing tests**: `handle_in_record_shares_set` (a record type with a
  `File.Handle` field built from a handle whose set has name `h` has `h`; reading the field
  gives it back); `handle_builtin_result_is_plain` (`file_read_line(h)`'s result has no set).
  Both build the name with a test-only seed on the binder, since Task 4 is not in yet.
- [ ] **Step 2: red.**
- [ ] **Step 3: implement.**
- [ ] **Step 4: green**; `git diff --stat test/captures/` is empty; `scripts/capture-cost.sh -n 5`
  pass column within 10% of the 8a numbers in the progress file (record both).
- [ ] **Step 5: commit.**

### Task 4: tracked names and escape positions in the pass

**Files:**
- Modify: `lib/typecheck/capture.ml`
- Test: `test/test_captures.ml`

**Interfaces:**
- Consumes: `env.scoped_params` (Task 1), Tasks 2 and 3.
- Produces:
  ```ocaml
  type escape = {
    e_name : S.name;               (* the handle *)
    e_open : string * Ast.span;    (* the scoped function referred to, and where *)
    e_route : route;
    e_at : Ast.span;               (* the value that leaves: the returned expr, the stored arg *)
    e_via : (string * Ast.span) list;  (* calls between the callback and the route, outermost first *)
    e_why : reason list;           (* why that value holds the name *)
  }
  ```
  and `escapes : escape list` on `Capture.result`, sorted by `e_at`.

Rules the implementer must hold to:
- Instantiating the scheme of a key in `scoped_params` (call or value, builder's call 3) makes
  one fresh `S.name` per scoped parameter and adds it to the set of that callback's handle
  parameter. Label: the lambda's parameter name when the argument is a lambda, else the
  parameter name of the named function passed, else `handle`.
- Escape positions, each recorded with its route when created: every set variable in the
  callback's **result** type; the stored argument of each `retaining_builtins` call; every
  argument of a call the pass does not model, and every argument of a call through a function
  value whose set is `unknown` (route `Untracked`).
- A scheme exports the escape positions its parameters can reach, so a callee that stores or
  loses its parameter is seen from the callback; instantiation copies them with the call
  appended to `e_via`.
- After the ground solve, each escape position whose solution holds a name yields one `escape`
  per name. A name inside its own callback's body is never an error.
- `analyse ~unsound:"escape"` (8a's test hook) reports no escapes: Task 6 uses it.

- [ ] **Step 1: failing tests**, one per route, each asserting route and the line of `e_at`:
  `escape_returned_handle` (`fn h -> h`), `escape_returned_closure` (`fn h -> fn () ->
  File.read_line(h)`), `escape_in_record`, `escape_table` (`Vault.put`), `escape_send`,
  `escape_detached_task`, `escape_actor_spawn`, `escape_via_helper_store` (Review Focus 2,
  `e_via` names `keep`), `escape_untracked` (Q3), `escape_first_class_open` (builder's call 3),
  `escape_named_callback` (Review Focus 1), `escape_nested_inner_only` (Review Focus 4).
  And accepted cases asserting `escapes = []`: `ok_read_inside`, `ok_result_of_data` (Review
  Focus 3), `ok_local_closure_called_inside`, `ok_local_record_inside`,
  `ok_task_awaited_inside`, `ok_handle_passed_to_helper_that_reads`.
- [ ] **Step 2: red.** Expected: all escape tests fail with `escapes = []`; the `ok_` tests pass.
- [ ] **Step 3: implement.**
- [ ] **Step 4: green.** `scripts/run-tests.sh captures`.
- [ ] **Step 5: commit.**

### Task 5: the diagnostic, in every mode

**Files:**
- Modify: `lib/typecheck/typecheck.ml` (`check_module_core`, `check_module_with_env`),
  `lib/typecheck/capture.ml` (reads impl methods and interface default bodies on the editor
  path), `lib/errors/` (slug, `--explain` page source), `bin/main.ml` only if a mode bypasses
  the two entry points
- Create: `test/errors/capture_escape_{1..7}.march` with `.expected` and `.json.expected`
  (`scripts/seed-error-corpus.sh`), `specs/lang/errors/capture_escape.md`
- Test: `test/test_captures.ml`, `test/run_errors.exe`

**Interfaces:**
- Consumes: `Capture.result.escapes` (Task 4).
- Produces: error slug `capture_escape`, header `CAPABILITY`. First line (§11.2):
  ``` `h` cannot leave the `File.with_open` callback, but <what> <route phrase>. ```
  Route phrases: `is returned` · `is stored in a table (line N)` · `is sent to an actor (line
  N)` · `is given to a detached task (line N)` · `is given to a spawned actor (line N)` · `is
  kept by `<builtin>` (line N)` · `is passed to `<f>`, which the compiler cannot follow (line
  N)`. `<what>` is `it`, `this closure captures it and`, or `the `<Type>` it is put in`. Notes:
  "`h` is a scoped handle: `with_open` closes it when the callback returns." and one "holds `h`
  because …" line per `e_why`, then one "through `<fn>` (line N)" per `e_via`. Help: "read what
  you need inside the callback and return the data instead."
  The pass runs for each function of the unit whose `fn_refs` include a key of
  `scoped_params`; an exception in it is an internal compiler error.

- [ ] **Step 1: failing tests.** Seven golden cases, one per route phrase. In
  `test/test_captures.ml`: `escape_rejected_in_every_mode` runs one program under `--check`,
  the interpreter, the REPL harness, `--compile` and `--target js` and requires exit 1 with
  `[capture_escape]` in each; `escape_in_impl_method_editor_path` (the escape is inside an impl
  method, checked through `check_module_with_env`); `no_scoped_reference_skips_the_pass`
  (`--timings` shows no `captures` stamp for hello world); `pass_crash_is_an_ice` (the
  test-only `MARCH_CAPTURE_FAULT=1` makes the pass raise; expected the ICE report and a
  non-zero exit, not a clean check).
- [ ] **Step 2: red.** Expected: goldens missing; every-mode test exits 0.
- [ ] **Step 3: implement.** No machine fix (there is no single obvious edit).
- [ ] **Step 4: green.** `scripts/run-tests.sh captures errors`; the internals lint in
  `run_errors` passes with `test/errors/internals-allowlist.txt` unchanged.
- [ ] **Step 5: commit.**

### Task 6: the stdlib opens, and the proof

**Files:**
- Modify: `stdlib/file.march:352`, `:377` (`f : scoped File.Handle -> a`),
  `stdlib/socket.march:413` (`f : scoped Socket -> Result(a, SocketError)`), their `doc`
  blocks, `specs/lang/` capability chapter (then `scripts/gen-lang-docs.py`),
  `test/test_capture_oracle.ml`
- Create: `test/captures/escape/<route>.march` (one per route of Task 4),
  `test/cap_conformance/scoped_handle_*.march` (accepted uses)

**Interfaces:**
- Consumes: everything above. `MARCH_CAPTURE_ESCAPE=off` (test-only, read once in the
  typechecker) maps to `analyse ~unsound:"escape"`.

- [ ] **Step 1: failing test** `escape_pairs` in `test/test_capture_oracle.ml`: for each
  `test/captures/escape/*.march`, (a) `march --check` exits 1 with `[capture_escape]`, and (b)
  with `MARCH_CAPTURE_ESCAPE=off` the program runs and prints `used after close: Err(Closed)`
  (each fixture uses the leaked handle after the callback and prints what it got).
  `stdlib_has_no_escape`: the pass forced over every stdlib function reports `escapes = []`.
- [ ] **Step 2: red.** Expected: (a) fails, the opens are not scoped yet.
- [ ] **Step 3: mark the three signatures.** Fix any stdlib or example caller the check
  rejects by returning data instead of the handle; list each one in the progress file.
- [ ] **Step 4: green**, then the full local gate: `scripts/run-tests.sh` (all suites),
  `scripts/check-docs.sh`, `scripts/check-tree-sitter.sh`,
  `scripts/oracle-base.sh all`. Expected: IR identical; types and refine differ only in files
  this branch touches.
- [ ] **Step 5: red proof of the pair test.** Remove `Table` from `retaining_builtins`,
  run `escape_pairs`: expected the table fixture fails at (a). Restore.
- [ ] **Step 6: commit.**

### Task 7: records

**Files:**
- Create: `specs/progress/2026-11-25-ocap-p8b-scoped-escape.md`,
  `specs/todos/2026-11-25-ocap-scoped-function-valued-callback-params.md`
  (`HttpClient.with_connection`), `specs/todos/2026-11-25-ocap-p8c-handle-borrow-rule.md` (Q1's
  deferred rule and `(T needs h)`)
- Modify: `CHANGELOG.md` (`### Added`), `git mv` the always-on prerequisites todo to
  `specs/progress/` with what was done for each bullet,
  `specs/todos/2026-11-24-ocap-capture-inference-precision-gaps.md` (what 8b changed),
  `scripts/affected.sh` and `scripts/test-affected.sh` if a new path needs a rule

- [ ] **Step 1:** write them; numbers from Task 3 Step 4 and Task 6 Step 4 go in the progress
  file.
- [ ] **Step 2:** `scripts/check-docs.sh` green.
- [ ] **Step 3: commit**, push, open a draft PR with the oracle results and the cost numbers in
  the body. Do not merge.
