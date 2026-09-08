# Known_call's self-binding rule assumes `$clo` is never shadowed — guard it

Filed 2026-08-22 while landing
`specs/progress/2026-08-22-selfrec-closure-float-tail-call.md`. Small, and
purely defensive — nothing is known to be broken.

## The assumption

`Known_call.go` now carries the traversed function's `($clo parameter name,
own name)` and treats `let v = $clo` inside an apply fn as binding `v` to that
apply fn, so the self-call becomes a direct `EApp` and gets TCO'd. The
traversal recurses into `ELetRec` function bodies and `ECase` branch bodies
with that pair still set.

That is correct as long as no inner binder REBINDS the name `$clo`. If one
ever did, `let v = $clo` in that inner scope would name a *different* closure
and the rewrite would dispatch the call to the WRONG apply function — a
compiled-only miscompile of the kind this codebase has been bitten by
repeatedly (`specs/progress/2026-08-19-actor-handler-binder-shadowing.md` is
the same shape).

No such shadow exists today: defun's apply fns are top-level, and the
`ELetRec` groups that survive to codegen (join points, mutual-recursion
groups) take ordinary value parameters. So this is an observation about the
current pipeline standing in for an invariant.

## The guard

Clear the pair whenever a binder rebinds that name — a `shadowing` helper
applied at the `ELet` binder, `ELetRec` parameters and `ECase` branch vars.
It can only ever REMOVE a resolution, i.e. return that call to its
pre-2026-08-22 behaviour, so it cannot introduce a miscompile; the only thing
to check is that it does not remove the one we want.

## Verification (cheap, and exact)

One measurement decides it: `test/native/native_float_box_abi_leak_probe.march`
must still report a `live_allocs` delta of **1**. If the guard accidentally
disabled the self-binding rule, `selfrec_leg` re-leaks and the delta becomes
~1,000,001 — a 6-order-of-magnitude signal, not a judgement call. Follow with
`run_codegen` and the 71-program corpus sweep.

Written and reviewed but NOT landed in the original commit: the build lock was
held by a full `@runtest` on a box at load 60 and shipping it unmeasured would
have been worse than shipping without it.

---

## Landed 2026-09-08

`lib/tir/known_call.ml` gains a `shadowing` helper that clears the
`(clo_param, own_name)` pair whenever a binder rebinds the `$clo` parameter's
name. Applied at every binding site the traversal descends through:

- the `ELet` binder — in all four `ELet` arms, including the two closure-alloc
  arms and the self-binding arm itself, since each of those binders could in
  principle be the shadowing one. The RHS keeps the outer pair, because the
  binder scopes over the body only;
- each `ELetRec` function's parameters, for that function's body;
- each `ECase` branch's `br_vars`, for that branch's body.

### Verification

The todo's decisive measurement first.
`test/native/native_float_box_abi_leak_probe.march`, compiled `--opt 2`:

- **`live_allocs` delta = 0.** The regression signature is ~1,000,001 (one box
  per back-edge) — six orders of magnitude away — and the dune rule's assertion
  is `< 1000`. The guard did not disable the self-binding rule. (The todo
  predicted a healthy delta of 1; it is 0 on the current tree. Either value is
  unambiguously in the healthy band.)
- stdout is byte-identical to `native_float_box_abi_leak_probe.expected`.

Then, stronger than the todo asked: the guard is a **no-op on the current
tree**, which is exactly what it should be, since no shadow of `$clo` exists
today. Comparing `--emit-llvm` output from two compilers built from the same
source differing only in this patch:

- the probe's own IR is **byte-identical**;
- across `test/native/*.march`, **74 programs emit IR and all 74 are
  byte-identical**; 0 differ. (112 of the 186 files emit no `.ll`; the skip is
  symmetric — those failed identically under both binaries, so nothing is
  hidden by it.) 74 matches the "71-program corpus sweep" figure the todo cites.

Run under a **private `HOME`**: `~/.cache/march`'s cached spans carry the
populating worktree's absolute paths and produce phantom diffs naming another
worktree.

`scripts/run-tests.sh codegen` passes, 602 `[OK]`, exit 0.

### No CHANGELOG entry

Deliberate. The guard is purely defensive against an invariant that currently
holds, and the IR sweep above shows it changes no emitted code anywhere in the
corpus. There is no observable behaviour to describe to a user.
