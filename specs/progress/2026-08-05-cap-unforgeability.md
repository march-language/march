# Capability unforgeability (R3), and the `needs` coverage gap it uncovered

Landed 2026-08-05. Design: `specs/2026-08-05-cap-unforgeability-design.md`.
Implements **R3** and pins **R4** from `specs/2026-08-04-provable-sandbox-design.md`,
reaching **stage 1** of that document's ladder:

> "capabilities cannot be fabricated, only received and narrowed"

Stage 1 is independent of the rest of the sandbox work and is not wasted if the
effect-row work (R1b) never happens.

## What was actually open

R3 lists four exclusions. Measured against the compiler at `7ad39a97`, two of
them had no vector at all:

| R3 bullet | vector |
|---|---|
| deserialization producing a `Cap` | **was open** |
| `derive(FromJson)` producing a `Cap` | **was open** |
| cast / reinterpretation (`Bytes` → `Cap`) | none — no `unsafe_cast`/`transmute`/coercion builtin exists |
| default-value / zero construction | none — March has no default-value construction |

So R3 was two checks, not four.

**The deserialization hole.** `to_json`, `from_json` and `from_json_events` are
the only three builtins typed `poly2 (fun a b -> TArrow (a, b))` — fully
unconstrained. This typechecked clean with `--cap-strict`, fabricating root
authority from a string literal:

```march
let forged : Cap(IO) = from_json("{}")
let w : Cap(IO.FileWrite) = cap_narrow(forged)   -- module declares only IO.Console
```

It failed at run time with `from_json: cannot determine target type`, but that
is the unimplemented return-type dispatch in
`specs/todos/2026-07-31-from-json-return-type-dispatch-unimplemented.md` — an
open item to *build* that feature. The forge completed the day it landed. The
derive path was further along: a codec was generated over the capability
position and the decoder ran as far as a `Json.DecodeError`.

**The `needs` coverage gap (not in R3, found while checking it).** Check 1's
decl walk ended in `| _ -> []`, and so did `cap_paths_in_surface_ty`. Both of
these were accepted under `needs IO.Console` with `--cap-strict`:

```march
let forged : Cap(IO) = ...                -- let annotation: uncovered
type Loot = { tok : Cap(IO.FileWrite) }   -- type-decl field: uncovered
```

A module could name a capability it never declared. Unlike the deserialization
hole this needed no unimplemented feature to reach — `root_cap` is ambient, so
a console-only module could take the root, narrow it, and bind the result
without ever putting a capability in a signature.

## What shipped

**`lib/caps/cap_surface_ty.ml`** (new) — one exhaustive walk for capability
positions in surface `Ast.ty`, shared by the typechecker and the desugarer so
the two cannot drift. `march_caps` gained a `march_ast` dependency and
`march_desugar` gained `march_caps`. `cap_paths_in_surface_ty` now delegates to
it; its private copy is gone.

One behaviour change came with the move: the old copy skipped `Tagged(_, _)`'s
arguments outright to avoid mistaking the marker for a capability. The shared
walk recurses instead — the marker is a nullary constructor not named `Cap`, so
it still extracts nothing, while `Tagged(R, Cap(IO))` is now found.

**Check A — `Cap` is not a serializable type, either direction.** Rejecting
only decoding would leave `derive Json` half-expanded (a working encoder beside
a refused decoder), so one symmetric rule.

- *Derive*, in `lib/desugar/desugar.ml` — eager, guarded on the `"Json"` arm of
  `derive_impl`. Rejected at the `derive` declaration, which is also the only
  real span available: every declaration the expansion emits carries
  `dummy_span`.
- *Call sites*, in `lib/typecheck/typecheck.ml` — `env.json_cap_sites` records
  each application's INSTANTIATED arrow (capturing both the encoded argument
  and the decoded result in one value), swept by `check_json_cap_sites` after
  checking, mirroring `mint_cap_sites`.

Hard error, not gated on `--cap-strict`.

**Check B — type declarations and `let` annotations are cap uses.** The decl
walk gained `DType`/`DAlwaysLinearType` arms; `cap_annots_in_expr` (new) walks
expressions for `bind_ty`, lambda and local-fn parameter types, local-fn return
types, and `EAnnot`. Both walks are now exhaustive with no wildcard: a new
`Ast.decl` or `Ast.expr` constructor breaks the build.

## The two things that would have shipped broken

**The deferred sweep is load-bearing, and an eager check looks identical until
one specific program.** `from_json`'s result type is a bare `TVar` at the
application site; in `let x = from_json(s)` followed by `cap_narrow(x)` it is
the LATER `cap_narrow` that pins it. An eager check reads an unsolved variable,
reports nothing, and still passes every reject case that writes the annotation
inline. `reject/t143_cap_from_json_deferred_zonk.march` exists to fail if this
is ever made eager — and it did fail, on the first implementation, after the
other four reject cases were already green.

**The value restriction is equally load-bearing.** Even deferred, `let x =
from_json(s)` generalizes `x` to `∀b. b`; every use instantiates a fresh var
pinned to that use's type while the recorded node stays unbound forever. Fixed
by `demote_to_monomorphic` on the instantiated arrow, exactly as `cap_narrow`
and `mint_cap` already do, and for the reason that function's docstring already
spelled out ("REOPENING the forge in every let-/generic-flow position").

Cost, stated rather than discovered: a single `from_json` application can no
longer be used at two different result types. Decoding one string as two
unrelated types is already meaningless at run time, since `from_json`
dispatches on a single determinable target.

## Deliberate limitations

- A `let`-annotation cap does **not** feed that function's `cap_closures`
  propagation. Signature caps propagate to callers because they are the
  function's interface; a local annotation is not, and folding it in would
  widen every caller's ceiling on the strength of a binding they cannot see.
- **`EAnnot` has no reject witness** — the parser never produces one. Desugar
  synthesizes the sole instance, a hardcoded `SupervisorSpec` on an `app`
  block's spec field, so no source program can route a capability through it.
  Walked anyway, defensively.
- **An alias right-hand side has no reject witness** — it has no source
  spelling. `type T = Cap(IO.FileRead)` parses as a VARIANT declaring a
  constructor named `Cap` (verified: `T` does not unify with `Cap(_)`), and
  `type T = (Cap(IO.FileRead), Int)` does not parse. `caps_in_type_def` handles
  `TDAlias` for completeness; the coverage is defensive, not witnessed.
- **`DLet`** (a top-level binding's annotation) is enumerated and left
  uncovered — revisit if a witness appears.
- **`DMod`** is correctly skipped: nested modules get their own
  `check_module_needs` pass, which attributes diagnostics to the INNER module.
  Verified, not assumed.

## Tests

13 new conformance files (corpus now 257/257 — 127 accept, 130 reject) plus
`test/test_cap_unforgeable.ml` (5 cases) registered in `run_compiler`.

Every case is an accept/reject pair: an accept-only witness cannot tell a
working contract from one that checks nothing.

The alcotest file exists for the assertions the corpus **cannot** express —
`check_types.sh` only inspects exit status, so it cannot assert the absence of
a WARNING. That matters here: the new positions must count as USES, or fixing
the error from `reject/t148` would merely trade it for a "declared but never
used" warning, and a check that always leaves a diagnostic behind reads as
broken whichever way the program is written.

**R4 rides along as a regression pin with no production change.** Attenuation
was already monotone, enforced structurally through unification (`cap_narrow`
demands the *parent* `Cap(IO)` at its argument) rather than by a lattice call;
the runtime `march_cap_narrow` is `return cap;` — deliberate erasure, since the
gating is compile-time. A property test over that runtime function would assert
nothing. The pin is an accept/reject pair over both lattice directions,
justified because the subsumption direction was written backwards twice during
the sandbox work and shipped once.

Non-vacuousness was verified by reverting `lib/typecheck/typecheck.ml` to base
and re-running: the two Check B cases fail, the R4 pair passes both ways as
intended.

## Apparatus notes for whoever runs this next

Two apparatus failures cost real time here and are worth not repeating.

**A stale staged `_build` faked three separate results.** Building only
targeted exes leaves `_build/default/runtime` and `_build/default/stdlib`
stale, and both are resolved exe-relative. Symptoms seen: 11 compiled stdlib
tests failing on `Undefined symbols: _march_string_concat3`; `cap_strip`
failing to find a profile string; and `reject/t142_refine_nth_out_of_range`
passing when it should be rejected — because the staged `stdlib/list.march`
(111 files, not 112) predated `nth`'s bounds contract, so no obligation was
ever raised. All three cleared after `dune build --root . @install` and
`@test/cas-runtime-dir`.

The refine one is the instructive failure: a base-compiler control was run and
AGREED the test failed, which looked like proof the failure was pre-existing.
It agreed because both arms shared the same stale staged stdlib. **A control
does not isolate a variable it also holds wrong.**

**The ASAN regression test fails on this host for an unrelated reason.** A
trivial `printf("ok")` compiled with `-fsanitize=address` hangs and is killed
at 30s with no output, so `MARCH_SANITIZE` cannot pass here regardless of March
(cf. `185202ae`, which skips the ASAN golden gate under CrowdStrike Falcon on
macOS). The test's own failure message says to check exactly this first.
