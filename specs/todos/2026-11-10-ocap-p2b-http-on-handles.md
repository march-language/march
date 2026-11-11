# HTTP client and server on handles (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 6. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `HttpServer` `Conn` carries a borrowed `Socket` (TCP_BORROWED) instead of an `Int` fd; `HttpServer.fd` becomes `@[stdlib_internal]`; `HttpServer.test_conn`; the HTTP client uses `Socket`.
- Run the HTTP benchmark named in `specs/benchmarks.md` before and after.
