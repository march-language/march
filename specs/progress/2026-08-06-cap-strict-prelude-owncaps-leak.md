# `--cap-strict` rejected the emptiest possible program

Filed and fixed 2026-08-06, found while measuring the nested-module keying bug
(`specs/progress/2026-08-06-cap-ceiling-nested-module-keying.md`).

## Symptom

```march
mod EagerMin do
  fn main() : () do
    ()
  end
end
```

```
$ march --compile --cap-strict -o /tmp/bin min.march
-- CAPABILITY CEILING --
`IO.Console` is used but cannot be attributed to any module — it is reached
only through indirect calls, whose callee is not statically known
```

A program with no capability use at all. Declaring `needs IO.Console` does not
help — an *unattributed* capability has no owner to check a declaration against,
so it fails closed by design. In practice `--cap-strict` could only pass if the
program itself called `println`.

Every accept test in `test/test_cap_ceiling.ml` happened to call `println`,
which is exactly why this was never caught: the user's own call attributes
IO.Console to the entry module and the unattributed branch never fires.

## Root cause

`own_caps_of_this_module` (`bin/main.ml`) collects "functions this file
declares" by walking the module's decls. Both call sites pass `desugared`
**after** the stdlib prepend — and they have to, since that is the module that
gets lowered. The prelude is unwrapped into global scope, so its top-level
functions ride in the entry module's decl list, and `println`/`debug` were
registered as the user's own. Their capabilities were then credited to the
user's module:

```
DBG owncap-key debug   -> [IO.Console]
DBG owncap-key println -> [IO.Console]
DBG own_caps=[IO.Console]  DBG flat_caps=[IO.Console]  DBG attrib=[]
```

`flat_caps` is the used-capability set; `attribution` is who used what. IO.Console
entered the former from the prelude and was absent from the latter, which is the
literal definition of "unattributed".

`march caps` was unaffected — it keys its own `belongs` off the module names the
listed FILES declare, so a bare `println` never matches. The comment on
`own_caps_of_this_module` claims the two paths cannot disagree; they did.

## Fix

Filter the walk by span file, skipping any `DFn` declared in a stdlib file —
the same `stdlib_span_files` gate the typechecker's Check 1b already uses to
avoid attributing prelude's capability uses to the entry module. Both call sites
(`--cap-strict` and `--cap-sandbox`) pass `~stdlib_files`.

Only IO.Console leaks today (the prelude's other top-level functions declare no
capabilities), and `--cap-sandbox` derives its SBPL grants from FileWrite /
Network / Process only, so the embedded profile is byte-identical before and
after. The observable fix is `--cap-strict`.

## Verification

- The empty program, and the doubly-nested reproducer from the keying bug with
  no `println` anywhere, both compile clean.
- Enforcement intact: `println` without `needs IO.Console` is still reported as
  ``module `X` uses `IO.Console` but does not declare needs IO.Console``.
- Pinned by two tests in `test/test_cap_ceiling.ml`: a capability-free program
  must compile, and an undeclared console use must still be caught. The second
  is the guard that the filter did not simply blind the check.
- `cap_ceiling` (17), `cap_strip` (4), `cap_package` (5), `cap_markers` (8),
  `cap_scope` (15), `test_caps` (13) all pass.
