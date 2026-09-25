# Plan: a real `Send` check, and closures that can't smuggle mutable state across threads

**Date:** 2026-09-25
**Todo:** `specs/todos/2026-09-25-send-marker-and-closure-capture-checks.md`
**Scope:** items A and B of the data-race review: (A) make sendability a
structural, derivable property of types, usable as a bound; (B) enforce it at
every place a value crosses a thread, including through closure captures.
**Out of scope:** making the mutable buffers linear (C), purity/capability
requirements on the `Parallel.*` functions (D), atomic compound `Vault`
operations (E). C and D build on this plan; E is independent.

## Why

March's data-race freedom rests on three facts: ordinary data is immutable,
actors share nothing, and FBIP mutates in place only when a value has one owner.
The exceptions are six mutable builtin types (`RingBuf` and the five
`Native*Arr` backing types). The only thing keeping them owned by one thread is
`check_sendable` (`lib/typecheck/typecheck_exhaustive.ml:831`). It runs in one
place: the `ECon` arm, on an actor-message constructor's argument types
(`lib/typecheck/typecheck.ml:2503`). That leaves five holes:

| # | Hole | Example that type-checks today |
|---|---|---|
| H1 | Only message payloads are checked; `task_spawn` and friends are not | `Task.async(fn () -> RingBuf.push(rb, 1))` twice |
| H2 | A closure's captures are invisible: the check walks `TArrow`'s argument and result types, not its environment | `send(s, Run(fn x -> RingBuf.push(rb, x)))` |
| H3 | A user ADT hides its fields: the walk visits a `TCon`'s type *arguments*, not its constructors' fields | `type Wrap = Wrap(RingBuf(Int))`, then `send(s, Put(Wrap(rb)))` |
| H4 | Type variables are skipped (`TVar _ -> ()`) | a generic helper that forwards its argument into a message |
| H5 | The HTTP server invokes one handler closure concurrently from N connection threads (`http_server_listen`/`http_server_spawn_n`) | a handler closure capturing a `RingBuf` |

These holes were found by reading the code, not by running it. Phase 0 turns
each row into a checked-in fixture before any fix lands.

## Design decisions

**D1. One marker, `Send`, not `Send` + `Sync`.** Rust needs two traits because
it has interior-mutable types that are safe to *share* but not to *move*, or the
reverse. March has no such types: every non-`Send` type is a single-owner
mutable buffer, and the one shared mutable structure (`Vault`) is a handle to a
table that locks every operation in the runtime (`runtime/march_runtime.c`,
the `pthread_mutex_t` block near line 818). So "may cross a thread" and "may be
used from two threads at once" are the same judgement here. If a future type
separates them, add `Sync` then.

**D2. No change to `TArrow`.** Tracking captures in the function type (Rust's
closure auto-traits) would be the textbook answer, but `TArrow` appears about
650 times in `typecheck_builtins.ml` alone, plus in `lsp/`, `lib/refinecheck/`
and `lib/tir/`. Instead, B checks closure *values* in a pass after inference,
reading types from `env.type_map`. The capability checker's role-root analysis
already works this way (`resolve_root_value`, `iter_expr_scoped`,
`typecheck.ml:7464–7760`), and this plan reuses its scope machinery.

**D3. Check a closure where it enters a thread boundary, and trust it after.**
A closure that crosses a boundary is checked at the crossing, so a closure
*received* at the far side (bound by a match on an actor message, or a
`Task` result) is `Send` by construction. This is what lets B be modular.

**D4. Demand flows backwards through function summaries, not forwards through
call sites.** `Task.async(f)` is `task_spawn(fn _ -> f())`. The closure literal
there is fine; the danger is whatever the *caller* passes as `f`. The
role-root analysis follows a parameter to "every call of the function in its
module" (`call_site_args`), which cannot see a user module calling a stdlib
wrapper. Instead, each function gets a summary, "parameter i must be a `Send`
closure", computed to a fixpoint and applied at every call site. `Task.*`,
`Parallel.*`, `HttpServer.*` and any user wrapper then need no special-casing.

**D5. Unverifiable closures warn first, error later.** Some closures have no
static origin: a record field, a match binder on an ordinary ADT, the result of
a call to a function-valued parameter. Phase B reports these as a warning at the
crossing ("can't verify this closure captures only sendable values"), as the
capability checker does. Whether to promote the warning to an error is an
explicit decision in Phase 5, taken with numbers from the corpus. Concrete
non-`Send` captures (a captured `RingBuf`) are errors from the start.

**D6. No opt-out in this plan.** `impl Send(T)` by users is rejected. An
`unsafe`-style escape hatch is a separate decision; nothing in the stdlib needs
one (see *Audit* below).

## Phases

| # | Phase | Effort | Depends on |
|---|---|---|---|
| 0 | Repro fixtures for H1–H5 | ½ day | — |
| 1 | `is_send`: structural judgement over types (A, fixes H3) | 1–1½ days | 0 |
| 2 | `Send` as a bound, and inferred `Send` bounds (A, fixes H4) | 1½ days | 1 |
| 3 | Boundary registry, and value-level closure check at builtins (B, fixes H1/H2/H5 for literals) | 2 days | 1 |
| 4 | Send-demand summaries across functions (B, fixes H1/H2 through wrappers) | 2 days | 3 |
| 5 | Diagnostics, docs, corpus, rollout decision | 1–1½ days | 2, 4 |

About 8–9 days in total. Phases 2 and 3 are independent of each other once 1
lands, and can go in either order or in parallel.

### Phase 0: fixtures first

Write one program per hole and confirm, with a built compiler, that each one
type-checks today. That confirmation is the evidence this plan currently lacks.
Record the programs in the todo file. The typing corpus
(`specs/lang/types/check_types.sh`) has no expected-failure lane, so each
program moves into `specs/lang/types/reject/` (next free id; update
`specs/lang/types/INDEX.md`, whose counts doc-lint checks) in the same commit
as the phase that makes it fail. `accept/` fixtures for what must keep working
can land in Phase 0 directly:

- a `RingBuf` as actor initial state (`spawn(A, rb)` is a *move*, see Phase 3);
- `Parallel.pmap` over a pure lambda that captures an immutable `Map`;
- a message carrying a closure that captures only immutable values;
- a closure capturing a `RingBuf` used only on its own thread (never crosses).

**Two-repo rule:** new `reject/` fixtures and new ERROR-level checks must be
mirrored in `march-language/march-lean` (see the INDEX header). Plan for
the dispatch run after each merge, or file a ledgered skip there.

### Phase 1: `is_send`, a structural judgement

In `typecheck_exhaustive.ml` next to `check_sendable`, add:

```ocaml
type send_result =
  | Send
  | Not_send of string list * ty      (* path to the offender, the offender *)
  | Send_if of ty list                 (* unresolved type variables *)
  | Send_mod_closures of string list   (* paths to arrow-typed components *)
val is_send : env -> ty -> send_result
```

- **Primitive roots:** the existing `non_sendable_types` list, renamed
  `non_send_primitives`. It stays the single source of truth for what is
  intrinsically mutable. Everything else is derived.
- **`TCon (name, args)`**: if `name` is a primitive root, `Not_send`. Otherwise
  look up its constructors (`ctors_for_type`, `typecheck_exhaustive.ml:153`)
  and record definition (`env.records`). Substitute `args` for `ci_params` in
  each constructor's `ci_arg_tys` and recurse. This fixes H3.
- **Recursive types:** keep a `seen` set of `(name, args)` keys and treat a
  revisit as `Send` (coinductive; `List(a)` terminates). Reuse the `?seen`
  convention `ctors_for_type` already has.
- **Memoize** per `(name, pp of repr'd args)` in a shared `Hashtbl` on `env`, so
  a hot message type is judged once per program.
- **Opaque builtin types with no constructors** (`Task`, `Pid`, `Cap`, `Vault`
  handles, `WorkPool`, sockets): `Send` unless listed as a primitive root. The
  audit below confirms each one.
- **`TTuple`, `TRecord`, `TLin`, `TRefine`, `TNatOp`**: recurse into components.
  A `TLin` value is uniquely owned, but a linear `RingBuf` is still a buffer,
  so linearity does not make a type `Send`.
- **`TChan`**: `Send`. Session endpoints are linear and meant to be handed off.
- **`TArrow`**: `Send_mod_closures` with the path. The type can't say what a
  closure captures; the value-level check decides (Phase 3).
- **`TVar`**: `Send_if [tv]` (Phase 2 turns this into a constraint).
- **Combine** results in order `Not_send` > `Send_if` / `Send_mod_closures` >
  `Send`, keeping the first offender's path for the error message.

Then reimplement `check_sendable` on top of `is_send`. Keep the existing
message-construction call site. `Send_if` from a message payload becomes a
`CInterface ("Send", tv)` pending constraint (Phase 2); before Phase 2 lands,
ignore it as today.

**Tests:** alcotest unit cases for `is_send` in `test/test_typecheck*.ml`: each
primitive root; nested in a user ADT; in a record; in a type parameter
(`Option(RingBuf(Int))`); a recursive type; a mutually recursive pair; a
parameterised ADT that is `Send` only for `Send` arguments. Flip H3's fixture to
passing.

### Phase 2: `Send` as a bound, including inferred bounds

1. **Register `Send`** as a builtin, method-less interface. Users write
   `when Send(a)`, the existing bound syntax (`specs/lang/interfaces.md:153`;
   parsed by the `bound_surface` path, `typecheck.ml:~4278`).
2. **Discharge:** in `discharge_constraints` (`typecheck.ml:4928`), give
   `CInterface ("Send", t)` its own arm before the `impls` lookup: call
   `is_send`. `Not_send` becomes an error; `Send_if` re-queues the variables;
   `Send_mod_closures` is accepted at the type level, because closures are
   Phase 3's job.
3. **Reject `impl Send(...)`** at the `impl` registration site (`typecheck.ml:
   ~6365`), per D6.
4. **Infer bounds instead of dropping them (H4).** Today a pending constraint
   on a type variable that is still unbound at the declaration boundary is
   skipped (`TVar _ -> ()`), and only *declared* bounds reach the scheme
   (`bound_constraints @ class_constraints`, `typecheck.ml:4589`). For `Send`
   only, collect the pending `CInterface ("Send", tv)` whose `tv` is about to be
   generalized, and add them to the function's `Poly` constraint list. The
   instantiation path already re-emits scheme constraints at every call site
   (`typecheck_env.ml:1807`). This has to happen *before*
   `discharge_constraints` clears the pending list; do it in the `DFn` arm, next
   to the existing `extra_ids` logic.
5. **Surface it:** hover, `--emit-core-ast` and generated stdlib docs should
   print an inferred `when Send(a)` like a declared one. Check
   `lsp/lib/analysis.ml`'s scheme printer and the stdlib doc generator.

**Risk:** inferred constraints change the schemes of public stdlib functions.
Run `scripts/types-oracle.sh baseline` before and `check` after. The only diffs
should be added `Send` constraints on functions that forward values into
messages or tasks, and each one should be reviewed.

### Phase 3: thread boundaries and the value-level closure check

**3a. Boundary registry.** One table in a new
`lib/typecheck/typecheck_send.ml`, rather than a check scattered across arms:

| Boundary | Position | Kind |
|---|---|---|
| actor-message constructor (`ci_is_actor_msg`) | every argument | move |
| `task_spawn`, `task_spawn_link`, `task_spawn_with_cancel` | the thunk | move |
| `task_spawn_steal` | the thunk (arg 1) | move |
| `http_server_listen` | `pipeline_fn` (arg 3) | shared, concurrent |
| `http_server_spawn_n` | `pipeline_fn` (arg 4) | shared, concurrent |
| `spawn(A, args…)` | each init argument (`actor_init_sigs`) | move |
| a `Task(a)` result (`task_await*`) | the result type `a` | move (back) |

The **audit** task for this phase is to confirm the table is complete. Grep
`typecheck_builtins.ml` and `runtime/` for every builtin that takes a closure
and runs it on a scheduler thread other than the caller's. A first pass found
the names above plus `process_spawn_*` (OS processes: values are serialised,
not shared; they probably don't belong) and `actor_send_after` (sends a
message, so it is already covered by the constructor row). Record the verdict
for each in the module's header comment.

**Actor initial state is a move, and moves are fine.** `spawn(A, rb)` hands the
buffer to the new actor. Today's error message recommends exactly this. It is
only safe if the spawner doesn't keep using `rb`, and nothing enforces that
today; that is item C (linear buffers). Until C, `spawn` arguments are checked
for `Send` *except* the primitive roots, which stay allowed as today. Record
that as a known gap in the todo.

**3b. The check.** `check_send_value env ~boundary scope e`:

1. **Type part:** `is_send` on `e`'s type from `env.type_map`. `Not_send` is an
   error naming the path. `Send_if` pushes `CInterface ("Send", tv)`.
2. **Closure part,** only when the type part says `Send_mod_closures` or the
   type is itself an arrow. Resolve `e` the way `resolve_root_value` does,
   reusing `local_scope` / `iter_expr_scoped` rather than copying them:
   - **lambda literal:** for each free variable (`free_vars_expr`), check its
     type with `is_send`. If the captured variable is itself an arrow, recurse
     on its binding: `LLam` checks that literal, `LAlias` checks the
     right-hand side, `LParam i` records a demand on the enclosing function's
     parameter `i` (Phase 4), `LOpaque` goes to step 3.
   - **a top-level named function:** `Send`. It captures nothing, and
     module-level `let`s are immutable.
   - **a partial application or other call producing a closure:** check the
     arguments; the result is unknown (step 3).
3. **Unknown origin** (D5): a warning at the boundary, naming why the closure
   couldn't be traced (reuse the role-root analysis's `RVUnknown` reasons).
   Exception, per D3: a variable bound by a pattern on an actor-message
   constructor, or from a `Task` result, is trusted.

**3c. Wiring.** Run the pass once per module after inference, in the same place
`check_role_grants` runs, so `type_map` is complete. The message-constructor
check moves out of the `ECon` arm into the registry, so there is exactly one
implementation. Keep the "at construction" semantics the arm's comment
explains; the pass visits `ECon` nodes, not `send` calls.

This phase closes H1, H2 and H5 when the closure is written at the boundary
(`task_spawn(fn _ -> ...)`, `send(s, Run(fn ...))`, a handler lambda passed
straight to the listener).

### Phase 4: send-demand summaries

A table, `send_demands : (qualified fn name, int list) Hashtbl.t`, on `env`,
shared the same way `actor_init_sigs` is:

1. **Seed:** Phase 3's `LParam i` results. Parameter `i` of `f` is demanded if
   its value reaches a boundary position.
2. **Propagate:** a call `g(… a_j …)` where `g` has parameter `j` demanded is
   itself a boundary position of kind "demanded parameter". Check `a_j` with
   `check_send_value`, which may in turn demand a parameter of the caller.
3. **Iterate to a fixpoint** over the module's functions. The set only grows
   and is bounded by the number of parameters. Process modules in the order the
   typechecker already uses, so a stdlib summary exists before user code
   consults it.
4. **Calls through a function-valued parameter** (`h(x)` where `h` is a
   parameter) create no demand; demand only starts at real boundaries.

With summaries, `Task.async`, `Task.async_stream*`, every `Parallel.*` function
and the `HttpServer` entry points get their demands derived from their bodies.
A user's `Task.async(fn () -> RingBuf.push(rb, 1))` is then checked exactly like
a direct `task_spawn`. This closes H1 and H2 through wrappers.

**Where summaries are stored.** If any typecheck result is cached per module
(the `ExCtor` export bridge, the LSP's incremental analysis, forge's CAS), the
summaries must travel with the exported function signatures, or a cached stdlib
will have empty demands. Find every such path at the start of this phase and
extend it. A cached module with missing summaries must fail closed: treat all
its function-typed parameters as unknown and warn, not as undemanded.

**Tests:** a wrapper two levels deep; a user-defined wrapper around `Task.async`;
mutual recursion between two wrappers; a demanded parameter that is only
forwarded, never called; `Parallel.pmap` with a capturing lambda (reject) and
with a pure one (accept); an HTTP handler capturing a `RingBuf` (reject).

### Phase 5: diagnostics, documentation, rollout

**Diagnostics** carry the chain, in the style the capability checker uses:

```
error: this closure can't run on another thread
  captures `rb : RingBuf(Int)`, a mutable buffer owned by one thread
  passed to `Task.async` as `f`, which runs it on a new task (stdlib/task.march:40)
hint: keep the buffer in an actor's state and send it messages,
      or use an immutable collection (List, Map, RRB)
```

For H3, name the field path: "`Wrap` is not sendable: field 1 of constructor
`Wrap` has type `RingBuf(Int)`".

**Documentation:** edit `specs/lang/`, then run `scripts/gen-lang-docs.py`:

- `actors.md` (~line 130 and ~664): replace the `non_sendable_types` list
  with the `Send` rule.
- `interfaces.md`: `Send` as a builtin marker, with an inferred-bound example.
- `parallelism.md` (~line 240): the function passed to `Parallel.*` must now be
  `Send`; purity is still unchecked (D).
- `core-march-types.md` (~2402 and ~5283): replace the "hardcoded denylist"
  description with the new rule.
- `memory-model.md`: one paragraph on what `Send` guarantees and what it
  doesn't (logical races through `Vault`).

Add a `CHANGELOG.md` entry (`### Changed`, since it rejects code that used to
compile) and move the todo to `specs/progress/`.

**Rollout decision (D5).** Before flipping warnings to errors, run the checker
over the stdlib, `test/`, `bench/`, `examples/` and the conformance corpus, and
count "unverifiable closure" warnings by reason. If they are all closures in
ADT fields that never cross a thread in practice, keep the warning and file a
follow-up to track closure-typed fields properly. If they are rare and real,
promote to an error. Either way, record the numbers in the progress entry.

## Audit already done while writing this plan

- No stdlib module passes a `RingBuf` or `NativeArray` into `task_spawn`,
  `Task.*` or `Parallel.*` (grep over `stdlib/*.march`). Phase 1–4 errors on
  stdlib code would therefore be bugs in the check, not in the stdlib.
- `Vault` is not in `non_sendable_types` and should stay `Send` (per D1).
- `actor_send_after` sends a message constructor, so the existing site
  already covers it.

## Verification, for every phase

- `scripts/run-tests.sh` (full), plus the typing corpus via
  `specs/lang/types/check_types.sh`.
- `scripts/types-oracle.sh` baseline/check, run under a private `HOME`. Prove
  it goes red on a deliberate perturbation first (CLAUDE.md). The expected
  diffs are the new rejections and inferred `Send` bounds, nothing else.
- `scripts/check-docs.sh` after the documentation phase.
- No IR, runtime or benchmark effect is expected, because the check is
  typecheck-only. Run `scripts/ir-oracle.sh` once at the end to confirm.

## Open questions

1. **Closures in ADT fields** (D5): warn at the crossing, or track "built from
   a `Send` closure" at construction? Decide from Phase 5's numbers.
2. **The `spawn`-argument move gap:** closed by item C (linear buffers), or by
   a narrower "use after passing to `spawn`" check?
3. **Should `Send` inference be visible in public signatures**, or only in
   diagnostics? The plan makes it visible (Phase 2, step 5), because an
   invisible bound on a public function is a breaking change nobody can see.
