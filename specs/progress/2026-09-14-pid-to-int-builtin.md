# `pid_to_int(pid)`: the inverse of `pid_of_int`

Landed 2026-09-14, out of the distributed-actors work
([[2026-09-14-remote-send-to-a-global-pid]]): building a `GlobalPid` for a
local actor needs the actor's spawn index, and the only way to get it was to
parse `to_string(pid)` (`"Pid(N)"`), which both loopback fixtures did with a
`pid_int` helper.

## What shipped

`pid_to_int(pid : Pid(a)) : Int`, on both backends: the spawn index, the `N`
in the pid's `Pid(N)` display, so `pid_of_int(pid_to_int(p))` is `p`.

- Typecheck: `lib/typecheck/typecheck_builtins.ml`, next to `pid_of_int`.
- Interpreter: `lib/eval/eval_builtins.ml` (`VPid n -> VInt n`).
- Compiled: no new C symbol. `march_pid_index_of` already existed as the
  lowering's internal name (`pid_index_of`, used when a supervisor stores a
  child's pid in an `Int` state field); the surface name maps to the same
  symbol in `lib/tir/llvm_builtins.ml` with no second `PDeclare`, so the
  `test_codegen` preamble golden is unchanged. Registered in `defun.ml`'s
  builtin names and `borrow.ml`'s owned-actor family (the pid family stays
  owned until pid ownership is settled; see the comment there).

## Tests

- `test/test_stdlib_suite.ml` "pid_to_int round-trips with pid_of_int"
  (interpreter): the value is the display index, and `pid_of_int` of it is
  alive.
- Compiled: `test/native/node_send_loopback` and
  `test/native/peer_reader_loopback` now use it (the string-parsing helper
  is gone); both goldens unchanged.

Docs: the builtins table in `specs/lang/actors.md` and `docs/actors.md`.
