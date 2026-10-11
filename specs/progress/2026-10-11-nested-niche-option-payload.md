`[P2]` - [x] **An `Option` over a niche-shaped type was itself a niche: `Some(NoName)` matched as `None`.**

Found 2026-10-11 while fixing
`specs/todos/2026-10-11-compiled-to-string-newtype-niche.md` (an
`Option(MaybeName)` printed `None` for `Some(NoName)`). Landed the same day.

## What was wrong

A niche-shaped type (one nullary constructor and one single-field one, such
as `type MaybeName = NoName | Named(String)`) is niche-encoded: `NoName` is
raw 0 and `Named(s)` is `s`. Wrapping it in an `Option` asked
`Kind.niche_payload_ok` whether the payload can ever be raw 0. The payload
reaches that function as `TCon ("MaybeName", [])`, `repr_of` cannot decide a
niche without type arguments and answers Boxed, and Boxed means "a heap
pointer, never 0". So the `Option` was niche-encoded too, `Some(NoName)` was
raw 0, and every match read it as `None`. The interpreter was right.

The same shape with a recursive payload (`type Chain = End | Link(Chain)`)
inside an `Option` made the compiler loop forever (it never finished on the
train branch's compiler).

## The change

`Kind.niche_payload_ok` answers false for a niche-shaped `TCon` named without
type arguments, before asking `repr_of`. It does not ask whether the inner
type really is niche-encoded, because that question recurses through the
payload and never ends for a recursive type. A false "no" costs a boxed outer
`Option`; every encode and decode site (`Llvm_emit_alloc`, `Llvm_case`,
`Llvm_eq`, `Drop`) asks this same function, so they stay in agreement.

## Test

`test/native/niche_nested_option.march` runs interpreted and compiled
against one `.expected`: `Some(NoName)` through a function boundary, a
pattern that binds the inner payload, an Int-payload niche, the recursive
`Chain`, and `Option.is_some` over a list.
