`[P3]` # TRMC's `crosses_actor_boundary` claims a structural actor check but uses a name suffix

`lib/tir/trmc.ml:395-403`'s doc comment says:

> Both checks are STRUCTURAL — a name-suffix guess here was previously found to
> false-positive on a user type called `Tree_Actor` (see `Repr.is_actor_struct_type`).

The code immediately below it calls `Tir_names.is_actor_struct_name`
(`lib/tir/tir_names.ml:394`), which **is** a name-suffix check — exactly the
thing the comment says was replaced. Only `Repr.is_actor_struct_type`
(`lib/tir/repr.ml:38`) is structural: it confirms field 0 is literally
`$d_dispatch`, a name no surface March identifier can spell.

## Why this is not urgent

The failure direction here is **conservative**, unlike the codegen case that
motivated `Repr.is_actor_struct_type`. In `llvm_emit.ml`'s `EReuse` arm a false
positive was unsound — it skipped the refcount check that shared-value FBIP
safety depends on. Here a false positive makes `crosses_actor_boundary` return
`true`, which only causes TRMC to **decline** the rewrite. A user type named
`Tree_Actor` therefore loses a tail-recursion-modulo-cons optimization it was
entitled to; nothing miscompiles.

So this is a missed optimization plus a comment that is false as written — not
a correctness bug.

## Why it is still worth fixing

The comment actively misleads. A reader auditing actor-boundary handling will
believe this site was already hardened, and the next person to touch it may
copy the suffix check somewhere the direction *is* unsafe.

## Fix

Either switch the call to `Repr.is_actor_struct_type` (it needs `type_defs`, so
check whether `crosses_actor_boundary`'s callers can thread that through), or
correct the comment to say the struct check is a deliberately conservative
name-suffix test and explain why over-approximating is safe here.

Note `is_actor_msg_name` in the same expression may have the same issue — check
both before claiming either is structural.

Found during the final whole-branch review of the named-registry work
(2026-08-14), while verifying that nothing still depended on the actor-refcount
clobber removed in `a9032530`. Pre-existing; unrelated to that fix.

## Acceptance

The comment and the code agree, and a user type coincidentally named
`Tree_Actor` either gets TRMC or is documented as deliberately excluded.
