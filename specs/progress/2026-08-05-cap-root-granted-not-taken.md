# R2: the root capability is granted at the boundary, not taken

Landed 2026-08-05, immediately after R3/R4
(`specs/progress/2026-08-05-cap-unforgeability.md`). Implements **R2** from
`specs/2026-08-04-provable-sandbox-design.md`.

## Why, and what it fixes about R3's claim

R3 made a capability impossible to fabricate *from data* — it cannot be
deserialized, derived, or cast into existence. While deciding what came next,
this turned up:

```march
mod Anything do
  fn main() do
    let x = root_cap        -- no `needs` declared at all. Cap(IO), in hand.
    println("...")
  end
end
```

`root_cap` was an ordinary global of type `Cap(IO)`, in scope in every module.
The only diagnostic that program received was about its `println`. Narrowing
from there to any descendant was then free **and legitimate**, because
`cap_narrow` demands exactly the parent the module now held.

That is no-authority-from-nothing violated at the *source* rather than at the
construction site, and it is why the claim earned by R3 had to be worded "a
capability cannot be fabricated from data" rather than the shorter "a
capability can only be received, never constructed". Nothing was received
here. R2 is what makes the shorter sentence true.

## What R2 turned out to be

Much smaller than the design implied, because **the boundary already existed**.
`main` may be zero-arity or take exactly one `Cap(IO)`; `check_main_signature`
in `lib/desugar/desugar.ml` already enforced that, and `run_module` in
`lib/eval/eval.ml` already passed the erased root to the one-parameter form.
There was no runtime plumbing to build — capabilities are opaque unit
sentinels and `march_cap_narrow` is `return cap;`, so the whole game is
compile-time.

So R2 reduced to one change: **make `root_cap` unnameable.**

- `env.root_cap_allowed` (new) gates it. Referencing `root_cap` where it is
  false is a hard error naming `fn main(cap : Cap(IO))` as the grant site.
- The name stays **bound**. Unbinding it would report "I cannot find
  `root_cap`", which is a worse experience than the hole was, and would send a
  cascade of unification failures after a single mistake. Only *naming* it is
  refused; its type is still `Cap(IO)`.

### Two exemptions, both scoped by enclosing context

Enforced by checking where we are, **not** by the checker declining to look.
The distinction is the whole point: "we never checked here" and "we decided
not to check here" are indistinguishable from a passing test, and the second
is a decision someone can review.

- **`test` / `describe` / `setup` / `setup_all` bodies.** They have no `main`
  to be granted from. Without this, capability behaviour would not be testable
  from March at all.
- **The REPL**, likewise entry-point-less. Carried by
  `check_module_with_env`, whose only caller is `lib/jit/repl_jit.ml` — which
  is what makes that function the right carrier rather than a flag threaded
  down from the CLI.

Both are ambient authority, in a context that cannot reach production code: a
dependency's `test` blocks do not run in a consumer's build. Documented as a
known remaining hole rather than waved through.

## Interaction: R2 partly subsumed a Check B witness

`reject/t151` (from the R3 work) demonstrated that `needs` coverage must reach
inside function bodies. Its route was *"`root_cap` is ambient, so a
console-only module can take the root and narrow it to file-write in a `let`
annotation"* — exactly what R2 closed.

Rewritten around a **lambda parameter annotation**
(`let take = fn (c : Cap(IO.FileWrite)) -> 1`), which is strictly better: it
names a capability without needing a *value* at all, so it does not depend on
obtaining one from anywhere and survives R2 unchanged. Renamed to
`reject/t151_cap_body_annotation_undeclared.march`.

Consequence worth recording: **the `let`-annotation spelling specifically is
now unreachable.** A `let` needs a right-hand side, and after R2 every route to
a capability value runs through a signature Check 1 already reads. `bind_ty`
is still walked and `accept/t145` pins the positive case, but it is defensive
rather than witnessed — the same status as `EAnnot` and alias-RHS.

The same forced the alcotest counterpart to change: constructing "declare
`IO.FileWrite`, use it *only* in a body annotation" now requires `needs IO` to
obtain the value, which subsumes `IO.FileWrite` and makes the separate
declaration redundant — destroying the thing the test measures. It uses the
lambda-parameter route for the same reason.

## A vacuous test found on the way

`test_proof_cap_pfn_forge_error` in `test/test_codegen.ml` used
`cap_narrow(root_cap())` to make its body typecheck while asserting Check 6
fires. But `root_cap()` — the callable spelling — was **already** a typecheck
error in its own right (`noncallable_builtin_values`), so the assertion passed
whether or not Check 6 fired at all. Now takes the capability as a parameter,
which makes it non-vacuous.

## Tests

3 new conformance files (corpus 257 → **260**, 129 accept + 131 reject):

- `reject/t152_root_cap_is_ambient_authority` — the hole itself.
- `accept/t146_root_cap_in_test_body` — the exemption, and that it is real.
- `accept/t147_main_receives_the_root` — the grant path, threading through a
  private helper. Predates R2 and already passed; pinned because R2's argument
  is that the ambient global was removable *without* removing the ability to
  obtain a capability. If it ever fails, R2 stopped being a fix and became a
  removal.

`test_tc_root_cap_bare_ok` in `test/test_compiler.ml` is **inverted** to
`test_tc_root_cap_bare_rejected` — it asserted that a bare `root_cap`
reference was fine, which was true and was the problem. It also now asserts
the diagnostic names `main`, since a bare "unbound variable" would be worse
than the hole.

Migrated to `main`-threading: 6 corpus/example `.march` files,
`test/test_cap_unforgeable.ml`, `test/test_codegen.ml`, and
`docs/cookbook/capabilities.md`. `docs/capabilities.md` and
`specs/lang/capabilities.md` already documented the correct pattern and needed
no change. **Zero stdlib files reference `root_cap`.**

## What this does NOT do

R2 moves the root; it does not gate IO. **Built-in IO is still ambient** —
`file_read(p)` compiles with no capability in scope, because that is R1 and
untouched. A program can still do everything it could before without ever
holding a capability. What changed is that a capability *value* can now only
come from `main`.

## Verification caveat

The conformance corpus was confirmed at 260/260 and the capability suites pass.
The full suite was **not** re-run to completion: the host was at load average
~375 on 14 cores with several unrelated processes wedged for days, under which
a green or red result is not evidence either way. See the apparatus notes in
`specs/progress/2026-08-05-cap-unforgeability.md` — this is the second time in
one day that machine state, not the code, was the thing producing "failures".
