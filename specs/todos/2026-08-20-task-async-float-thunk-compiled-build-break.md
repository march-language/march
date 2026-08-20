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
