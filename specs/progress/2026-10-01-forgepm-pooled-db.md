# forgepm: real DB pool from compiled HTTP handlers (sub-project A, March side)

Logged 2026-10-01. Design: `specs/2026-10-01-forgepm-pooled-db-design.md`.

March side: a wired native fixture `test/native/pooled_actor_http.march` driven
from `test/test_http_native.ml` that proves a depot-shaped actor Pool (heap
payload reply, `task_spawn(actor_call)` from HTTP pool/evloop pthreads) works
under 32-way concurrency with flat RSS, in both server modes. Replaces the
never-wired `test/native/foreign_actor_http.march`. Any runtime hang or
corruption it surfaces is in scope.

forgepm side (separate repo): `Repo.with_conn` and `Packages.pkg_exec` use
the depot Pool `Application.start` already creates, with fallback to
connect-per-query; acceptance script per the design.

Siblings not started: B (HTTP handlers as green threads,
`specs/2026-07-09-http-handlers-as-green-threads.md`), C (root-cause the
reverted Vault-slot pool's ~1.6 MB/request leak).

Landed 2026-10-01 (March side): `test/native/pooled_actor_http.march` +
`run_pooled_e2e` in `test/test_http_native.ml`, both server modes, in
`run_stdlib.exe`. forgepm side tracked in the forgepm repo (Part 2 of the
plan `specs/plans/2026-10-01-forgepm-pooled-db.md`).
