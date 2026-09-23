# Parameterised actor `init` (D24)

**Landed:** 2026-09-22. Decision **D24** of
[`../plans/2026-09-21-distributed-authority-and-deploys-plan.md`](../plans/2026-09-21-distributed-authority-and-deploys-plan.md)
(decisions table; section 4.1 "Stateful roles are bound to an actor"; II.3
"Parameterised `init` (D24)"), a prerequisite of build step 3
(`specs/todos/2026-09-22-dd-step03-level0-generated-main.md`).

## What

- `actor A do state {…} init(env : T, n : Int) { … } … end`: `init` takes zero
  or more **typed** parameters, in scope in the init expression (and in the
  supervise block's child `init` arguments) and nowhere else. `init()` is the
  zero-parameter spelling of the bare `init { … }` form.
- `spawn(A, e1, …)`: the arguments are checked against the `init` signature.
  Arity mismatches name the signature (`actor A's init takes 2 arguments, but
  spawn(A) supplies 0. Its signature is init(start : Int, label : String) { … }`);
  extra arguments on a param-less actor get a hint on how to declare params.
- Supervised children: `Worker w(expr, …)` in a `supervise` block. The
  arguments are evaluated once in the supervisor's spawn glue and re-supplied
  verbatim on every respawn.
- State migration / `@compat`: unaffected. The `.schemas.json` writer records
  an init-param actor's STATE fields only, and `--check-migration` runs over
  such a module (pinned by the `actor_init_params_schema` dune rule).

## How

- **Grammar** (`lib/parser/parser.mly` `actor_init`/`init_param`; `spawn` and
  `supervise_child` productions). `init` immediately followed by `(` is a
  distinct token, `INIT_PAREN`, produced by the token filter's one-token
  lookahead (the same mechanism as its soft-keyword demotions, promoting instead
  of demoting): `init ()` followed by an expression start is otherwise an LR(1)
  shift/reduce conflict with the unit literal as a bare init expression. The
  grammar stays at its 11-conflict baseline. `INIT_PAREN` is also a
  `soft_lower_name`, so a function named `init` can still be called. A
  parenthesised bare init (`init (mk())`, never written in the corpus) is now
  read as a parameter list and rejected with a hint.
- **AST**: `actor_def.actor_init_params : param list`;
  `supervise_field.sf_init_args : expr list`. `ESpawn` keeps its shape: the
  arguments ride as the actor-name constructor's args (`ESpawn (ECon (A, args))`),
  so the ~80 generic expression walkers (LSP, lint, refactor, refinement, caps)
  see them without change.
- **Typecheck**: `env.actor_init_sigs` (shared table) records each actor's
  parameters; `check_spawn_args` checks `spawn` sites and child specs against
  it. Init params are bound with `bind_lam_param`, like handler params.
- **Lowering** (`lower_actor.ml`): `<A>_spawn` takes the params; the init
  expression and child args lower with the params registered in
  `_fn_param_types` (the alias shield). A child's args are bound once to
  `$sup_init_arg_<f>_<i>`; the first spawn calls `<Child>_spawn` with them, and
  registration passes a zero-arg **respawn closure** (`$respawn<N>`, a lifted
  lambda whose captured environment is exactly those vars) instead of the static
  spawn reference. `lower_expr.ml` passes `spawn`'s args; `cap_passing.ml` now
  matches the spawn-glue shapes by shape, not zero arity.
- **Runtime**: no change was needed. `march_respawn_child` already calls
  whatever closure cell `march_actor_register_child` holds (the mechanism
  `cap_passing.ml` uses for capability-carrying respawns), incs it before every
  call, and the registration takes ownership of the cell; the captured
  arguments are the "init argument held beside the spawn pointer" the plan
  asked for, with the RC discipline already proven by
  `cap_mock_supervised_nested`. Actor refcount words are untouched.
- **Interpreter**: `actor_inst.ai_init_args`; `eval_actor_init_state` binds the
  params (arity-checked, which also covers the dynamic `Supervisor.spec` path);
  `spawn_child_actor` re-supplies the crashed incarnation's args.
- LSP scope analysis, capability scans and refinement checking bind the init
  params (refinements stripped: a spawn site is not an obliged position).

## Tests

- `test_compiler`: accept (params used in init, `init()`), missing/extra
  args, wrong arg type, untyped param rejected, child-spec arity.
- `test_eval`: spawn with args, read back through handlers.
- `test_supervision`: interpreted restart keeps the child's init argument.
- `test_codegen`: IR shape (spawn glue signature, lifted respawn thunk).
- `test/native/actor_init_params`, `test/native/supervisor_init_arg_restart`
  (two restarts of the same slot), each compiled AND interpreted;
  `test/native/actor_init_params_schema` (`.schemas.json` + `--check-migration`).
- TIR snapshots: the corpus has no actor program, so no golden moved.

## Not covered / notes

- ASAN on this host hangs before printing for the pre-existing
  `supervisor_one_for_all_restart` fixture too (0 bytes of output, killed by
  alarm), so the multi-restart closure path was verified plain (three restarts,
  a String argument) but not under ASAN here.
- A snapshot-restored interpreter instance carries no init args.
