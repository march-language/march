# Supervised children never get their capabilities captured at spawn

**Status:** filed 2026-09-03 out of `2026-09-02-lift-one-cap-per-actor.md`,
**shipped 2026-09-03** (see "What shipped" at the end). That spec lifted the one-capability-per-actor limit on
capture at spawn and deliberately left this gap alone. Pre-existing; it is
independent of how many capabilities an actor needs.

## The gap

`lib/tir/cap_passing.ml`'s `thread` captures capabilities onto an actor's
runtime metadata by matching EXACTLY the shape `lower` emits for a plain
`spawn(Name)`:

```
let $raw_actor = Name_spawn() in spawn($raw_actor)
```

A `supervise` block's children are spawned through a different builtin and a
different shape. `lib/tir/lower_actor.ml` binds each declared child with
`$sup_child_raw_<field> = Child_spawn()` and hands it to `spawn_supervised`
(around L350–L370), then `wrap_sup` (around L453) registers each child with
the supervisor after the supervisor's own `spawn`. The capture pattern does not
see any of that, so a supervised child's dispatch reads back an empty slot and
its operations run unmocked — `actor_caps` returns the sentinel, exactly as
every actor did before #397. A mock reaching the supervisor itself does not
propagate: the child is a separate actor with its own metadata.

## What to build

A second pattern in `thread`, next to the plain-spawn one, that recognises
the `spawn_supervised` shape and attaches the same capability record after the
runtime call that creates the child's metadata (`march_spawn_supervised`, like
`march_spawn`, is what creates it, so the setter has to follow it). It must
share `dispatch_caps` / `spawn_caps` with the plain path so the two cannot
disagree about WHICH capabilities a child needs; the record shape, field
names, and the dispatch-side projection are unchanged.

Keep the two patterns distinct in code and in tests: the plain-spawn one is
guarded by `test/cap_mock/cap_mock_actor.march` and
`test/cap_mock/cap_mock_actor_two.march`, and neither exercises a supervisor.

## Test

A golden under `test/cap_mock/` (compiled `--test` only, like the other
`cap_mock_*` rules in `test/dune`): a supervisor with one declared child whose
handler performs an interceptable `IO.Console` builtin, started inside
`with_cap`, and the child's output must come through the mock. Red control
first: without the second pattern the child's line is unmocked.

## Out of scope

Children spawned dynamically by a supervisor at runtime (not declared in the
block) go through whichever shape their spawn site lowers to; check which
before assuming they are covered.

---

## What shipped (2026-09-03)

The "second pattern in `thread`" as planned, plus the piece the plan's
"what to build" did not have to say out loud: where the capabilities come
from, since a supervised child is spawned by the SUPERVISOR's spawn glue,
not by user code, and the glue took no parameters.

- **`needed_caps`** models a supervisor's spawn glue (`Sup_spawn`) as calling
  each of its supervised children's dispatch (`supervised_children` reads the
  children off the glue's body shape), so the fixpoint charges the glue with
  everything the children's handlers reach. The glue is only ever a call head,
  so it can gain parameters; the user's `spawn(Sup)` site — where a
  `with_cap` mock is in scope — threads them in like any elaborated callee.
  A CHILD's spawn fn is passed as a value to `register_supervisor_child` (for
  respawn) and stays frozen, which is fine: it needs no parameters, only a
  record set on it. Pinned in `test/test_cap_dict.ml`.
- **The plain spawn pattern** now threads the supervisor's spawn call
  (`go spawn_call`), whether or not the supervisor's own dispatch needs
  anything — before this it re-emitted the call unthreaded, which with a
  parameter-carrying glue would have been an arity mismatch.
- **The second pattern** in `thread` matches
  `let $raw = Child_spawn() in let $ptr = spawn_supervised($raw) in …` inside
  the glue and attaches the child's record right after `spawn_supervised`
  (which creates the meta, as `march_spawn` does), built from the glue's own
  parameters. Same `spawn_caps` table and record shape as the plain pattern;
  nothing else shared.
- **Respawn carry-over (runtime, 4 lines).** A crashed child's replacement is
  created by `march_respawn_child` through `find_or_create_meta`, never
  through the glue, so its `spawn_cap` was NULL and the restarted child lost
  its mock. The replacement now inherits the crashed incarnation's record
  pointer (retained forever on the meta, so no RC). The
  null-safe dispatch from the parent item is what made this a lost mock
  rather than a crash in the meantime.

### Red controls (both done)

`test/cap_mock/cap_mock_supervised.march`: a supervisor with one `Logger`
child, spawned inside `with_cap`; the child is sent to, `kill`ed (restart),
sent to again; a second supervisor spawned outside and sent to after the
block closes.

- Capture pattern disabled (`| Some _ when true -> …` fall-through):
  `MOCK[L:in]`/`MOCK[L:again]` → `L:in`/`L:again`; `L:out` unchanged.
- Pattern restored, runtime carry-over disabled (`if (old_meta && 0)`):
  only `MOCK[L:again]` → `L:again` — the restart line alone, proving both
  that a respawn really gets a fresh meta and that the carry-over is what
  keeps the mock.

Both restored byte-for-byte: green.

### RC proof (`MARCH_DUMP_TXT=perceus`)

```
fn Sup_spawn($cap_IO_Console : Cap(IO.Console)) : Ptr(Unit) =
  …
let $sup_child_raw_w : Ptr(Unit) = Logger_spawn() in
let $sup_child_ptr_w : Ptr(Unit) = inc_rc $sup_child_raw_w;
spawn_supervised($sup_child_raw_w) in
let $sup_child_raw_w_caps : { $cap_IO_Console : Cap(IO.Console) } = { $cap_IO_Console = $cap_IO_Console } in
set_actor_caps($sup_child_raw_w, $sup_child_raw_w_caps);
```

No `inc_rc` on the field, which is the "consumed at its last use" half of
the parent contract's item 3: the parameter is OWNED — its call site reads
`inc_rc mock; Sup_spawn(mock)` — and this is its last use, so the record
takes the caller's +1. Two children reaching the same capability would each
get a dup at their non-last uses by the same rule.

### Still not covered

- A supervisor that is itself a supervised child of another supervisor: its
  spawn fn is then passed as a value (frozen), so it cannot carry its own
  children's capabilities. Its grandchildren are uncaptured (null-safe:
  they run unmocked). **Done right after**, see
  `2026-09-03-nested-supervisor-children-not-captured.md` in this directory:
  the respawn value becomes a closure carrying the caps, so the glue stops
  being frozen, plus one runtime `march_incrc` per respawn call.
- Children a supervisor spawns dynamically at runtime go through whatever
  shape their spawn site lowers to (a plain `spawn` inside a handler is the
  plain pattern, supplied from the handler's threaded capabilities).
