# Aggregate missing-`needs` errors into one diagnostic per module

**Status:** Landed (2026-08-14). Task 5 of the capability-UX plan
(`specs/2026-08-13-capability-ux-plan.md`).

## The problem

A `main` that prints, writes a file, reads the clock, and calls the RNG with
nothing declared produced **five** errors for one mistake: the grant error
(already aggregating all four capabilities into one replacement signature)
plus four separate missing-`needs` errors, one per offending call site, each
carrying its own single-line `FInsert` fix. `forge fix` applied all four in
one pass already (it iterates diagnostics), so functionally nothing was
broken — but the diagnostic noise scaled with the number of undeclared
builtins touched, not with the number of mistakes made.

## The fix

Restructured Check 1b (`lib/typecheck/typecheck.ml`, body-scan check that
walks `body_cap_uses`) from a `List.iter` that emitted one `Err.error_with_fix`
per uncovered `(cap_path, span)` pair into a `List.filter_map` that
accumulates every uncovered pair into `missing_needs`, followed by a single
`match` that emits at most one diagnostic:

- Capabilities are sorted (`List.sort_uniq String.compare`) and de-duplicated
  for the message and the code.
- The span reported is the **earliest** offending call site by
  `(start_line, start_col)`, found with an explicit `List.fold_left` over
  `missing_needs` — not just `List.hd`, because `body_cap_uses` is built by a
  fold that *prepends*, so it is not in source order and the first list
  element is not necessarily the first call site in the file.
- The fix is a single `Err.FInsert` whose `text` joins every missing
  `needs <cap>` line with `\n`, reusing the exact `after_line` expression the
  original single-cap fix used (`mod_name.span.start_line`) — no new
  line-computation logic.
- The code is `cap_needs:<Cap1>,<Cap2>,...` (comma-joined, sorted), extending
  Task 1's single-cap `cap_needs:<Cap>` convention so a presentation-layer
  consumer can still parse the exact missing set.

## Deviation from the brief

The brief's Step 3 sketch (`!missing_needs` as a mutable ref threaded through
the existing `List.iter`, `mod_header_line` as an already-existing name) does
not match the real code: there is no mutable-ref-based accumulator pattern in
this function, and the fix's `after_line` is inlined as
`mod_name.March_ast.Ast.span.March_ast.Ast.start_line` at the call site, not
bound to a name. Implemented as a `List.filter_map` producing an immutable
`missing_needs` list instead of a ref (idiomatic for this codebase and this
function has no other mutable state), and reused the inline `after_line`
expression verbatim rather than inventing a `mod_header_line` binding.

The brief's sketch also implicitly assumed `missing_needs` would already be
in a useful order for "first span" (`List.sort_uniq compare` over `(cap,
span)` pairs, taking the head) — but `compare` on the pair would sort by
`cap_path` first (since it's the first tuple field), giving the *span of the
alphabetically-first capability*, not the *first call site in the file*. That
does not satisfy the brief's own explicit requirement ("first offending call
site's span, so the rendered source excerpt still points at real code") once
the missing capabilities are not encountered in alphabetical order in the
source. Used an explicit position-comparing fold instead.

## Message wording

Old (single-cap, one per call site):
```
function body calls a builtin that requires `Cap(IO.FileWrite)` but `Logger`
does not declare `needs IO.FileWrite`.
hint: add `needs IO.FileWrite` to the module body.
```

New (aggregated; degenerates to near-identical wording for exactly one
missing capability):
```
function bodies in `Logger` call builtins that require `Cap(IO.FileWrite)`, but
`Logger` does not declare `needs IO.FileWrite`.
hint: add `needs IO.FileWrite` to the module body.
```

New, multi-capability case (`ManyCaps` example, `main(cap : Cap(IO))` with an
undeclared `println` and `file_write`):
```
function bodies in `ManyCaps` call builtins that require `Cap(IO.Console)`, `Cap(IO.FileWrite)`, but `ManyCaps` does not declare `needs IO.Console` and `needs IO.FileWrite`.
hint: add `needs IO.Console` and `needs IO.FileWrite` to the module body.
```

## Tests

- `test/test_helpers.ml`: added `count_errors_with ctx sub`, mirroring
  `has_error_with` exactly but returning the match count instead of a bool
  (needed to assert "exactly one", not just "at least one").
- `test/test_compiler.ml`: `test_missing_needs_reported_once_per_module`,
  registered in the H9 actor-handler group next to
  `test_actor_handler_cap_needs_ok`. Pins: exactly one error containing "does
  not declare" for a module reaching four undeclared builtins across two call
  sites, and that both `IO.Console` and `IO.FileWrite` are named in it.
- No existing alcotest test asserted the exact old sentence
  `"function body calls a builtin that requires"` verbatim (checked with
  `grep -rn "calls a builtin that requires" test/*.ml`, zero hits) — the
  existing single-cap assertions in `test/test_cap_ceiling.ml` all match on
  the substring `` "does not declare `needs <Cap>`" ``, which is unchanged
  for the single-capability case (the aggregated sentence degenerates to the
  same trailing clause when there is exactly one missing capability), so none
  needed editing.

### Red/green

Red (test added, code not yet changed — one error per call site):
```
$ ./_build/default/test/run_compiler.exe -e   (H9 group)
FAIL: one aggregated missing-needs error, not one per builtin — got 2, expected 1
```

Green (after the aggregation change):
```
$ scripts/run-tests.sh -q compiler
...
  [OK]          typecheck                                179   missing needs reported once per module
...
Test Successful in 4.947s. 837 tests run.
All suites passed.
```
exit 0.

## Verification

`dune build --root . bin/main.exe test/run_compiler.exe` — exit 0.

`scripts/run-tests.sh -q compiler` — exit 0, 837 tests run (836 pre-existing
+ 1 new), all pass. Full `scripts/run-tests.sh` deliberately skipped per this
task's instructions (machine under heavy concurrent load across five
worktrees).

`dune build --root . @types-check` — exit 0, `=== core-march-types: 290
passed, 0 failed ===`. Swept `specs/lang/types/reject/*.march` for files
whose `EXPECT-ERROR` pins the old wording or a multi-capability Check-1b
scenario; none do (`t44_cap_no_extern_extern_block.march` and
`t19_impl_extra_method.march` were the only "does not declare" hits, both
unrelated checks — Check 1c and interface-method checking respectively). No
corpus file needed editing, so `specs/lang/types/INDEX.md` and its counts are
unchanged.

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

### End-to-end `forge fix` walkthrough

Hermetic toolchain: a shell-script PATH shim (not a symlink — `march`
resolves its stdlib/runtime relative to the invoked path, so a symlink from a
private bin/ directory would resolve against that directory instead of the
real build tree) `exec`ing the absolute paths of the just-built
`_build/default/bin/main.exe` and `_build/default/forge/bin/main.exe`, plus
`MARCH_HOME` pointed at an empty directory so no installed release resolves
ahead of the shim.

```
$ forge new aggfix && cd aggfix
created app project 'aggfix'

# lib/aggfix.march rewritten to:
mod Aggfix do
  fn main() do
    println("a")
    let _ = file_write("/tmp/aggfix.txt", "d")
    ()
  end
end

$ forge fix
fixed .../aggfix/lib/aggfix.march (2 changes)
1 file changed, 2 fixes applied
$ echo $?
0

# resulting lib/aggfix.march:
mod Aggfix do
  needs IO.Console
  needs IO.FileWrite
  fn main(_cap_console : Cap(IO.Console), _cap_filewrite : Cap(IO.FileWrite)) do
    println("a")
    let _ = file_write("/tmp/aggfix.txt", "d")
    ()
  end
end

$ forge build
compiled .../aggfix/.march/build/debug/aggfix
built: .../aggfix/.march/build/debug/aggfix
$ echo $?
0

$ forge run
a
$ echo $?
0
$ cat /tmp/aggfix.txt
d
```

Both `needs` lines landed from the single aggregated `FInsert`, in one
`forge fix` pass alongside the pre-existing grant `FReplace` fix (2 total
fixes, 1 file) — confirming the aggregated diagnostic composes with the
Task 1 grant fix exactly as the task's motivation described (five errors,
now two: one grant error, one aggregated `needs` error).

## Docs

`specs/lang/capabilities.md` and `docs/capabilities.md` ("What the compiler
tells you" section): updated both example transcripts to the new wording,
and added a new aggregated-example block (four capabilities collapsed into
one error/one fix) to `specs/lang/capabilities.md`, applied identically to
`docs/capabilities.md`. The two changed diagnostic-text blocks are verified
byte-identical between the files; the surrounding prose in the second block
already had minor pre-existing wording drift between the two copies ("Look
at" vs "But look at") unrelated to this change, left as found.

`CHANGELOG.md`: added under `### Changed` in `[Unreleased]`.
