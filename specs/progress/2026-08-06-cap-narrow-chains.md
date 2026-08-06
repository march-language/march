# R4a: attenuation chains — `cap_narrow` no longer demands the root

Landed 2026-08-06. Implements **R4a** in
`specs/2026-08-04-provable-sandbox-design.md`, which was recorded there on
2026-08-05 while researching R1.

## The problem

`cap_narrow` was typed `Cap(IO) -> Cap(a)`. Its argument was *literally the
root*, so a holder of anything narrower could not attenuate:

```march
pfn attenuate(fs : Cap(IO.FileSystem)) : Cap(IO.FileRead) do
  cap_narrow(fs)              -- expected `IO` but got `IO.FileSystem`
end
```

R4 says attenuation is monotone, and it is. What it did not say is that
attenuation was only available **to whoever holds the root**. Delegation with
attenuation at each hop — hand a subsystem `Cap(IO.FileSystem)`, let it hand a
helper `Cap(IO.FileRead)` — is the core object-capability discipline and was
not expressible. Every narrowing had to happen at `main`, with the
already-narrowed values threaded down.

That became urgent rather than academic once R2 made `main` the sole source of
authority: under R1, "least privilege, threaded down" becomes the normal way
to write March, and it was precisely the idiom the typing forbade.

## What shipped

`cap_narrow : Cap(a) -> Cap(b)`, with `Cap_lattice.cap_subsumes src dst`
enforced by `check_cap_narrow_sites` — a deferred sweep over recorded
application sites, mirroring `mint_cap_sites` and `json_cap_sites`.

## The tradeoff, accepted deliberately

Monotonicity used to be enforced **structurally through unification**: the
argument type literally was `Cap(IO)`, so a widen failed to unify and there
was nothing to bypass. It now lives in a post-pass, which is weaker *in kind*
— an application site the sweep fails to record is a silently permitted widen.

HM unification cannot express a subtyping relation, so there was no way to
have both chaining and structural enforcement. The mitigations:

- every site is recorded at a **single** place (the `cap_narrow` arm of
  `infer_expr`);
- `reject/t153`–`t155` become the **load-bearing** witnesses rather than
  decorative ones. `t153` used to pass for free because unification did the
  work; it now passes only if the sweep works.

## Two scoping decisions

**Proof caps are left alone** on either side. They are not in the IO lattice
and have their own discipline (`mint_cap`'s gate, Check 6).
`cap_narrow(root) : Cap(Db.Migrated)` typechecks today and is governed on the
way out by Check 6; making subsumption reject it here would have changed
proof-cap semantics under cover of an IO change. `cap_subsumes` would have
said `false` for every proof cap, so this had to be explicit — without the
guard, `test_codegen.ml`'s proof-cap tests would have started failing for a
reason unrelated to what they test.

**An unpinned side is silent, not rejected.** I proposed failing closed and
was wrong. A `cap_narrow` whose result is never pinned to a concrete
capability is a result never *used* as one, so no authority is exercised and
there is nothing to widen into — the same argument that made silence correct
for an unresolved `from_json` result in R3. Failing closed would reject
ordinary code that narrows into a polymorphic position.

## The knock-on that looks like a regression and is not

`reject/t143` — R3's deferred-zonk witness — now reports `Cap(_)` where it
used to report `Cap(IO)`:

```march
let x = from_json("{}")
let w = cap_narrow(x)
```

`cap_narrow` no longer pins its argument to the root, so nothing in that
program determines *which* capability is being forged, only that one is. Its
`EXPECT-ERROR` was narrowed to `cannot be deserialized` accordingly.

**R3 still rejects it, and that is not luck.** `cap_in_solved_ty` reports an
unpinned capability argument as `_` rather than skipping it, precisely because
an un-pinned capability position is not a safe position. Had it skipped, R4a
would have silently reopened R3's hole for exactly this program — and the
corpus would have gone green while doing it. This is the second time that
design choice has paid for itself.

## Not changed

`mint_cap : Cap(IO) -> Cap(a)` still consumes the root, so a module that mints
a proof cap must be handed root authority. That is the same shape of problem
R4a fixed for `cap_narrow` and is left open deliberately: minting is gated by
declaring-module + public-function rules that have nothing to do with the IO
lattice, so widening its argument type is a separate decision with its own
risk. Worth revisiting when R1 lands and threading becomes universal.

## Tests

4 new conformance files (corpus 260 → **264**, 130 accept + 134 reject):

- `accept/t148_cap_narrow_chains` — two hops below the root, plus the identity
  case (`cap_subsumes p p` is true; a strict-ancestor test would wrongly
  reject it).
- `reject/t153_cap_narrow_widen_rejected` — `IO.Console` → `IO.FileWrite`.
- `reject/t154_cap_narrow_siblings_rejected` — `IO.FileRead` → `IO.FileWrite`.
  Separate from `t153` because they fail different halves: a check written as
  "reject when the target subsumes the source" catches `t153` and lets this
  through.
- `reject/t155_cap_narrow_widen_deferred` — **the decisive one.** The widen is
  visible only after later unification pins the result; an eager check has no
  target to compare against. If this passes while `t153` fails, the sweep is
  eager.

Full suite green: compiler 786, eval 256, stdlib 833, codegen 546, corpus
264/264, doc-lint pass.
