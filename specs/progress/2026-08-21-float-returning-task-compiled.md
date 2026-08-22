# A Float-returning Task now works compiled

Filed 2026-08-20 as "`Task.async` with a Float-returning thunk does not compile
(invalid LLVM IR)". Landed 2026-08-21. The title was mis-scoped: the build
break was the *second* of two independent defects, and the first one — which
silently SIGSEGVed rather than failing to build — affected **every**
Float-returning task, `Task.async` or not.

## What was broken

```march
let t = task_spawn(fn _ -> 2.5)
match task_await(t) do
  Ok(v)  -> println(int_to_string(float_to_int(v *. 2.0)))
  Err(_) -> println("err")
end
```

* interpreted: `5`
* compiled, every `--opt` level: **SIGSEGV (rc=139), no output**

and the `Task.async(fn () -> 1.5)` spelling additionally did not compile at
all:

```
error: '%ldN' defined with type 'double' but expected 'i64'
march: clang failed (exit 1)
```

A documented stdlib API — `Task.async` / `Task.await` on a Float — was
unusable natively while the interpreter returned the right answer. There was
**no** suite coverage of a Float-returning task, which is why it shipped.

## Defect 1 (the crash) — `task_await` decoded a value it should only normalize

`lib/tir/llvm_emit.ml`, the `task_await` arm.

The thunk trampoline (`march_thunk_trampoline`, `runtime/march_runtime.c`)
stores `task[3] = (apply_ret << 1) | 1` — the apply wrapper's uniform-slot
return value, tagged exactly once. `march_task_await` wraps that verbatim into
an `Ok`. The emit site's job is to turn the raw `task[3]` back into
`apply_ret`, so that the `Ok` payload holds what an ADT field is supposed to
hold. `task[3]` is always odd, so one unconditional `ashr i64 %v, 1` is the
exact inverse — for `i64`, `ptr`, **and** `double` alike.

The `double` arm did that ashr and then kept going: it called
`march_unbox_float` on the recovered pointer and stored the raw `double` bits
back into the payload slot. But a Float's uniform representation *is* the
`march_alloc_float` box pointer — the apply fn boxed it through the generic
`coerce` `"double"->"ptr"` arm before returning — so the `Ok(v)` destructure
applies its own `"ptr"->"double"` coerce and calls `march_unbox_float` a
**second** time. On the IEEE-754 bit pattern. For `2.5` that dereferences
address `0x4004000000000000`.

Fix: the `double` payload takes the same single `ashr` as the other two and
nothing more. Decoding is the destructure's job, not this site's. The three
`llvm_ty` outputs (`i64` / `ptr` / `double`) now share one code path, which is
also why the arm no longer needs to inspect the Task's inner type at all.

Note the contrast with `task_await_unwrap`'s `double` arm, which **does**
unbox and is correct to: it yields the scalar as its expression value rather
than as an ADT field. The two sites pull in opposite directions on purpose;
both now say so in their comments.

The todo's earlier "layer 2" diagnosis — that the `ashr` itself was wrong
because a box pointer is even — was a **misdiagnosis**, and worth recording so
nobody re-derives it. It overlooked that the trampoline tags *everything* it
stores, box pointers included. Removing the `ashr` would have been a second
bug; the extra unbox was always the whole of it.

## Defect 2 (the build break) — a zero-arg lambda's closure typed as its return type

`lib/tir/lower.ml`, `lower_to_atom_k`'s generic arm.

The temp that holds a lowered lambda was typed from `ty_of_expr env e`, i.e.
the source **span**, which for a zero-arg lambda hands back the RETURN type
instead of `() -> ret`. `Task.async(f)` is `task_spawn(fn _ -> f())`
(`stdlib/task.march`), so the inner thunk captures `f : () -> Float` — and the
capture was typed `Float`. Codegen then loaded a closure pointer with
`load double` and fed a `double` to `inttoptr i64`, which clang rejects.

`lower_expr`'s `ELam` case already builds the authoritative type: it returns
`ELetRec ([fn], EAtom (AVar fn_var))` with
`fn_var.v_ty = TFn (param_tys, ret_ty)` assembled from the `fn_def` it just
constructed. Fix: when the lowered form has that shape, take the temp's type
from `fn_var.v_ty` rather than from the span. Binder type and emitted function
signature now agree by construction.

This is not Float-specific. An **Int** thunk was mistyped identically and only
appeared to work because i64 and ptr share a register, so the bogus `inttoptr`
was an ABI no-op — the same works-by-luck shape as an even tagged scalar
surviving a spurious untag. Float was simply the type where the register file
disagreed loudly enough to surface it.

### Adjacent hazard, now pinned rather than fixed

With the capture typed correctly, `Task.async`'s inner thunk
(`fn _ -> f()`) mono'd to `fn_ret_ty = () -> Float` rather than `Float`. That
is imprecise, but the emitted code is **right**, and for a load-bearing reason:
`llvm_ty` maps `TFn _` to `ptr`, the thunk returns whatever `f()` returned
verbatim, and what `f()` returned is a float box — a pointer. Only the awaiting
side, which knows the Task's inner type, decodes it. A pass-through wrapper
being representation-agnostic is the correct design here.

The hazard is that "tightening" that `fn_ret_ty` to `Float` would map it to
`double`, and the C trampoline reads its result out of the **integer** return
register:

```c
typedef void *(*apply_fn_t)(void *, int64_t);
apply_fn_t apply = *(apply_fn_t *)((char *)clo + 16);
void *result = apply(clo, (int64_t)0);
```

An apply fn that returned a raw `double` would leave it in `d0` while the
trampoline reads `x0` — silent garbage, no crash at the boundary. A task
thunk's apply fn must return in the integer register. Not defended in code;
the two fixtures below are what catch it, since a wrong register shows up
immediately as a wrong value.

## Order matters

Defect 1 alone fixes the one-arg repro. Defect 2 alone turns "does not
compile" into "compiles and crashes" — strictly worse for a user, which is why
the 2026-08-20 attempt that landed only the typing half correctly reverted
itself. Measured three-way, with the fixtures below:

| sources | `task_spawn_float_thunk` | `task_await_float` |
| --- | --- | --- |
| neither fix | compiles, SIGSEGV rc=139, no output | clang error, no binary |
| defect 1 only | **passes** | clang error, no binary |
| both | **passes** | **passes** |

## Tests

* `test/native/task_spawn_float_thunk.march` — the raw one-arg
  `task_spawn`/`task_await` builtin pair, isolating defect 1 (a one-arg thunk
  never reaches the zero-arg typing path). Capture-free **and** capturing
  thunks, since those are different RC paths into the same trampoline. The Int
  legs are the control: same code path, previously unpinned, passing by luck.
* `test/native/task_await_float.march` — the documented stdlib surface
  (`Task.async` / `await` / `await_unwrap` / `await_many` / `async_stream`) on
  Float. Needs both fixes.

Both are native compiled-and-run goldens wired into `test/dune`, run under
`MARCH_NUM_SCHEDULERS=1` for deterministic ordering. Floats print as scaled
Ints rather than through `float_to_string`: the subject is the Float
*representation* crossing the task boundary, not its rendering, and
`float_to_string` has several backends. Every constant is exactly
representable in binary FP, so the scaling is exact.

## Follow-on

`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md` was blocked on
this item and is now unblocked. Its **site 2** (`task_await`'s Result-path
float unbox) no longer exists — that unbox *was* defect 1 and is gone; the box
is now handed to the `Ok` payload as an ordinary boxed field. Its site 1
(`task_await_unwrap`) is still open and is now reachable for leak-probing.


---

# Independent corroboration from a concurrent session (carried over)

While this was being fixed, the uniform-ABI leak work (#321) re-measured the
same bug on `d5576f20` and recorded the following in the todo this file
supersedes. It is preserved here because it reached the layer-3 conclusion by a
different route, and because it is the evidence that the trampoline was never
at fault:

> Confirms the 1-arg repro exactly: `task_spawn(fn _ -> 2.5)` +
> `match task_await(t)` -> compiled rc=139, interpreted `5`. One NEW fact that
> narrows layer 3: **`task_await_unwrap` on the same task WORKS** — compiled ==
> interpreted == correct value, and double-await of the same task returns the
> value twice. So the trampoline's store side and `task_await_unwrap`'s decode
> side agree; only `task_await`'s Ok-payload path (layer 2's in-place field
> rewrite) is on the crashing path.

That is exactly what the fix turned out to be: `task_await_unwrap` performs the
single `ashr 1` and stops, which is correct; `task_await`'s `double` arm did the
same `ashr` and then additionally unboxed and stored raw double bits back into
the payload, so the `Ok(v)` destructure unboxed a second time. Two independent
investigations converging on the same site is worth more than either alone.

The same note also observes that the working `task_await_unwrap` route leaks one
Float box per await, and that a double-await makes releasing at the unbox site a
use-after-free — so the box's owner has to be the Task object's free path. That
ownership analysis is tracked in
`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md` and
`specs/todos/2026-08-21-task-object-never-freed.md`, both still open and both
now unblocked by this fix.
