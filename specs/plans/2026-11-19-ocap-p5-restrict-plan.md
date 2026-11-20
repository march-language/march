# Object capabilities, phase 5: `restrict` blocks and scope values — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `restrict SCOPE do ... end` narrows the current authority for a block and everything
it reaches, and `Scope` is a value type with `+` for union. Both behave identically in the
interpreter, `--jit`, the REPL, compiled code and JS. A program that uses no `restrict` compiles
to byte-identical IR.

**Architecture:** A `restrict` block is a phase-4 frame whose limit is `ByRestrict(where)`
instead of `ByFnNeeds(name)`. It reuses `Authority.enter_fn` / `cap_restore` for entry and exit,
the `$auth_layer` once-per-site layer cell for literal scopes, and phase 4's capture pass for
closures. Nothing new goes into the C runtime. The type checker treats a block with only literal
entries like a function `needs` clause: it proves the block's reach by kind. The TIR pass drops
the run-time frame where that proof is enough, using the same rule phase 4 uses for function
frames. A `Scope` value is an opaque box around the scope's canonical text, so a computed
`restrict` parses its text at entry. The parse is the same `Authority.parse` (and, natively,
the C `cap_rt_parse`) that frames use.

**Tech stack:** OCaml 5.5.1 (parser, type checker, TIR, interpreter), March (stdlib), JS emitter,
tree-sitter grammar. No C changes are expected.

**Spec:** `specs/2026-11-10-object-capability-design.md` §3, §5, §7, §8, §9, §15, §18 (the
`restrict` and scope-value lines), §19 items 8 and 10, and the phases table in §17 (row 5).
`restrict`'s syntax and meaning come from `specs/2026-11-09-dependency-grants-and-restrict-design.md`
§5, unchanged. This plan builds on phase 4 (`specs/plans/2026-11-15-ocap-p4-runtime-plan.md`).

## What phase 4 already gives us (read before Task 4)

- `stdlib/authority.march`: `Layer(CapLimit, text, scopes)`, `parse`, `enter_fn(layer)` (which
  pushes unless the same frame is on top) and `check_layers` (innermost refusal first).
  `CapLimit` already has `ByRestrict(String)`, and `limit_text` prints it as `the restrict at <w>`.
  `test/stdlib/test_authority.march:26-28` already pins `the restrict at main.march:12`.
- `lib/tir/auth_rt.ml`: `frames` decides whether a function is framed with the rule
  *scoped ∨ reaches an actor spawn ∨ reaches a call of a function value* (`reaches_actor_spawn`,
  `reaches_indirect_call`, `calls_value_under`). `captures` runs only when `has_frames`. A
  zero-argument fn whose name ends in `Tir_names.auth_layer_suffix` is built once per site by
  the LLVM emitter (`march_cap_layer_once`) and memoised by the JS emitter, and is never inlined.
- `lib/tir/auth_native.ml` retargets the policy functions to C for native and JIT code. It
  depends on the **short type names** `Layer Scope Arg CapLimit CapError Result List` not
  colliding (`Auth_native.applicable`).
- `lib/eval/eval.ml` `framed_call` shows how the interpreter enters a frame: it calls March
  `Authority.frame_layer`/`enter_fn` through `apply (lookup ...)`, and restores under `Fun.protect`.
- `March_ast.Cap_request.request_of_entries` turns `(name list * string option) list` (the
  `needs` AST encoding) into canonical text.
- `test/run_cap_conformance.exe` runs every fixture in five modes (interp, jit, compiled, js,
  repl), with `-- GRANT:` / `-- EXIT-ONLY` headers, `js_unsupported` and `repl_unsupported`.

## Global Constraints

- Authority inside the block is the intersection of the current authority and the scope.
  Nested blocks intersect further. Nothing widens. Any code may restrict itself; no `needs`
  line is required to write `restrict` (design §3, §9).
- Function values, tasks and actors **created** inside keep the narrowed authority after the
  block ends. Function values and pids **brought in** keep theirs (design §5, §9). There is no
  revocation.
- A scope value grants nothing. Its only use is as `restrict`'s argument (design §8). `mock`
  is phase 7.
- `IO.FileRead(e)` with a non-literal `e` has type `Result(Scope, ScopeError)`; with literals
  only, it has type `Scope` (design §8). An invalid computed argument (a `..` path segment, a
  malformed host) makes it `Err`.
- A literal `restrict` is checked at compile time, and the block's static reach is proved by
  kind. A computed `restrict` is checked at run time only (design §8).
- Refusals stay values: `Err(CapError(kind, target, ByRestrict(where), scope_text))`.
- Every runtime gives the same output (design §15). The JS target has no tasks or actors, so
  fixtures that need them go in `js_unsupported` with the reason "the JS target has no tasks".
- A program with no `restrict` compiles to byte-identical IR (`scripts/oracle-base.sh ir`), and
  the pure-compute benches stay within noise.
- Repo rules (CLAUDE.md):
  - Run `dune build --root .` in the worktree.
  - Stage files by name.
  - No attribution lines in commits or PR text.
  - Merge `origin/main`; never rebase or force-push.
  - Never skip or quarantine a test.
  - Update `specs/todos/`, `specs/progress/`, `CHANGELOG.md`, and `specs/lang/` (then run
    `scripts/gen-lang-docs.py`) in the same commit.
  - A parser change comes with the tree-sitter grammar, corpus and keyword allowlist.
  - A new `bench/*.march` is registered in `test/test_bench_gate.ml`.

## Decisions taken in this plan (for the owner to check)

1. **`Scope` is an opaque box around its canonical scope text.** It is `ptype Scope =
   ScopeText(String)` in a new `stdlib/scope.march` (`mod Scope`). The same-name rule
   (`Map(k, v)`) makes the type the bare `Scope` everywhere. `+` joins the two texts with
   `", "` and drops a `()` side, since a scope list is a union of its entries. A computed
   `restrict` parses the text at each entry; a literal one is parsed once per site. It is
   `Show`able as its text. It has no `Eq`, because text equality would be order-sensitive.
2. **The internal `Authority.Scope` is renamed `Authority.CapEntry`.** Otherwise the public
   `Scope` and the internal `Authority.Scope` would share a short name. That collision would
   make every program fall back from the C policy to the March one (`Auth_native.applicable`).
   Constructor tags do not change, so the C walk is unaffected. `Auth_native.shapes` and the
   comments in `runtime/march_authority.c` / `runtime/march_runtime.c` follow the rename.
3. **Scope expressions.** In expression position, a constructor written with a capability path
   (`IO.Console`, `IO.FileRead("./src/")`, `IO.NetConnect("api.x.com", methods(get))`) is a
   scope expression. Capability paths take precedence: no stdlib module declares a constructor
   under those paths.
   - The arguments follow the `needs` grammar. Strings come first; options (`methods(...)`,
     `prefix("...")`, `no_redirects`) must be literal.
   - Any string position may be an arbitrary `String` expression, which makes the entry
     *computed*.
   - All literal, or a `+` chain of all-literal entries: the type is `Scope`, validated at
     compile time with the `needs` validator (`invalid_cap_scope`).
   - Otherwise the type is `Result(Scope, ScopeError)`, and the arguments are validated when
     the value is built.
   - One classifier, `March_caps.Scope_expr.classify`, is shared by the type checker, `Lower`
     and the interpreter.
   - `ScopeError(String)` joins `CapError` in the Prelude. Its payload is the detail message.
4. **`+` on `Scope`.** A new constraint `CAdd t` (`t` is `Int`, `Float` or `Scope`) types `+`
   only; `-`, `*` and the rest keep `CNum`. An unresolved `CAdd` defaults to `Int`, as `CNum`
   does. The existing `+`-on-`String` diagnostic text does not change.
5. **Grammar:** `restrict e1, ..., en do block end`. It is an expression whose value is the
   block's value. Each `ei` is an expression, and `()` is the empty scope.
   - If every entry is a literal scope expression or `()`, the block is a **literal restrict**.
     Its text is `request_of_entries` of the entries.
   - Otherwise it is a **computed restrict**. Each entry must have type `Scope`; a `Result` is
     a type error with a hint to bind it with `let?`. At run time the entries are unioned.
6. **Static check.** A literal restrict's reach must lie within its kinds. Its reach is its own
   operations, its direct calls' rows, and lambdas made in the block (charged to the block, as
   a lambda is charged to the function that makes it). A violation is the new diagnostic
   `cap_restrict`: "`<op/callee>` needs `<kind>`, which the restrict at `<where>` does not
   allow". It gets a `--explain` page and corpus cases (`scripts/seed-error-corpus.sh`). The
   module ceiling applies unchanged. Listing a kind the module lacks is not a widening, so it
   is not an error.
7. **The run-time frame is dropped** for a literal restrict whose entries carry no scope and
   whose block reaches no actor spawn and no call of a function value: phase 4's rule, applied
   to the block. Every other restrict keeps its frame. The interpreter always enters the frame,
   as it does for function frames.
8. **`ByRestrict(where)`:** `where` is `<source basename>:<line>` of the `restrict` keyword,
   matching the existing doctest. Re-entering the same restrict while its layer is on top is a
   no-op: `top_is_frame` compares limit and text for any limit.
9. **`SessionTheory.restrict` is renamed `restrict_role`**, because `restrict` becomes a
   keyword. Its callers are internal to `stdlib/session_theory.march`. CHANGELOG `### Changed`.
10. **Deferred, each with a todo:**
    - `IO.Spawn(max(n))` as a separate budget in a `restrict`. The scope form does not exist
      yet, so append this to `specs/todos/2026-11-17-ocap-env-and-spawn-scopes.md`.
    - Compile-time checking of a literal *target* under a scoped literal restrict. Widen
      `specs/todos/2026-11-17-ocap-scoped-fn-needs-literal-check.md` to cover restrict.
    - A tail call out of a framed restrict body is not a tail call: the stack grows by one frame
      per hop, though the layer list does not. New todo.

## Performance approach and budget

| Path | Mechanism | Budget (checked by) |
|---|---|---|
| No `restrict` | The parser accepts one more keyword; `Auth_rt.restricts` finds no site and returns the module physically unchanged | `scripts/oracle-base.sh ir`: **zero** changed programs. Task 2 runs it after the rename |
| Pure compute | Unchanged | `scripts/perf-ab.sh` verdict `~` on cpu for `fib tree_transform binary_trees list_ops list_ops_nested json_stream`; counters identical |
| Literal, unscoped, frame dropped | The block is just its body | `bench/restrict_enter_static.march` within noise of the same loop without `restrict` |
| Literal, framed | One `$auth_layer` cell read, `enter_fn` (two string compares when re-entering, else one cons), one `cap_restore` | `bench/restrict_enter.march`: report ns/entry; target ≤ 50 ns |
| Computed | `Authority.parse` of the text at each entry, then the same as the framed case | `bench/restrict_enter_computed.march`: report ns/entry; target ≤ 2 µs for a two-entry scope |

The cost per entry is (bench wall time − the wall time of the same loop with the `restrict`
removed) / iterations, measured compiled at `--opt 2`. All numbers go into the PR body.

## Review Focus

1. **A closure made outside a `restrict` and called inside, including when the frame is
   dropped.** It runs under its outside authority. Pinned by `restrict_closure_outside_called_inside`.
2. **Recursion that re-enters the same framed restrict** (10,000 deep). Every check inside
   still answers from the same two layers, and the layer list does not grow. Pinned by
   `restrict_reenter_noop`.
3. **A panic inside a restrict caught outside it.** Authority after the catch is the outer
   authority. Pinned by `restrict_panic_caught_restores`.
4. **Hostile computed arguments**: `..`, an embedded `"`, `;`, `,`, `=`, an empty first string,
   and a malformed host. Each gives `Err(ScopeError(_))`, never a panic or a wider scope.
   Pinned by `scope_value_invalid_computed` and by the stdlib test in Task 2.
5. **`restrict ()`, and a union with `()`.** The empty scope admits nothing, and `s + ()` is
   `s`. A mixed entry list (a literal plus a computed value) is computed, and it is still
   enforced. Pinned by `restrict_unit_admits_nothing` and `restrict_mixed_entries`.

Not pinned, but expected and documented: a closure made inside a restrict *in module-level
code* captures nothing and runs under its caller's authority (design §21), so it never widens
the caller's authority.

---

### Task 1: The `restrict` keyword, `ERestrict`, formatter and tree-sitter

**Files:**
- Modify: `lib/lexer/lexer.mll` (`("restrict", RESTRICT)`), `lib/parser/parser.mly` (rule beside `if`'s: `RESTRICT; es = separated_nonempty_list(COMMA, expr); DO; b = block_body; END`)
- Modify: `lib/ast/ast.ml`: add `| ERestrict of expr list * expr * span` (entries, body, span of the whole; the `restrict` keyword's start is the span start)
- Modify: every exhaustive match over `Ast.expr` (`dune build --root . 2>&1 | grep -c "not exhaustive"` must reach 0); traversals recurse into the entries and the body. The formatter prints `restrict e1, e2 do ... end`
- Modify: `stdlib/session_theory.march`: `restrict` → `restrict_role` (and `restrict_bs`'s doc)
- Modify: `tree-sitter-march/grammar.js` (+ corpus case), `tree-sitter-march/keyword-allowlist.txt`
- Test: `test/test_compiler.ml` (parse tests), the formatter round-trip test file used for new syntax (find with `grep -ln "format.*round" test/*.ml`)

**Interfaces (Produces):** `Ast.ERestrict (entries, body, sp)`. Later tasks rely on the entries being parsed as ordinary expressions; `()` arrives as the parser's unit expression.

- [ ] Step 1: Write parse tests: `parse_restrict_literal` (`restrict IO.Console, IO.FileRead("/srv/") do f() end` gives `ERestrict ([ECon IO.Console; ECon IO.FileRead [..]], _, _)`), `parse_restrict_unit` (`restrict () do 1 end`), `parse_restrict_expr` (`restrict tools do 1 end` gives `[EVar tools]`), `parse_restrict_nested`, and `restrict_is_expression` (`let x = restrict () do 1 end`). Add a formatter round-trip case for each.
- [ ] Step 2: Run `scripts/run-tests.sh -q compiler`. Expect FAIL.
- [ ] Step 3: Implement. Rename the `SessionTheory` function. Run `scripts/check-tree-sitter.sh`.
- [ ] Step 4: Run `scripts/run-tests.sh -q compiler stdlib_march` and `scripts/check-tree-sitter.sh`. Expect PASS. Typechecking an `ERestrict` may still be a "not yet supported" error at this point (Task 3), but it must not crash.
- [ ] Step 5: Commit `ocap p5: the restrict keyword and ERestrict (parser, formatter, tree-sitter)`.

### Task 2: The `Scope` value in the stdlib, and the policy hooks

**Files:**
- Create: `stdlib/scope.march` (`mod Scope`, no `needs` line)
- Modify: `stdlib/prelude.march` (`type ScopeError = ScopeError(String)`, `derive Eq` and a `Show` that prints the detail)
- Modify: `stdlib/authority.march`: rename `Scope`→`CapEntry` (the type and every use, including doctests), add `restrict_layer`, and generalise `top_is_frame`
- Modify: `lib/tir/auth_native.ml` (`shapes`: `"Scope"` → `"CapEntry"`), the C comments that name the type, `test/test_authority_differential.ml` and any test that spells `Authority.Scope`
- Modify: the stdlib module count wherever `scripts/check-docs.sh` reports it stale
- Test: `test/test_scope_value.ml` (new, registered in `test/run_compiler.ml`; a stdlib-spanned fixture run interpreted, `--jit`, compiled and `--target js`, as `test/test_cap_runtime_slot.ml` does)

**Interfaces (Produces):**
- `Scope.union(a : Scope, b : Scope) : Scope`. It joins with `", "`, and a side whose text is `"()"` is dropped (`() + () = ()`).
- `Scope.to_string(s : Scope) : String`. `impl Show(Scope)` uses it.
- `@[stdlib_internal] Scope.literal(text : String) : Scope`. It is the target of a literal scope expression. The text was already validated at compile time.
- `@[stdlib_internal] Scope.build(kind : String, strings : List(String), options : List(String)) : Result(Scope, ScopeError)`. It is the target of a computed one. Each string must be non-empty in the first position and contain none of `"` `;` `,` `=`. The text is built as the parser would print it (`IO.FileRead("a", "b")`; options after the strings, as written) and must then pass `Authority.parse`. The `ScopeError` detail is `"<kind>: <reason>"`, where the reason is parse's message or `the string "<s>" contains <c>`.
- `@[stdlib_internal] Scope.text(s : Scope) : String`.
- `Authority.restrict_layer(where : String, text : String) : Layer`, which returns `Layer(ByRestrict(where), text, parsed)`. It panics with `internal:` on a parse failure, which cannot happen for a validated scope.
- `top_is_frame(layers, layer)` is true when the top layer's limit `==` the new layer's limit and its texts are equal, for every `CapLimit`.

- [ ] Step 1: Write the fixture and its expected output (the same in all four modes):
  - `Scope.to_string(Scope.union(Scope.literal("IO.Console"), Scope.literal("IO.FileRead(\"/srv/\")")))` prints `IO.Console, IO.FileRead("/srv/")`;
  - a union with `Scope.literal("()")` on either side prints the other side;
  - `Scope.build("IO.FileRead", ["/srv/" ++ "x"], [])` prints `Ok(IO.FileRead("/srv/x"))`;
  - `build` with `"../etc"`, `"a\"b"`, `"a;b"`, `""`, and `Scope.build("IO.NetConnect", ["bad host!"], [])` each print `Err(...)` with a detail starting `IO.FileRead: ` (or `IO.NetConnect: `);
  - `Authority.describe` of a check refused by a `restrict_layer("t.march:3", "IO.Console")` layer pushed with `enter_fn` prints `... refused by the restrict at t.march:3 (IO.Console)`;
  - pushing the same restrict layer twice leaves the layer count unchanged (print `List.length(cap_layers())`).
- [ ] Step 2: Run `scripts/run-tests.sh -q compiler` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run `scripts/run-tests.sh -q compiler stdlib_march` and `scripts/run-tests.sh test_jit`, and expect PASS.
- [ ] Step 5: Run `scripts/oracle-base.sh ir` and expect **zero** changed programs. If the rename changes any IR, find out why (for example, a type name inside a mangled symbol) and fix it before going on. This is the no-`restrict` IR guarantee.
- [ ] Step 6: Commit `ocap p5: the Scope value (union, literal, checked build) and restrict layers`.

### Task 3: Type checking: scope expressions, `+` on `Scope`, `restrict`, and the static reach check

**Files:**
- Create: `lib/caps/scope_expr.ml` + `.mli` (added to `lib/caps/dune` `modules`)
- Modify: `lib/typecheck/typecheck_types.ml` (`CAdd of ty`), `lib/typecheck/typecheck_builtins.ml` (`+` uses `CAdd`), `lib/typecheck/typecheck.ml` (constraint solving and defaulting next to `CNum` at :7437/:7461, `ECon` scope expressions, `ERestrict`), `lib/typecheck/typecheck_env.ml` (instantiation of `CAdd`; a `Restrict_block of string` `bound_origin`)
- Modify: `lib/typecheck/typecheck_caps.ml`: a literal restrict is recorded as a bound point keyed `<enclosing qname>$restrict@<line>:<col>` whose row is the block's own operations, direct calls and lambdas; validate the literal scopes with `validate_cap_scopes`; report unknown capabilities
- Modify: `lib/errors/code.ml` (`cap_restrict`) and the explain registry
- Test: `test/test_compiler.ml` (`scope_expr_*` classifier and typing unit tests), `test/errors/` (seeded with `scripts/seed-error-corpus.sh`: `cap_restrict_1` reach outside, `cap_restrict_2` a lambda made inside that reaches outside, `invalid_cap_scope_N` a malformed literal scope expression, `type_mismatch_N` a `Result(Scope, ScopeError)` given to `restrict`, whose hint names `let?`)

**Interfaces:**
- Consumes `Ast.ERestrict` (Task 1).
- Produces:
  ```ocaml
  (* March_caps.Scope_expr *)
  type entry = (Ast.name list * string option)            (* the needs encoding *)
  type form =
    | Literal of entry list                               (* () is Literal [] *)
    | Computed of { kind : string; strings : Ast.expr list; options : string list }
    | Not_scope
  val classify : Ast.expr -> form
    (* ECon of a known capability path with needs-grammar arguments; `+` of two
       Literal forms is Literal (concatenated); a computed string anywhere is
       Computed (only for a single entry: a `+` involving a Computed form is
       Not_scope, an ordinary `+` on Scope values); a non-literal option is
       Not_scope and the type checker reports invalid_cap_scope *)
  val restrict_text : Ast.expr list -> string option
    (* Some text when every entry classifies Literal (text by
       Cap_request.request_of_entries, "()" when empty); None when computed *)
  ```
- Types: `Literal` gives `Scope`; `Computed` gives `Result(Scope, ScopeError)`. `ERestrict (es, b, _)` has `b`'s type. A computed restrict requires each entry to unify with `Scope`.

- [ ] Step 1: Write unit tests:
  - `classify` of `IO.Console`, `IO.FileRead("/a/")`, `IO.NetConnect("h", methods(get))` gives `Literal` with the same entries the parser gives for `needs`;
  - `IO.FileRead(dir)` gives `Computed`;
  - `IO.Console + IO.FileRead("/a/")` gives `Literal` of two entries;
  - `Some(1)` gives `Not_scope`.
  - Typing tests: `let s : Scope = IO.Console` checks; `let r : Result(Scope, ScopeError) = IO.FileRead(d)` checks; `s + t` on two `Scope`s checks; `1 + 2` still defaults to `Int`; `"a" + "b"` keeps its exact current diagnostic.
  - Then seed the four error cases and write their programs.
- [ ] Step 2: Run `scripts/run-tests.sh -q compiler errors` and expect FAIL.
- [ ] Step 3: Implement. The static check reuses `check_fn_bounds`'s row machinery with the block as its own owner. The enclosing function's row still includes the block's reach, so nothing about the function changes.
- [ ] Step 4: Run `UPDATE_ERRORS=1 ./_build/default/test/run_errors.exe -e` only for the new cases (`ERRORS_ONLY=cap_restrict_,invalid_cap_scope_N,type_mismatch_N`), review `git diff test/errors/`, then run `scripts/run-tests.sh compiler errors` and expect PASS. Run `scripts/oracle-base.sh types` and expect no changed fixture.
- [ ] Step 5: Commit `ocap p5: type scope expressions, + on Scope, and restrict; prove a literal restrict's reach`.

### Task 4: Lowering and frames (native, `--jit`, REPL JIT, JS)

**Files:**
- Modify: `lib/tir/lower_state.ml`: `restrict_sites : (string, restrict_site) Hashtbl.t`, keyed by the layer fn name, with `type restrict_site = { rs_where : string; rs_text : string option (* None = computed *); rs_scoped : bool }`; reset with `fn_needs_tbl`
- Modify: the `Lower` expression lowering (`lib/tir/lower_expr.ml`):
  - scope expressions: `Literal` lowers to `Scope.literal("<text>")`, and `Computed` to `Scope.build(kind, [strings], [options])`;
  - `+` at type `Scope` lowers to `Scope.union`;
  - a literal `ERestrict` lowers to the shape below, adding the top-level fn `<encl>$restrict<N>$auth_layer() = Authority.restrict_layer("<where>", "<text>")`;
  - a computed one lowers to the same shape, with `l` bound to `Authority.restrict_layer("<where>", Scope.text(<union of entries>))`.
  ```
  let l = <layer>; let s = Authority.enter_fn(l); let r = <body>; cap_restore(s); r
  ```
- Modify: `lib/tir/auth_rt.ml` + `.mli`: `restricts : Tir.tir_module -> sites:(string, Lower_state.restrict_site) Hashtbl.t -> Tir.tir_module * bool`. It runs before `frames` and returns whether any frame was kept. A site whose `rs_text` is `Some _`, whose `rs_scoped` is false, and whose body neither calls a fn in `reaches_actor_spawn`/`reaches_indirect_call` nor has `calls_value_under` true is replaced by its body, and its `$auth_layer` fn is removed. With no sites it returns the module physically unchanged. `has_frames` for `captures` becomes `frames_kept || restricts_kept`.
- Modify: the three call sites of `Auth_rt.frames` (`bin/main.ml`, `lib/jit/repl_jit.ml`, the JS path) to run `restricts` first
- Test: `test/test_auth_rt.ml`, `test/snapshots/src/auth_restrict.march` (new TIR snapshot)

**Interfaces:** Consumes `Scope.*` and `Authority.restrict_layer` (Task 2), and the classifier (Task 3). Produces `Auth_rt.restricts` and `Lower_state.restrict_sites`.

- [ ] Step 1: `test_auth_rt.ml` cases on lowered TIR:
  - a module with no restrict is physically equal after `restricts`, and `kept = false`;
  - `restrict IO.Console do println("x") end` is dropped (the body remains, and no `$auth_layer` fn is left);
  - `restrict IO.FileRead("/a/") do ... end` is kept;
  - an unscoped literal restrict whose body calls `List.map(xs, f)` is kept;
  - an unscoped literal restrict whose body spawns an actor is kept;
  - a computed restrict is kept;
  - a lambda made inside a kept restrict gets a capture (`captures` with `has_frames = true`).
- [ ] Step 2: Run `scripts/run-tests.sh -q compiler` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run `scripts/run-tests.sh compiler codegen test_jit`. Add the snapshot with `UPDATE_SNAPSHOTS=1`, and review `git diff test/snapshots/` (only `auth_restrict` may change). Expect PASS.
- [ ] Step 5: Commit `ocap p5: lower restrict to a ByRestrict frame; drop the frame where the static proof suffices`.

### Task 5: The interpreter

**Files:**
- Modify: `lib/eval/eval.ml`:
  - a scope expression (via `Scope_expr.classify`) applies `Scope.literal` or `Scope.build`;
  - `ERestrict` builds its layer with March `Authority.restrict_layer(where, text)`, memoised per span for a literal and built at each entry for a computed one;
  - it enters the layer with `Authority.enter_fn` and restores the slot under `Fun.protect`, as `framed_call` does.
- Modify: the interpreter's `+` primitive. Find out how it dispatches. If it has no type information, add a case for a `Scope` value (`VCon ("ScopeText", [VString _])` or however the opaque value is represented) that applies `Scope.union`.
- Test: `test/test_eval.ml` cases

- [ ] Step 1: Write `test_eval` cases:
  - `restrict_refuses_computed_target_eval`: inside `restrict IO.FileRead("/srv/") do probe("IO.FileRead", "/etc/x") end`, the check describes `... refused by the restrict at <file>:<line> (IO.FileRead("/srv/"))`;
  - `restrict_union_eval`: `Scope.to_string(IO.Console + IO.Clock)` is `IO.Console, IO.Clock`;
  - `restrict_restores_after_eval`: after the block, the same probe is admitted.
- [ ] Step 2: Run `scripts/run-tests.sh -q eval` and expect FAIL.
- [ ] Step 3: Implement.
- [ ] Step 4: Run `scripts/run-tests.sh eval stdlib_march` and expect PASS.
- [ ] Step 5: Commit `ocap p5: restrict and scope values in the interpreter`.

### Task 6: Conformance fixtures across the five modes

**Files:**
- Create in `test/cap_conformance/` (a `.march` and an `.expected` each). Put each `restrict` inside a named helper fn, not in `main`'s body, so that the REPL mode (which types `main`'s body at the prompt) reports the same `<file>:<line>`. Probe with real operations or `Authority.check` only under **scoped** or computed restricts, because an unscoped literal restrict's frame is dropped natively. The fixtures:
  - `restrict_refuses_scoped`;
  - `restrict_nested_intersect` (one refusal attributed to each layer, innermost first);
  - `restrict_unit_admits_nothing` (computed `()`, plus a closure);
  - `restrict_computed_scope` (`let? s = IO.FileRead(dir)`, then `restrict s do`);
  - `restrict_mixed_entries`;
  - `scope_value_union` (`+` of a literal and a computed value; prints the texts);
  - `scope_value_invalid_computed` (prints each `Err`);
  - `restrict_closure_inside_called_outside`, `restrict_closure_outside_called_inside`, `restrict_named_fn_value_inside` (`List.map(paths, File.read)` inside the block keeps the narrowed authority);
  - `restrict_reenter_noop` (10,000 deep);
  - `restrict_panic_caught_restores` (mirror `panic_caught_restores_authority`);
  - `restrict_actor_restricted_for_life` (including across a supervisor restart);
  - `restrict_task_inherits`;
  - `restrict_under_grant` (with `-- GRANT:`: the refusal names the restrict when the restrict refuses and the launch when the launch does).
  - Add the actor and task fixtures to `js_unsupported` with the reason "the JS target has no tasks".
- [ ] Step 1: Write the fixtures. Generate the `.expected` files from the interpreter with `UPDATE_CAP_CONFORMANCE=1` **only after** checking each one by hand against the design rule it names. Put one line per fixture in the commit body: which rule it checks and the line that proves it.
- [ ] Step 2: Run `scripts/run-tests.sh cap_conformance`. Every mode must agree for every fixture (JS shows `SKIP` only for the listed ones). On a mismatch, fix the backend, not the fixture.
- [ ] Step 3: Prove the suite goes red on a deliberate break: make `Auth_rt.restricts` drop every frame, run the suite, and confirm `restrict_refuses_scoped` fails in compiled mode. Revert the break, and record the check in the commit body.
- [ ] Step 4: Commit `test: ocap p5 conformance fixtures for restrict and scope values`.

### Task 7: Benchmarks, IR proof, docs, specs, changelog, PR

**Files:**
- Create:
  - `bench/restrict_enter.march`: 1,000,000 calls of a fn whose body is `restrict IO.FileRead("/srv/") do n + 1 end`; prints the sum.
  - `bench/restrict_enter_static.march`: the same loop with `restrict IO.Console do n + 1 end`, whose frame is dropped.
  - `bench/restrict_enter_computed.march`: the same loop with `restrict s do n + 1 end`, where `s = IO.Console + IO.FileRead("/srv/")` is built once outside the loop.
  - Register all three in `test/test_bench_gate.ml` with their expected output.
- Modify:
  - `specs/benchmarks.md` (restrict changes → these three, plus `list_ops`);
  - `specs/lang/capabilities.md` (a `restrict` section, a scope-values section, `ByRestrict`, the static check and when a frame is kept), `specs/lang/surface-syntax.md` and `specs/lang/grammar.md` (the keyword and the rule); then run `scripts/gen-lang-docs.py`;
  - `CHANGELOG.md` `[Unreleased]`: `### Added` for `restrict` blocks and the `Scope` value type with `+`; `### Changed` for `SessionTheory.restrict` → `restrict_role`, and `restrict` now a reserved word;
  - the todos in decision 10. The tail-call one is new: `specs/todos/2026-11-19-ocap-restrict-tail-calls.md`.
- Create: `specs/progress/2026-11-19-ocap-p5-restrict.md`. Update `specs/todos/2026-11-12-ocap-capture-checking.md` if it names phase 5 as a dependency.

- [ ] Step 1: Write the benches, register them, and run `scripts/run-tests.sh -q` (bench gate).
- [ ] Step 2: Perf:
  - Run `scripts/perf-ab.sh --runs 15 --no-counter-gate --cand-dir . --benches "fib tree_transform binary_trees list_ops list_ops_nested json_stream println_loop" origin/main` and record the load average. Repeat once if any row is outside noise.
  - Measure the three restrict benches against a copy of the loop with the `restrict` removed (in the scratchpad, not committed), compiled `--opt 2`, at 11 interleaved runs each. Report ns/entry against the budget table.
  - Run `scripts/oracle-base.sh ir`: zero changed programs outside the new fixtures and benches.
- [ ] Step 3: Run `scripts/check-docs.sh`, `scripts/check-tree-sitter.sh` and the full `scripts/run-tests.sh`, and expect PASS.
- [ ] Step 4: Commit `docs/specs: ocap phase 5`. Merge `origin/main`, push, and open the PR with the perf and IR numbers in its body. Drive CI to green, mark the PR ready for review, and do not merge it.

---

## Self-review notes

- **Spec coverage:**
  - §9 syntax: Task 1. §9 meaning (intersection, nesting): Tasks 2, 4 and 5.
  - §9 values created inside versus brought in: the capture pass (Task 4), the interpreter (Task 5), and the fixtures (Task 6).
  - §9 spawn budget and no revocation: decision 10 and `restrict_closure_inside_called_outside`.
  - §8 scope values (type, `+`, `Result` for computed, validation): Tasks 2 and 3.
  - §8 "computed is checked at run time only; literal also statically": decisions 5–7, and Tasks 3 and 4.
  - §7 actors restricted for life, across restarts: `restrict_actor_restricted_for_life`.
  - §15 every runtime: Task 6. §18 restrict and scope-value lines: Task 6.
  - "Any code may restrict itself": no `needs` requirement (decision 6).
- **Types:** `restrict_site`, `Scope_expr.form`, `Scope.build` and `Authority.restrict_layer` are named the same in every task that uses them.
