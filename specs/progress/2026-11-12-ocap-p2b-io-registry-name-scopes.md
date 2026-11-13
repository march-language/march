# `IO.Registry`, and name-checked lookups (2026-11-12)

Ocap phase 2b, Task 12 of `specs/plans/2026-11-10-ocap-p2-handles-plan.md` (logged as a
todo 2026-11-10). Spec: `specs/2026-11-10-object-capability-design.md` §6 ("Lookups by
name are opens").

- **New kind `IO.Registry`** (child of `IO`) in `lib/caps/cap_lattice.ml`, the C table
  (`runtime/march_cap_lattice.c`, regenerated), `builtin_types`, `builtin_cap_table`
  (`actor_register`, `actor_unregister`, `actor_whereis`, `actor_registered`),
  `lib/caps/cap_symbols.ml` and `lib/refinecheck/cap_infer.ml`. `stdlib/actor.march`
  declares `needs IO.Registry` beside its `needs IO`. A caller's missing-capability error
  carries the existing generic machine fix (insert `needs IO.Registry`, and widen `main`'s
  grant), which is how the three in-repo callers that lacked `needs IO` were migrated
  (`bench/actors/spawn_churn.march`, `test/native/actor_registry_retire_vault.march`,
  `test/native/observe_types_hr.march`).
- **Name scopes** `needs IO.Mut("sessions")`, `needs IO.Registry("logger", prefix("worker."))`:
  `lib/caps/name_scope.ml` (`parse` decodes Task 11's one-string encoding itself, since
  `Host_scope.split_options` refuses digits and dots; `admits`; `subsumes`). Validated in
  the `DNeeds` arm of `typecheck.ml` (`invalid_cap_scope`).
- **The check** (`check_name_scopes` in `lib/typecheck/typecheck_caps.ml`, table
  `name_arg_fns`): calls of the stdlib wrappers `Vault.new/open/whereis` and
  `Actor.register/unregister/whereis` (and the raw builtins user code can still name) in a
  module whose OWN `needs` scopes the kind. A literal outside the scope, a computed name
  ("cannot prove ... the check at run time arrives with phase 4") and a name-taking function
  used as a value are `cap_scope_violation`; `Actor.registered` under a scoped
  `IO.Registry` is refused. Scopes are read from the module's own `DNeeds`, not
  `env.mod_need_scopes`, so a nested module's scope is judged (unlike path scopes,
  `specs/todos/2026-11-10-nested-path-scope-unchecked.md`).
- **One surface form per encoding** (review ruling R16), enforced in the parser where the
  forms still differ: only `methods(...)` takes identifiers, `methods` takes no string,
  there is no `name(...)` option, no scope string may contain `;`, and an empty first
  string may not be followed by more. The formatter therefore prints every accepted scope
  back to itself (idempotence and escape test in `test/test_host_scope.ml`).

Not done here: a call reached through an `import Actor` / alias (`register(pid, "x")`) is
not matched by name, and a run-time check of computed names is phase 4.
