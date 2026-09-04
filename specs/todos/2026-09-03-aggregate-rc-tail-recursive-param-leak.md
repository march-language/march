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

## Attempted 2026-09-03: owned-parameter drop site — DOES NOT WORK ALONE

The two directions below were tried and are the SAME fix, not alternatives. A
drop site for owned aggregate parameters only pays off if some aggregate
parameter is actually owned, and while `borrow_eligible` is true for
`TTuple`/`TRecord` none is.

What was built (then reverted, deliberately not committed):

- `Perceus.insert_owned_aggregate_param_drops`, a post-pass mirroring
  `insert_apply_fn_clo_drop`. It drops owned aggregate params the body never
  releases, with the same guards as the `ELet` scope-end drop
  (`used_only_as_field_source`, `releases_var`, `moved_vars`).
- Crucially it must push the drops down to every TAIL position, not wrap the
  body. Wrapping (`let tmp = body in dec_rc p; tmp`) moves a self tail call out
  of tail position, TCO stops firing, and the loop recurses: measured correct
  and leak-free to ~5,000 iterations, then SIGBUS from stack exhaustion by
  20,000. Dropping just before each tail expression keeps the tail call intact
  and gives constant space — at the back-edge the parameter holds THIS
  iteration's cell, which is exactly the one to release.

Measured with that in place AND `borrow_eligible` false for aggregates:
`rec_scalar` and `rec_heap` went FLAT (0 and 2 live objects at both N=1,000 and
N=100,000). So the mechanism is right.

Why it was reverted: `borrow_eligible` false for `TTuple`/`TRecord` reopens the
documented `0b52510d` class, as `rc_types.ml` warns. Full suite went from 0
failures to 2 real ones (beyond the truth-table pins):
`perceus 3 "to_string borrowed field"` and
`perceus 13 "record param multi-call"` — the latter being that exact bug.
A hand-written multi-call program still produced the right answer, but one
passing program is not grounds for overriding a bug-history-backed invariant.

And with `borrow_eligible` left true the drop site is PROVABLY DEAD: its guard
(the parameter is used only as an `EField` source) is precisely the condition
under which borrow inference marks the parameter `cfg:borrowed`, which the
`not (StringSet.mem p borrowed)` filter then excludes. Instrumented and
confirmed: zero firings across `stdlib/toml.march`, `stdlib/json.march`,
`stdlib/http.march`, `stdlib/cluster.march` and every fixture.

So any real fix must FIRST make some aggregate parameters owned without
reopening `0b52510d`, or attack the TCO side directly.

## Candidate directions

- Make a self tail call pass its aggregate argument as OWNED, so no post-call
  dec is needed and the back-edge stays a true tail call.
  `perceus_core.ml` already special-cases `is_self_call` when computing
  `inc_vars`/`post_dec_vars`, which is the natural hook. This is now the most
  promising direction: it is narrower than flipping `borrow_eligible`
  wholesale, so it need not disturb the multi-call borrowed-parameter shape
  that `0b52510d` protects.
- Understand why `perceus 3` / `perceus 13` fail under owned aggregate params
  and whether they are genuine miscompiles or over-broad TIR-shape assertions.
  Precedent: `test_perceus_local_record_field_no_spurious_decrc` asserted "no
  EDecRC anywhere in render" and had to be narrowed to "no EDecRC of the
  extracted field t", because the record's own drop is now legitimate. These
  two may be the same kind of over-broad assertion — but that must be
  established by reading them, not assumed.

Two remaining fixtures are blocked on separate questions, not on this one:

- `rec_update` (`{ b with n: ... }`): `b` sits at an `EUpdate` BASE position.
  Whether that is a consuming position or a borrow is the open ownership
  question in `specs/2026-09-03-record-fbip-reuse-design.md`; `emit_update`
  copies from the base and does not consume it, which suggests borrow, but the
  Perceus `EUpdate` arm runs the base through `find_inc_vars` as if it were
  consumed. Settle that before touching either.
- `tuple`: tuple destructuring binds `let linear $p = t`, moving ownership to a
  LINEAR alias. The scope-end drop requires `v_lin = Tir.Unr`, so neither `t`
  (aliased away) nor `$p` (linear) is dropped. Linear/affine aggregates need
  their own release path (`EFree` rather than `EDecRC`).

Either way, add a fixture asserting `live_objs` is flat across N=1,000 and
N=100,000 for the `spin` shape above, in records, tuples, and record-update
form.

## Blocks

`specs/2026-09-03-record-fbip-reuse-design.md` does not strictly depend on this,
but a record-update loop is exactly the shape FBIP reuse targets, so landing
reuse while this leaks would make the reuse benchmark meaningless.
