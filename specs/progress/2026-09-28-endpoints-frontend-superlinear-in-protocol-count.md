# `[P2]` `@[endpoints]`: `--check` time was exponential in the protocols of one module (DONE, 2026-09-28)

**Filed:** 2026-09-24 as `specs/todos/2026-09-24-endpoints-frontend-superlinear-in-protocol-count.md`
while writing `test/session/drain_peers.march` (D27 drains).
**Closed:** 2026-09-28.

## Cause

Not a slow pass: the constructor table itself **doubled per generated role module**.

Every `@[endpoints]` role module declares public types with the same bare names
(`Entry`, `Yield`, ...). When a nested `mod` finishes, `check_decl`'s `DMod` export
step (`lib/typecheck/typecheck.ml`) re-exports each constructor in scope whose parent
type (`ci_type`, a BARE name) is one of the module's public types, under
`<Mod>.<key>`. The filter ran over `inner_env.ctors`, which includes everything
inherited from the enclosing scope, so the already-qualified keys the previous
sibling exported (`P0_A.X`) came back as `P1_A.P0_A.X`, then `P1_B.P1_A.P0_A.X`,
and so on. Instrumented on three identical three-role protocols: the table grew
22.7k -> 41.4k -> 77.7k keys across P2_A, P2_B, P2_C, and each role module took
twice as long as the one before it (P4_A 0.85 s ... P5_C 22.8 s with six).
Everything that walks the table (exhaustiveness's `ctors_for_type`,
`name_is_variant` via `contains_linear`) paid for it on every match and type.

## Fix (typecheck only; no protocol semantics touched)

1. **The doubling.** The export step skips a QUALIFIED key that the module merely
   inherited unchanged from the outer scope (the entry is physically the outer
   env's list). Bare keys are unaffected, and so are qualified keys this module's
   own nested modules exported. The table now grows ~17-20 keys per role module.
2. **`pub_set` membership** in that export step is a hash lookup instead of
   `List.mem`/`List.exists ... String.sub` over the public-name list, which ran
   for every name in scope (stdlib included) once per nested module.
3. **A parent-type index over `env.ctors`** (`Typecheck_env.bare_ctors_of_type`,
   `ctors_name_a_variant`) for `ctors_for_type` and `name_is_variant`, which were
   full-table scans per match / per type. `env.ctors` is an immutable map, so the
   index is keyed on the map value's physical identity; a map is scanned directly
   until it has been queried three times, so declaration registration (where the
   map changes between queries) does not rebuild an index per change.

Fix 1 is the one that removes the exponential; 2 and 3 remove the remaining
quadratic terms. Alternating A/B, min of 5, fix 1 alone vs all three:
16 synthetic protocols 4.65 s -> 1.62 s; the six-protocol drain file 1.37 s -> 0.76 s.

## Measurements

`--check`, cold CAS (fresh `.march`), 14-core Mac at load average 10-12 (other
sessions). origin/main = 9f4c543f2.

| input | origin/main | this change |
|---|---:|---:|
| six-protocol drain file (the pre-split `drain_peers.march` + `drain_peers_multi.march`) | 533.6 s | 0.77 s |
| synthetic, 2 three-role protocols with a chaos-seeds helper each | 5.08 s | 0.59 s |
| synthetic, 4 protocols | 48.99 s | 0.70 s |
| synthetic, 5 protocols | 577.18 s | — |
| synthetic, 6 protocols | killed at 1200 s | 0.83 s |
| synthetic, 16 protocols | — | 1.64 s |

This-change figures are min of 3; origin/main figures are single runs (they take minutes).
The synthetic modules repeat one three-role looping protocol N times, each with a helper that registers and runs its three chaos peers (the regression test below generates the same shape).

Diagnostics for the six-protocol file are byte-identical to origin/main's (72
lines of hints), and so is its stdout.

## Tests

- `test/test_compiler.ml` `session_compile` "--check linear in @[endpoints] protocol
  count": generates 12 three-role protocols with helpers and `--check`s them from a
  fresh temp dir under a 120 s alarm, bound 60 s. GREEN in ~1.5 s; RED on origin/main's
  typechecker (killed at the alarm, 121 s).
- `test/session/drain_peers.march` is one file again (Stream, Ring, Steady, Pair,
  Relay3, Fork); `drain_peers_multi.march`/`.expected` and their dune rules are gone.
  The merged golden is the two old goldens concatenated; compiled and interpreted both
  match (the whole dune rule takes ~21 s).
- `scripts/types-oracle.sh` (baseline on origin/main's typechecker, check on this
  one, private `HOME`), 824 fixtures. Every inferred type, scheme, instantiation and
  module-cap set is identical. The only change is in the "Did you mean one of:"
  constructor suggestions: 211 lines across 4 fixtures drop, 0 are added, all of
  them the aliases fix 1 stops creating: doubled prefixes (`Logger.Logger.Warn`) and
  another type's constructors listed under a module that merely declares a type of
  the same bare name (`Logger.Level.Fast`/`Best`, which are a compression `Level`'s).
  Four endpoints reject fixtures (t189, t275, t277, t278) show this in Tier 1 too,
  inside the diagnostic message text only.
