# A `use`-imported name competes for an `impl` method's contract

Landed 2026-07-30.

**At landing:** `test_refinecheck` 395 (was 387, +8 — six obligation-count cases and
a two-case division-safety pair). Typing corpus 241/241, grammar corpus 45/45,
`run_codegen` 523, `run_compiler` 619, `run_eval` 256, `run_snapshots` 33,
`run_stdlib` 826 with only the pre-existing environmental `MARCH_SANITIZE`
failure — all unchanged. CI obligation ratchet unchanged: `t118`'s user-code
slice still `1 proved, 0 violated, 0 trusted, 0 skipped` (floor 1) and
`stdlib/list.march`'s whole-program slice still `8 proved, 0 violated,
0 trusted, 28 skipped` (ceiling 28).

**What changed.** `adoptable_impl_methods` (`lib/refinecheck/refine_check.ml`)
decides which `impl` method names denote exactly one contract, and therefore
which parameter refinements are registered so callers must establish them. It
counted sibling `fn`s and other `impl`s but not **imports**, so a
`use Other.{run}` beside `impl Runner(Box) do fn run(b, k : {Int | k != 0})`
left `run` looking unambiguous. The contract was adopted, and a call the import
resolves elsewhere was checked against a predicate it never touches — the false
positive this subsystem must never have, arrived at from the direction opposite
to the usual one. Imports now compete: an enumerated selector
(`use Other.{run}`, `use Other.run`, `import Other, only: [run]`) withdraws that
one name; a glob (`use Other.*`, a bare `import Other` — which parses to the
*same* `UseAll` — or `import Other, except: […]`) names a module this pass
cannot see, so its import set is undecidable here and **every** `impl` method in
that declaration list is withdrawn; `use Other` with no selector binds the
module rather than a bare name and withdraws nothing.

The rule fails **closed** by design. Over-withdrawing costs silence;
under-withdrawing costs a wrongly rejected program, and this pass trades the
first for the second everywhere. Withdrawal stays symmetric, as it already was
for the `fn`/two-impl cases: `division_safety.ml` consults the same function, so
a withdrawn contract cannot be assumed inside its own body either — `cap
no_panic` asks such a body to prove its division safe some other way, rather
than discharging it from a predicate nothing enforces.

**Blast radius, measured rather than asserted.** Failing closed on an
unresolvable import, combined with the standard library being prepended to every
compilation, could in principle withdraw adoptions far more widely than
intended. It does not, and the number is **zero**: `--refine-report` over all
111 `stdlib/*.march` and all 241 typing-corpus fixtures (352 compilations, both
the `user code` and `user + stdlib` slices) is byte-identical before and after.
The syntactic reason is that **no `.march` file in the repository declares an
`impl` and a `use`/`import` at all** — the standard library contains exactly one
import (`import Process` in `stdlib/system.march`, a module with no `impl`).
That the measurement can *detect* a withdrawal was confirmed with a positive
control: the same fixture with and without one `use` line reports 0 versus 1
obligation.

**Residual, filed not fixed.** Competition is judged over one declaration list.
A `use` in an *enclosing* module also binds names lexically inside a nested one,
and that case is still adopted. Closing it is a further withdrawal in the same
safe direction, deliberately not taken without a witness that the shape occurs.

**Tests.** Six of the eight new cases assert **obligation counts** off
`Obligation.summary`/`all`, not the presence or absence of a diagnostic, because
a withdrawn contract is silent and so is a satisfied one — the trap that let
`{List(a) | len(_) > 0}` ship enforcing nothing. The withdrawal cases assert the
ledger is *empty*; the anchor asserts the same source minus one `use` line
raises exactly one obligation and finds the violation, so the zeros cannot pass
vacuously. Two over-shoot controls (a `use` naming a *different* function, and a
selector-less `use Other`) pin that the rule is "this name is imported", not
"some import exists". All four withdrawal cases were verified RED against the
parent commit with the exact `Expected: 0 / Received: 1`.
