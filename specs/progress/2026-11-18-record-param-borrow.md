# A record parameter the callee only reads is borrowed (DONE)

Follow-up to `2026-11-17-wide-record-shared-drop-fast-path.md`. After that fix
the release of Ur's 105-field `City` record still cost about 6% of the main
thread: every small read-only helper owned its `City` parameter, so each call
retained the record in the caller and released it in the callee.

## Why records were excluded

`Kind.borrowable_of` returned false for `TRecord` and `TTuple` since
`5bedb1232` (2026-09-04, "make aggregate parameters owned"). The bug it fixed:
a borrowed aggregate in a self-tail-recursive loop leaves the release with the
caller, after the call. TCO turned the call into a jump and discarded that
release, so the loop leaked one cell per iteration. `86333560e` (2026-09-26)
later gave such a release a home, the `march_tco_defer_push/drain` list drained
at loop exit, which is leak-free but holds one cell per iteration until the
loop ends.

So the hazard is real but narrow: it is loop-carried state, a record built
fresh for each iteration of a recursion. A helper that reads a record and
returns has no such problem.

## Change

- `lib/tir/kind.ml`: `borrowable_of` is true for `TRecord`. `TTuple` stays
  false (see `specs/todos/2026-11-18-tuple-param-borrow.md`).
- `lib/tir/borrow.ml`: `loop_carried_flips`. Inside the fixpoint, for every
  direct call `f -> g` where `f` and `g` are in the same strongly connected
  component of the direct-call graph (`call_sccs`, Tarjan), a record-typed
  parameter of `g` that is still borrowed is flipped to owned unless the
  argument is one of `f`'s own parameters that is itself still borrowed and not
  shadowed (`iter_calls` tracks shadowing). Forwarding a borrowed record
  unchanged round a loop is safe: nobody inside the loop owes a release. Any
  other argument (a new record, a field, a local) would be a per-iteration
  release owed after a tail call.
- `lib/tir/perceus_core.ml`, `lib/tir/perceus.ml`: the per-path drop counters
  for owned aggregate parameters (`path_counts`, `covered_by_incs`,
  `used_only_as_field_source`) took every call argument as a consuming use.
  With borrowed record parameters that is wrong: `let b = bump(a)` followed by
  a read of `a` leaked `a`. They now take the borrow map and count an argument
  at a borrowed position as a read. `call_is_safe` refuses a tail call that
  receives the value itself.

## Three latent bugs the change exposed

All three were found by CI (`sanitize-gate`, `two-node`, the native fixture
rules), not by the new fixture, and all predate this change.

**A closure-returning call was given a scalar result type.** A function that
returns a closure carries an uncurried type: `fn mk(c : R) : Int -> Int` is
`TFn ([R; Int], Int)` and is called with one argument. When a call has a
release to run after it, Perceus binds the result to a temporary first
(`let $rc = mk(c) in dec_rc c; $rc`) and typed that temporary with the type's
final result, `Int`, so codegen treated the closure pointer as a scalar and the
first call through it crashed. Nothing reached that path while the record
argument was owned, because an owned argument has no release after the call.
`test/hcr_closure_pin` (`Handler.mk(mk_conn(i))`) segfaulted. Fixed in
`Perceus_core`: the temporary takes the callee definition's declared return
type (`fn_ret_tys`, filled per module) when that is the uncurried tail of the
callee's type. Counting the call's arguments against the type's parameters,
the first attempt, is wrong: a function with ghost parameters keeps them in
its type and is called without them, and the `ghost` erasure test (same IR as
the hand-erased twin) caught it. Fixture leg `closure`.

**A nominal record's drop released an ambiguous record field shallowly.**
`ClusterNode.CnState` has a field `driver : SwimDriver.State`.
`Kind.record_fields_short` rewrites declared field types to their bare names
(the spelling variants are represented under), and bare `State` is shared by
`Swim.State`, `SwimDriver.State` and `DistSupervisor.State`, so it resolved to
nothing and `__drop$CnState` released the driver with a plain `dec_rc`: the
cell was freed and its SWIM state, probe and RNG were orphaned. It was masked
because the actor's old `CnState` was always handed to an owning callee, which
dropped it through the structural record type. With `core_tick` now borrowing
its state, the actor handler drops the old state itself through the nominal
drop, and `two-node[control_leaderless_flat]` grew by 418 objects per 30 s on
every node. Fixed in `Kind.record_fields_short`: a qualified field type that
names a record whose short name two or more types share is rewritten to that
record's structural type, which has the same layout and is what use sites
carry. The scenario is back to 0 objects.

**Copy propagation erased a newtype cast.** For a newtype field
(`type Bag = Bag(Map(String, Int))`) the drop pass writes
`let $dp : Map(..) = bag in __drop$Map($dp)`: one pointer viewed under its
payload type. `Cprop` treated that as a plain copy and replaced `$dp` with
`bag`, and once the map's drop was inlined the result was
`case bag of HamtMap(n)` with a `Bag`-typed scrutinee. Codegen destructures by
the scrutinee's static type, took the newtype path, bound `n` to the map cell
itself, and released that cell twice. It only fires when the record's drop
holds the last reference to the map; before, the owning callee's own (correctly
typed) match always freed it first. `test/native/perceus_three_deep_field_borrow`
segfaulted on Linux and is a heap-use-after-free under ASAN. Fixed in
`Cprop`: a `let` between two different nominal types is a cast and is not
propagated (`retypes_nominal`).

Unchanged, and why it is sound:

- A field that escapes a borrowed record (returned, stored, passed to an owned
  parameter, matched and its payload kept) is retained by the existing
  `borrowed_field_vars` dup-on-escape path, the one that already served
  borrowed variants.
- `{ st with .. }` copies the base and never reuses it in place, so it is a
  read of `st`.
- A closure that captures the record stores it in its environment, which is an
  owning use; the parameter is inferred owned.
- Escape analysis stack-promotes only `EAlloc`, so no record lives on a stack
  frame a borrower could outlive.

## Tests

- `test/native/record_param_borrow.march` (dune rules at default opt and
  `--opt 2`): 16 legs, each run 10,000 times, checking the computed value and
  that `live_allocs()` is flat. It covers a field returned, stored, passed on,
  matched and nested; `with` on a borrowed record; a capturing closure; one
  record at two parameters; a record held twice by a list; a self-recursive and
  a mutually recursive loop that build a new record per iteration (they must
  stay owned and see a flat heap from the base case); an owned loop that lends
  its record to a borrowing helper; a local lent and then read again; a
  function that returns the record on one arm; and a borrowing helper that
  returns a closure over the record's fields.
- `test/hcr_closure_pin`, `two-node[control_leaderless_flat]` and
  `test/native/perceus_three_deep_field_borrow` (under `MARCH_SANITIZE=1`)
  cover the three latent bugs above; each fails without its fix.
- `test/test_codegen.ml`: "record param: read-only is borrowed, no RC",
  "record param: escaping field is retained", "record param: loop-carried,
  captured and tuple stay owned".
- TIR snapshots regenerated where the Perceus output changed.
