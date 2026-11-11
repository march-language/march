# Ocap phase 2a: handle box, handle types, `@[stdlib_internal]` (2026-11-10)

Phase 2 Tasks 1-3 of `specs/plans/2026-11-10-ocap-p2-handles-plan.md` (Task 4, `File.Handle`,
is `2026-11-10-file-handle-api.md`). Shipped as phase 2a in march-language/march#1244; Tasks 5-14
are open as `specs/todos/2026-11-10-ocap-p2b-*.md`.

- **Runtime handle box** (`runtime/march_handle.c`, tag `MARCH_HANDLE_TAG` = -10, test
  `test/test_handle.c`): `[rc][tag][kind][raw][aux][state]`, state = closed bit, released bit,
  in-flight count, all CAS. Release happens exactly once, after the last in-flight use leaves;
  `close` takes an in-flight reference in the same CAS that sets closed, so a concurrent last
  `leave` cannot release (and reuse the descriptor number) before close's `shutdown`. Kinds
  1 FILE .. 9 PROCESS; TCP_BORROWED satisfies an expected TCP and releases nothing. UDP/TLS
  releasers register from `march_udp.c`/`march_tls.c`. A message copy shares the box.
- **Types and primitives**: builtin types `File.Handle`, `File.Dir`, `Socket`, `Listener`,
  `Process`; seven stdlib-only primitives `handle_new/enter/leave/close/detach/is_closed/aux`
  in the type checker, LLVM backend (all five types lower to one reserved TIR type `$Handle`)
  and interpreter (`VHandle`, `lib/eval/eval_handle.ml`). `==` on handles is `missing_impl`.
  `Channel.Socket` was renamed `Channel.ChannelSocket`. `canon_type_name` no longer folds
  `IO.Process` into `Process`, and a user type (variant, record or alias) named `Socket`,
  `Listener` or `Process` gets a module-qualified identity so it never unifies with, or is
  lowered as, the handle.
- **`@[stdlib_internal]`**: a stdlib `fn` with the attribute is refused (`stdlib_internal`) when
  referenced from user code, through a qualified call, a value reference, or any `use`/`alias`
  import (imports from user code skip such members; an explicit `use M.{f}` is the error). The
  gate checks the resolved binding, so a user module of the same name is unaffected. No stdlib
  function carries it yet (phase 2b Task 5 is the first).
- The raw builtins behind `File.Handle` (`file_open_write`, `file_write_handle`, `file_seek`) are
  stdlib-only. The older raw builtins stay public until phase 2b Task 10.
