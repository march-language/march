# Compiled `println` SIGSEGVs on a value whose type is an unresolved TVar (e.g. `Actor.call`'s `Ok(...)` payload)

Found 2026-08-11 while working on SIMD Task 2's compiled fixtures (unrelated to
SIMD) — a pre-existing gap in compiled `println`/generic-value interaction.

## Repro (native compile)

```march
mod Repro do
  needs IO.Console
  type CallGet = CallGet
  actor Counter do
    state { last : Int }
    init { last: 0 }
    on GetLast(ref) do
      Actor.reply(ref, state.last)
      state
    end
    on Extract(n : Int) do
      { state with last: n }
    end
  end
  fn main() : Unit do
    let c = spawn(Counter)
    let _ = send(c, Extract(5))
    match Actor.call(c, CallGet, 5000) do
      Ok(n) -> println(n)        -- SIGSEGV (exit 139) compiled
      Err(_) -> println("timeout")
    end
    kill(c)
  end
end
```

`march --compile -o out repro.march && ./out` segfaults. `Ok(n) ->
println(to_string(n))` (or `int_to_string(n)`) does NOT crash — so this is not
a general `println(Int)` bug (`println(5)` standalone works fine) and not a
general Result-unwrap-into-println bug either: a plain non-actor function
returning `Result(Int, String)`, matched, with `Ok(n) -> println(n)` compiles
and runs correctly (confirmed with a minimal repro). It reproduces only when
**nothing else in the program constrains the `Ok` payload's type to a
concrete type** — here `Actor.call`'s reply-type parameter is never unified
with `Int` (the actor never gets a compile-time-visible link between the
`CallGet` request tag and the `on GetLast` handler that answers it, so the
typechecker leaves it fully polymorphic), and `println` is itself
polymorphic, so nothing forces resolution.

## Root cause

`--dump-tir` on the repro shows:

```
let $t28832 : Result('_37596, String) = ... actor_call(c, $t28831, 5000) in
case $t28832 of
  Ok($f28833) -> ...
    let n : '_37596 = $f28833 in
    println$String(n)
```

`n`'s type is a genuinely **unresolved TVar** (`'_37596`) all the way through
typecheck (confirmed: `lib/typecheck/typecheck.ml`'s constraint-solving loop,
~line 8085-8095, leaves `CInterface(iface, TVar _)` constraints untouched —
"Still polymorphic — cannot check yet", no defaulting, unlike the `CNum`
case at line 8080 which *does* default an unresolved `Num` var to `Int`).

The TVar survives into `lib/tir/mono.ml`, where
[`default_residual_tvars`](../../lib/tir/mono.ml) (line ~79-87) turns any
leftover non-placeholder `TVar` into `Tir.TString` before finalizing a
specialization. The function's own doc comment explains this choice
carefully for the **RC-safety** angle (a String's heap-ptr representation
with `IS_HEAP_PTR`-guarded dup/drop is safe to apply to a value that might
actually be a tagged immediate) — but does not account for `println`'s
dispatch: once `n`'s type defaults to `TString`, `println`'s interface
dispatch in `lib/tir/lower.ml` (`resolve_iface_method`, via `mono.ml`'s
post-monomorphization pass) picks `Show$String.show` / mangles the call to
`println$String(n)`. `println$String` calls `march_println` expecting a
`ptr` (heap String), but `n`'s actual runtime representation is a tagged
`i64` Int (the value `state.last` sent through `Actor.reply`). Reading that
tagged-int bit pattern as a heap string pointer and dereferencing it is what
SIGSEGVs.

So there are two contributing layers:
1. `Actor.call`'s reply-type parameter can be left **completely
   unconstrained** by real programs (nothing type-checks it against the
   actual `on` handler's reply value) — this is arguably fine/expected for a
   dynamically-tag-dispatched actor protocol, but it means downstream passes
   must be prepared for a truly free type variable at a *value use site*, not
   just at a dead/unobserved binding (the case `default_residual_tvars` was
   designed for, per its own comment: "a residual TVar can still be the type
   of a REAL erased value... AND it has the standard Show/Eq/Ord/Hash impls
   the **dead interface-method branch** needs to resolve" — the branch here
   is not dead).
2. `default_residual_tvars`'s String default is silently WRONG for any
   interface method (`show`/`println` dispatch) applied to a *live* erased
   value whose real runtime representation is a tagged scalar (Int/Bool),
   not a heap pointer — it only stays RC-safe, not value-safe.

## Fix shape (not yet implemented — investigation only)

Options to weigh, not yet decided:
- Make `println`/`show`'s codegen dispatch runtime-polymorphic on a
  genuinely-unresolved-at-compile-time argument (inspect the tag at runtime,
  like the interpreter's dynamic `value_to_string` does) instead of
  statically mangling to `$String` and trusting the ABI.
- Or: surface unresolved `CInterface(Show, TVar)` constraints that reach a
  real call site (not just a dead branch) as a compile error demanding an
  explicit annotation, rather than silently defaulting — mirrors how `CNum`
  already defaults (to `Int`) only because that default is value-safe for
  every concrete instantiation; `String` is not value-safe here.
- Or: give `Actor.call` a way to constrain its reply type from the actor
  definition/message tag (bigger, session-types-adjacent change) so `n`
  resolves to `Int` before `println` ever sees a TVar.

Needs a design decision before implementation; filed as investigation output
after being reported from an unrelated SIMD Task 2 branch.
