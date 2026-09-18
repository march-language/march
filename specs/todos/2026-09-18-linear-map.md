# `[P2]` `LinearMap`: a keyed collection that can hold linear values

Filed 2026-09-18. Design spec, not built. Needed by phase 4 of the choreography work
([[2026-09-18-choreography-access-points]]): an actor that hosts several sessions at once
keeps one linear `Parked_<Role>` per session
([[2026-09-13-endpoints-event-api-actor-state]]), so it needs a map from session id to
`Parked_<Role>`. **Decided by the user: checked statically**, not with a runtime use-once
flag as Maty's Scala implementation does.

## Summary of the decisions

1. **A separate module, `LinearMap`**, not a linear-safe subset of `Map`. Almost nothing in
   `Map`'s API can be given to a linear value.
2. **`always_linear opaque type LinearMap(k, v)`.** Every `LinearMap` binding must be
   consumed, whatever `v` is. Not linearity by containment: measured below, containment
   does not see through a stdlib type with private constructors.
3. **Every operation consumes the map and hands it back.** `take` (or `take_slot`) is the
   only way a value leaves; `put` returns the value it displaced.
4. **Dropping a non-empty map is prevented by the type, not by an emptiness proof.** The
   map is linear, so it must end in `drain` (consumes every value through a callback that
   must consume each one), `to_list`, or `dispose`, which returns `Err(m)`, the map
   itself, when it is not empty. No runtime panic, no use-once flag.
5. **Keys stay unrestricted.** Only `v` is opted in to linear instantiation; a linear key
   type is rejected by the existing generic rule. Keys are hashed with the builtin `hash`
   and compared with a comparator stored in the map at construction.
6. **A pure-March stdlib module on top of the existing HAMT `Map`**, with a small trusted
   kernel: about a dozen short functions whose bodies are reviewed, not checked, for
   using each value once. Callers are fully checked. This needs one new attribute,
   `@[trusted_linear(v)]`, restricted to the stdlib.
7. **Prerequisites:** three existing linearity bugs, found by this survey and filed
   separately, plus the concurrent actor-state container fix. See "Prerequisites".

## Survey: what exists (verified on `origin/main` `b4252d39b`)

### The generic rule and containment (shipped 2026-09-13)

`check_linear_instantiations` (`lib/typecheck/typecheck.ml`) sweeps every named
polymorphic use once the module is solved. A use is rejected when a type variable in a
**negative** position of the callee's scheme (`consumed_var_ids`) is instantiated with a
type for which `contains_linear` holds, unless the variable's id is in `linear_ok_ids`.
`mark_linear_ok` puts ids there. It is called for a parameter declared `linear`/`affine`
and marks **every** type variable in that parameter's type.

`holds_linear` (`typecheck_unify.ml`) makes a binding linear when its type holds a linear
value in an owning position: a tuple component, a `List` element, or a payload of a type
that `name_is_variant` recognises. `name_is_variant` looks the name up among the
**constructors** in `env.ctors`.

### `Map` (stdlib/map.march)

`ptype Map(k, v) = HamtMap(HEntry(k, v))`: a HAMT keyed by the builtin polymorphic
`hash(k)`, with key equality derived from a less-than comparator `cmp` that **every call
takes as an argument**. `size` is O(n). The public API, and why each one is unusable on a
linear value:

| `Map` function | what it does to a value |
|---|---|
| `get`, `get_or`, `values`, `entries`, `to_list`, `fold` | copies values out while the map keeps them |
| `insert` | drops the old value when the key is present |
| `remove` | drops the removed value |
| `size`, `keys`, `is_empty`, `contains_key` | read the map without returning it, so the map is consumed and gone |

The refinement contracts (`keys(_) == union(keys(m), ...)`) also treat `m` as still alive
after the call. The only `Map` functions a linear value could pass through are `empty`
and `singleton`.

### Measured probes

All run with `march --check` on `b4252d39b`, with the stdlib freshly staged.

| probe | result | what it shows |
|---|---|---|
| `Map.insert(Map.empty(), 1, S1(1), Map.int_cmp)` | rejected: "`S1` is linear, but `Map.insert` is generic in a parameter of that type" | the generic rule works as described |
| `let m : Map(Int, S1) = Map.empty()`, `m` never used | **accepted** | containment does not reach a stdlib `ptype`: `Map`'s constructors are not in the user's `env.ctors`, so `name_is_variant "Map"` is false |
| same, with a user `type W(k, v) = W(Map(k, v))` | rejected: `m` never used | containment does work for a user variant |
| `fn put(linear m : LM(k, v), key : k) : LM(k, v) do m end`, called with key `S1(1)` | **accepted**; the key is dropped | `linear m` marks `k` as well as `v` |
| same without `linear` on `m` | rejected | an unmarked `k` is protected by the generic rule |
| `fn w(linear val : v) do g(val) end` with `g(x) = x`, called at `S1` | **rejected** (false) | the mark on `v` is lost when unification links it to another variable. Also `Map.insert(inner, key, val, ...)` inside an opted-in wrapper |
| `let (_, n) = (Some(S1(1)), 2)`; `let _ = Some(S1(1))` | **accepted**; `S1(1)` is gone | the wildcard check tests the wildcard's own type with `is_linear_ty`, not `contains_linear` |
| `let (n, s) = (5, S1(1))`, then `n + n` | **rejected** (false): "`n` is used more than once" | a `let` pattern over a linear value makes every binder linear, including an `Int` |
| actor `state { sessions : LM }` with `always_linear type LM`: take, then return `{ state with n: … }` on one branch | rejected: "`m` is consumed on some branches but not others" | an `always_linear` field is tracked by today's move-out rules (R1–R5) |
| same field, `{ state with sessions: lm_put(lm_empty(), …) }` without reading it | rejected: "`state.sessions` was never used" | overwriting a map field is caught |
| a lambda `fn p -> 0` passed where `p : S1` | rejected: `p` never used | callbacks are checked, so `drain` can be too |

## Decision 1: a separate module

A linear-safe subset of `Map` would be `empty` and `singleton`. Every other signature
promises a read that leaves the map intact (see the table above), and changing those
signatures would break every `Map` user. Making `Map` itself linear is not an option for
the same reason. So: a new module and a new nominal type. `Map` functions cannot be
applied to a `LinearMap`, since they are different types, and would be rejected at a
linear `v` anyway.

This confirms the earlier recommendation.

## Decision 2: `always_linear`, not containment

The map's own linearity could come from two places:

- **Containment.** `LinearMap(Int, Parked_B)` is linear because it holds a linear value,
  and `LinearMap(Int, Int)` is not. That is precise, but it depends on `name_is_variant`
  seeing the type's constructors, and the probe shows it does not for a stdlib type with
  private constructors (`Map(Int, S1)` is unrestricted today). It would also make the
  map's tracking depend on a heuristic that the FQN-identity work may change.
- **`always_linear`.** Every binding of any `LinearMap(k, v)` must be consumed. That is
  robust: `resolves_always_linear` is the mechanism `Handle` already uses from the stdlib,
  and `field_linearity` already treats an `always_linear` actor-state field as a linear
  field (probes above), so R1–R5 apply to a `sessions : LinearMap(…)` field with no
  further work. The cost: a `LinearMap(String, Int)` must be consumed too. That doesn't
  matter, because such a map should be a `Map`.

**Chosen: `always_linear`.** Constructors must be private, so the declaration is
`always_linear opaque type`. That combination has no grammar production today (only
`always_linear type`, with public constructors). Add one production that mirrors
`opaque type`: the variants are marked `var_vis = Private` and it produces
`DAlwaysLinearType`. With public constructors a user could build a `LinearMap` directly or
destructure one. That would not break soundness (a payload bound from a linear scrutinee
is linear), but it would expose the representation.

## Decision 3: operations

Uncurried, collection first (the stdlib convention). `k` is unrestricted and `v` is opted
in (Decision 6). Every function that receives a map returns one, except the three
terminal ones.

```march
always_linear opaque type LinearMap(k, v) = LM(Int, k -> k -> Bool, Map(k, v))
                                          -- count, comparator, entries
always_linear opaque type Slot(k, v) = LSlot(k, Int, k -> k -> Bool, Map(k, v))
                                          -- the key taken, and the map without it

-- construction
fn empty(cmp : k -> k -> Bool) : LinearMap(k, v)
fn empty_int() : LinearMap(Int, v)
fn empty_string() : LinearMap(String, v)

-- moving values in and out
fn put(m : LinearMap(k, v), key : k, val : v) : (Option(v), LinearMap(k, v))
                                         -- Some(old) when key was present
fn take(m : LinearMap(k, v), key : k) : (Option(v), LinearMap(k, v))
                                         -- the only way a value leaves
fn take_slot(m : LinearMap(k, v), key : k) : (Option(v), Slot(k, v))
fn fill(s : Slot(k, v), val : v) : LinearMap(k, v)   -- put back; cannot displace
fn vacate(s : Slot(k, v)) : LinearMap(k, v)          -- leave the key absent

-- reads: answer plus the map
fn size(m : LinearMap(k, v)) : (Int, LinearMap(k, v))         -- O(1): count is cached
fn member(m : LinearMap(k, v), key : k) : (Bool, LinearMap(k, v))
fn keys(m : LinearMap(k, v)) : (List(k), LinearMap(k, v))

-- ending a map
fn drain(m : LinearMap(k, v), acc : a, f : a -> k -> v -> a) : a
fn to_list(m : LinearMap(k, v)) : List((k, v))
fn dispose(m : LinearMap(k, v)) : Result((), LinearMap(k, v))  -- Err(m) if not empty
```

Notes:

- **`put` returns the displaced value** rather than refusing or dropping it. The caller
  must match `Some(old)` and consume `old`; that is the whole point.
- **`take_slot`/`fill`/`vacate` exist for the actor's turn.** The common turn takes one
  session out, resumes it, and puts the next state back under the same key. With `take`
  and `put`, the second `put` returns an `Option(v)` that is `None` at runtime but still
  needs a `Some(p)` arm that consumes `p`, and for a `Parked` value there is nothing
  sensible to write there. A `Slot` is a linear "map with a hole at `key`": `fill` cannot
  displace anything, and `vacate` is the path where the session ended. `take_slot` on an
  absent key gives `(None, slot)`; the caller vacates it (stale session id) or fills it
  (a new session).
- **`size` is O(1)**: the count is kept in the wrapper, because `Map.size` walks the trie.
- **Iteration without duplication.** `keys(m)` returns the keys (unrestricted, so they
  can be copied) and the map; the caller then takes, updates and puts back one entry at a
  time with explicit recursion over the key list. The accumulator of a stdlib HOF such as
  `List.fold_left` is not opted in to linear values, so a `LinearMap` cannot be threaded
  through one, and that is correct until those HOFs opt in. `drain` is the consuming
  fold: `f` receives each value once, and because a lambda passed at `v = Parked_B` has a
  linear parameter, a callback that drops or copies it is rejected (probe above).
  Iteration order is the HAMT's hash order, as for `Map`.
- **Not provided:** `get` (a copying read), `update(m, k, f)` (a closure cannot capture
  the linear values an actor step usually needs), `map_values` (easy to add later on
  `drain`'s pattern, but no use case yet), `merge`.

### The actor shape this is for

```march
actor Host do
  state { done : Int, sessions : LinearMap(Int, Svc_B.Parked_B) }
  init  { done: 0, sessions: LinearMap.empty_int() }
  on Deliver(s : Cap(Session.Live), sid : Int, from : Int, msg : Bytes, ep : Int) do
    match LinearMap.take_slot(state.sessions, sid) do
      (None, slot) ->                       -- a session already ended or cancelled
        { state with sessions: LinearMap.vacate(slot) }
      (Some(parked), slot) ->
        match Svc_B.resume(parked, from, msg, ep) do
          Got_Req(n, st) ->
            { state with sessions: LinearMap.fill(slot, Svc_B.await_Req(s, Svc_B.reply(s, st, n))) }
          Got_Bye(_, st) ->
            let _ = retire(Svc_B.finish(s, st))
            { state with done: state.done + 1, sessions: LinearMap.vacate(slot) }
        end
    end
  end
end
```

(`retire` is the user's consumer of a `Closed_B`; names are illustrative.) Every
returning branch consumes `state.sessions` once and stores a map back, and R1–R5 already
enforce that for an `always_linear` field (probes above).

## Decision 4: preventing the drop of a map that still holds values

Whether a map is empty at a program point cannot be decided statically in general. The
three candidates:

- **`drain(m, acc, f)` only.** Sound and total, but disposing of a map you know is empty
  then needs a callback that is never called.
- **`consume_empty(m)` that panics when non-empty.** Statically allowed, checked at
  runtime. A panic drops every value still inside, which is exactly the failure we are
  preventing, only louder. Rejected.
- **The map type is always linear, plus terminal operations that cannot lose a value.**

**Chosen: the third.** `LinearMap` is `always_linear` (Decision 2), so every binding must
be consumed. The only consumers are:

- `drain(m, acc, f)`: every value passes through `f`, which must consume it;
- `to_list(m)`: the list holds the values, so it is linear by containment and must itself
  be consumed (by matching, or by a function that opts in);
- `dispose(m) : Result((), LinearMap(k, v))`: `Ok(())` when empty; otherwise `Err(m)`
  hands the same map back. The `Err` payload is an `always_linear` value, so `Err(_)` is
  rejected (probe R7 below) and `Err(m)` must go to `drain`.

The emptiness test in `dispose` happens at runtime, but its failure case is still checked
statically: no path loses a value, and nothing panics.

**Actor death.** When an actor stops or crashes, its state is released by reference
counting, and any `Parked` values in a `LinearMap` go with it without being cancelled.
That is the same situation as a single `parked` field today, and the phase 1–3 machinery
(cancellation and heartbeat on the peers) is what covers it. Linearity governs the
program's own paths, not process death.

## Decision 5: keys

- **Unrestricted.** A key is hashed, compared, copied into the trie and returned by
  `keys`, so it cannot be linear. That is enforced for free: `k` is never opted in, so
  instantiating it with a type for which `contains_linear` holds is rejected by
  `check_linear_instantiations` at the first function that receives a `k`
  ("`S1` is linear, but `LinearMap.put` is generic in a parameter of that type", measured
  with a generic stand-in). This depends on the opt-in marking `v` and not `k`, which is
  why the kernel cannot use `linear m : LinearMap(k, v)` (the probe shows that marks `k`
  too).
- **Equality and hashing.** As in `Map`: the builtin `hash(k)` places the key, and
  equality is derived from a strict less-than comparator. The comparator must be a strict
  total order consistent with structural equality on the key type, which is the same
  assumption `Map`'s contracts document.
- **The comparator is stored, not passed per call.** `Map` takes `cmp` on every call, and
  a mismatched comparator silently misses keys. For a `LinearMap` a missed key does not
  lose the value (it stays inside and comes out in `drain`), but `take` would report
  `None` for a live session. Storing it at `empty(cmp)` removes that class of mistake;
  `empty_int()` and `empty_string()` cover the session-id case. A closure in the wrapper
  is ordinary data.

## Decision 6: implementation as a stdlib module over the HAMT

### Why a trusted kernel

A fully checked implementation would need the body of each `LinearMap` function to treat
`v`-typed values as linear, and then the body could not call `Map` at all (every `Map`
function copies or drops). It would need a new linear HAMT, in which every node helper
(`list_nth_safe`, `node_get`, …) destructures and rebuilds instead of reading. That is
possible, and Perceus would make the rebuilds in-place because a linear map is never
shared, but it means about 400 lines of new, subtle code before phase 4 can start.

Instead, the linear guarantee is split in two:

- **Callers are fully checked.** Every rule above applies at every use site.
- **The kernel is trusted.** The dozen `LinearMap` functions are written over `Map`, and
  their bodies are reviewed (not checked) for moving each value exactly once. The
  invariants to review are short: `take` = `Map.get` + `Map.remove` of the same key (one
  value out, none left); `put` = `take` first, then `Map.insert` into a key now absent (so
  `insert` never overwrites); `fill` inserts into a key the `Slot` removed; `drain` =
  `Map.fold` (each value to `f` once); `to_list` = `Map.to_list` of a map that is not used
  again. This is the same kind of trust as the session runtime primitives, and it is much
  smaller.

At runtime a value is a reference-counted heap object either way. Linearity is a
discipline over March-visible references, and the kernel keeps it by never keeping a
`v` it has handed out.

### `@[trusted_linear(v)]`

This needs one new, narrow opt-in. Per-parameter `linear x : a` does not fit: `take`,
`size`, `keys`, `drain`, `to_list` and `dispose` have no parameter of type `v`, and
`linear m : LinearMap(k, v)` would mark `k` too.

`@[trusted_linear(v)]` on a function:

- **For callers:** the function's type variable named `v` is added to `linear_ok_ids`, so
  callers may instantiate it with a linear type. The attribute names that one variable;
  others (`k`, `a`) are unaffected.
- **For the body:** it is checked as ordinary generic code, where `v` is a plain type
  variable. The one exception: pattern bindings are linear only if their own type is
  linear. They do not inherit linearity from the `always_linear` scrutinee, so the
  kernel can read `LM(n, cmp, inner)` and use `n` and `cmp` freely. The parameter `m`
  itself stays tracked, so each kernel function consumes its map once.
- **Resolution:** `v` must name a type variable in the function's annotated signature,
  otherwise it is an error. The mark is applied to the **generalised scheme's** variable
  (resolve the annotation name through the signature after the body is checked), not to
  whatever id the annotation had while the body was being checked. That sidesteps the
  mark-loss bug ([[2026-09-18-linear-ok-mark-lost-on-tyvar-link]]), which otherwise
  rejects exactly this kernel's `Map.insert(inner, key, val, cmp)` call.
- **Gate:** accepted only in stdlib files, with an error elsewhere ("`@[trusted_linear]`
  is reserved for the standard library; use `linear x : a` to opt in a parameter"). The
  trusted base stays small and reviewable. A user-facing checked per-variable form is
  separate future work (see "Out of scope").

The grammar already parses it: `fn_attr` turns `@[name(value)]` with a lower-case payload
into the string `"trusted_linear:v"`. The work is in `check_fn` and the attribute
validation.

### Perceus, RC and the compiled representation

- **No codegen or runtime change.** `LinearMap` and `Slot` are ordinary boxed ADTs;
  `always_linear` is a typecheck-only property, as it is for `Handle`, which compiles
  today.
- **Uniqueness helps.** A `LinearMap` value is never shared at the March level, so its
  wrapper cell has refcount 1 at every operation and Perceus can reuse it in place
  (`LM(n, cmp, inner)` → `LM(n + 1, cmp, inner2)`). The HAMT underneath still path-copies
  1–7 nodes per update, as `Map` does. An in-place HAMT is a possible optimisation later,
  not a requirement.
- **Values are moved, not copied, at the RC level.** `Map.get` increments the value's
  count and `Map.remove` releases the trie's reference, so `take` hands the caller the
  only reference. No double free and no leak, as long as the kernel keeps its invariants.
- **Compiled-only risk: niche `Option`.** `(Option(v), LinearMap(k, v))` returns carry an
  `Option(v)` that monomorphisation may niche-encode. The module must be added to
  `lib/modules/stdlib_manifest.ml` (eager load, right after `map.march`, which
  `Stdlib_manifest_test` enforces), otherwise it reproduces the lazy-stdlib niche
  miscompile (`specs/progress/2026-09-18-lazy-stdlib-niche-miscompile-closed.md`). The
  runtime tests must include an `Option(Int)`-valued map, compiled, not only
  interpreted.

## Prerequisites

1. **Wildcards over a container holding a linear value** —
   [[2026-09-18-linear-wildcard-misses-containers]]. **Blocks soundness.**
   `let (_, m2) = LinearMap.put(m, k, v)` silently drops a displaced session today
   (witness R3 is accepted on `main`). `check_wildcard_discards` must use
   `contains_linear`, not `is_linear_ty`.
2. **The linear-ok mark is lost when unification links it to another variable** —
   [[2026-09-18-linear-ok-mark-lost-on-tyvar-link]]. `@[trusted_linear]` avoids it by
   marking the generalised scheme, but the per-parameter form has the bug today, and any
   future opted-in `LinearMap` helper written with `linear x : v` would hit it.
3. **A `let` pattern over a linear value makes every binder linear** —
   [[2026-09-18-linear-destructure-over-inherits]]. Not soundness but ergonomics:
   without it, `let (n, m2) = LinearMap.size(m)` makes the `Int` `n` linear, and
   `let (ks, m2) = LinearMap.keys(m)` makes the key list linear. Fix it first or in the
   same change.
4. **Actor state fields that hold a linear value inside another type** (being fixed in a
   concurrent session: a field of type `Option(Parked_B)` is not tracked and can be
   overwritten). The `sessions : LinearMap(…)` field does **not** depend on it: the map
   is `always_linear`, which today's `field_linearity` already tracks (measured). What
   does depend on it: any state field that holds a `LinearMap` or a `Slot` inside
   another type (`Option(LinearMap(…))`, a tuple, a variant), and any handler that keeps
   the `Option(v)` from `take`/`put` in state. This design assumes the fixed behaviour:
   such a field is a linear field under R1–R5.

## Implementation plan

0. Land prerequisites 1 and 3 (and confirm 4 has landed, or record that `sessions` must
   stay a bare `LinearMap` field until it does).
1. Grammar: `always_linear opaque type` (both variant and record forms, mirroring
   `opaque type`). Menhir conflict count must not move.
2. Typecheck: `@[trusted_linear(v)]`: validation, stdlib gate, scheme-level marking, and
   the no-inheritance rule for pattern bindings in the body. Unit tests in
   `test/test_compiler.ml` next to the linear-generic cases, each proved able to fail
   (attribute ignored → accept witness A1 fails; marks `k` too → reject R6 passes when it
   should fail; gate off → a user-file probe is accepted).
3. `stdlib/linear_map.march`: the module over `Map`, docstrings with `march>` doctests
   for every public function, entry in `stdlib_manifest.ml`.
4. Tests: `test/stdlib/` March tests (put/take/displace/slot/size/keys/drain/dispose,
   colliding hashes via many keys, `Option(Int)` values), run interpreted and compiled;
   the corpus witnesses below; an actor fixture in the phase-4 work.
5. Docs: a `LinearMap` section in the linear-types chapter, in both
   `specs/lang/` and `docs/` (they are separate copies); stdlib docs page; the stdlib
   module count in `CLAUDE.md` and `docs/stdlib.md` (checked by `scripts/check-docs.sh`);
   a `CHANGELOG.md` "Added" bullet.
6. Run `scripts/types-oracle.sh` against a pre-change baseline: no existing fixture may
   move.

## Corpus witnesses (specs/lang/types/)

Numbers are assigned at landing: accept and reject share one pool, and the next free
number on `main` today is `t244`. Reject files pin the substring in their
`-- EXPECT-ERROR:` first line, as in `reject/t229`. New reject fixtures must also be
mirrored in march-lean (the two-repo rule in `INDEX.md`).

Every shape below except R3 and R6 was checked against today's compiler with a
monomorphic stand-in `LinearMap` (an `always_linear` type over `List((Int, S1))` with
stub bodies): A1 and A2 are accepted, and R1, R2, R4, R5 and R7 are rejected with the
pinned message. R3 is **accepted today** (prerequisite 1). R6 was checked with a generic
stand-in without `@[trusted_linear]`; its message is the generic rule's.

### accept: `tNNN_linear_map_threaded.march`

```march
mod Main do
  needs IO.Console
  -- A LinearMap holding linear values, threaded through every operation: each
  -- call consumes the map and hands it back, a displaced value comes back to
  -- the caller, `take` is the only way a value leaves, and the map ends in
  -- `drain` or `dispose`. Keys are ordinary Ints. `size` returns an Int beside
  -- the map, and that Int is used once here so this fixture does not depend
  -- on the destructuring fix.
  always_linear type S1 = S1(Int)
  fn sink(s : S1) : Int do match s do S1(e) -> e end end
  fn main(c : Cap(IO.Console)) do
    let m0 = LinearMap.empty_int()
    let (d1, m1) = LinearMap.put(m0, 1, S1(10))
    let (d2, m2) = LinearMap.put(m1, 1, S1(20))
    let first = match d1 do
      Some(s) -> sink(s)
      None -> 0
    end
    let displaced = match d2 do
      Some(s) -> sink(s)
      None -> 0
    end
    let (n, m3) = LinearMap.size(m2)
    let (got, m4) = LinearMap.take(m3, 1)
    let taken = match got do
      Some(s) -> sink(s)
      None -> 0
    end
    let (d3, m5) = LinearMap.put(m4, 2, S1(30))
    let none = match d3 do
      Some(s) -> sink(s)
      None -> 0
    end
    let total = LinearMap.drain(m5, 0, fn (acc, k, s) -> acc + k + sink(s))
    let rest = match LinearMap.dispose(LinearMap.empty_int()) do
      Ok(_) -> 0
      Err(m) -> LinearMap.drain(m, 0, fn (acc, k, s) -> acc + sink(s))
    end
    println(int_to_string(first + displaced + n + taken + none + total + rest))
  end
end
```

Run interpreted, it prints `0 + 10 + 1 + 20 + 0 + 32 + 0` = `63`.

### accept: `tNNN_linear_map_actor_sessions.march`

```march
mod Main do
  needs IO.Console
  -- The phase-4 shape: an actor hosts several sessions, one linear value per
  -- session id, in a LinearMap in its state. A turn takes the session the
  -- message is for out through a Slot, then fills the slot (the session goes
  -- on) or vacates it (the session ended, or the id was stale). The field is
  -- always_linear, so R1-R5 make every returning branch store a map back.
  always_linear type S1 = S1(Int)
  fn step(s : S1) : S1 do match s do S1(e) -> S1(e + 1) end end
  fn retire(s : S1) : Int do match s do S1(e) -> e end end
  actor Host do
    state { done : Int, sessions : LinearMap(Int, S1) }
    init  { done: 0, sessions: LinearMap.empty_int() }
    on Open(sid : Int) do
      let (old, m) = LinearMap.put(state.sessions, sid, S1(0))
      match old do
        None -> { state with sessions: m }
        Some(s) -> { state with done: state.done + retire(s), sessions: m }
      end
    end
    on Step(sid : Int, last : Bool) do
      match LinearMap.take_slot(state.sessions, sid) do
        (None, slot) -> { state with sessions: LinearMap.vacate(slot) }
        (Some(s), slot) ->
          if last do
            { state with done: state.done + retire(s), sessions: LinearMap.vacate(slot) }
          else
            { state with sessions: LinearMap.fill(slot, step(s)) }
          end
      end
    end
  end
  fn main(c : Cap(IO.Console)) do
    let h = spawn(Host)
    send(h, Open(1))
    send(h, Step(1, false))
    send(h, Step(1, true))
    println("ok")
  end
end
```

### reject R1: `tNNN_linear_map_dropped.march`

`-- EXPECT-ERROR: The linear value \`m\` was never used`

```march
  -- A map still holding S1(1) goes out of scope. LinearMap is always_linear,
  -- so the binding must be consumed whether or not it is empty.
  fn main(c : Cap(IO.Console)) do
    let (d, m) = LinearMap.put(LinearMap.empty_int(), 1, S1(1))
    let n = match d do
      Some(s) -> sink(s)
      None -> 0
    end
    println(int_to_string(n))
  end
```

### reject R2: `tNNN_linear_map_stale_version.march`

`-- EXPECT-ERROR: The linear value \`m0\` is used more than once`

```march
  -- `put` consumed m0 and returned m1; taking from m0 afterwards would read a
  -- map version whose values now live in m1.
  fn main(c : Cap(IO.Console)) do
    let m0 = LinearMap.empty_int()
    let (d, m1) = LinearMap.put(m0, 1, S1(1))
    let (got, m2) = LinearMap.take(m0, 1)
    ...  -- d, got, m1, m2 all consumed
  end
```

### reject R3: `tNNN_linear_map_displaced_discarded.march` (needs prerequisite 1)

`` -- EXPECT-ERROR: This `_` discards a linear value of type `Option(S1)` ``

```march
  -- The second put displaces S1(1). A `_` over the returned Option drops it:
  -- the wildcard's own type is Option(S1), which holds a linear value.
  -- Accepted on main b4252d39b.
  fn main(c : Cap(IO.Console)) do
    let (_, m1) = LinearMap.put(LinearMap.empty_int(), 1, S1(1))
    let (_, m2) = LinearMap.put(m1, 1, S1(2))
    println(int_to_string(LinearMap.drain(m2, 0, fn (a, k, s) -> a + sink(s))))
  end
```

### reject R4: `tNNN_linear_map_drain_drops.march`

`-- EXPECT-ERROR: The linear value \`s\` was never used`

```march
  -- drain hands each value to the callback once; a callback that ignores it
  -- drops it.
  ... LinearMap.drain(m, 0, fn (acc, k, s) -> acc + k) ...
```

### reject R5: `tNNN_linear_map_actor_forgets_map.march`

`-- EXPECT-ERROR: The linear value \`m\` is consumed on some branches but not others`

```march
  -- The Some branch retires the session but returns an update that does not
  -- store the map back: every other session in it would be dropped.
  actor Host do
    state { done : Int, sessions : LinearMap(Int, S1) }
    init  { done: 0, sessions: LinearMap.empty_int() }
    on Close(sid : Int) do
      let (got, m) = LinearMap.take(state.sessions, sid)
      match got do
        None -> { state with sessions: m }
        Some(s) -> { state with done: state.done + retire(s) }
      end
    end
  end
```

### reject R6: `tNNN_linear_map_linear_key.march`

`` -- EXPECT-ERROR: `S1` is linear, but `LinearMap.put` is generic in a parameter of that type ``

```march
  -- Keys are hashed, compared and copied, so they must be unrestricted.
  -- @[trusted_linear(v)] opts in v only; k is protected by the generic rule.
  let (d, m) = LinearMap.put(LinearMap.empty(cmp_s1), S1(1), 5)
```

(A comparator over a linear key type cannot be written without its own errors; the
fixture pins only the `put` line, and its comment says so. It is here to show `k` was not
opted in along with `v`, the `linear m` hazard in the probes.)

### reject R7: `tNNN_linear_map_dispose_err_discarded.march`

`` -- EXPECT-ERROR: This `_` discards a linear value of type `LinearMap(Int, S1)` ``

```march
  -- dispose hands a non-empty map back in Err; discarding it drops the
  -- values inside.
  let e = match LinearMap.dispose(m) do
    Ok(_) -> 0
    Err(_) -> 1
  end
```

Also, unchanged: `Map.insert` at a linear value stays rejected with today's message.

## Out of scope

- **A checked per-variable opt-in for users** (`fn f[linear v](…)`, whose body is
  checked to treat `v` linearly). This is the principled version of `@[trusted_linear]`.
  It needs linear-safe core data structures (a linear HAMT) before anything
  collection-shaped can be written with it. If the trusted kernel is later judged
  unacceptable, this is the replacement, and `LinearMap`'s signatures don't change.
- **Borrowing reads** (`get` without taking). A separate language feature, as the
  2026-09-13 containers record says.
- **Opting stdlib HOFs in** (`List.fold_left` with a linear accumulator), which would let
  a `LinearMap` be threaded through them.
- **A `LinearMap` surviving actor restart.** It lives in actor state, so a restarted
  actor starts with an empty map, as `Parked` starts `Idle`.
