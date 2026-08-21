# `Task.async` with a Float-returning thunk does not compile (invalid LLVM IR)

Filed 2026-08-20, found while trying to build a `task_await`-on-Float leak
probe for
`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md`.

## Repro

```march
mod MinAwait do
  needs IO.Console
  needs IO.Spawn
  fn main(_c : Cap(IO.Console), _s : Cap(IO.Spawn)) do
    let t = Task.async(fn () -> 1.5)
    match Task.await(t) do
      Ok(v)  -> println(float_to_int(v *. 2.0))
      Err(_) -> println(-1)
    end
  end
end
```

* Interpreted: prints `3`. Correct.
* `--compile --opt 2` (and `--opt 0`): **clang rejects the emitted IR.**

```
min_await.ll:708:24: error: '%ld95' defined with type 'double' but expected 'i64'
1 error generated.
march: clang failed (exit 1)
```

## Diagnosis

`Task.async(f) = task_spawn(fn _ -> f())` (`stdlib/task.march:39`). The inner
thunk captures `f : () -> Float`. In the thunk's apply fn the capture is loaded
with the **return** type's LLVM representation instead of the function type's:

```llvm
%ld91 = load ptr, ptr %$clo.addr
%fp92 = getelementptr i8, ptr %ld91, i64 24
%fv93 = load double, ptr %fp92, align 8    ; <- capture is a CLOSURE, not a double
%f.addr = alloca double
...
%ld95 = load double, ptr %f.addr
%cv96 = inttoptr i64 %ld95 to ptr          ; <- then called as a closure
%fp97 = getelementptr i8, ptr %cv96, i64 16
%cr99 = call ptr (ptr) %fv98(ptr %cv96)
```

So the captured variable `f`, whose type is `() -> Float`, is being given the
LLVM type of `Float`. The bug is in how the capture's TIR type reaches
`llvm_ty` — a `TFn (_, TFloat)` collapsing to its return type — not in the
task machinery itself. Compare the still-open non-`"_"` dangling-TVar item in
`mono.ml`'s `build_subst`/`match_ty`, and
`specs/progress/2026-07-14-mono-wildcard-tvar-collapse.md` for the shape of the
`"_"` variant that was already fixed.

Int- and ptr-returning tasks are unaffected (`test/native/task_await_int.march`,
`task_await_ptr.march` — note there is no Float fixture, which is why this was
never caught).

## Severity

Higher than a leak: it is a hard build failure, and it is silent about its real
cause (the user sees a clang type error in generated IR, not a March
diagnostic). Any program that spawns a task computing a Float — a parallel
numeric reduction, an async timing/measurement task — cannot be compiled.

## Blocks

`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md` — the two Float
sites in the Task trampoline / `task_await` codegen cannot be reached, and so
cannot be leak-probed or verified, until this is fixed.

## Guard to add with the fix

A `test/native/task_await_float.march` golden alongside the existing
`task_await_int` / `task_await_ptr` fixtures, covering `Task.await`,
`Task.await_unwrap` and `Task.async_stream` with Float payloads.


---

# Investigated 2026-08-20 — sharper repro, three layers, NOT fixed

Attempted alongside the `typed_array_*` fix. Two layers were fixed and the
feature still crashed, so **both attempts were reverted**: they turned "does not
compile" into "compiles and SIGBUSes", which is strictly worse for a user, and
neither had any observable standalone benefit. Recording the diagnosis so the
next attempt does not restart from zero.

## The core bug is simpler and worse than this file's title

`Task.async` is not required, and the failure is not a build break. A ONE-arg
thunk skips the zero-arg issue entirely and still dies:

```march
let t = task_spawn(fn _ -> 2.5)
match task_await(t) do
  Ok(v)  -> println(int_to_string(float_to_int(v *. 2.0)))
  Err(_) -> println("err")
end
```

* interpreted: `5`
* compiled: **SIGSEGV (rc=139)**, no output

Verified identical on clean `origin/main` (c2f747f7) and on the attempted fix
branch, so it is pre-existing and independent of everything tried here.
**Any Float-returning task is broken**, not just `Task.async`. Use this as the
primary repro; the `Task.async` build break below is a second, separate layer
stacked on top of it.

## Layer 1 — a zero-arg lambda's closure is typed as its RETURN type

`--dump-tir` on the `Task.async(fn () -> 1.5)` form:

```
let $t30193 : Float = alloc $Clo_$lam30192$3620($lam30192$apply$3620)
closure $Clo_$lam26966$4628(Ptr(Unit), Float)
fn $lam26966$apply$4628($clo : Ptr(Unit), _ : Int) : Float =
  let f : Float = $clo.$fv1 in call_ptr f()
```

`f` is a CLOSURE typed `Float`, then called. `Ast.ELam` lowering is correct
(`fn_var.v_ty = TFn(params, ret)`); the loss happens in `lower_to_atom_k`'s
generic arm, which types the temp from `ty_of_expr env e` — the source SPAN
type — and for a zero-arg lambda that returns the RETURN type rather than
`() -> ret`. Taking the type from the lowered `ELetRec([fn], EAtom (AVar fv))`'s
`fv.v_ty` instead fixes the TIR (verified: becomes `() -> Float`).

Note an **Int** thunk is mistyped identically (`$t : Int`) and only "works"
because i64 and ptr share a register, so the bogus `inttoptr` is an ABI no-op —
the same works-by-luck shape as an even tagged scalar surviving a spurious
untag. A zero-arg lambda called DIRECTLY (not captured) is unaffected on both
main and the fix branch, so this layer has no standalone repro.

## Layer 2 — `task_await`'s Float path untags a box POINTER

`llvm_emit.ml`, the `inner_ty = "double"` branch of the `task_await` arm:

```
%tawv14 = load i64, ptr %tawf13        ; Ok payload
%tawv15 = ashr i64 %tawv14, 1          ; unconditional untag
%tawbp16 = inttoptr i64 %tawv15 to ptr
%tawd17 = call double @march_unbox_float(ptr %tawbp16)
```

A Float payload is a `march_alloc_float` box pointer — even — so the `ashr`
halves the address and `march_unbox_float` dereferences garbage. The adjacent
i64 branch is right to shift (an Int payload genuinely is `(n<<1)|1`); only the
double branch is wrong. Loading the slot as `ptr` and unboxing directly is the
fix, and it removed one crash.

## Layer 3 — still crashing, not yet diagnosed

With layers 1 and 2 both fixed the `Task.async` form compiled and then SIGBUSed
(rc=138), and the 1-arg repro above still SIGSEGVs. The remaining suspect is the
trampoline's `double` RETURN store — `specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md`
names `llvm_emit.ml`'s task trampoline double-return site as leaking a box, and
a leak there implies the encode side is hand-rolled rather than going through
`Llvm_ctx.coerce`'s `("double","ptr")` arm. Start there.

## Guidance for the next attempt

Fix layer 3 FIRST and verify against the 1-arg repro, which needs neither of the
other layers. Only then add layers 1 and 2 — landing them alone regresses the
user experience from a compile error to a crash. All three should land together
with a regression test using the 1-arg repro, plus a `Task.async` variant.

The full suite (`scripts/run-tests.sh`) stayed green through all of this, so it
has no coverage of a Float-returning task at all.
