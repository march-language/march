# `println(ADT)` reported a missing `Show` impl as an ambiguity

**Filed:** 2026-09-08
**Landed:** 2026-09-08

## What was wrong

```march
type Shape = Circle(Int) | Square(Int)
println(Circle(7))
```

compiled to:

    error: ambiguous interface-method call to `show`: 20 implementations are in
    scope (Show$U8x16.show, ... Show$Int.show) and the call site's types do not
    determine which one applies.

`Shape` has no `Show` impl at all. The message described an ambiguity and
listed twenty types, none of which was `Shape`, and never mentioned
`derive Show for Shape` — the thing that fixes it. Interpreted, the same
program printed `Circle(7)` and raised nothing.

Two failures wear the same shape at
`Llvm_calls.fail_if_unresolved_iface_method`, and only one of them is an
ambiguity:

- the dispatch position is ERASED (`from_json`'s return-type shape) — genuinely
  ambiguous, several impls could apply;
- the dispatch ARGUMENT is concrete and simply has no impl — nothing is
  ambiguous, and no extra type information would change the answer.

## The fix

Both resolutions from the brief, because they cover different cases.

**(b) Remove the requirement, where there is a fallback.** `Mono.rewrite_calls`
already computes the concrete argument type name before looking for an impl.
Where that name is concrete and the method is `show`, a failed lookup is a
missing impl, so the call is rewritten to the `to_string` builtin, which now
renders any boxed ADT through the constructor-name table
(`specs/progress/2026-09-08-compiled-to-string-adt-ctor-names.md`) exactly as
the interpreter's Show-less fallback does. `println(Circle(7))` compiles and
prints `Circle(7)`. Scoped to `show` alone: no other interface method has a
universal fallback to route to.

**(a) Improve the diagnostic, for everything else.** When the dispatch
argument's type is concrete and no candidate impl is for that type, the message
now names the missing implementation and the `derive` that supplies it, instead
of listing every impl in scope. The ambiguity wording is kept for the erased
case, which is what it was written for — and is also kept when an impl for the
argument's own type IS among the candidates, since then the argument type is
not the reason the call failed.

## Not covered

The `ECallPtr` resolution path in `Mono.rewrite_calls` has the same
"no impl for this concrete type" fall-through and did NOT get the (b) rewrite:
turning an `ECallPtr` into an `EApp` is a different transformation than the
`EApp` path's rename, and no repro reaches it. It still gets the improved (a)
diagnostic, since that is applied at the codegen guard both paths share.
