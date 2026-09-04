# `field_escape_owns` is per-TYPE, not per-FIELD

`lib/tir/borrow.ml`'s `field_escape_owns` marks a parameter OWNED as soon as
ANY field extracted from it is used in an owning position. Its rationale is
about HEAP fields: extraction hands out a field's value without incrementing
its refcount, so an escaping field leaves the caller holding an aliased pointer
it does not own.

As of 2026-09-03 the rule no longer fires for a variant whose every
constructor's every declared field is a scalar (`Borrow._scalar_only`), because
for those types no extracted field can be a pointer. That unlocked stack
promotion through a reading callee (see
`specs/progress/2026-09-03-stack-promotion-through-a-call.md`).

It is still conservative for a MIXED type. An `Int` field extracted from
`Node(Int, Tree)` and handed to `+` marks the whole parameter owned, even
though the `Tree` field never escapes. The consequences are a needless
`dec_rc` in the callee and a value that cannot be stack-promoted at the call
site.

The fix is to ask the question per FIELD rather than per TYPE — is THIS
`br_var` heap-carrying — which is exactly what the current rule's comment says
it cannot do:

> Note we intentionally do NOT gate on the `br_var`'s own `v_ty`: `Lower`
> creates `br_vars` with a placeholder `TVar "_"` type even when the concrete
> constructor field is heap-carrying.

So the work is: give `br_vars` their concrete field types at lowering (or
resolve them in `Borrow` from the scrutinee's type plus the branch's
constructor, the way `Llvm_data.resolve_ctor_fields` does at codegen), then
gate `field_escape_owns` on the individual binder. Both halves need the
scrutinee's type to be concrete, which it is not for the closure-generated
helpers the current comment names — so the rule would have to stay
type-conservative wherever that resolution fails.

Measure before and after with the same instrument used for the scalar-only
change: `alloca [N x i8]` counts across `bench/`, plus the full suite and
`dune build @test/oracle`.
