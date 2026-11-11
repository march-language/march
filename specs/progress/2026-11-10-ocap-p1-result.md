# Object capabilities, phase 1: capability operations return Result(T, CapError)

Plan: specs/plans/2026-11-10-ocap-p1-result-plan.md. Design:
specs/2026-11-10-object-capability-design.md (§15). Owner decision 2026-11-10:
strict `Result(T, CapError)`; an operation that already returned `Result(U, E)`
returns `Result(Result(U, E), CapError)`.

## What landed

- `CapError(kind, target, limit, limit_scope)` and `CapLimit` (`ByLaunch`,
  `ByFnNeeds`, `ByModNeeds`, `ByRestrict`, `ByGrant`) in the Prelude;
  `stdlib/authority.march`: `check`, `describe`, `must`, `ignore`.
- One run-time check point, `cap_check_raw(kind, target) : Int` plus
  `cap_launch_text()`, in the C runtime (runtime/march_extras.c, shared by the
  JIT), the interpreter and the JS runtime. Nothing refuses yet except the
  test-only `MARCH_TEST_REFUSE` hook (exact kind match); phase 4 replaces it.
- `lib/caps/cap_ops.ml`: every capability builtin classified as a checked
  operation, a use of an opened value, or internal plumbing, with a freshness
  test; stdin reads charged to IO.Console.
- Re-typed entry points: console, clock, random, process/environment, spawns,
  table opens, signals, files/dirs/CSV/Seq, `Socket.connect*`, `Dns.resolve*`
  (CHANGELOG lists them).
- `test/test_cap_check_coverage.ml`: a stdlib function calling a checked
  builtin must call `Authority.check` or carry an allowlist reason.
- `test/run_cap_conformance.ml` (suite `cap_conformance`): every fixture
  interpreted, through the JIT, compiled and as JS must print the same.
- Diagnostic `cap_result_unhandled` with machine fixes; `forge fix PATH...`
  with `--only`; `forge fix` keeps final newlines; the REPL does not echo a
  console operation's `Ok(())`.
- Three benches (`println_loop`, `clock_loop`, `spawn_loop`).

- Fixed on the way: the token filter peeked the token after `match`/`choose`
  without restoring the lexbuf positions, so menhir gave the keyword the
  peeked token's start and an `EMatch` span began at its scrutinee. The
  `cap_result_unhandled` fix for a trailing `match` was then spliced in after
  the keyword. `peek_keeping_pos` (lib/parser/token_filter.ml) restores them;
  eight error-corpus carets moved to the keyword.

## Not done here (each has a todo)

- Gate on raw capability builtins: specs/todos/2026-11-10-ocap-p1-gate-raw-capability-builtins.md.
- UDP, TLS contexts, HttpTransport/HttpClient, HttpServer; HttpError's refusal
  variants: specs/todos/2026-11-10-ocap-p1-network-opens-deferred-to-p2.md.
- Found on the way, pre-existing: specs/todos/2026-11-10-user-fn-named-show-hijacks-prelude-println-compiled.md.

## Things to know

- The stdlib `.march` test runner does not typecheck, so a type change shows
  there as a runtime panic or a wrong assert, not a type error.
- A `match` over a nested result with only `Ok(_)`/`Err(_)` arms still
  typechecks but now means "permitted"/"refused"; no fix can tell. Review those
  by hand.
- Stdlib diagnostics are filtered from user compiles; every stdlib change was
  checked with `march --check stdlib/<file>.march` against a per-file baseline
  (checked file inside MARCH_STDLIB, or the counts differ).
