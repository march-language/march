# Plan: data-race freedom for March's mutable types (items A, B and C)

**Date:** 2026-09-25
**Todo:** `specs/todos/2026-09-25-send-marker-and-closure-capture-checks.md`
**Scope:** items A, B and C of the data-race review:
- **(A)** make sendability a structural, derivable property of types, usable as a bound;
- **(B)** enforce it at every place a value crosses a thread, including through closure captures;
- **(C)** give each mutable stdlib type the right ownership model: linear where
  it really mutates in place, plain value where it is already copy-on-write.

**Out of scope:** purity/capability requirements on the `Parallel.*` functions
(D); more atomic compound `Vault` operations (E; `put_new`, `incr` and
`push_capped` already exist, `stdlib/vault.march:145–178`).

## Summary: do C first, and A/B shrink to a guard rail

A careful pass over the standard library (next section) changes the picture the
review started from. Of the six types the sendability check exists to protect:

- **Five are not mutable at all, observably.** The `Native*Arr` types have
  copy-on-write value semantics. Every in-place write in the runtime is gated on
  sole ownership (`rc == 1`) and copies otherwise, and the interpreter always
  copies. They were added to the non-sendable list by analogy with `RingBuf`
  (`specs/progress/2026-08-07-nativearray-added-to-non-sendable-message-types.md`:
  "structurally the same … hazard"), but the runtime says otherwise.
- **One, `RingBuf`, really is shared mutable state**, and nothing outside its own
  module and tests uses it.

So C is small and closes all five holes (H1–H5 below) for every type that exists
today:
1. Make native arrays sendable.
2. Make `RingBuf` `always_linear` with a consume-and-return API.

Closures already cannot capture a linear value; an ADT holding one is linear;
a generic function must opt in to receive one; and a send is a move. After C,
the non-sendable list is **empty**.

That makes B (about 4 days, and the riskiest part) unnecessary for today's types.
The recommendation is:
1. Do C (Part C below).
2. Keep A's Phase 1 as a cheap guard for the next mutable primitive.
3. Defer A's Phase 2 and all of B until someone proposes a type that is
   neither linear nor copy-on-write.
4. Write that rule down (Phase C5) so the question is asked when such a type is
   proposed, not after.

Parts A and B stay below, fully planned, for that day.

## What the standard library actually contains

Every opaque builtin type in `lib/typecheck/typecheck_builtins.ml`, checked
against its runtime implementation:

| Type | What it is | Mutation | Users outside its module | Verdict |
|---|---|---|---|---|
| `RingBuf(a)` | fixed-capacity FIFO | **in place, unconditionally.** All aliases see every push (`stdlib/ring_buf.march:21`); `ring_buf_push` returns `void` | none. Only `test/stdlib/test_ring_buf.march`, `test/native/ring_buf_ops.march`, reject fixtures t159–t163, and `test/test_codegen.ml`'s declare/purity lists | **linear** (C2) |
| `NativeIntArr`, `NativeFloatArr`, `NativeF32Arr`, `NativeI32Arr`, `NativeU8Arr` | flat numeric arrays | **copy-on-write.** `set` and `sort` for all five widths (`march_runtime.c:10701`, `11028`, `11278`, `11295`, `11657`, `11673`, and the `DEF_NARROW_INT_ARR` macro near `11599`) and the SIMD vector store (`lib/tir/llvm_emit_simd.ml:~527`) write in place only at `rc == 1` and copy otherwise. The interpreter always copies (`lib/eval/eval_builtins.ml:4387`). Documented as "Return a new array … O(n)" | `stdlib/dataframe.march`, benches, ~35 `test/native/` programs, `examples/dataframe_basic.march` | **sendable** (C1), after the ordering fix (C0) |
| `TypedArray(a)` | DataFrame column storage | **always copies** (`march_typed_array_set`, `march_runtime.c:10365`) | `stdlib/dataframe.march` | sendable (already) |
| `Bytes` | wraps an immutable `String` | none | many | sendable (already) |
| `Vault` | process-global table | shared by design; every operation takes a runtime mutex (`march_runtime.c:~818`); atomic `put_new`/`incr`/`push_capped` exist | many | sendable, and safe to share |
| `CancelToken` | shared cancel flag | shared by design; `_Atomic int` with release store and acquire load (`runtime/march_scheduler.h:1076`, `march_scheduler.c:~4550`) | `Task` | sendable, and safe to share |
| `LiveProcess` | a running child process | an OS resource: `read_line`, `write`, `kill` and `wait_proc` share one pipe pair; `wait_proc` closes it | none outside `stdlib/process.march` | **linear** (C3): a resource, not a memory race of March values |
| `Pid`, `Cap`, `ActorCap`, `Task`, `WorkPool`, `TimerRef` | handles to scheduler objects | the runtime owns the state | many | sendable (A's Phase 1 audit re-confirms) |
| file descriptors | raw `Int` from `file_open` | an OS resource | `File`, `Seq` | out of reach of types; a typed handle is a separate project |

Found on the way, and filed separately because it is a plain runtime bug:
`march_process_spawn_async` takes a registry slot with an unguarded
`live_proc_next++` and reuses slots modulo `LIVE_PROC_MAX`, closing the pipes of
whatever process held the slot (`runtime/march_runtime.c:~9056`). Two tasks
spawning processes race on it; see
`specs/todos/2026-09-25-live-process-registry-unsynchronised.md`.

## The holes (why any of this is needed)

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

How each hole closes under C alone:
- **H1, H2, H5:** a closure cannot capture a linear `RingBuf`
  (`specs/lang/linear-types.md`, "Closures can't capture one"), and a captured
  native array is a shared immutable value.
- **H3:** an ADT holding a linear value is linear itself, so sending it is a move.
- **H4:** a generic function receives a linear value only through a parameter
  marked `linear`.
- **The `spawn(A, rb)` gap** from the original A/B plan: passing a linear value
  consumes it, so the spawner can't touch the buffer again.

## Order of work

| # | Phase | Effort | Depends on |
|---|---|---|---|
| 0 | Repro programs for H1–H5, confirmed against a built compiler | ½ day | — |
| C0 | Acquire ordering on every sole-ownership check | ½–1 day | — |
| C1 | Native arrays become sendable | 1 day | C0 |
| C2 | `RingBuf` becomes `always_linear`, with a consume-and-return API | 2–3 days | 0 |
| C3 | `LiveProcess` becomes `always_linear` | 1 day | — |
| C4 | Retire the sendability fixtures' `RingBuf` witness; docs; changelog | ½–1 day | C1, C2 |
| C5 | The rule for future mutable primitives, and A's Phase 1 as its guard | 1–1½ days | C4 |
| — | A's Phase 2 and B's Phases 3–5 | about 6½ days | only if C5's rule is ever waived |

About 7–9 days for C plus the guard. C0, C2 and C3 are independent of each other.

## Part C: the right ownership model for each mutable type

### Phase C0: make sole-ownership checks synchronise

Every in-place write in March depends on reading `rc == 1`: FBIP `reuse`,
native-array `set`/`sort`, the SIMD store. Those reads are a plain C load (the
native-array functions) or an LLVM `load atomic … monotonic`
(`lib/tir/llvm_emit_alloc.ml:391`, `709`, `791`; `llvm_emit_simd.ml:548`).
`march_decrc` is `acq_rel`, so another thread dropping its reference *releases*
its earlier reads of the object. But a relaxed load on this side doesn't
*acquire* them. Under the C11 model, a thread that sees `rc == 1` and then writes
has no happens-before edge with the other thread's last reads: a formal data
race. On x86, and in practice on ARM thanks to the control dependency, it
doesn't bite. It is also the exact pattern Rust's `Arc::get_mut` uses `Acquire`
for.

This is not new with C. A native array or a list captured by two
`task_spawn` closures crosses threads today. But C1 makes cross-thread native
arrays an advertised feature, so fix it first:

- **C runtime:** replace `((march_hdr *)arr)->rc == 1` with a helper,
  `march_rc_is_unique(p)`, that does
  `atomic_load_explicit(..., memory_order_acquire) == 1`. Grep for every
  `->rc == 1` in `runtime/`, not only the native-array functions.
- **LLVM:** `monotonic` becomes `acquire` at the four emit sites.
- **Cost:** free on x86-64 (a plain `mov`); `ldar` instead of `ldr` on arm64.
  Run `bench/tree_transform.march` (FBIP) and `bench/array_sort.march`
  compiled at `--opt 2` on arm64 before and after, per `specs/benchmarks.md`.
- **Check:** `scripts/check-actor-rc-stores.sh` still passes (it polices
  stores, not loads, but both touch the same word).

### Phase C1: native arrays are values, so let them be sent

1. **Audit, and record the result in the `native_array.march` header:** confirm
   that every in-place path is gated on sole ownership. Already confirmed in
   this plan's audit: `set` and `sort` at all five widths, and the SIMD store.
   Still to confirm: the inline `map`/`map2` reuse paths (the
   `test/native/native_arr_map_inline_reuse` family), `filter_mask`, the
   width conversions and `bytes_to_u8_arr`. Anything not gated is a bug to fix
   here: it is already an aliasing bug within one thread.
2. **Remove the five names from `non_sendable_types`**
   (`typecheck_exhaustive.ml:822`).
3. **Fixtures:** `reject/t164`, `t165`, `t169` and `t170` become `accept/`
   fixtures. `git mv` them, keeping their ids (the corpus shares one numbering
   pool), rename the files and rewrite the headers. Update
   `specs/lang/types/INDEX.md`. Two-repo rule: these flip a verdict in
   `march-lean` too.
4. **New tests:**
   - an actor that receives a native array, `set`s it, and replies, while the
     sender `set`s its own copy; each side must see only its own write
     (interpreted and compiled);
   - `Parallel.pmap` over a list, reading a captured native array;
   - two tasks each `set` the same captured array and keep their results. This
     is the copy-on-write race C0 protects; run it in a loop in the compiled
     suite.
5. **Docs:** the `native_array.march` header gets a "Sharing and sending"
   paragraph: value semantics, O(n) copy on the first write to a shared array,
   in place when threaded.

### Phase C2: `RingBuf` becomes linear

`RingBuf` mutates in place with no ownership check, which is what makes it
O(1) and allocation-free. Two ways to make that safe:

| Option | Aliasing | Cost | Verdict |
|---|---|---|---|
| Copy-on-write value, like native arrays | allowed, copies | hidden O(cap) copy whenever the buffer is aliased. In actor state, `push(state.buf, x)` can see `rc == 2`, because the state record still holds it, and copy on **every** push | rejected: a silent performance cliff in the intended use |
| `always_linear`, consume-and-return | impossible, checked | none at runtime: the in-place write stays unconditional; linearity is compile-time-erased | **chosen** |

Linear is also exactly how the stdlib already handles its one other
container with a single-owner discipline, `LinearMap`
(`stdlib/linear_map.march`), and its actor-state idiom carries over unchanged.

**Mechanism.** Add `"RingBuf"` to the initial `always_linear_types`
(`typecheck_env.ml:694`), next to where the builtin type is registered.
First confirm that the promotion rule (`core-march-types.md` §2.9.1) and the
"same-named types don't inherit linearity" resolution (finding L4) work for a
builtin `TCon` with no declaring module. If either doesn't, fall back to
`always_linear opaque type RingBuf(a) = RingBufRep(RawRingBuf(a))` in
`stdlib/ring_buf.march`, as `LinearMap` does, and check that the wrapper is
unboxed (`Bytes` kept its wrapper for layout reasons, so read its header first).

**API**, modelled on `LinearMap`:

```march
fn make(cap : Int) : RingBuf(a)
fn push(rb : RingBuf(a), x : a) : RingBuf(a)
fn pop(rb : RingBuf(a)) : (Option(a), RingBuf(a))
fn get(rb : RingBuf(a), i : Int) : (Option(a), RingBuf(a))
fn peek_oldest(rb : RingBuf(a)) : (Option(a), RingBuf(a))
fn peek_newest(rb : RingBuf(a)) : (Option(a), RingBuf(a))
fn size(rb : RingBuf(a)) : (Int, RingBuf(a))
fn cap(rb : RingBuf(a)) : (Int, RingBuf(a))
fn is_empty(rb : RingBuf(a)) : (Bool, RingBuf(a))
fn is_full(rb : RingBuf(a)) : (Bool, RingBuf(a))
fn clear(rb : RingBuf(a)) : RingBuf(a)
fn snapshot(rb : RingBuf(a)) : (List(a), RingBuf(a))   -- new: read out, keep the buffer
fn to_list(rb : RingBuf(a)) : List(a)                   -- ends the buffer
fn drop(rb : RingBuf(a)) : Unit                         -- new: ends the buffer
```

Elements stay unrestricted. `ring_buf_*` is generic without a `linear`
opt-in, so a linear element is already rejected; keep it that way, since a
buffer that silently overwrites its oldest element can't hold values that
must be consumed. Because elements are unrestricted, `drop` returns `Unit`,
unlike `LinearMap.dispose`, which must hand back a non-empty map.

**Builtins.** Change `ring_buf_push`/`ring_buf_clear` to return the buffer, and
the read builtins to return a pair, in all four places:
- `typecheck_builtins.ml:1626`;
- the interpreter's `VRingBuf` arms (still mutating the OCaml record in place);
- `runtime/march_runtime.c` (from ~11906);
- `lib/tir/llvm_builtins.ml` (~885).

The stdlib bodies then use each binding once and need no `@[trusted_linear]`.
Check that returning a `(Int, RingBuf)` pair doesn't allocate when the caller
destructures it immediately. If it does, add a small `bench/ring_buf.march`
(push/pop loop), and compare against today before and after.

**Actor state**, the documented use:

```march
actor Recent do
  state { buf : RingBuf(Int) }
  init  { buf: RingBuf.make(64) }
  on Seen(x : Int) do
    { state with buf: RingBuf.push(state.buf, x) }
  end
end
```

**Sending.** Remove `"RingBuf"` from `non_sendable_types`. A linear value can
be sent, and the send consumes it (`linear-types.md`, "Linear Types and
Actors"; compiled as the zero-copy `march_send_linear`). Moving a buffer to
another actor is now safe and, unlike today, allowed.

**Tests and callers to update:**
- rewrite `test/stdlib/test_ring_buf.march` (242 lines) and
  `test/native/ring_buf_ops.march` to the threaded API;
- update `test/test_codegen.ml`'s golden `declare` list (~13875);
- keep `ring_buf_push` in its purity list as impure (~3735);
- keep `test_ring_buffer` (~3453): it tests the OCaml `ring` helper, not the
  builtin;
- add `reject/` fixtures for each hole under the new rule: capture in a
  `Task.async` lambda, use after `push` without rebinding, use after `send`,
  and a generic `dup` of a buffer.

### Phase C3: `LiveProcess` becomes linear

`LiveProcess` is a resource whose operations interleave badly if shared. Two
tasks `read_line` from one pipe, or one `wait_proc` closes the pipe while the
other reads. It is the typestate `Handle` pattern (`stdlib/handle.march`) the
stdlib already recommends:
- declare the type `always_linear` in `stdlib/process.march`;
- `read_line(p) : (Option(String), LiveProcess)`;
- `write(p, s) : LiveProcess`;
- `kill(p) : LiveProcess`;
- `wait_proc(p) : ProcessResult` ends it.

Nothing outside `stdlib/process.march` calls these (grep over `stdlib/`,
`test/`, `examples/`, `forge/`, `lsp/`, `bench/`), so the API change is
contained. The one other pin is `test/test_codegen.ml`'s golden `declare`
list (~13758).

The bodies must use `p` once each. There are two ways:
- **Destructure and rebuild:** `LiveProcess(pid, id)` is an ordinary two-field
  ADT, so destructure it once, pass the fields to the builtins, and rebuild
  the handle in the result. That costs one small allocation per call.
- **Change the builtins** to return the handle, as for `RingBuf`, which keeps
  the golden list in step.

Prefer the second. The
registry race above is a separate runtime fix and doesn't wait on this.

### Phase C4: fixtures, docs, changelog

- **Fixtures `reject/t159`–`t163`** use a `RingBuf` payload to prove every
  send path (`send_checked`, `Actor.cast`, `Actor.call`, qualified and bare)
  runs the sendability check. After C1 and C2 no type fails that check, so
  they lose their witness. Keep the per-path coverage by rewriting each one to
  send a `RingBuf` through that path and then use it: each must reject with
  the linearity error, proving every path is a consuming use. Update their
  `EXPECT-ERROR` lines and the INDEX, and apply the two-repo rule.
- **`accept/t40`'s** comment mentions the `RingBuf` family. Reword it.
- **`specs/lang/`, then run `scripts/gen-lang-docs.py`:**
  - `actors.md` (~130, ~664, ~1045): the non-sendable paragraph becomes
    "linear values move, everything else is immutable or copy-on-write";
  - `linear-types.md`: add `RingBuf` next to `LinearMap` as a stdlib linear
    type;
  - `core-march-types.md` (~2402, ~5283): the `check_sendable` description;
  - `memory-model.md`: C0's ordering rule;
  - `parallelism.md` (~240): native arrays are fine to share with parallel
    code.
- **`CHANGELOG.md`:** `### Changed`: the `RingBuf` and `Process.*` live-process
  APIs are breaking changes; native arrays may now be sent. `### Fixed`: C0.
- **`.claude/skills/march-lang/SKILL.md`:** check its `RingBuf` examples.

### Phase C5: the rule for the next mutable primitive, and its guard

Write into `specs/lang/memory-model.md` (and the `non_sendable_types` doc
comment):

> A builtin type whose operations write memory another March reference could
> observe must be either `always_linear`, or copy-on-write gated on sole
> ownership (`march_rc_is_unique`). A type that is neither must be listed as
> non-`Send`, and adding the first such type requires Parts A and B of
> `specs/plans/2026-09-25-send-data-race-freedom-plan.md` first.

Then land **A's Phase 1** (`is_send`, the structural walk) with the primitive
list empty. It is cheap, and it means the first entry added to the list is
checked through user ADTs and fields from day one. Add a unit test that fails
if a name is added to the list while B's closure check is absent, so the rule
can't be skipped by accident.

## Parts A and B (deferred unless C5's rule is waived)

Everything below is the original plan for a general `Send` check. Phase 1 lands
as part of C5. The rest is only needed once March has a type that is neither
linear nor copy-on-write; until then it would guard an empty set.

### A/B design decisions

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

### A/B phases

Phase 0 is shared with Part C and runs first either way. Phase 1 lands in C5.

| # | Phase | Effort | Depends on |
|---|---|---|---|
| 0 | Repro fixtures for H1–H5 | ½ day | — |
| 1 | `is_send`: structural judgement over types (A, fixes H3) | 1–1½ days | 0 |
| 2 | `Send` as a bound, and inferred `Send` bounds (A, fixes H4) | 1½ days | 1 |
| 3 | Boundary registry, and value-level closure check at builtins (B, fixes H1/H2/H5 for literals) | 2 days | 1 |
| 4 | Send-demand summaries across functions (B, fixes H1/H2 through wrappers) | 2 days | 3 |
| 5 | Diagnostics, docs, corpus, rollout decision | 1–1½ days | 2, 4 |

About 8–9 days on their own, or about 6½ after C5. Phases 2 and 3 are independent of each other once 1
lands, and can go in either order or in parallel.

#### Phase 0: fixtures first

Write one program per hole and confirm, with a built compiler, that each one
type-checks today. That confirmation is the evidence this plan currently lacks.
Record the programs in the todo file. The typing corpus
(`specs/lang/types/check_types.sh`) has no expected-failure lane, so each
program moves into `specs/lang/types/reject/` (next free id; update
`specs/lang/types/INDEX.md`, whose counts doc-lint checks) in the same commit
as the phase that makes it fail. `accept/` fixtures for what must keep working
can land in Phase 0 directly:

- a `RingBuf` as actor initial state (`spawn(A, rb)` is a *move*; with C2, it is a consuming use);
- a native array sent in a message and captured by a task (C1);
- `Parallel.pmap` over a pure lambda that captures an immutable `Map`;
- a message carrying a closure that captures only immutable values;
- a closure capturing a `RingBuf` used only on its own thread (never crosses).

**Two-repo rule:** new `reject/` fixtures and new ERROR-level checks must be
mirrored in `march-language/march-lean` (see the INDEX header). Plan for
the dispatch run after each merge, or file a ledgered skip there.

#### Phase 1: `is_send`, a structural judgement

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

#### Phase 2: `Send` as a bound, including inferred bounds

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

#### Phase 3: thread boundaries and the value-level closure check

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
today; Part C's Phase C2 closes it for `RingBuf`, because passing a linear
value consumes it. Any later non-`Send` primitive should come with the same
guarantee, per C5's rule.

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

#### Phase 4: send-demand summaries

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

#### Phase 5: diagnostics, documentation, rollout

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

## A/B audit already done while writing this plan

- No stdlib module passes a `RingBuf` or `NativeArray` into `task_spawn`,
  `Task.*` or `Parallel.*` (grep over `stdlib/*.march`). Phase 1–4 errors on
  stdlib code would therefore be bugs in the check, not in the stdlib.
- `Vault` is not in `non_sendable_types` and should stay `Send` (per D1).
- `actor_send_after` sends a message constructor, so the existing site
  already covers it.

## Verification, for every phase

- C0 and C1 touch the runtime and codegen: run `scripts/ir-oracle.sh`
  (C0 should change exactly the four `monotonic` loads and nothing else), the
  compiled `test/native/` suite, and the benchmarks named in C0.

- `scripts/run-tests.sh` (full), plus the typing corpus via
  `specs/lang/types/check_types.sh`.
- `scripts/types-oracle.sh` baseline/check, run under a private `HOME`. Prove
  it goes red on a deliberate perturbation first (CLAUDE.md). The expected
  diffs are the new rejections and inferred `Send` bounds, nothing else.
- `scripts/check-docs.sh` after the documentation phase.
- For Parts A and B, no IR, runtime or benchmark effect is expected, because
  the check is typecheck-only. Run `scripts/ir-oracle.sh` once at the end to
  confirm.

## Open questions

1. **Closures in ADT fields** (D5): warn at the crossing, or track "built from
   a `Send` closure" at construction? Decide from Phase 5's numbers.
2. **The `spawn`-argument move gap:** resolved; Phase C2 closes it with
   linearity.
3. **`RingBuf`'s mechanism** (C2): the seeded builtin name or the opaque
   wrapper. It depends on whether L4's "same-named types" resolution handles a
   builtin `TCon`; answer it with a two-line fixture before starting C2.
4. **Should a buffer be droppable without a call?** `always_linear` forces an
   explicit `drop`/`to_list`. An `always_affine` declaration would let a
   buffer of plain values be dropped silently, which is closer to how
   `RingBuf` is used today. That needs parser, typechecker and `march-lean`
   work. Decide after C2 lands, from how noisy `drop` turns out to be in the
   rewritten tests.
5. **Should `Send` inference be visible in public signatures**, or only in
   diagnostics? The plan makes it visible (Phase 2, step 5), because an
   invisible bound on a public function is a breaking change nobody can see.
