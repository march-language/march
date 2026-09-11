# `[P2]` Linearity: a lambda's parameter is never checked for "must be used"

Found 2026-09-10 while reviewing
`2026-09-03-protocol-projector-typed-endpoints.md`, whose generated API hands a
linear session state to a user callback on every step. Not recorded in
`specs/lang/linear-types.md`'s findings (L1–L8) nor in
`2026-07-10-p2-compiler-linearity-found-during-core-march-widening-slice-7.md`.

## The hole

A value of an `always_linear` type passed into a **lambda** parameter and never
used is accepted with no error and no warning. The same value passed into a
**named function's** parameter and never used is rejected.

```march
mod PB1 do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn run(k : S1 -> ()) : () do k(S1(1)) end
  fn main(c : Cap(IO.Console)) do
    run(fn st -> print_line("st abandoned"))   -- accepted, silently
  end
end
```

`march --check` exits 0 with no output. Annotating the parameter
(`fn (st : S1) -> …`) changes nothing. Compare:

```march
fn drop_it(st : S1) : () do print_line("st abandoned") end   -- exit 1:
-- The linear value `st` was never used.
```

## What is and is not checked, measured

| shape | never used | used twice |
|---|---|---|
| named function parameter | rejected | rejected |
| `let`-bound, including a value returned from a function | rejected | rejected |
| **lambda parameter** | **accepted, silent** | rejected |

So the duplicate-use check is global over `always_linear` values and does reach
lambda bodies; only the must-use (drop) check is skipped for a lambda's own
parameters. The likely cause is that the must-use pass runs over a function's
declared parameters and `let` bindings and never registers a lambda's binders
as owned in the lambda's scope. Confirm in `lib/typecheck/` before fixing;
this file records the behaviour, not the mechanism.

## Why it matters

Any API that passes a linear value to a callback — the projector's generated
`offer`/`recv` wrappers, but equally a hand-written `with_handle(fn h -> …)`
— gets no guarantee that the callback consumed it. The projector spec routes
around this by construction (callbacks must return a token only a consuming
call can produce), so it does not depend on this fix. The language still
should not have the hole.

## What to build

- Register a lambda's parameters as owned linear binders for the lambda body
  and run the same must-use check a named function gets.
- Reject witness: the program above, expecting "The linear value `st` was
  never used." Accept witness: the same lambda consuming `st`.
- Re-check the `linear`-keyword form on a lambda parameter, if the parser
  admits one, for the same behaviour.
- Add the row to `specs/lang/linear-types.md`'s findings list when fixed, and
  to `docs/linear-types.md` (both trees are served).
