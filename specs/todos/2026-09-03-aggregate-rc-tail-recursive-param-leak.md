`[P1]` Aggregate RC: a record/tuple parameter rebuilt per iteration of a self
tail call is still never dropped

## What is fixed and what is not

The aggregate deep-drop change (`specs/2026-09-03-aggregate-rc-deep-drop-design.md`)
made `needs_rc` true for `TTuple`/`TRecord`, gave `drop.ml` an aggregate path,
and added a scope-end drop in Perceus's `ELet` case. That covers aggregates
bound by a `let`:

    fn mk(i) = let b = { n: i, s: ... } in b.n
    -- now: let $rc = b.n in dec_rc b; $rc, and dec_rc b is a deep __drop$R

Measured with `MARCH_STRING_STATS=1` (`live_objs`): a 1,000-iteration loop
allocating such a record went from 2,001 live objects at exit to 1.

What is NOT fixed: an aggregate that is a function PARAMETER of a
self-tail-recursive function, rebuilt each iteration.

    fn spin(b : Box, i : Int) : Int do
      if i <= 0 do b.n else spin({ n: b.n + 1, m: b.m }, i - 1) end
    end

`live_objs` still scales 1:1 with the iteration count, for records, tuples, and
record updates alike.

## Why

Two facts meet:

1. Records and tuples are borrow-eligible, so `spin`'s `b` is inferred
   `cfg:borrowed` (it is only read via `EField`). The CALLER therefore owns the
   argument and `post_dec_vars` correctly emits `dec_rc` after the call.
2. `llvm_tco.ml`'s `has_self_tail_call` deliberately looks THROUGH that trailing
   dec — see its comment: *"the EDecRC lands in dead code after TCO emits the
   back-edge, so it is safe to treat e1 as a tail call"*. The dec is discarded.

Discarding a dec cannot crash, only leak, which is why this went unnoticed: it
is a PRE-EXISTING bug for any borrowed argument dec'd after a self tail call.
Aggregates merely made it fire on every iteration of every such loop.

Note the dec genuinely cannot just be moved before the back-edge: it would free
the very cell the next iteration is about to read.

## Ruled out

- Making aggregates non-borrow-eligible (`borrow_eligible` false for
  `TTuple`/`TRecord`). Measured: slightly WORSE (1,001 vs 1,000 live at
  N=1,000), because the callee then owns `b` but a parameter has no `ELet` for
  the scope-end drop to attach to. It also reopens the `0b52510d`
  record-liveness class. Do not re-try this without addressing the param drop
  site first.

## Candidate directions

- Give owned aggregate PARAMETERS a drop site, the analogue of the `ELet`
  scope-end drop (and of `add_scrutinee_free_for` for `ECase` scrutinees).
- Or make a self tail call pass its aggregate argument as OWNED, so no
  post-call dec is needed and the back-edge stays a true tail call. Note
  `perceus_core.ml` already special-cases `is_self_call` when computing
  `inc_vars`/`post_dec_vars`.

Either way, add a fixture asserting `live_objs` is flat across N=1,000 and
N=100,000 for the `spin` shape above, in records, tuples, and record-update
form.

## Blocks

`specs/2026-09-03-record-fbip-reuse-design.md` does not strictly depend on this,
but a record-update loop is exactly the shape FBIP reuse targets, so landing
reuse while this leaks would make the reuse benchmark meaningless.
