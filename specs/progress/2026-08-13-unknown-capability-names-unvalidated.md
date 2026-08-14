# Reject unknown capability names in `needs` with a suggestion

**Status:** Landed (2026-08-14). Task 4 of the capability-UX plan
(`specs/2026-08-13-capability-ux-plan.md`).

## The problem

`needs IO.Filesystem` (wrong case), `needs IO.FileWrit` (typo), and
`needs Network` (a bare leaf missing its `IO.` root) were all silently
accepted. Each produced only the existing unused-capability warning —
*"declares `needs X` but no function requires it — help: remove the unused
capability declaration"* — which points the user at deleting the declaration
rather than at the typo, while the actual capability the code needed then
surfaces elsewhere as an apparently unrelated missing-`needs` diagnostic. The
`IO` lattice (`March_caps.Cap_lattice.hierarchy`) is closed, so an `IO`-rooted
path that isn't in it is definitely wrong and can be checked eagerly.

## The fix

`March_caps.Cap_lattice.suggest_cap : string -> string option`
(`lib/caps/cap_lattice.ml` / `.mli`) — `None` when `cap` is a legal
capability path, `Some known` naming the closest known capability otherwise.
Rule, in order:

1. An exact match against `hierarchy` is legal.
2. Otherwise, if the cap's leaf (text after the last `.`) matches a known
   capability's leaf case-insensitively, that known capability is the
   suggestion — this is what catches `needs Network` (leaf `Network` matches
   `IO.Network`'s leaf) and `needs IO.Filesystem` (leaf `Filesystem` matches
   `IO.FileSystem`'s leaf case-insensitively).
3. Otherwise, if the path is not rooted at `IO` (first segment isn't `IO`,
   and the whole path isn't just `IO`), it's an FFI capability root (e.g.
   `Ffi`, `LibC`, `Db.Migrated`) — these are intentionally outside the
   lattice per `cap_lattice.ml`'s header comment and are legal.
4. Otherwise (an `IO`-rooted path not in the lattice and with no leaf match)
   it's a typo inside the closed lattice: Levenshtein-distance-rank against
   every known capability, suggest the closest if edit distance <= 3, else
   fall back to suggesting the root `IO`.

Called from `check_module_needs` (`lib/typecheck/typecheck.ml`), added as a
new "Check 0" right after `declared_needs` is computed, so it runs
unconditionally for every module (not gated behind any `cap` module
annotation) and fires before any of the existing checks. Reports
`Err.error_with_fix` with an `FReplace` fix that rewrites the `needs` line to
the suggested capability.

Note on brief deviation: the brief's Step 4 pointed at the `Ast.DNeeds` arm
inside `check_no_extern_module` (~line 11089 pre-change). That function only
runs when a module declares `cap no_extern` (`if inner_env.no_extern_mod then
check_no_extern_module ...`), so validation placed there would never fire for
the plan's own test modules (none declare `cap no_extern`). Placed the check
in `check_module_needs` instead, which every module's `needs` list already
passes through unconditionally — this is also where `declared_needs` (the
exact list this check needs to walk) is already computed.

## Tests

`test/test_compiler.ml`, new `cap_unknown_name` suite (registered after
`cap_propagation`), four tests verbatim from the plan brief:

- `test_unknown_capability_is_rejected_with_suggestion` — `needs IO.FileWrit`
  is an error naming both the bad path and `IO.FileWrite`.
- `test_wrong_case_capability_is_rejected` — `needs IO.Filesystem` suggests
  `IO.FileSystem`.
- `test_bare_leaf_capability_is_rejected` — `needs Network` suggests
  `IO.Network`.
- `test_ffi_capability_root_still_accepted` — `needs IO.Foreign` plus an
  `extern "libc": Cap(LibC)` block produces no "is not a known capability"
  error; pins that FFI roots outside the lattice stay legal.

### Red/green

Red (before implementing `suggest_cap` / the `check_module_needs` call site,
test file only):
```
$ ./_build/default/test/run_compiler.exe test cap_unknown_name -e
...
3 failures! in 0.005s. 4 tests run.
```
exit 1. Failures were exactly the first three (unknown-capability, wrong-case,
bare-leaf); the FFI-root test passed already (nothing rejected it yet).

Green (after implementing):
```
$ ./_build/default/test/run_compiler.exe test cap_unknown_name -e
...
Test Successful in 0.005s. 4 tests run.
```
exit 0.

## Verification

Build (exit 0):
```
dune build --root . bin/main.exe test/run_compiler.exe
```

`scripts/run-tests.sh -q compiler` — exit 0, `Test Successful in 11.423s. 834
tests run.` (machine was under heavy concurrent load — full `scripts/run-tests.sh`
across all suites is deferred to the final whole-branch review, per the task's
constraints).

`dune build --root . @types-check` — exit 0, `=== core-march-types: 290
passed, 0 failed ===`. This corpus is not covered by `run-tests.sh`; a
regression here (a corpus file declaring a capability the new check now
rejects) would have shipped invisibly otherwise, per the note this task's
brief carried about Task 3's own miss.

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

## Sweep

Searched `stdlib/`, `specs/lang/types/`, `test/`, `bench/`, and (for
completeness) `forge/` and the whole repo for `needs <cap>` declarations that
the new check might now reject:

```
grep -rn "^[[:space:]]*needs[[:space:]]" --include="*.march" . \
  | grep -v -E "needs\s+IO(\.|$|\s)"
```

Findings, all confirmed legal under the FFI-root rule (root isn't `IO`, and
no leaf collides with a known capability's leaf):
- `needs Ffi` (`stdlib/audio.march`, `stdlib/canvas.march`, `stdlib/dom.march`,
  `forge/tasks/notebook_server.march` uses `IO.WebSocket` — fine — plus
  ~18 files under `test/native/*.march` and `forge/test/test_forge.ml`'s
  embedded fixtures).
- `needs Db.Migrated` (`specs/lang/types/accept/t63_proof_cap_passthrough.march`)
  and `needs Db.P` (`specs/lang/types/reject/t55_...`, `t56_...`) — FFI-style
  proof-capability roots, leaf `Migrated`/`P` collide with nothing.

No stdlib or corpus module declares an `IO`-rooted capability outside
`hierarchy`, so no widening of the FFI-root rule and no addition to
`hierarchy` was needed.

Doc updates applied identically to `specs/lang/capabilities.md` (new
paragraph after the hierarchy diagram, under "Capability hierarchy") and its
`docs/` copy (`docs/capabilities.md`, same paragraph adapted to that file's
Jekyll-link style).
