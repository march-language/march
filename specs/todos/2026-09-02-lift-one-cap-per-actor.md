# Lift the one-capability-per-actor limit on capture at spawn

**Status:** specced 2026-09-02, not started. Parent design:
`2026-08-31-cap-runtime-dictionaries.md` (§"Actor handlers: capture at spawn",
landed in #397). Full account of the landed v1 in
`specs/progress/2026-09-01-actor-capability-capture-at-spawn.md`.

## What the limit is, precisely

`lib/tir/cap_passing.ml` threads IO capabilities into ordinary functions as
extra parameters, one `$cap_<X>` per capability the function reaches, in
sorted order, any number of them. The ACTOR boundary is the one place that is
single-capability:

- `dispatch_cap need fd` returns `Some c` only when `caps_reached` for the
  actor's `_dispatch` function is a list of EXACTLY one; two or more → `None`.
- `spawn_caps : actor -> cap` (one string), filled from `dispatch_cap`.
- The spawn-site rewrite stores that one `Cap` pointer:
  `set_actor_caps($raw_actor, <cap>)`.
- The dispatch opens with `let $spawn_cap : Cap(c) = actor_caps($actor)` and
  binds it for that one capability.
- The runtime slot is one pointer: `march_actor_meta.spawn_cap`
  (`runtime/march_runtime.c:1934`), set/read by `march_set_actor_caps` /
  `march_actor_caps`.

An actor whose handlers reach two capabilities gets nothing captured at all,
so none of its operations can be mocked. It keeps release behaviour rather
than a partly-wrong one, which was the right v1 call; it is also the ordinary
actor — one that logs (`IO.Console`) and reads the clock (`IO.Clock`) is
already over the limit.

## What the limit is NOT (correcting the parent spec)

The parent spec's "Order of remaining work" put "an actor-hosted endpoint,
once the one-capability-per-actor limit is lifted" first, as if the endpoint
were blocked on it. It is not. `Cap(Session.Live)` is a user `proof cap`; it
is passed EXPLICITLY, never threaded, and `cap_of_interceptable_op` only knows
the IO builtins. Probe, 2026-09-02, identical on both backends:

```march
mod CapByMsg do
  needs IO
  needs IO.Console
  needs Session.Live
  actor Ep do
    state { n : Int }
    init  { n: 0 }
    on Attach(c : Cap(Session.Live)) do
      let _ = Session.close(c, 7)
      { state with n: state.n + 1 }
    end
  end
  fn main(io : Cap(IO)) do
    let ops = { register: fn (ap, role) -> ap + role,
                emit: fn (ep, to, msg) -> ep,
                suspend: fn (ep, h) -> ep,
                close: fn ep -> print_line("closed " ++ int_to_string(ep)) }
    let sess = Session.attach(io, ops)
    let p = spawn(Ep)
    send(p, Attach(sess))
    run_until_idle()
  end
end
-- prints: closed 7     (interpreted AND --compile, no --test)
```

A session capability reaches a handler as a message payload
(`typecheck_caps.ml` H9: handlers may receive `Cap(X)` message arguments
under the module's `needs`). What an actor-hosted endpoint actually needs is
a way to GET the capability into the actor — by message, as above, since there
is deliberately no ambient transport — and that works today. The one-cap limit
only matters to it if its handlers also perform two IO capabilities' worth of
builtins, which a logging endpoint with a clock-based timeout would.

So this item is worth doing on its own merits (any two-capability actor), and
the actor-hosted endpoint is unblocked independently of it. The parent spec's
remaining-work list is corrected in the same commit as this file.

## Design: a record of capabilities on the existing pointer

This is the shape #397's own diagnosis sketched ("one pointer rather than N
keeps the struct and the spawn ABI fixed regardless of how many capabilities
an actor needs") and then deferred. Nothing outside `cap_passing.ml` changes.

### Analysis

`dispatch_cap : … -> string option` becomes `dispatch_caps : … -> string list`
(sorted, possibly empty). `spawn_caps` becomes `actor -> string list`.
`caps_reached` already returns the sorted, de-duplicated list; the change is
to stop discarding it when its length is not one.

### Spawn site

For an actor with caps `[c1; …; cn]` (n ≥ 1), the rewrite becomes

```
let $raw_actor = Name_spawn() in
let $pid       = spawn($raw_actor) in
let $caps      = { $cap_c1: <supply c1>, …, $cap_cn: <supply cn> } in
set_actor_caps($raw_actor, $caps); $pid
```

- Field names are `cap_param_name c` (the `$cap_IO_Console` spelling already
  used for parameters: `$` keeps it out of the user namespace, dots become
  underscores). `$cap_…` does not collide with the closure free-variable
  convention, which is `Tir_names.is_fv_field` = prefix `$fv`.
- The record is an ordinary `T.ERecord`; its var is typed
  `T.TRecord [(field, cap_ty c)]` **sorted by field name**, the TRecord
  invariant (`tir.ml:12`) that `Llvm_data.field_index_for` relies on to
  compute the projection index. Since `caps_reached` is sorted by capability
  name and `cap_param_name` is monotone in it (only dots change), sorting the
  caps sorts the fields; assert it anyway (`test_cap_dict` already pins the
  same invariant for dictionary fields).
- `<supply c>` is what it is today: the enclosing function's own `$cap_c`
  parameter, a `with_cap` mock, or — when the spawn site cannot supply that
  capability — the ambient sentinel `root_cap`, which is NULL in the record
  field and reads back as "no dictionary". **Partial mocks therefore work:**
  an actor reaching Console and Clock, spawned inside a Console-only
  `with_cap`, gets a mocked Console and a real Clock.
- `set_actor_caps`'s C signature is already `(ptr actor, ptr caps)`; a record
  is a `ptr` (`llvm_ctx.ml:443`). No builtin, declaration, or runtime change,
  so the nine-site new-builtin dance does not apply.

### Dispatch

```
fn Name_dispatch($actor, $msg) =
  let $caps       : TRecord{…} = actor_caps($actor) in
  let $spawn_cap_c1 : Cap(c1)  = $caps.$cap_c1 in
  …
  <body, threaded with binds [(c1, $spawn_cap_c1); …]>
```

`actor_caps`'s builtin return type in the table is `Cap(a)`; the CALL is
emitted from the table (`llvm_emit_call.ml:298`) as returning `ptr`, and the
let-bound var carries the `TRecord` type the projections need. Both are `ptr`
at the LLVM level, so no coercion is involved — and no erased-i64 hazard,
since neither side is ever an i64.

### Single-capability actors: unify, do not special-case

Recommend routing n = 1 through the same record shape rather than keeping the
bare-pointer path alongside it. One shape, one RC argument, one test surface;
the cost is a one-field record per spawn in `--test` builds only. The existing
`test/cap_mock/cap_mock_actor.march` golden is the guard that the unified path
still produces `MOCK[A:in] / A:out`. (If it turns out the bare path has to
stay — e.g. a snapshot outside our control depends on its TIR — the two paths
must share `dispatch_caps` so they cannot disagree about WHICH caps an actor
needs.)

## The RC contract, stated so it can be checked

This is the only part with a way to be subtly wrong, so it is spelled out.

1. **The record is retained forever, on purpose.** `march_actor_meta` is
   never freed ("leak-don't-free", `march_runtime.c:2040`, `:2086`), and
   `spawn_cap` is one raw pointer on it with no release path. Today that
   retains the single `Cap`; tomorrow it retains the record. Per spawn, in a
   `--test` build, that is one small allocation, matching the meta's own
   discipline.
2. **`needs_rc (TRecord _) = false`** (`rc_types.ml:122`): Perceus never
   emits inc/dec on a record aggregate; it reconciles at the FIELD level
   through `borrowed_field_vars` (`perceus_core.ml:137`, `:770`). So the
   `$caps` var in the dispatch, bound from a builtin call, gets no aggregate
   dec at scope end — the UAF that a `TCon`-typed result WOULD have produced
   on the second message does not arise. Do not type `$caps` as anything but
   `TRecord`.
3. **Fields entering the record at spawn** are ordinary `ERecord` atoms;
   Perceus treats a record build as consuming owned copies of its fields, so
   each `Cap` (a dictionary pointer, `needs_rc = true`) is dup'd into the
   record and outlives the `with_cap` scope that supplied it — the property
   that lets `cap_mock_actor`'s `outside` actor be sent to after the block
   closes. Today the same +1 comes from `set_actor_caps`'s argument being
   owned (`set_actor_caps` is not in `Borrow.extern_borrow_table`, so its
   parameters are owned, and the runtime never decs). With the record, the
   builtin's owned argument is the record itself, whose `needs_rc` is false:
   **the caps' +1 now comes from the record build, not the builtin call.**
   Prove it, don't assume it: `MARCH_DUMP_TXT=perceus` on the fixture must
   show an `EIncRC` on each cap atom feeding the `ERecord` (or the cap being
   consumed there as its last use).
4. **Projections in the dispatch** (`let $spawn_cap_c = $caps.$cap_c`) are
   borrowed-field vars; when one escapes into a threaded handler call as an
   owned argument, Perceus incs it there (the `borrowed_field_vars` escape
   rule). No dec is emitted for the projection itself. This is the same
   shape as closure `$fv` fields and record-param field reads that the rest
   of the pipeline already exercises.
5. **The sanitize-gate CI leg** (ASAN over the native corpus) must run the
   new fixture; locally ASAN needs Docker (`ci/Dockerfile.ubuntu`; build only
   `bin/main.exe` there), so the local proof is the Perceus dump plus the
   fixture's output, and the ASAN proof is CI's.

## Tests

### Golden: `test/cap_mock/cap_mock_actor_two.march` (+ `.expected`, dune rule)

An actor whose handler performs BOTH `IO.Console` and `IO.Clock` builtins
(`cap_mock_clock` already proves Clock is interceptable), and four spawns that
together pin every property above:

| actor spawned … | expected |
|---|---|
| inside `with_cap(console)` inside `with_cap(clock)` | both mocked |
| inside `with_cap(console)` only | Console mocked, real Clock (partial) |
| inside `with_cap(clock)` only | Clock mocked, real Console (partial) |
| outside any `with_cap`, sent to AFTER the blocks close | neither mocked |

Print through the mocked Console so the Clock's value is visible in the trace
(mock the clock to a fixed number; the real clock's line is matched only by
shape, e.g. printed as `real`, since its value varies). Compiled `--test`
only, like the other three `cap_mock_*` rules (`test/dune` ~L1351), because
capture exists only where the elaboration runs.

**Red control, mandatory:** disable the spawn-site record build and watch the
first row become unmocked; then restore. A golden that has never been red has
proven nothing (see the parent spec's history on this).

### Unit: `test/test_cap_dict.ml`

Next to the existing "a nested local fn's IO is charged to its enclosing fn"
case (which drives `Cap_passing.needed_caps` on lowered TIR, L459): lower a
two-capability actor and assert `dispatch_caps` returns
`["IO.Clock"; "IO.Console"]` — and that a one-capability actor returns a
one-element list, not `None`-shaped anything, so the unified path is pinned
at the analysis level as well as the golden.

### Existing guards that must stay green

`cap_mock_actor` (single cap, unified path), `cap_mock_file`, `cap_mock_clock`,
`stream_replay`, and the TIR snapshots (`test/run_snapshots.exe`) — the spawn
rewrite shape changes only under `--test`, and the snapshot corpus is compiled
without it, so an unexpected snapshot diff means the change leaked past the
gate.

## Out of scope, filed or noted

- **Supervised children are never captured, today or after this.** The
  `thread` rewrite matches exactly `let $raw = Name_spawn() in spawn($raw)`.
  A `supervise` block's children are spawned through `spawn_supervised` inside
  `lower_actor.ml`'s `wrap_sup` (L354–L363, L452–L461), a different shape the
  pattern does not see, so a mock never reaches a supervised child. That is a
  pre-existing gap independent of the capability count; it deserves its own
  todo and its own fixture once this lands, because its fix is a second
  pattern in the same place and must not be confused with this one.
- **Interpreter.** Capture is compiled-`--test`-only (#397's scope): the
  elaboration runs on TIR, and `set_actor_caps`/`actor_caps` have no eval
  implementation. Unchanged here.
- **Release builds** are untouched by construction: the pass does not run.

## Order of work

1. `dispatch_caps` + `spawn_caps` as lists; the unit test. (Analysis only;
   nothing changes in emitted code yet — every existing golden must be
   byte-identical.)
2. Spawn-site record build + dispatch projections, single-cap unified.
   `cap_mock_actor` stays green.
3. The two-cap golden, red control first, then green.
4. RC proof: the Perceus dump shows the +1s in the right place (contract item
   3); push and let the sanitize-gate leg run the fixture.
5. Parent spec status row + this file to `specs/progress/`, CHANGELOG
   (`### Fixed`: "an actor whose handlers reach two capabilities can now be
   mocked; previously only one-capability actors were captured at spawn").

Estimated size: ~60 lines in `cap_passing.ml`, one fixture, one unit test. No
runtime, ABI, builtin, or typechecker change.
