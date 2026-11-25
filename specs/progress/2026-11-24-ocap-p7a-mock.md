# Object capabilities, phase 7a: `mock` blocks and the checked witness APIs (2026-11-24)

Plan: `specs/plans/2026-11-24-ocap-p7-mock-plan.md` (Tasks 1–6; the owner approved
every recommended answer, Q1–Q8). Design: `specs/2026-11-10-object-capability-design.md`
§7, §12, §14, §17 row 7, §21.

## What landed

- **`mock SCOPE with HANDLER do ... end`** (test builds only; `mock_outside_test`
  elsewhere). Parser/lexer (`MOCK`, a reserved word), `Ast.EMock`, every AST walker, the
  formatter, tree-sitter.
- **The mock is a layer of the current authority**: `Layer(ByMock(id), text, scopes)`,
  with `id` naming the handler record in a mock registry (`mock_register` /
  `mock_lookup`: C runtime, interpreter, JS). `Authority.first_refusal` (and the C port,
  `march_cap_rt_check_layers`) treats a mock as never refusing and as admitting an
  operation it covers (an entry of exactly the operation's kind admitting its target).
  `Authority.mock_for`, `check_unmocked`, `mock_fallthrough`. Capture is the phase-4
  capture: closures, tasks, actors and supervised restarts inside keep the mock; a program
  with a mock turns on `Auth_rt.captures`.
- **Interception**: `Lib/tir/mock_dispatch.ml` routes each interceptable builtin call to
  the generated wrapper `__march_dispatch_<op>` in test builds (compiled, JS, and the
  JIT, whose test-build prelude carries the wrappers); the interpreter intercepts in
  `Eval.apply_inner`'s builtin arm. One target table, `March_caps.Mock_target`.
- **Handler typing**: the kind's operation record (`Io_ops_gen.mock_fields`); a record
  literal in the `with` position names only the fields it overrides (`Lower.lower_mock`
  completes it from `__march_ops_empty_<Kind>`). `mock_scope_invalid`,
  `mock_handler_field`.
- **Vault mocks**: `mock IO.Mut(...) with { open: ... }` gives covered table names a
  private namespace per mock (`Vault.table_name`), and the `open` hook can fail an open.
  An empty record does not parse, so an isolation-only vault mock is
  `with { open: None }` (the plan wrote `with {}`).
- **Removed**: `Cap_passing` (the capability-passing TIR pass), `with_cap`, `cap_impl` /
  `cap_ops_empty` on IO capabilities, `march_set_actor_caps` / `march_actor_caps` and the
  supervisor's spawn-capability carry-over.
- **New kinds** `IO.Cluster` (under IO), `Actor.Introspect`, `Actor.Debug` (roots).
  `Actor.introspect()`, `Actor.debug()`, `Actor.pid_from_int(n)`, `Session.attach(ops)`,
  `ClusterNode.attach(ops)` are checked operations returning `Result(_, CapError)`;
  `ClusterNode.start(cfg)` keeps its `String` error. They are charged statically through
  `Typecheck_builtins.witness_entry_caps`, and the main-grant / bound / grant checks judge
  every lattice kind (`Cap_lattice.is_authority`), not only `IO`'s. The REPL requests
  `IO, Actor.Introspect, Actor.Debug`. The stdlib may name `root_cap` (to mint after the
  check). Callers across the corpus migrated (about 465 call sites).

## Tests

`test/cap_conformance/mock_*` (capture, task, actor, admits-handled, unhandled-refused,
restrict-inner, scoped, value ops, vault, vault open fails: every mode that supports
them), `test/cap_mock/*` rewritten to `mock`, `test/test_cap_dict.ml` (typing, the TIR
rewrite, no wrappers in a release build), `test/test_authority_differential.ml` (the mock
layer in the March policy and the C port), error-corpus cases and `--explain` pages for
the three codes (`-- MARCH-MODE: test` runs `--check --test`).

## Left for 7b

`specs/todos/2026-11-22-ocap-phase-7-mock-and-retire-cap-params.md`.
