# `IO.Registry`, and name-checked lookups (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 12. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- New capability kind `IO.Registry` for `actor_register`/`unregister`/`whereis`/`registered`; name scopes for `IO.Registry` and the `IO.Mut` lookups (`lib/caps/name_scope.ml`, a `name_arg_fns` literal-name scan beside `path_arg_builtins`).
