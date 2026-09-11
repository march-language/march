# `[P2]` Linearity: an actor-state field can be consumed and then silently retained

Found 2026-09-10 while reviewing
`2026-09-03-protocol-projector-typed-endpoints.md`, whose first draft proposed
keeping a linear session state in an actor's state. Related to finding L3 in
`specs/lang/linear-types.md` (field tracking only engages for `let`-bound
records; parameter-bound records "degrade to a warning"), but worse: here there
is no warning at all.

## The hole

An `always_linear` field of an actor's state, consumed by a call inside a
handler and then retained by the `{ state with … }` update, is accepted with no
error and no warning. The value now exists twice: once consumed, once still in
the state for the next handler turn.

```march
mod PCN do
  needs IO.Console
  always_linear type S1 = S1(Int)
  fn sink(s : S1) : Int do match s do S1(e) -> e end end
  actor Ep do
    state { st : S1, n : Int }
    init  { st: S1(0), n: 0 }
    on Tick() do
      let k = sink(state.st)          -- consumes state.st ...
      { state with n: state.n + k }   -- ... and retains the old st: duplicate
    end
  end
  fn main(c : Cap(IO.Console)) do
    let p = spawn(Ep)
    send(p, Tick())
    run_until_idle()
  end
end
```

`march --check` exits 0 with no output. The happy path (`{ state with st:
bump(state.st) }`) typechecks and runs on both backends, so linear fields in
actor state are *accepted* by the checker; they are just not tracked.

## Why it matters

An actor is the natural home for a long-lived linear resource — a session
endpoint, a handle — precisely because its state outlives one handler turn.
Today that is the one place the resource gets no protection. The projector
spec therefore keeps endpoint state out of actor state (it rides in each
message and is `let`-bound in the handler, where tracking is real) until this
is fixed; that is the workaround, not the answer.

## What to build

- Treat the handler's `state` as an owned linear record for the handler body:
  a consumed linear field must be re-supplied by the returned state, and a
  returned state that retains a consumed field is an error. This is the L3
  gap specialised to actors; fixing L3 for parameter-bound records generally
  may be the cleaner route, in which case this file is the actor witness for
  that fix.
- Reject witness: the program above. Accept witness: the happy path with
  `st: bump(state.st)`.
- Decide and document what a handler that *does not touch* `state.st` means
  (it is retained unchanged, which is fine) versus one that reads it into a
  local and drops it (must be an error).
- When fixed, add the row to `specs/lang/linear-types.md` and
  `docs/linear-types.md`, and revisit the projector spec's item 3, which is
  gated on this.
