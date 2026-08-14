# TRMC's actor-struct check is now structural (and the comment is honest about the other half)

**Shipped 2026-08-14.** Filed the same day out of the named-registry branch's final
review, while verifying that nothing still depended on the actor-refcount clobber
removed in `a9032530`.

## What was wrong

`lib/tir/trmc.ml`'s `crosses_actor_boundary` carried a doc comment claiming:

> Both checks are STRUCTURAL — a name-suffix guess here was previously found to
> false-positive on a user type called `Tree_Actor` (see `Repr.is_actor_struct_type`).

The code immediately below it called `Tir_names.is_actor_struct_name`, which **is**
the name-suffix check the comment said had been replaced. `Repr` was mentioned only
inside that comment — `trmc.ml` did not reference it in code at all.

## Why it was not urgent, and why it was still worth fixing

The failure direction here was **conservative**, unlike the codegen site that
motivated `Repr.is_actor_struct_type`. In `llvm_emit.ml`'s `EReuse` arm a false
positive was unsound — it skipped the refcount check shared-value FBIP safety
depends on. Here a false positive only makes `crosses_actor_boundary` return `true`,
which **declines** the rewrite: a user type coincidentally named `Tree_Actor` quietly
lost tail-recursion-modulo-cons it was entitled to. A missed optimization, not a
miscompile — plus a comment that was false as written, which is the part that would
have misled the next reader into trusting this site as already hardened.

## What shipped

- `crosses_actor_boundary` now takes `type_defs` and asks
  `Repr.is_actor_struct_type` (field 0 is literally `$d_dispatch`, a name only
  `lower_actor.ml` can construct since no surface March identifier may begin with
  `$`). Threaded through `transform_fn` from `transform_module`'s `tm_types`.
- The **message** half is deliberately still the `"_Msg"` name suffix
  (`Tir_names.is_actor_msg_name`) — there is no structural predicate for a message
  variant, and over-approximating only costs an optimization. The comment now says
  this plainly instead of claiming both halves are structural, and warns against
  copying the suffix test to any site where a false positive would *skip* a safety
  check rather than decline one.

## Tests

Two cases in `test/test_trmc.ml`, pinning **both** directions — a gate is only
correct if it still says no to the thing it guards:

- `user type named _Actor gets TRMC` — a `Tree_Actor` with no `$d_dispatch` is now
  transformed. Fails by construction against the old suffix check, which declined it.
- `real actor struct refused` — a `Counter_Actor` whose field 0 is `$d_dispatch` is
  still refused.

Note these live in `run_codegen.exe`, not `run_compiler.exe` (`test/dune:26` puts
`test_trmc` in the codegen driver) — a full green `run_compiler.exe` run does not
exercise them at all.

## Verification

`run_codegen.exe -e`: all three actor-gate cases OK. The one `llvm_ir_validity_gate`
failure seen in that run was `simd_poly_eq.march` killed by **SIGKILL** (the harness
prints "OOM killer or an external kill; a resource problem") under three concurrent
agent builds; re-emitting it standalone exits 0 and `opt -passes=verify` on the
result exits 0.
