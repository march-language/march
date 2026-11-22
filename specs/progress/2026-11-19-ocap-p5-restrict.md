# ocap phase 5: `restrict` blocks and `Scope` values

Plan: specs/plans/2026-11-19-ocap-p5-restrict-plan.md. Design:
`specs/2026-11-10-object-capability-design.md` §3, §5, §7, §8, §9, §15, §18, §17 row 5 (syntax
and meaning of `restrict` from `specs/2026-11-09-dependency-grants-and-restrict-design.md` §5).
Language reference: `specs/lang/capabilities.md`, "Narrowing a block: `restrict`" and "Scope
values".

`restrict SCOPE, ... do ... end` narrows the current authority for a block and everything it
reaches, and `Scope` is a value type with `+` for union. Both behave the same in the
interpreter, `--jit`, the REPL, compiled code and `--target js`.

## What landed, by task

- **Task 1, syntax.** `restrict` is a reserved lexer keyword; `restrict e1, ..., en do block
  end` parses to `ERestrict (entries, body, span)` (expression and lambda-body rules), with the
  formatter, the tree-sitter grammar and corpus. `SessionTheory.restrict` became
  `restrict_role`.
- **Task 2, the value.** `stdlib/scope.march`: `opaque type Scope = ScopeText(String)` holding
  canonical scope text; `union` (`+`), `literal`, `text`, `to_string`/`Show`, and the checked
  `build` (escapes `\`, rejects `"` `;` `,` `=`, a computed `..` path segment and a malformed
  host). `ScopeError(String)` is in the Prelude. The internal `Authority.Scope` is renamed
  `Authority.CapEntry` so the short name `Scope` stays unique for `Auth_native.applicable`.
  `Authority.restrict_layer(where, text)` builds a `ByRestrict` layer; `top_is_frame` compares
  limit and text for any limit, so re-entering a restrict already on top pushes nothing.
- **Task 3, types and the static check.** `March_caps.Scope_expr.classify` (shared by the type
  checker, `Lower` and the interpreter) decides literal vs computed scope expressions. A literal
  is `Scope`, validated like `needs` (`invalid_cap_scope`); a computed one is
  `Result(Scope, ScopeError)`. `+` gets the constraint `CAdd` (`Int`, `Float` or `Scope`). A
  literal restrict's reach is proved by kind like a function `needs` clause (its operations, its
  direct calls' rows, lambdas made in it); a violation is `cap_restrict` with a `--explain`
  page and corpus cases. A `Result` entry is a type error with a `let?` hint.
- **Task 4, lowering.** `ERestrict` lowers to a phase-4 frame with limit `ByRestrict(where)`
  (`where` = source basename and line of the keyword). A literal restrict's layer is a
  once-per-site `$auth_layer` fn (`march_cap_layer_once` natively, memoised in JS); a computed
  one unions its entries and parses the text at each entry. `Auth_rt.restricts` drops the frame
  for a literal restrict with no scoped entry whose block reaches no actor spawn and no call of a
  function value; `captures` makes values created inside a kept restrict save the narrowed
  authority.
- **Task 5, the interpreter.** `eval.ml` enters every restrict through `Authority.enter_fn`,
  restores under `Fun.protect`, memoises literal layers per site, and evaluates `+` on scopes.
- **Task 6, conformance.** 15 new fixtures under `test/cap_conformance/` (`restrict_*`,
  `scope_value_*`) plus the accept twin of `restrict_reach` in `cap_mode_parity`, each run in
  interp, jit, compiled, js and repl, with three JS and one REPL exclusion for tasks/actors and
  `file_read`. Found and fixed: REPL-loaded files lexed without
  their file name (refusals read `.:18`), and `Scope.build` accepting a computed `..`.
- **Task 7, benches, docs, changelog.** `bench/restrict_enter.march`,
  `restrict_enter_static.march`, `restrict_enter_computed.march`, gated in
  `test/test_bench_gate.ml` and mapped in `specs/benchmarks.md`. The capability chapter gained
  the `restrict` and scope-value sections; `surface-syntax.md` and `grammar.md` the form and the
  keyword.

- **Final-review fixes.** (F1) The literal-restrict reach check charged prints with
  `IO.FileRead` when the enclosing function was named `go`: `free_vars_block` (and the
  restrict walker and `Cap_rows.seed_of_body`) did not put a local `fn` in scope for the rest
  of its block, so every stdlib local `fn go` loop was recorded as a call of the program's
  top-level `go` and that function's kinds leaked into `println` and every helper reaching such
  a loop (also into `needs` bounds and `march caps`). Pinned in `test_restrict_reach`,
  `test/errors/cap_restrict_3`, and `restrict_refuses_scoped`'s `go` helper; plus the missing
  pins (inner restrict past outer, interface method, actor spawn, `IO.Console + 1`). (F2, F3)
  The chapter now says a closure made in a module-level `restrict` captures nothing, and that
  only direct calls of module-level functions are charged to a block while a lambda or local
  `fn` made before it is a value brought in; fixtures
  `restrict_module_level_closure_captures_nothing` and `restrict_local_fn_brought_in`. (F4)
  The `Authority.check` caveat covers a call through a helper. (F6) `cap_restrict`'s help for
  a function used as a value or a spawn names that use (`cap_restrict_4`). (F7) The `let?`
  hint renders the entry as written (`type_mismatch_59`). (F8) `record_restricts` skips a body
  with no `restrict` before its scope walk.

## Performance (macOS arm64, 14 cores, against merge-base 7552b97ec)

- `scripts/perf-ab.sh --runs 15` over `fib tree_transform binary_trees list_ops
  list_ops_nested json_stream println_loop` against origin/main 31f84bfcd (load 5.3 at start,
  4.1 at end): all seven within noise on cpu, allocation counters identical.
- Restrict entry, 11 interleaved runs each against a copy with the `restrict` removed, `--opt
  2`, load about 3.3: literal framed about 13 ns per entry (budget 50 ns), computed about 380 ns
  (budget 2 µs), frame dropped within noise (2 ns on medians, 0.1 ns on minima).
- IR: a program with no `restrict` compiles to the same IR after normalising fresh-name digits
  and constructor-id offsets (every stdlib addition shifts the global counters); the only real
  diffs are in programs that already had phase-4 frames (`__march_eq_CapLimit` from
  `top_is_frame`'s `==`, drop glue `List_Scope` → `List_CapEntry`). The classification is in the
  PR description.

## Deferred

- Spawn budget in a `restrict`: `specs/todos/2026-11-17-ocap-env-and-spawn-scopes.md`.
- Literal targets under a scoped literal restrict checked at compile time:
  `specs/todos/2026-11-17-ocap-scoped-fn-needs-literal-check.md`.
- Tail calls out of a framed restrict body: `specs/todos/2026-11-19-ocap-restrict-tail-calls.md`.
- Perf and coverage minors: `specs/todos/2026-11-19-ocap-p5-restrict-follow-ups.md`.
- By design: `Authority.check` inside a frame-dropped restrict (directly or through a helper)
  is not narrowed in compiled code (the block's real operations are proved statically); a literal `..` follows the
  `needs` grammar (folded lexically) while a computed one is a `ScopeError`.
