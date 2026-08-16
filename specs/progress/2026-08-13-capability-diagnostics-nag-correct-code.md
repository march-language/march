# Stop nagging correct capability code (Task 6, capability-UX plan)

**Status:** Landed (2026-08-14). Task 6 of the capability-UX plan
(`specs/2026-08-13-capability-ux-plan.md`).

## The problem

Two diagnostics fired on capability code that was already correct:

1. Every capability parameter warned `Unused variable `cap`.`. A capability
   value is a runtime-erased grant token — never referencing one in the body
   is its normal, correct state. `forge new`'s own scaffold template had to
   name its parameter `_cap` purely to dodge this warning (Task 2's fix,
   see `specs/progress/2026-08-13-forge-new-scaffold-not-cap-correct.md`,
   `forge/lib/scaffold.ml`).
2. `fn main(cap : Cap(IO))` emitted the Check-3 "consider narrowing... for
   least-privilege" hint, while `specs/lang/capabilities.md` calls
   `fn main(cap : Cap(IO))` "the established entry-point convention" and
   says `needs IO` in entry points "is fine." The compiler nagged users for
   following its own documented advice.

## The fix

`lib/typecheck/typecheck.ml`:

- **`warn_unused_params`**: a parameter is now exempt from the
  unused-variable warning when its declared type names a capability
  (`March_caps.Cap_surface_ty.caps_in_ty p.param_ty <> []`), checked for the
  `FPNamed` and `FPDefault` param forms (the only forms that carry a
  `param_ty`). The exemption is narrow by construction: a `Some ty` with no
  `Cap(...)` anywhere in it (e.g. `x : Int`) still warns exactly as before.
- **Check 3** (the `Cap(IO)`-root narrowing hint): `used_caps`' element type
  changed from `(string * Ast.span)` to `(string * string * Ast.span)`, the
  middle component being the enclosing function's bare name when the
  capability use comes from a single named function (`DFn`, a `DImpl`
  method, via `fd.fn_name.txt`), and `""` for every use that names no single
  function (a type declaration, `extern` block, interface method
  declaration, or actor handler parameter — `""` can never equal `"main"`,
  so none of these are ever accidentally exempted). The hint's `List.iter`
  now reads `if cap_path = "IO" && fn_name <> "main" then ...`, so `main`'s
  own `Cap(IO)` parameter or annotation no longer triggers it, while every
  other function's still does. All three consumers of `used_caps` (Check 1's
  "must be covered by `needs`" error, Check 2's "is this need actually
  used" existence check, and Check 3 itself) were updated to the 3-tuple
  shape; only Check 3 reads the new middle field.

`forge/lib/scaffold.ml`: renamed the scaffold's `main` parameter from
`_cap` back to `cap` in all three generated templates (`app`, `tool`, and
the test-module template) — the underscore prefix was Task 2's workaround
for the warning this task removes, and reads oddly in freshly generated
code once the warning is gone.

## What was deliberately NOT touched

- `used_caps`' `sig_caps` component for `DFn` still includes return-type
  capabilities, not just parameters, and the exemption applies uniformly to
  the whole function once tagged with its name — a `main` that returns
  `Cap(IO)` or carries a body annotation naming `IO` is exempt from the hint
  too, not just a `Cap(IO)` *parameter*. This is a reasonable widening of
  the brief's literal parameter-only framing: the reference calls
  `fn main(cap : Cap(IO))` the convention, and the same rationale (don't nag
  the entry point about the root capability) applies regardless of which
  signature position names it.
- Capabilities remain module-scoped: neither change introduces or removes
  any requirement that a capability value be passed to satisfy a check.
- Docs (`specs/lang/capabilities.md`, `docs/capabilities.md`): neither
  document quotes the exact diagnostic text of either suppressed message
  (grepped for "Unused variable", "consider narrowing", "least-privilege" —
  no hits in either file), so no doc edit was needed under the plan's
  "if capabilities.md documents either diagnostic" condition.

## Tests

`test/test_compiler.ml`, new `cap_ux_no_nag` suite (4 tests, verbatim from
the task brief):

- `test_unused_cap_param_is_not_warned` — a `Cap(IO.Console)` parameter
  named `cap`, unreferenced in the body: no "Unused variable" warning.
- `test_ordinary_unused_param_still_warned` — an ordinary `Int` parameter,
  unreferenced: still warns (the narrow-exemption control).
- `test_main_is_not_nagged_about_root_cap` — `fn main(cap : Cap(IO))`: no
  "root capability" hint.
- `test_non_main_still_hinted_about_root_cap` — a non-`main` function
  `helper(cap : Cap(IO))`: still hinted (the Check-3 control).

## Verification

Build (both exit 0, `$?` captured directly, no pipe):
```
dune build --root . bin/main.exe
dune build --root . test/run_compiler.exe
```

**Genuine red/green cycle**, done by temporarily replacing
`lib/typecheck/typecheck.ml` with `git show HEAD:lib/typecheck/typecheck.ml`
(safe: the edit was still uncommitted, so this reads from `HEAD` — no
`git stash` used, per repo policy), keeping a copy of the edited file
alongside, rebuilding, running the new suite, then restoring the edited
file and rebuilding again:

- **Red** (pre-fix `typecheck.ml`, new tests already in place):
  `./_build/default/test/run_compiler.exe -e 'cap_ux_no_nag'` — `2 failures!
  in 0.026s. 4 tests run.` Exactly the two expected: `test 0`
  ("a capability parameter is not an unused variable": expected `false`,
  received `true`) and `test 2` ("main is not told to narrow the root
  capability": expected `false`, received `true`). Tests 1 and 3 (the
  controls) passed even pre-fix, as expected.
- **Green** (edited `typecheck.ml` restored): same command —
  `Test Successful in 0.028s. 4 tests run.`

`scripts/run-tests.sh -q compiler` — `842 tests run`, all suites passed,
exit 0.

Full (non-`-q`) `test/run_compiler.exe` — run directly (not through
`scripts/run-tests.sh`, per the task's machine note) to exercise the
`` `Slow` `` tests in `test/test_cap_ceiling.ml` that `-q` skips (a prior
task in this plan found five of them pinning exact diagnostic wording);
all suites including `cap_scope`, `cap_ceiling`, `cap_unforgeable` passed —
exit 0. Grepped `test/test_cap_ceiling.ml`, `test_cap_scope.ml`,
`test_cap_unforgeable.ml`, `test_codegen.ml`, `test_refinecheck.ml`,
`test_stdlib_suite.ml` for the literal diagnostic text ("Unused variable",
"narrowing", "root capability", "least-privilege") beforehand: the only
codegen hit (`test_check_diagnostic_display_deterministic`,
`test/test_codegen.ml:10462-10495`) asserts the Check-3 hint fires for a
**non-`main`** function (`fn run(io : Cap(IO))`), which this task leaves
untouched — confirmed unaffected.

`dune build --root . @types-check` — `core-march-types: 290 passed, 0
failed` — exit 0.

`scripts/check-docs.sh` — exit 0:
```
== Check A: source pointers in current docs ==
  ok — all cited source paths exist
== Check B: stdlib module count (actual: 115) ==
  ok — no stale stdlib counts
== Check C: conformance-corpus INDEX counts ... ==
  ok — corpus INDEX counts match on-disk file counts
doc-lint passed
```

**`forge new` + `forge check` walkthrough**, hermetic (PATH shims — shell
scripts, not symlinks, `exec`ing the absolute `_build/default/bin/main.exe`
and `_build/default/forge/bin/main.exe` — plus `MARCH_HOME` at an empty
directory and `MARCH_RUNTIME_DIR`/`MARCH_STDLIB` pointed at
`_build/default/{runtime,stdlib}`, modeled on
`forge/test/test_cap_sandbox.ml`'s `setup_hermetic_toolchain`, since a bare
`march`/`forge` on `PATH` resolves to a stale installed compiler):

```
$ forge new demoapp --app
created app project 'demoapp'
$ cat demoapp/lib/*.march
mod Demoapp do

  needs IO.Console

  fn main(cap : Cap(IO.Console)) do
    println("Hello from demoapp!")
  end

end
$ cd demoapp && forge check
  1.05s
checked 1 file(s) in .../demoapp/lib
$ echo $?
0
```

No warnings, no hints — the generated `fn main(cap : Cap(IO.Console))` (no
longer `_cap`) round-trips clean through `forge check`.
