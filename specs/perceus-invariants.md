# Perceus Ownership Invariants

This is the ownership-discipline contract for March's Perceus RC pass
(`lib/tir/perceus.ml` and its Wave-3 file-split siblings `perceus_liveness.ml`,
`perceus_elide.ml`, `perceus_fbip.ml`, `perceus_scrut.ml`) and its codegen
counterpart in `lib/tir/llvm_case.ml` (§9), which turns TIR's static RC ops
into runtime shared-vs-unique branches. It exists because every rule below
was independently rediscovered as a crash at least once — four separate
campaigns (the Toml cluster, the P0 pipeline-review pass, the sort_by saga,
finding C1) kept re-deriving the same handful of facts about who owns what
across a call, a branch, or a closure capture. **Each section cites the
owning module as the source of truth and narrates around it**; where a doc
comment is quoted, that comment governs — if this page and the code
disagree, the code comment wins and this page is stale.

Cross-reference: `docs/value-representation.md` (Wave 4 Task 1) covers the
memory-layout / tagging side of the contract (what a value's bits mean).
This document covers the *lifetime* side (who increments, who decrements,
when). Neither restates the other.

Audience: anyone touching `lib/tir/perceus*.ml` or `lib/tir/borrow.ml`, or
debugging a "works in the interpreter, aborts/leaks when compiled" report.

---

## 1. The two RC-relevance predicates: `needs_rc` vs `borrow_eligible`

**Governing module: `lib/tir/rc_types.ml`.** This section summarizes; the
module doc's truth table is the single source — do not fork it into a second
copy here.

Perceus and Borrow ask two *different* questions about the same
`Tir.ty`, and the two predicates deliberately disagree on **four**
constructor patterns:

- `needs_rc ty` (Perceus's question) — must Perceus emit `EIncRC`/`EDecRC`
  for a value of this type?
- `borrow_eligible ty` (Borrow's question) — may a parameter of this type be
  considered for the borrowed (non-owning) calling convention by the
  fixpoint in `lib/tir/borrow.ml`?

The divergent set, exactly as `rc_types.ml` states it:

| constructor | `needs_rc` | `borrow_eligible` |
|---|---|---|
| `TFn _` | **true** | **false** |
| bare `TVar _` | **true** | **false** |
| `TTuple _` | true | true |
| `TRecord _` | true | true |

Everything else agrees (atoms and scalars: both false; `TCon`/`TString`/
`TPtr`/`TVar "_"`: both true). The divergence is load-bearing, not an
oversight:

- **`TFn`/bare `TVar` — Perceus true, Borrow false.** After defun, any
  `AVar` typed `TFn` is a heap-allocated closure struct (`llvm_ty (TFn _) =
  "ptr"`), never a raw code pointer — so Perceus must track its lifetime.
  But closures must never enter borrow inference: ownership of a closure
  and the free variables reachable through it is managed entirely by
  Perceus at capture/apply sites (§3 below); letting the borrow fixpoint
  reclassify a `TFn`/`TVar` param as borrowed changes who is responsible
  for the dec while Perceus's capture-site accounting still assumes
  ownership transfer — this is exactly the boundary the closure-FV fix
  lineage (§3) landed on.
- **`TTuple`/`TRecord` — both true; these no longer diverge.** Aggregates
  own their fields and are DEEP-dropped at death, exactly like variants.
  `borrowed_field_vars` (§4) still governs the *read* path — a field
  extracted from a live aggregate is borrowed, and is dup'd if it escapes —
  and record/tuple params stay borrow-*eligible* so the fixpoint can infer
  `cfg:borrowed` for functions that only read fields via `EField` (the
  toml-cluster fix, §5). What changed is the *death* path, which previously
  did not exist: with `needs_rc` false, Perceus never decided an aggregate
  was dead, so every record and tuple cell leaked together with every heap
  value it owned (measured: a 200k-iteration loop rebuilding a
  `{ n : Int, s : String }` leaked ~200k strings and ~200k cells, where the
  equivalent two-field variant leaked nothing).

  The read and death paths are orthogonal, which is why the `390dff00`
  double-free warning below does not forbid this: that bug was about fields
  extracted from a *live* aggregate being independently freed.

`rc_types.ml`'s module doc carries the full fix-history citations for each
arm (Map.fold `TFn` crash, Gate.cast `TVar` UAF, the Toml `get_str`
corruption for the `TTuple`/`TRecord` read path) — this document does not
repeat them; changing any arm without reading that doc first reopens one of
those crash classes.

---

## 2. The owned/borrowed contract at call boundaries

**Governing module: `lib/tir/borrow.ml`** (the fixpoint; "the key rule" in
its header doc) **and `lib/tir/perceus.ml`**'s `EApp`/`ECallPtr`-extern
cases (RC-op emission at the boundary the borrow map describes).

A parameter is **borrowed** iff Borrow's fixpoint proves it is only read
(pattern match / field access / passed to another borrowed position) and
never stored, returned, or passed to an owning position of an unknown
callee. The contract each side promises:

- **Callee, borrowed param:** no `EDecRC` at the parameter's last use — the
  parameter is added to the live-at-exit ("borrowed") set, which suppresses
  ownership-transfer accounting for it.
- **Caller, arg at a borrowed position:**
  - If the arg is still live after the call: no `EIncRC` — the callee will
    not dec it, so the caller's existing reference is untouched.
  - If the arg is the caller's last use (would otherwise transfer
    ownership): the caller emits an `EDecRC` **after** the call, because the
    callee will never dec it itself — someone still has to release the
    reference.
- **Caller, arg at an owned position:** standard last-use accounting
  (`find_inc_vars`): `EIncRC` when the same occurrence count exceeds the
  number of references the caller can safely relinquish, none otherwise.

### 2.1 The dual-position invariant (B1)

**A variable passed at BOTH an owned and a borrowed position of the same
call, dead afterward, must be dup'd exactly once — not zero, not twice.**

Naively, `find_inc_vars` only counts the *owned* occurrences (so a variable
that appears solely at owned + borrowed positions gets `count - 1 = 0`
dups from the owned side), while the borrowed-position accounting
(`post_dec_vars`) independently schedules a post-call `EDecRC` for the
borrowed occurrence. Both fire: the owned position already transfers the
caller's one reference, and the borrowed-position post-call dec then
releases a reference the caller never re-acquired — net **two**
consumptions against **one** owned reference. This is RC underflow /
use-after-free, and it reproduced as `both(s, s, 1)` calling
`both(a:own, b:borrow, n:own)` — exit 134 compiled, correct under the
interpreter.

**Fix (commit `a5dad194`):** `perceus.ml`'s `EApp` case (mirrored in the
`ECallPtr`-extern case) partitions `post_dec_vars` into `dual_pos_vars`
(names that also appear at an owned position of the *same* call) and the
rest. For a normal call, `dual_pos_vars` get **one balancing `EIncRC`** in
addition to keeping the post-call dec — this also keeps the value alive
across the whole call even if the callee consumes the owned parameter
before the borrowed alias's last read. For a **self**-recursive call, the
post-dec is dropped instead: TCO rewrites the trailing `ESeq`-wrapped
`EDecRC` into dead code after emitting the back-edge, so a balancing inc
would leak one reference per loop iteration. See `perceus.ml`'s "Dual-
position args" comment (currently at lines 529–556 for the `EApp` case, and
646–651 for the `ECallPtr`-extern case) for the exact accounting.

**Verified (transcript item 1 below):** `MARCH_DEBUG_BORROW=1` on the exact
regression shape shows `both(a:own, b:borrow, n:own)`; `--dump-tir` on the
caller shows exactly one balancing `inc_rc s` before the call and one
`dec_rc s` after:

```
fn both(a : String, b : String, n : Int) : String =
  ...
fn main() : () =
  ...
  let r : String = let $rc_729 : String = inc_rc s;
  both(s, s, 1) in
dec_rc s;
$rc_729 in
  println$String(r)
```

Compiled and run: exit 0, prints the same 39-byte string the interpreter
prints — no underflow, no leak.

**Standing regression tests** (both still present at HEAD, both green in the
`adversarial-regressions` stdlib group — see §8 for the run): pin this exact
shape and its FBIP sibling (§6):

- `test_compiled_dual_position_owned_borrowed` (`test/test_stdlib_suite.ml`)
  — `both(s, s, 1)` compiled/interpreter parity + exit 0.
- unit-level: the borrow-map partition logic itself has no dedicated unit
  test (it is exercised end-to-end only); the compiled/interpreter parity
  test above is the pinning mechanism.

---

## 3. The closure free-variable rule

**Governing citations:** `lib/tir/perceus.ml`'s `env.closure_fvs` field doc
(§4 of this document's env-tiers section quotes it in full);
`lib/tir/borrow.ml`'s `closure_escapes`/`owned_in`; `lib/tir/tir_names.ml`'s
`is_apply_fn` doc (the ABI contract, quoted verbatim in
`docs/value-representation.md` §4 — not re-quoted here).

Three rules, one boundary:

1. **A closure's captured free variables (FVs) are owned by the closure
   struct, not by the apply function that reads them.** `perceus.ml`'s
   `collect_closure_fvs` scans an apply function's body for the
   `let fv = $clo.$fvN` pattern and adds every such `fv` to
   `env.closure_fvs`. Perceus then treats those names as **always-live**
   (added to the `borrowed` set for the whole traversal): `find_inc_vars`
   emits an `EIncRC` before any consuming (last-use) call, and the ELet
   dead-binding cleanup / EApp post-call decs both skip them. The closure's
   own reference count keeps each FV alive across every invocation of the
   apply function, however many times it is called.
2. **Locally-invoked closures do not transfer FV ownership to the
   invocation site.** `borrow.ml`'s `closure_escapes` defines "escape" as:
   returned, stored in an `EAlloc`/`ETuple`/`ERecord`/`EUpdate`, or passed
   as a *data argument* to a call. It is explicitly **not** an escape for a
   closure to appear as the `ECallPtr` *callee* (join points, immediately-
   applied lambdas) or as the thunk argument of `__try_call`/
   `__try_call_val` (which invoke-and-free the thunk within the call
   without retaining it). `owned_in` defers such a capture to the FV's
   remaining uses rather than unconditionally marking it owned.
3. **The closure-apply ABI CONSUMES `$clo` at apply-function argument 0,
   unconditionally, overriding any borrow-map classification of that
   slot.** `perceus.ml`'s `post_dec_vars` computation in the `EApp` case has
   an explicit exclusion: `not (i = 0 && callee_is_apply)` — the closure
   slot never gets a post-call `EDecRC` from the borrow machinery, because
   the apply ABI (`is_apply_fn`'s doc, quoted in `docs/value-
   representation.md`) already consumes it by convention.

### Fix lineage (why this boundary is drawn exactly here)

- **`a705cc95`** — introduced the `_closure_fvs` mechanism (pre-env-
  threading; module-level ref) to fix a data race: apply functions emitted
  non-atomic `march_decrc_local` on FVs that the C HTTP runtime
  concurrently `march_incrc`'d per request.
- **`d2cf09e`** — generalized the fix: apply functions must not silently
  transfer FV ownership to a consuming callee. A single-use FV (the inner
  `Generator` in `Gen.map`) was freed on the first invocation and became a
  dangling pointer on the second call — SIGSEGV.
- **`fd520110`** — extended the *borrow inference* side: a closure captured
  and handed to `__try_call`/`__try_call_val` was wrongly classified `:own`
  in `owned_in`, because those builtins invoke-and-free the thunk without
  retaining it. This is a borrowing dup, not an ownership transfer.
- **`78e31ff7`** — generalized further: a captured FV is borrowed (not
  owned) whenever the closure does **not escape** the current function,
  full stop — not just for `__try_call*`, but also for join-point closures
  (`ECallPtr` callees minted by `join_points.ml`). This is the
  `closure_escapes` helper quoted above.

**Verified (probe, transcript item 2):** a two-arg HOF closure over a
captured `Int`:

```march
fn apply_twice(f : (Int) -> Int, x : Int) : Int do
  f(f(x))
end
fn main() do
  let n = 5
  let inc = fn x -> x + n
  println(apply_twice(inc, 10))
end
```

`--dump-tir` shows the apply-function body borrowing its capture via an
`inc_rc $clo` (not a transfer) before projecting the field, and the caller
(`apply_twice`) inserting exactly one `inc_rc f` before the *second*
`call_ptr f(...)` (the first call consumes one reference per the apply ABI,
so a second reference must be minted for the second call):

```
fn apply_twice(f : (Int) -> Int, x : Int) : Int =
  let $t27190 : Int = inc_rc f;
call_ptr f(x) in
call_ptr f($t27190)

fn $lam27191$apply$3662($clo : Ptr(Unit), x : Int) : Int =
  let n : Int = inc_rc $clo;
$clo.$fv1 in
+(x, n)
```

Compiled and run: prints `20` (`inc(inc(10)) = 20`), matching the
interpreter — confirms the capture is read twice without a double-free and
without a leak.

---

## 4. The env's three scoping tiers

**Governing module: `lib/tir/perceus.ml`**, the `env` type's header comment
(currently lines 112–219). This section summarizes; the comment is the
contract — quote it directly rather than re-deriving the tiers if they ever
seem to disagree with this section.

Perceus's `insert_rc_expr` threads one immutable `env` record (Wave 3 Task
4 replaced module-level mutable refs with this record — no behavior
change, just an explicit save/restore discipline via `{ env with ... }`).
Three tiers, by how long a field's value is constant:

1. **Module-scoped** (`borrow_map`, `type_defs`, `extern_names`): set once
   per `perceus` run, read-only for the whole traversal — every
   `insert_rc_expr` call for every function in the module sees the
   identical value. No save/restore needed.
2. **Function-scoped** (`current_fn_name`, `closure_fvs`, `actor_sent`): set
   once per top-level `insert_rc` call, constant across that function's
   entire traversal. Nested `ELetRec` closures reuse the **same** env —
   they are not separately entered via `insert_rc`, so a nested closure
   sees its enclosing function's `closure_fvs`/`actor_sent`, matching the
   old refs' behavior of never resetting mid-traversal for nested fns.
3. **Subtree-scoped** (`borrowed_field_vars`, `var_ctx`): change as the
   traversal descends into `ELet` bindings / `ECase` branches. Each
   recursive call receives an `env` with the field already updated
   (`{ env with field = ... }`) — this is exactly the save/restore dance
   the old code performed by hand, except the "restore" is now implicit:
   the caller's own `env` value is never mutated, so sibling branches never
   see each other's subtree-local state.

`var_ctx` (tier 3) deserves its own callout: it maps every in-scope
variable name to its typed `Tir.var`, and is what makes the cross-branch
dead-variable `EDecRC` pass (§5) possible — without a type on hand for a
name that's live in one `ECase` arm and dead in a sibling, Perceus cannot
emit a correctly-typed `EDecRC` for it.

---

## 5. FBIP preconditions

**Governing module: `lib/tir/perceus_fbip.ml`** (the `same_arity` /
`fbip_arity_marker` contract); the producer lives in `perceus.ml`'s
`add_scrutinee_free_for` (inside the `ECase` case of `insert_rc_expr`).

FBIP (Functional-But-In-Place) reuse rewrites `EDecRC(dec_v)` immediately
followed by an `EAlloc` of a *compatible* shape into a single `EReuse` —
the freed cell's memory is reused for the new constructor instead of
`free`+`malloc`. "Compatible" means **exactly one thing**: same field
count. The March GC allocates every block as `tag + nfields × ptr`
(`16 + n*8`, per `docs/value-representation.md` §1), so any two
constructors with the same *field* count have identical allocation sizes
and can safely trade cells — cross-constructor reuse (P8) is legal
precisely because the check is arity, not identity.

**The precondition that matters: field count, never type-parameter
count.** `same_arity` only accepts a type whose name carries the
`fbip_arity_marker` (`"$fbip$"`) prefix — an unforgeable marker that a
user type name can never produce (`'$'` is unlexable in March surface
syntax). The marker is minted **once**, at the single point where the real
field count is statically known: `add_scrutinee_free_for` encodes the
freed constructor's arity as a dummy `TUnit` type-arg list behind the
marker, using the branch's bound-variable count (`br_vars`), not the
type's declared parameter list.

### Fix lineage (B2, commit `a5dad194`)

Before the fix, `same_arity` compared a `TCon`'s **type-parameter** count
against the new constructor's field count — conflating the two. A dead
1-field `Small(n) : Holder(a,b,c,d,e)` binding (5 type params, 1 actual
field) was judged "arity 5" and approved for reuse by the 5-field `Big`
constructor — an 8-byte-per-extra-field heap overflow clobbering the
neighboring chunk. **The runtime's own `rc == 1` (unique-owner) check is
necessary but not sufficient**: it proves the cell is safe to mutate
in-place, but says nothing about whether the cell is *big enough* — size
compatibility is a purely static obligation that only the compiler can
discharge, and only the field-count check (not the type-parameter count)
discharges it correctly.

**Verified (transcript item 3):** the exact overflow shape —

```march
type Holder(a, b, c, d, e) = Small(a) | Big(a, b, c, d, e)
```

— with a dead `Small(n)` binding followed by a live `Big(...)` match:
interpreter prints `293`; compiled prints `293`, exit 0 (pre-fix: compiled
printed `"big"` — the wrong arm, from the overflow corrupting `q`'s tag
word).

**Standing regression tests** (both present at HEAD, verified green — §8):

- `test_same_arity_match` / `test_same_arity_mismatch` /
  `test_same_arity_non_tcon` / `test_same_arity_raw_type_refused` —
  `test/test_codegen.ml`, `fbip_p8` group. `test_same_arity_raw_type_refused`
  is the direct B2 pin: a raw `TCon("Result", [TInt; TString])` (2 type
  params, no marker) must return `false` against `nfields = 2` even though
  the naive count would match.
- `test_fbip_cross_tag_reuse` / `test_fbip_no_reuse_arity_mismatch` — same
  group, integration-level `EReuse` rewrite checks.
- `test_compiled_fbip_arity_no_overflow` — `test/test_stdlib_suite.ml`,
  `adversarial-regressions` group (`` `Slow ``) — the exact `Holder`
  compiled/interpreter parity regression above.

---

## 6. The scrutinee-borrowed approximation (post-campaign truth)

**Governing module: `lib/tir/perceus.ml`**'s `ECase` case (the
`scrutinee_borrowed` computation and the cross-branch `add_cross_decrcs`
exclusion), plus `lib/tir/perceus_scrut.ml` (the Phase-0.5 rewrite that
narrows how often the approximation is even needed).

### What the approximation is

When an `ECase` scrutinee's branch re-matches the **same scrutinee
variable** on a sub-path of its own body (e.g. an `if`/`else` inside a
`Cons` arm, where the `else` branch falls through to `match xs do ... end`
again), Perceus cannot tell — without path-sensitive analysis — whether
the scrutinee escapes on *every* path through that arm or just one. It
conservatively answers "borrowed" (i.e., "some sub-path might still need
it") whenever the scrutinee's name is free **anywhere** in the branch
body (`name_free_in`), even if it's actually dead on the path being taken
at runtime. The branch-bound variables (fields extracted from the
scrutinee) are then re-added to that arm's live-at-exit set, protecting
them from a premature free.

**This is path-insensitive by design**, and `perceus.ml`'s own comment
names the tradeoff precisely: "conservative approximation (memory-safe,
minor leak)." A `name_free_on_every_path` check would be more precise but
is a materially larger refactor of the `insert_rc_expr` traversal — not
attempted in this campaign.

### CURRENT justification (post-campaign — this replaces the old rationale)

The approximation's conservatism is justified by exactly two things,
neither of which is sort_by:

1. **Leak-not-crash for genuine single-sub-path uses.** When the scrutinee
   really is used on only one sub-path, the conservative direction over-
   retains the branch variables (a bounded memory leak on the paths where
   it turns out not to be needed) rather than under-retaining them (which
   would free live data — a crash). This asymmetry is the actual reason to
   keep the conservative direction, independent of any specific stdlib
   function.
2. **The cross-branch dec exclusion from `20d1d144`.** The scrutinee's own
   variable must be excluded from `add_cross_decrcs`'s "dead here, live
   elsewhere" set (see below) — without this second, *independent* fix,
   the conservatism above actively causes a double-free, not just a leak.

### 6.1 Branch variables of a live-across-case scrutinee are borrowed
### field vars (the G73 elision)

**Governing module: `lib/tir/perceus_core.ml`**'s `ECase` case, the
`scrutinee_live_across_case` computation feeding `env_for_br`'s
`borrowed_field_vars`.

The `la` re-add described above makes a borrowed scrutinee's branch
variables *live*, which is enough to stop them being freed and enough to
make a consuming use dup them. It is **not** enough to stop them being
dup'd at a use that consumes nothing. A projection bound out of a live
scrutinee and then handed to a borrowed parameter got the full owned-
binding treatment:

```
Box($f) -> let s : String = inc_rc $f; $f in
             let $rc : Int = string_byte_length(s) in
             dec_rc s; $rc
```

`inc_rc` at the projection (because `$f` is live, so the alias binding
`let s = $f` must mint its own reference) and `dec_rc` after the call (§2's
borrowed-position rule: the callee will not release what the caller lent
it). Neither is needed — `b` outlives the whole arm and `s` never escapes
it. Under the scheduler `march_incrc_local` defers to the atomic
`march_incrc` on any scheduler thread, so this pair is an atomic
read-modify-write on a header that other workers are reading concurrently:
a cache line bouncing between cores for a *read*. Measured on a one-field
`Cell(NativeU8Arr)` wrapper against the same array read directly, the
wrapped form was 5.8x slower single-threaded and got **slower** as threads
were added, while the direct form sped up 5.8x.

**The fix** is not a new mechanism: such a br_var *is* a borrowed field
var in the sense §7 and the `ELet` `is_borrowed_field` cases already
define, so the `ECase` branch env now says so. Everything else follows from
the existing discipline — the alias-binding arm of `ELet` skips RC
processing of `let a = <br_var>`, the `post_dec_vars` filters in
`EApp`/`ECallPtr` exclude `borrowed_field_vars`, and a consuming use still
dups because the br_vars are in the branch's live-at-exit set. The dup for
an escaping projection is not removed, only **moved** from the projection
site to the escaping use.

**The safety gate is `live_after` membership ALONE, not `scrutinee_borrowed`.**
The premise being discharged is "the parent outlives the arm", and only the
first of `scrutinee_borrowed`'s three disjuncts establishes it:

- `name_free_in v br_body` — the path-insensitive conservatism above — says
  only that the scrutinee is *mentioned* somewhere in the arm. Ownership
  then transfers into the body, which may consume and free the scrutinee
  part-way through while a projected field is still being read. Today that
  field holds its own `+1` and survives. Eliding it there would convert
  this section's deliberate leak-not-crash into a use-after-free, which is
  the one direction that is not allowed to be wrong.
- `TTuple`/`TRecord` scrutinees are `needs_rc = false` (§1): Perceus never
  sees the aggregate's lifetime, so it cannot discharge the premise at all.

Excluding those two leaves elidable pairs on the table. That is the
acceptable direction; §6's asymmetry argument runs the same way here.

**Standing regression artifact:** the golden pair
`test/snapshots/{lower,perceus}/borrowed_scrutinee_field_read.expected`.
Its `read_only` function is two projections and two borrowed reads with
**zero** RC ops; its `escapes` control is the same projection returned from
the arm, carrying exactly one `inc_rc` at the return.

### The double-dec fix (`20d1d144`)

`add_cross_decrcs` (the cross-branch dead-variable `EDecRC` pass, §7)
unions `live_before_br` across **all** sibling `ECase` arms and emits a
cross-branch `EDecRC` for any variable "dead here, live elsewhere." Before
the fix, when one arm's scrutinee-borrowed re-add (above) made the
scrutinee look "live" in that arm's `live_before_br`, the union absorbed
it — so **every other sibling arm**, where the scrutinee is actually dead,
saw it as "dead here, live elsewhere" and received a cross-branch
`EDecRC` **in addition to** its own ordinary per-arm scrutinee free from
`add_scrutinee_free_for`. Two `EDecRC`s on the identical reference: RC
underflow, exit 134, compiled-only.

**Fix:** exclude the scrutinee's own variable name from
`add_cross_decrcs`'s `dead_here` set unconditionally — its lifecycle is
exclusively owned by `add_scrutinee_free_for`, which already decides,
independently per arm, whether to free it. `perceus.ml`'s comment on this
exclusion (in the `add_cross_decrcs` closure, immediately before the
`scrutinee_name` computation) states it exactly: "its fate can never
legitimately depend on what a sibling arm's body did with it."

**Verified (transcript item 4):** `--dump-tir` on the exact regression
shape —

```march
fn f(xs : List(Int), flag : Bool) : Int do
  match xs do
    Cons(h, t) ->
      if flag do h
      else
        match xs do
          Cons(h2, _) -> h2
          Nil -> 0
        end
      end
    Nil -> -1
  end
end
```

— shows exactly **one** `dec_rc xs` per terminal arm (the inner `Cons`,
inner `Nil`, and outer `Nil` arms each get exactly one), never two:

```
fn f(xs : List(Int), flag : Bool) : Int =
  case xs of
  Cons($f27196, $f27197) -> let t = inc_rc $f27197; ... in
    ...
    case flag of
      True() -> h
      _ -> case xs of
        Cons($f27190, $f27191) -> dec_rc xs; dec_rc $f27191; ...
        Nil() -> dec_rc xs; 0
        _ -> dec_rc xs; panic_(...)
  Nil() -> dec_rc xs; negate(1)
  _ -> dec_rc xs; panic_(...)
```

This byte-for-byte matches the standing golden
`test/snapshots/perceus/scrutinee_borrowed_conservatism.expected` (which
`test/test_snapshots.ml` pins under the name
`scrutinee_borrowed_conservatism` against
`scrutinee_borrowed_conservatism.march`) — the commit message for
`20d1d144` records that regenerating this exact snapshot "loses exactly
the two redundant dec_rc lines; no other snapshot churned," i.e. this
snapshot is the direct before/after artifact of the fix. Compiled and run:
exit 0, prints `-1` — no double-dec abort.

**Standing regression test:** `test_scrutinee_borrowed_cross_branch_no_double_dec`
(`test/test_codegen.ml`) — compiled/interpreter parity on this exact shape,
still present and green at HEAD.

### What the OLD rationale said, and why it is retired

Before this campaign, the comment adjacent to `scrutinee_borrowed` in
`perceus.ml` justified the conservative (path-insensitive) direction by
appeal to "protects sort_by" / "the root cause of the sort_by RC
underflow" / "cause the sort_by underflow to recur." **That story is
obsolete.** The historic "`List.sort_by` 100+ element compiled crash" was
formally closed with a different, unrelated root cause: `sort_by` was
**exonerated** (bit-for-bit correct compiled, confirmed against the
interpreter for checksum parity, stability parity, and heap-capturing-
comparator parity — see the diagnosis referenced from `specs/todos.md`'s
"Done" section, `.superpowers/sdd/sortby-diagnosis.md`). The actual bug
was in **`lib/tir/mono.ml`**: three interface-impl-resolution enqueue
sites rewrote a generic `show(xs : List(a))`-shaped call to its mangled
impl but enqueued that impl with an **empty substitution**, leaving the
impl body generic; `llvm_emit.ml`'s unqualified-name dot-suffix fallback
then resolved the impl's own nested `show(x : a)` call to whatever
same-suffixed impl was registered first — a type-confused call, not an RC
bug. Fixed in commit `ffe6fba8` (mono.ml now computes a real substitution
from the resolved call's concrete argument types at all three enqueue
sites). This has nothing to do with `ECase` scrutinee ownership or the
`scrutinee_borrowed` approximation at all — the two bugs happened to share
a test program's silhouette (a 100+ element sorted list) and nothing else.

**Discrepancy note (not fixed by this task — specs-only scope):** as of
this writing, `perceus.ml`'s comment text (currently around lines 984 and
995, inside the `scrutinee_borrowed` computation's doc) still states the
retired "protects sort_by" / "cause the sort_by underflow to recur"
rationale verbatim. This document supersedes that comment's *rationale*
(§6 above is the current justification); the comment itself is a `lib/`
edit and out of scope for this task. A one-line follow-up item has been
filed in `specs/todos.md` (P4 → Housekeeping) to reword the comment.

---

## 7. Cross-branch dead-variable `EDecRC`

**Governing module: `lib/tir/perceus.ml`**, the `ECase` case's
`add_cross_decrcs` (immediately following the per-branch processing loop).

A variable may be live in some `ECase` arms (used) but dead in others (not
used) without being dead in the *entire* continuation — the ordinary `ELet`
dead-binding check only fires when a variable is dead in the whole rest of
the function, so it misses "dead in this one arm, live in a sibling."
Left unhandled, an owned parameter whose last use is inside one arm leaks
in every *other* arm that doesn't reach it (observed: `Map.node_fold`'s `f`
parameter leaking in every `HEmpty` visit before the original `TFn`
`needs_rc` fix, §1's cited history).

**Algorithm** (per `perceus.ml`'s comment): union `live_before_br` across
all sibling arms; for each arm, `dead_here` = (union minus this arm's own
`live_before_br`) minus arm-bound vars, minus `live_after` (survives the
whole case), minus `env.closure_fvs` (closure-owned, §3), minus
`env.borrowed_field_vars` (§1's field-level analogue), minus **the
scrutinee's own name** (§6's exclusion — without it, this pass and the
scrutinee-borrowed conservatism interact to double-dec). Each surviving
name gets an `EDecRC` at the head of that arm's body, using the type
recorded in `env.var_ctx` (§4, tier 3).

---

## 8. Verification transcript (numbered, maps to claims above)

All probes compiled against this worktree's HEAD `94b7c36d` with
`./_build/default/bin/main.exe`, invoked from
`/Users/80197052/code/march/.claude/worktrees/hopeful-kapitsa-9f49f3`
(`dune build --root .`). Output always redirected to a file, never piped.
Probe sources under the session scratchpad
(`/private/tmp/claude-502/.../scratchpad/probe{1,2,3,4}-*.march`).

1. **§2.1 (B1 dual-position).** `probe1-dualpos.march`
   (`both(a:String, b:String, n:Int)` called as `both(s, s, 1)`) —
   `MARCH_DEBUG_BORROW=1 --compile` shows `both(a:own, b:borrow, n:own)`;
   `--dump-tir` on `main` shows exactly one `inc_rc s` (balancing) before
   the call and one `dec_rc s` after; `--compile` + run → exit 0, prints
   the 39-char string, matching the interpreter's output exactly.
2. **§3 (closure-FV borrowing dup).** `probe4-closurefv.march`
   (`apply_twice(f, x) = f(f(x))` over `inc = fn x -> x + n`) —
   `--dump-tir` shows the apply wrapper borrowing `$clo` via `inc_rc $clo`
   before the field projection (not a transfer), and the caller inserting
   exactly one `inc_rc f` before the second of the two `call_ptr f(...)`
   invocations; `--compile` + run → exit 0, prints `20`
   (`inc(inc(10))`), matching the interpreter.
3. **§5 (B2 FBIP arity).** `probe3-fbiparity.march` (`Holder(a,b,c,d,e) =
   Small(a) | Big(a,b,c,d,e)`, a dead `Small` binding followed by a live
   `Big` match) — interpreter → exit 0, prints `293`; `--compile` + run →
   exit 0, prints `293` (not `"big"` — the pre-fix overflow symptom).
4. **§6 (double-dec cross-branch exclusion).** `probe2-scrutdbl.march`
   (the exact `f(xs, flag)` shape from the `20d1d144` regression test) —
   `--dump-tir` shows exactly one `dec_rc xs` per terminal arm (three
   arms, three single decs, never two on any arm), matching
   `test/snapshots/perceus/scrutinee_borrowed_conservatism.expected`
   byte-for-byte modulo fresh-variable-name suffixes; `--compile` + run →
   exit 0, prints `-1`, matching the interpreter.
5. **Standing test-suite evidence** (run from this worktree,
   `scripts/run-tests.sh stdlib` and `scripts/run-tests.sh compiler eval
   codegen`, both exit 0):
   - `adversarial-regressions` group (`test/test_stdlib_suite.ml`), items
     `24` (`dual-position owned+borrowed arg both(s,s,1)`) and `25`
     (`FBIP same_arity: dead 1-field cell NOT reused for 5-field ctor`) —
     both `` `OK ``, part of "791 tests run … All suites passed."
   - `fbip_p8` group (`test/test_codegen.ml`): `same_arity_match`,
     `same_arity_mismatch`, `same_arity_non_tcon`,
     `same_arity_raw_type_refused`, `cross_tag_reuse`,
     `no_reuse_arity_mismatch` — all present by name at HEAD, part of
     "374 tests run … All suites passed" (compiler+eval+codegen run).
   - `test_scrutinee_borrowed_cross_branch_no_double_dec`
     (`test/test_codegen.ml`) — present at HEAD, part of the same green
     codegen run.
   - `rc_types` group (`test/test_codegen.ml`):
     `test_rc_types_truth_table`, `test_rc_types_divergence_set_exact` —
     present at HEAD, pin §1's table directly; not independently
     re-probed here (they are the pin).

Claims stated without a probe number (the env's three scoping tiers, the
closure-escapes rule's exact case list, the FBIP size-vs-arity argument)
are cited to their governing module/doc-comment/commit directly, per the
citation rule — the probes above exercise the code paths that implement
them.

---

## 9. The scrutinee-dec ordering hazard in codegen (finding C1, fixed 2026-07-11)

**Governing module: `lib/tir/llvm_case.ml`** (`strip_scrut_decrc`, the
codegen-side counterpart to §7's TIR-level `add_scrutinee_free_for`).

When Perceus emits a match arm whose scrutinee dies here (`ECase` on an
owned, non-live-after variable), the arm body's TIR begins with a plain
`EDecRC(scrutinee)` before the branch-bound fields are used (§7's
mechanism). At codegen time, a plain `dec_rc` is unsound on its own: if the
scrutinee is actually SHARED (refcount > 1 — e.g. a caller `inc_rc`'d it to
hand a copy to one call while keeping its own reference for a later call on
the same value), decrementing the header does not free the cell, so the
branch-bound fields extracted from it are silently under-refcounted — they
now have an extra live alias (the new binding) that was never counted.
`llvm_case.ml` handles this correctly **when it can see it**: it detects the
leading `EDecRC(scrutinee)`, replaces it with a runtime `march_decrc_freed`
check, and on the shared (not-actually-freed) path, `IncRC`s each extracted
heap field before the branch body runs — the mechanism cited in §7's
comment ("In the shared (RC > 1) case llvm_emit increments their RC").

**The bug: this detection required the scrutinee's `EDecRC` to be the
LITERAL head of the branch body.** `add_cross_decrcs` (§7) can prepend
OTHER cross-branch-dead variables' `EDecRC`s in front of it — e.g.
`Map.node_insert`'s `HLeaf` arm emits `dec_rc eq; dec_rc node; ...` (`eq`,
an unused comparator closure on this arm, dec'd before the scrutinee
`node`). `strip_scrut_decrc`'s exact head-only match failed on this shape,
silently falling through to a PLAIN, unprotected `dec_rc node` — the
shared-path field protection never fired, and an extracted `String` key
field's refcount went uncounted whenever `node` was shared.

**Reproduction (finding C1, filed slice 10, 2026-07-10; root-caused and
fixed slice-13, 2026-07-11):** the read-then-update map idiom
`Map.insert(m, k, f(Map.get_or(m, k, ...)), cmp)` — used by
`VectorClock.increment` and the `CRDT` counter updates — passes a function
parameter `m` at a borrowed position (`get_or`) then an owned position
(`insert`) in the SAME function, which requires an `inc_rc m` to hand
`get_or` a temporary copy while `insert` still needs the original — making
`m` (and, transitively, its tree nodes) genuinely shared at exactly the
point `Map.node_insert`'s `HLeaf` arm's `dec_rc node` fires. Minimal
reproduction (~12 lines, no newtype): a single call to a `vinc`-shaped
helper (`get_or` then `insert` on the same map parameter) into a
NON-EMPTY map (needed to reach the `HLeaf` comparison/expand path — an
empty-map insert never exercises this arm), then a `List.fold_left(Map.keys(a),
..., get_or(a, k, ...))` read that hashes the under-counted key — use-after-free
in `march_hash_string`, SIGSEGV or a hang, interpreted execution unaffected.

**Fix:** generalize `strip_scrut_decrc` to scan through a leading run of
bare `EDecRC`/`EAtomicDecRC` ops (on any variable), extract the ONE matching
the scrutinee wherever it falls in that run, and reconstruct the body with
the other decs preserved in their original relative order/position around
the extraction point. This widens exactly one match arm, changes no other
logic, and preserves the ORIGINAL literal-head case exactly (zero
intervening ops ⇒ identical behavior to before).

**Verified:** the minimal reproduction and the original `VectorClock.compare`
disjoint-clock scenario both go from crashing 100% of runs to matching the
interpreter byte-for-byte across repeated runs (0 crashes); `MARCH_SANITIZE=1`
on both is clean (no ASan/UBSan report); the full TIR snapshot suite is
UNCHANGED (this is a pure codegen fix — Perceus's TIR emission itself never
changed); the full six-runner suite (808 tests, including
`test_compiled_dual_position_owned_borrowed`, the closest existing regression
pin) and the `tree_transform`/`binary_trees` benchmarks are unaffected. Golden
`g44_crdt_convergence` now includes the disjoint-key `VectorClock.compare`/
`.concurrent` case unconditionally (previously excluded, scoped around this
bug).

---

## 10. Boxes that codegen allocates and Perceus cannot see (case merges)

**Governing module: `lib/tir/llvm_case.ml`** (`finish_ptr_merge`), with
`lib/tir/llvm_ctx.ml`'s `coerce` as the site that creates the boxes.

Every `ECase`/`if` merge stores its arms through a `ptr`-typed result slot, so
an arm whose value is NOT ptr-shaped is boxed on the way in and read back on
the way out. Two types are in that position, and both have `needs_rc = false`
(§1) — which is precisely why the box has no owner:

| arm type | box | why Perceus never drops it |
|---|---|---|
| `TFloat` (`double`) | `march_alloc_float` cell | `needs_rc TFloat = false` |
| an unboxed small scalar aggregate (`Repr.Unboxed`, `%ub.T`) | `march_alloc(16 + 8n)` cell | `needs_rc` is false for the aggregate |

**Invariant.** A box created by a merge's own coerce-to-`ptr` calls is owned by
that merge and must be released there. The proof that it is safe to release is
the arm-type uniformity check: when every arm that reaches the merge shared one
pre-coercion LLVM type that is not itself `ptr`, the pointer loaded at the
merge can only be a box this `emit_case` allocated — never escaped, never
aliased, never read by anyone else. Any other mix (including plain `ptr` arms,
whose value came from elsewhere and is owned by someone else) hands the pointer
back untouched.

Order matters: unbox **before** the release. `march_decrc_local` is a shallow
free, so the read must happen while the cell is still live — and the shallowness
is also what makes releasing an aggregate box safe at all, since its fields are
raw scalars (`Repr.is_scalar_field` admits only Int/Float/Bool) and a
field-walking free would sniff a raw `double`'s bits with `IS_HEAP_PTR`.

**Fix lineage.** Three instances of the same defect, one per boundary, each
found as a live-object leak scaling exactly with the loop count rather than as
a failing assertion:

- Boxed-path merge, `TFloat` — one leaked `march_float_box` per evaluation
  (`specs/progress/2026-08-12-float-boxing-case-merge-leak-fix.md`).
- Niche-path merge, `TFloat` — 20 000 leaked boxes on a 20 000-iteration
  `Option(Option(Float))` loop
  (`specs/progress/2026-08-22-erased-slot-ownership-leaks.md`).
- Both merges, unboxed aggregate — a `Pair(Float, Float)` built inside an `if`
  leaked one 32-byte cell per construction, 5 001 live objects over 5 000
  iterations, while the same program with the aggregate built straight-line or
  in a callee did not
  (`specs/progress/2026-09-04-unboxed-aggregate-branch-join-leak.md`).

The third is why the check is stated as "uniform non-`ptr` arm type" rather
than as a special case for `double`: a new boxable arm type is otherwise a
silent leak by default. **A type whose `needs_rc` is false but whose `llvm_ty`
is not `ptr` must be added to `finish_ptr_merge` in the same change that makes
it boxable**, or every branch join over it leaks.

Not covered by this invariant, and still open: the box an unboxed aggregate
gets when it is stored into a *niche-encoded ADT payload* (`Some(P2(...))`) has
the same no-owner problem at a different boundary — see
`specs/todos/2026-09-04-unboxed-aggregate-niche-payload-leak.md`.

---

## Historical note: commit provenance across branch lineages

The fix commits cited above (`a5dad194`, `20d1d144`, `a705cc95`, `d2cf09e`,
`fd520110`, `78e31ff7`, `ffe6fba8`) were verified present as ancestors of
this worktree's HEAD (`94b7c36d`, branch `claude/hopeful-kapitsa-9f49f3`)
via `git merge-base --is-ancestor <commit> HEAD` — all seven confirmed
ancestors. All source-line citations and test-name citations in this
document were checked against the files as they exist in this worktree,
not against the historical commit diffs (which reference line numbers and
file layouts from before the Wave 3 file-split); where a citation gives a
line number, it is the line number at HEAD, not at the fix commit.
