# `[P2]` `get_actor_field` is an unchecked cast: `Pid(a) -> String -> Option(b)` with `b` free

Filed 2026-09-24 by the distributed-deploys review (while checking step 2's
"no other forging path"). Pre-existing: older than #594, and outside the
reviewed range. Filed because it undermines D31's claim that references cannot
be manufactured.

## Defect

`lib/typecheck/typecheck_builtins.ml:942` types `get_actor_field` as
`Pid(a) -> String -> Option(b)` with `b` unconstrained. It reads any actor
field as any type.

## Confirmed

A `Box` actor stores `pid_to_int(v)` in an `Int` field. The program reads it
back as a `Pid` and sends to it. `--check` exits 0. Interpreted: runtime error
"send: first argument must be a Pid or Cap, got 0". Compiled: `march: fatal
SIGBUS … addr=0x19`, rc 138. It did not produce a working forge, because a
compiled pid is an actor pointer, but it is memory-unsafe and re-types any pid
already held.

## Fix I would make

Tie `b` to the field's declared type when the name is a literal, which the
typechecker knows. Otherwise restrict the public version to a fixed result
type and make the polymorphic one stdlib-only.

---

## Fixed 2026-09-25

`get_actor_field` is now `Pid(a) -> String -> Option(Int)` (typecheck_builtins; the
LLVM builtin table's return type matches). Both backends return `Some` only for an
immediate field (`'i'` kind: Int/Bool/Unit/Atom; the interpreter maps Bool to 0/1 and
Unit to 0) and `None` for any pointer or float field, so the result can never be a
disguised pointer. The review's repro (a pid stored as `pid_to_int` read back as a
`Pid` and sent to) no longer typechecks. Every caller in the repo (stdlib topology,
supervisor/actor native tests, examples, bench) reads an Int field; the suites stay
green.

This also removes half of `2026-09-24-get-actor-field-pid-and-result-ownership.md`:
a boxed field is no longer returned at all, so there is no unowned reference to hand
back. The leaked pid reference is still open there.

Known difference: an Atom field reads as its hash compiled and as `None`
interpreted (the interpreter's atom is not an integer).
