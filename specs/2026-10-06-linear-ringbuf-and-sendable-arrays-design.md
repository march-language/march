# Design: data-race freedom for March's mutable types

**Date:** 2026-10-06
**Plan this specifies:** `specs/plans/2026-09-25-send-data-race-freedom-plan.md`
(Part C). The plan says what to change and in what order; this document says
what a March program can and cannot do once it has landed, so the semantics
can be argued with before anything is built.
**Closes, with the plan:** `specs/todos/2026-09-25-send-marker-and-closure-capture-checks.md`.

March's freedom from data races rests on three facts: ordinary data is
immutable, actors share nothing, and in-place updates happen only when a value
has one owner. Six builtin types sit outside those facts: `RingBuf` and the
five `NativeArray` backing types (`NativeIntArr`, `NativeFloatArr`,
`NativeF32Arr`, `NativeI32Arr`, `NativeU8Arr`). Today a single check keeps
them on one thread, it runs only on actor-message payloads, and it can be
bypassed through a closure capture, a user type's field, a type variable, a
task, an HTTP handler, a module-level `let`, `Vault`, or a twice-awaited
task (holes H1–H8 in the plan). This design removes the exceptional category
instead of patching the check: after it, every value in a March program is
either immutable, copy-on-write under a sole owner, or linear.

---

## 0. Where things stand (read at `33527ba9`; probed 2026-10-06, see the todo)

| | Today | After |
|---|---|---|
| `RingBuf` | mutable in place, every alias sees every `push`; rejected in message payloads by name | `always_linear`; every operation consumes the buffer and hands it back; may be sent |
| `NativeIntArr` and the other four | copy-on-write (in place only at `rc == 1`); rejected in message payloads by analogy with `RingBuf` | an ordinary sendable value; same copy-on-write |
| the sendability denylist | six names | empty, and a rule for what may join it (§1) |
| sole-ownership check | relaxed load | acquire load |
| a dead linear value's memory | shallow-freed; a resource cell's destructor is skipped | destructor runs |

Phase 0 of the plan wrote the eight hole programs
(`specs/lang/types/staging/h1`–`h8`) and confirmed with a built compiler that
every one type-checks today; this document's "rejected" examples (§3.5) are
what those programs must become. The results are recorded in the todo.

---

## 1. The rule

> A builtin type whose operations write memory that another March reference
> could observe is either **`always_linear`** or **copy-on-write gated on sole
> ownership**. A type that is neither may not be added to the standard library
> or the runtime without first landing the general `Send` check (Parts A and B
> of the plan).

Everything below is this rule applied to the two kinds of type that exist.
The sendability denylist stays in the compiler with zero entries and a unit
test that fails if a name is added while the `Send` check is absent, so the
rule is enforced by the build, not by memory.

---

## 2. Native arrays are values

### 2.1 Semantics

A `NativeArray` value behaves exactly as its documentation already says:
`set_int(arr, i, v)` "returns a new array", `sort_int(arr)` sorts "in place
when the array is uniquely owned". The runtime writes in place when the
caller held the only reference and copies otherwise; the interpreter always
copies. No program can tell the two apart. So a native array is a value, and
a value may go anywhere a value goes:

```march
actor Summer do
  state { total : Float }
  init  { total: 0.0 }
  on Add(xs : NativeFloatArr) do
    { state with total: state.total +. NativeArray.sum_float(xs) }
  end
end

fn main() do
  let xs = NativeArray.from_list_float([1.0, 2.0, 3.0])
  let s  = spawn(Summer)
  send(s, Add(xs))                                  -- accepted after this design
  let ys = NativeArray.set_float(xs, 0, 9.0)        -- the sender's own copy
  let t  = Task.async(fn () -> NativeArray.sum_float(xs))   -- also fine
  ()
end
```

The sender's `set_float` sees a shared array (`send` and the task both hold
it) and copies; the actor's `xs` is untouched. Each side sees only its own
writes.

### 2.2 Cost model, stated for users

- A write to an array nobody else holds is in place: O(1) for `set`, O(n log
  n) for `sort`, no allocation.
- The first write to a *shared* array copies it: O(n), one allocation. Later
  writes to the copy are in place again.
- Sending, capturing in a closure, or storing in a record shares the array.
  A loop of `let arr = NativeArray.set_int(arr, i, v)` that threads the array
  through never shares it and never copies.

This paragraph goes into `stdlib/native_array.march`'s header as "Sharing and
sending".

### 2.3 The ordering guarantee

The in-place path reads "is my reference the only one" and then writes. When
another thread dropped its reference a moment earlier, the drop releases that
thread's last reads of the array, and the sole-ownership read must *acquire*
them or the write races with those reads under the C11 model. Today the read
is relaxed in both the C runtime and the LLVM-emitted FBIP reuse. This design
makes it an acquire load (`march_rc_is_unique`), which is free on x86-64 and
one `ldar` on arm64. It applies to every sole-ownership check, not only
native arrays: FBIP reuse of any value has the same shape.

### 2.4 What the typechecker stops doing

The five names leave the denylist. Four conformance fixtures that reject a
native array in a message (`reject/t164`, `t165`, `t169`, `t170`) become
`accept/` fixtures with the same ids. `march-lean` mirrors the flip.

---

## 3. `RingBuf` is linear

### 3.1 Why linear and not copy-on-write

`RingBuf` exists to be O(1) and allocation-free after `make`. Copy-on-write
would keep aliasing legal and copy O(cap) whenever the buffer is shared, and
the documented use, a buffer in actor state, shares it on every turn: the
state record still holds the buffer while the handler pushes to it. The copy
would fire on every `push`. Linearity keeps the unconditional in-place write
and makes aliasing a compile-time error instead. It is also how the standard
library already treats its one other single-owner container, `LinearMap`,
so the idioms carry over.

### 3.2 Declaration

`RingBuf(a)` is a builtin type registered as `always_linear`, exactly as if
the standard library had written

```march
always_linear type RingBuf(a)
```

Every binding of a `RingBuf` is tracked as linear with no `linear` keyword at
any use site. A record field or actor-state field of type `RingBuf(a)`, or of
a type that holds one such as `Option(RingBuf(a))`, is a linear field.
Elements (`a`) stay unrestricted (§3.5).

### 3.3 The API

Every operation consumes the buffer. A mutator returns it; a reader returns
its answer beside it; a terminator ends it.

```march
fn make(cap : Int) : RingBuf(a)                        -- panics if cap <= 0

fn push(rb : RingBuf(a), x : a) : RingBuf(a)           -- overwrites the oldest when full
fn clear(rb : RingBuf(a)) : RingBuf(a)

fn pop(rb : RingBuf(a)) : (Option(a), RingBuf(a))
fn get(rb : RingBuf(a), i : Int) : (Option(a), RingBuf(a))    -- 0 = oldest
fn peek_oldest(rb : RingBuf(a)) : (Option(a), RingBuf(a))
fn peek_newest(rb : RingBuf(a)) : (Option(a), RingBuf(a))
fn size(rb : RingBuf(a)) : (Int, RingBuf(a))
fn cap(rb : RingBuf(a)) : (Int, RingBuf(a))
fn is_empty(rb : RingBuf(a)) : (Bool, RingBuf(a))
fn is_full(rb : RingBuf(a)) : (Bool, RingBuf(a))
fn snapshot(rb : RingBuf(a)) : (List(a), RingBuf(a))   -- new: read out, keep the buffer

fn to_list(rb : RingBuf(a)) : List(a)                   -- ends the buffer
fn drop(rb : RingBuf(a)) : Unit                         -- new: ends the buffer
```

Complexity is unchanged: every operation is O(1) except `snapshot` and
`to_list`, which are O(n). Overwrite semantics are unchanged: `push` on a
full buffer silently drops the oldest element.

### 3.4 What a program can write

**A buffer in actor state.** The state owns the buffer; each handler that
reads it stores one back. This is the `LinearMap` idiom:

```march
actor Recent do
  state { buf : RingBuf(Int) }
  init  { buf: RingBuf.make(64) }

  on Seen(x : Int) do
    { state with buf: RingBuf.push(state.buf, x) }
  end

  on Dump() do
    let (items, buf) = RingBuf.snapshot(state.buf)
    println(show(items))
    { state with buf: buf }
  end
end
```

**A local buffer, threaded.** Rebind on every call; end it with `to_list` or
`drop`:

```march
fn last_three(xs : List(Int)) : List(Int) do
  let rb = List.fold_left(xs, RingBuf.make(3), fn (rb, x) -> RingBuf.push(rb, x))
  RingBuf.to_list(rb)
end
```

**Moving a buffer to another actor.** A send is the consuming use. This is
rejected today ("cannot be sent in actor messages") and accepted after this
design, because a moved buffer has exactly one owner on either side of the
move:

```march
let rb = RingBuf.make(8)
send(worker, Take(rb))     -- consumes rb
```

**A buffer as a `spawn` argument** is the same move: `spawn(Recent, rb)`
with `init(buf : RingBuf(Int))` consumes `rb`.

### 3.5 What a program cannot write, and what it is told

Every rejection below is an existing linearity error that `always_linear`
brings to `RingBuf` for free, except the module-level `let` rule, which is
new. The quoted text is the message the compiler already prints for other
linear types.

| Program | Error |
|---|---|
| `RingBuf.push(rb, 1)` then `RingBuf.size(rb)` (using the old binding after a call) | `` The linear value `rb` is used more than once here. `` pointing at both uses |
| `let rb = RingBuf.make(4)` and never ending it | `` The linear value `rb` was never used. `` |
| `Task.async(fn () -> RingBuf.push(rb, 1))`, or any closure over `rb` (H1, H2, H5) | `` The linear value `rb` cannot be captured by a closure `` |
| `send(s, Put(Wrap(rb)))` then using `rb` (H3) | the double-use error: a value holding a linear value is linear |
| `dup(rb)` where `fn dup(x) do (x, x) end` (H4) | `` `rb` is linear, but `dup` is generic in a parameter of that type, so it may drop or duplicate the value. `` with the `linear x : a` hint |
| `let _ = rb` | `` This `_` discards the linear value `rb` `` |
| `Vault.set(t, "k", rb)` (H7) | the generic-parameter error above: `vault_set` is generic in its value and does not opt in |
| `Task.async(fn () -> RingBuf.make(4))`, so that `Task.await(t)` could run twice (H8) | the generic-parameter error above, at the `Task.async` call: `task_spawn` is generic in its closure's result and does not opt in, so a `Task(RingBuf)` is never created and the second `await` is unreachable |
| a module-level `let rb = RingBuf.make(8)` (H6) | **new:** `` `rb` has the linear type `RingBuf(Int)`, so it cannot be a module-level `let`: a module-level value is shared by every function and every actor, and a linear value must be consumed exactly once. Create it where it is used, or keep it in an actor's state. `` |

The module-level rule applies to every `always_linear` type, so `Handle` and
`LinearMap` get it too; today both are silently accepted at module level.

Two of these rows were assumptions about the existing checker; Phase 0
probed both with an existing `always_linear` type. The generic-parameter rule
does fire for a *builtin* generic (`vault_set`) as well as for the stdlib
wrapper (`Vault.set`), so the H7 row stands as written. The "container holding
a linear value" rule does *not* reach the opaque `Task` type
(`contains_linear` excludes opaque handles deliberately), but it never needs
to: the H8 row was rewritten above, because `Task.async` of a linear result is
already rejected at the spawn, one step earlier than the plan assumed.

### 3.6 Elements

Elements are unrestricted. A `RingBuf` overwrites its oldest element without
telling anyone, so it cannot hold a value that must be consumed; the generic
`ring_buf_*` builtins do not opt in to linear elements, and
`RingBuf.make` of a linear element type is rejected by the generic-parameter
rule above. `drop` therefore returns `Unit` rather than handing a non-empty
buffer back the way `LinearMap.dispose` must.

### 3.7 Interpreted and compiled

The two backends must agree on every program in §3.4 and §3.5 and on the
conformance corpus. In the interpreter the buffer is a mutable OCaml record
mutated in place and handed back; `drop` is a no-op. In compiled code the
buffer is one resource cell with the reference-count contract in §4. The
contract is invisible to programs; a test that prints `snapshot` before and
after every operation in both modes pins the agreement.

---

## 4. The runtime contract (summary; the plan's C2 has the full table)

A live `RingBuf` cell has `rc == 1` from `make` to its terminator, and no
compiler-emitted reference-count operation ever touches it. Every builtin
consumes the buffer and returns the same cell (`push`, `clear`), or the same
cell inside a fresh pair (every reader), or releases it (`to_list`, `drop`).
Three facts of the compiled pipeline make this work with no new machinery:
Perceus emits no increment or decrement for a linear variable; destructuring
`let (v, rb2) = …` moves the components out and frees only the pair's shell;
and a linear send hands the single reference to the mailbox without copying.

Two runtime changes come with it: the ten `ring_buf_*` builtins move from
"borrowed" to "owned" in the compiler's borrow table, so the contract holds
on the one path where a buffer is reached through an unrestricted record
field; and `march_free`, which releases a dead linear value, runs a resource
cell's destructor rather than skipping it, so a dead buffer, once one can
exist (§8, question 2), frees its elements and its store.

---

## 5. Migration

`RingBuf` has no callers outside its own module and tests, so the breaking
change is contained. For anyone with one:

| Before | After |
|---|---|
| `RingBuf.push(rb, x)` | `let rb = RingBuf.push(rb, x)` |
| `RingBuf.clear(rb)` | `let rb = RingBuf.clear(rb)` |
| `let n = RingBuf.size(rb)` | `let (n, rb) = RingBuf.size(rb)` |
| `match RingBuf.pop(rb) do …` | `let (x, rb) = RingBuf.pop(rb)` then `match x do …` |
| `RingBuf.to_list(rb)` and keep using `rb` | `let (items, rb) = RingBuf.snapshot(rb)` |
| letting `rb` go out of scope | `RingBuf.drop(rb)` or `RingBuf.to_list(rb)` |
| a buffer in state, `RingBuf.push(state.buf, x)` then `state` | `{ state with buf: RingBuf.push(state.buf, x) }` |

`CHANGELOG.md`: `### Changed` for the `RingBuf` API; `### Added` for native
arrays in messages and tasks; `### Fixed` for the ordering and `march_free`
changes.

---

## 6. Language reference changes this implies

Edits to `specs/lang/`, regenerated into `docs/` by `scripts/gen-lang-docs.py`:

- **`actors.md`**, the "message payload may not carry a mutable-buffer type"
  paragraph: replaced by "a linear value moves on send, and everything else is
  immutable or copy-on-write", with §3.4's send example.
- **`linear-types.md`**: `RingBuf` listed beside `LinearMap` as a standard
  library linear type, with §3.4's actor example; the module-level `let` rule
  added to "Practical Rules".
- **`memory-model.md`**: §1's rule, and §2.3's ordering guarantee under
  "Parallel FBIP needs no locks".
- **`parallelism.md`**, the "function must be safe to run concurrently" rule:
  a native array may be read from parallel code; a `RingBuf` cannot be
  captured at all.
- **`core-march-types.md`**: the `check_sendable` description, now a
  zero-entry list with the rule.

The standard library's own documentation: `stdlib/ring_buf.march`'s header
(the "Shared-reference semantics" paragraph is deleted; the ownership contract
becomes §3.3), `stdlib/native_array.march`'s header (§2.2), and the
`march-lang` agent skill's one-line `RingBuf` mention.

---

## 7. Out of scope

- **`LiveProcess` as a linear handle.** Its memory-safety case was closed by
  the registry fix (PR #680). Deferred; the plan's C3 keeps the reasoning.
- **A general `Send` marker and closure-capture analysis** (Parts A and B).
  Needed only if §1's rule is ever waived.
- **Purity requirements on `Parallel.*`** (item D of the original review).
- **More compound atomic `Vault` operations** (item E); `put_new`, `incr` and
  `push_capped` already exist.
- **File descriptors** are raw `Int`s and out of reach of types; a typed
  handle is its own project.

---

## 8. Decisions and open questions

**Settled here.**

1. `RingBuf` is linear, not copy-on-write (§3.1).
2. Native arrays are sendable values (§2).
3. The sendability list stays, empty, as the enforcement point for §1's rule.
4. Readers return pairs. There is no non-consuming use of a linear value in
   March, so a read must hand the buffer back; `LinearMap.size` already
   pays the same pair.
5. An `always_linear` type is rejected in a module-level `let` (§3.5).

**Open.**

1. **Affine buffers.** `always_linear` forces every buffer to end in `drop`
   or `to_list`. An `always_affine` declaration would let a buffer of plain
   values go out of scope silently, closer to how `RingBuf` is used now, at
   the cost of parser, typechecker and `march-lean` work. Decide after the
   rewritten tests show how noisy `drop` is; §4's `march_free` change must
   land first either way, since it is what makes a dead buffer safe to drop.
2. **Unboxed pairs.** A reader's pair is a 32-byte allocation in compiled
   code. If the `RingBuf` benchmark shows it, the follow-up is an unboxed
   `(Int, RingBuf)` return; today's inline-struct support covers only
   `TCon`s.
