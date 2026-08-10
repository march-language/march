# A module-level fn/let shadowing a builtin was treated as calling it

Landed 2026-08-09. Found during a re-audit of seven filed capability todos
(`specs/2026-08-09-cap-loose-ends-plan.md`); the plan's Tier 0.

## What was filed vs. what was actually there

`2026-08-03-runtime-symbol-naming-and-uncompiled-cap-builtins.md` diagnosed
`dns_resolve`'s false-marker risk as narrow: its C function is unprefixed
(`dns_resolve`, not `march_dns_resolve`), so a user function of the same
bare name resolves through the identity-fallthrough and "would record a
spurious IO.Network capability marker."

Reproducing it turned up something much bigger. `file_read` — a builtin
whose C symbol is `march_file_read`, no naming collision anywhere near
codegen — reproduced identically:

```march
mod T do
  needs IO.Console
  fn file_read(x : Int) : Int do x + 100 end
  fn main() : () do println(int_to_string(file_read(1))) end
end
```

```
function body calls a builtin that requires `Cap(IO.FileRead)` but `T` does
not declare `needs IO.FileRead`.
```

Confirmed, interpreted and compiled, that the user's `file_read` is what
actually runs (`101`, not a file-read result — module-scope declarations
correctly shadow builtins in real name resolution). The diagnostic is not
imprecise, it is wrong: this program uses zero `IO.FileRead`. And since
Check 1b's severity flip (#219, 2026-08-06) turned this from a warning into
a hard, default-on compile ERROR, this is not a marker-accuracy nuance — it
silently breaks the build for any project that names a function
`file_read`, `file_write`, `random_bytes`, `dns_resolve`, or roughly twenty
other ordinary words that happen to be capability-bearing builtin names,
with no workaround short of renaming.

## Root cause

Every capability-inference pass scans call sites syntactically —
`March_ast.Calls.names_and_name_spans` walks raw AST call expressions and
string-matches the callee name against a table — with no awareness that a
module-level declaration of the same name shadows the builtin. Six sites in
`Typecheck.check_module_needs` alone did this (the Check 1b/Check 2
diagnostic surface, the closure-recording feeding Check 4 and `march caps`,
and the `@[scope]` literal-path check). The identical shape recurred
independently in `check_pure_module`/`check_deterministic_module`
(banned-name sets), and a THIRD time in `lib/refinecheck/cap_infer.ml`,
which carries its own, independently-duplicated `cap_table` — this
codebase's established "two-tables-drift" failure mode, now a third copy.

`march caps` (the inferred-capability extractor feeding
`forge audit --inferred` and the `--cap-sandbox` profile) shares the bug via
the same `builtin_caps_of_expr` helper, and fails in the OPPOSITE direction:
silently over-reporting a capability the program doesn't use, which would
over-grant a sandbox profile rather than reject a build. Verified before the
fix: `march caps` on a module whose only `file_read` is its own arithmetic
function reported `{"caps":["IO.FileRead"]}`.

## Fix

One shared helper, `Typecheck.locally_declared_names_of : Ast.decl list ->
(string, unit) Hashtbl.t` — a module's own bare `DFn` names and top-level
`DLet` `PatVar` names, exactly the set that provably wins name resolution
over a global builtin at that scope. Every one of the eight sites (six in
`check_module_needs`, one each in `check_pure_module`/
`check_deterministic_module`) now checks it before matching a call name
against a capability table.

`cap_infer.ml` — a different library (`march_refinecheck`, already depending
on `march_typecheck`) — reuses the same helper rather than deriving a fourth
copy of the walk: `iter_cap_calls` gained an optional `~shadowed` predicate,
threaded from `check_decls`'s own `decls`.

**Deliberately out of scope, and why:**
- Nested-module shadowing (`Lib.file_read`) was already immune — a nested
  module's qualified name never string-matches a bare table key.
- A parameter or local `let` shadowing a builtin *within* a function body
  (rather than at module level) is a real, rarer residual gap. Closing it
  needs actual scope-aware resolution these AST-level passes don't have.
  Filed as a follow-up in the plan doc rather than blocking this fix — the
  module-level case is the one that reproduces and the one the severity
  flip made dangerous.
- `cap_infer.ml`'s call-GRAPH edges (`direct_callees`, used only for the
  "reached from `main`: …" explanatory chain) were not given the same
  treatment — a spurious edge there degrades an already best-effort hint's
  wording, not whether the hint fires at all.

## The fix itself shipped a regression, caught by the corpus sweep

The first version of `locally_declared_names_of` scanned `decls` for bare
`DFn`/`DLet` names with no further filter. All nine `cap_shadow` unit tests
passed — because every one of them used the bare `typecheck` helper
(`parse_and_desugar` + `check_module`, no stdlib prepended). The REAL
pipeline (`bin/main.ml`, every `--check`/`--compile` invocation) unwraps
`prelude.march` directly into the ENTRY module's own flat `decls` list — the
exact same list `locally_declared_names_of` scans — so `println`'s own
`DFn` sat right there, and the fix treated it as "locally declared,"
shadowing every entry-module call to `println`. A program with **no `needs`
at all** calling bare `println` wrongly typechecked.

Caught by `specs/lang/types/check_types.sh`, not by the unit suite:
`reject/t40_migrate_state_does_io.march` — an unrelated fixture for a
DIFFERENT check ("Check 8", migrate-fn IO-freedom) that happens to read the
same `env.own_cap_closures` table this fix populates — started wrongly
*accepting*. Confirmed against a clean `origin/main` build in a scratch
worktree (never `git stash`, per project convention) before touching
anything, to rule out a pre-existing flake.

Root cause and fix: `locally_declared_names_of` now excludes any `DFn`/
`DLet` whose span is stdlib (`span_is_stdlib`) — the identical filter
`check_module_needs`'s own body-scan and `own_caps_of_this_module`
(bin/main.ml) already apply for the same reason, documented in both places
as a trap this codebase has hit before. A DIRECT regression test was added
first (`test_prelude_println_still_requires_needs`) and, on its first
attempt, **also failed to reproduce the bug** — it used
`load_stdlib_file_for_test`, which wraps prelude as a `DMod "Prelude"` for
addressability (`Prelude.foo`), which is NOT the flat shape the real
pipeline produces, so `println` was invisible to the top-level-only scan
either way. Un-wrapping the `DMod` before prepending made the test
reproduce the regression, and confirmed the fix.

**The lesson, stated plainly:** a fix to a syntactic, stdlib-touching pass
cannot be trusted on unit tests built from `parse_and_desugar` alone — it
has to be exercised against the actual stdlib-prepended shape at least once,
and the corpus sweep (which does run through the real `bin/main.exe`
pipeline) is what caught what nine passing unit tests did not.

## Verification

`cap_shadow` test group, 9 tests (RED first, including the regression test
above): module `fn` and module `let` shadowing a builtin call, the
`dns_resolve` witness specifically, a negative control (an unshadowed real
builtin call must still require `needs`), the `march caps` inferred-set fix,
both `cap pure`/`cap deterministic` fixes, the `cap_infer` hint fix (which
proved necessary empirically — after the typecheck-side fix alone, `--check`
on the reproducer exited 0 but still printed a wrong HINT, since
`cap_infer.ml`'s bug is independent of Check 1b's), and the prelude/`println`
regression guard.

Corpus: `accept/t168_module_fn_shadows_builtin_name`; full re-run 280/280,
`reject/t40_migrate_state_does_io.march` confirmed rejecting again.

Full suite: compiler 832 (9 new), corpus 280/280, `scripts/run-tests.sh`
green, check-docs pass, and a 313-program sweep over
`examples/`+`bench/`+`test/native/`+`test/stdlib/`+`test/whole_program/`
under `--check` for crashes.
