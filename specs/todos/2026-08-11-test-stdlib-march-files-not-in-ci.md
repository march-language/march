# 37 of 94 `test/stdlib/*.march` files run in no CI runner (manual-only)

Found 2026-08-11 while updating a comment in `test_dataframe.march` for the
Task 4b review. Pre-existing, not caused by Task 4/4b — but it makes a claim
those tasks relied on (a "regression net" for a future DataFrame Min/Max
migration) weaker than it reads, and the audit that followed showed the gap is
much wider than one file.

**Scope: 37 of the 94 files in `test/stdlib/` are wired into no automated
runner** — 237 `describe` blocks in total. Spot-checked, they pass and are
substantial: `test_array.march` 174 tests, `test_sort.march` 248 tests,
`test_dataframe.march` 220 tests. The other 57 files ARE wired (they account
for the 56 cases `test_stdlib_march.exe` runs).

The full unwired list is reproducible with:

```bash
for f in test/stdlib/*.march; do b=$(basename $f); \
  grep -q "\"$b\"" test/test_stdlib_march.ml || echo "$b"; done
```

and currently reads: actor, array, bigint, bytes, check, cli, csv, dataframe,
datetime, decimal, derive_json, derive_json_multi, dir, enum, file, gen, hamt,
html, iolist, island_bridges, iterable, map, math, option, path, plot,
prelude, properties, queue, regex, result, set, sigil, sort, string,
string_utf8, task.

## The finding (worked through on `test_dataframe.march`)

`test/stdlib/test_dataframe.march` contains 220 passing tests across 33
`describe` blocks, including the `col_native_min_max` block added by Task 4
specifically as the regression net for a future `Simd` migration.

**No automated runner executes it.** It is referenced by:

- `test/test_stdlib_march.ml` — NO. That runner has a hardcoded list of
  `run_stdlib_test "test_FOO.march" "TestFoo"` entries and `test_dataframe`
  is not among them. (It also would not fit as-is: that runner calls
  `TestFoo.main()`, and this file has no `main` — it uses top-level
  `describe`/`test` blocks, i.e. the `march test` runner's format.)
- `test/dune` — NO rule mentions it.
- `run_stdlib.exe` — NO. The 47 `stdlib_dataframe` alcotest cases that DO run
  come from March snippets embedded in `test/test_stdlib_suite.ml` (OCaml
  string literals), which is a completely separate body of tests from this
  file, despite the similar name.

Only the file's own header comment says how to run it:
`dune exec march -- test test/stdlib/test_dataframe.march`.

## Evidence (falsifiable both ways)

Inserted `test "SABOTAGE_PROBE" do assert false end` into the
`col_native_min_max` describe block, then:

| runner | result |
|---|---|
| `dune build test/run_stdlib.exe` + `run_stdlib.exe -e` (after rebuild) | **exit 0, probe never appears** |
| `test_stdlib_march.exe -e` | **exit 0, 56 tests, no dataframe group at all** |
| `march test test/stdlib/test_dataframe.march` | **exit 1**, `FAIL: "col_native_min_max SABOTAGE_PROBE"`, `1/221 tests failed` |

So the tests are real and correct — they just are not wired to anything that
runs in CI. Clean run: `220 tests passed`, exit 0.

(Note the rebuild step in the first row: the runner reads the `_build` copy, so
an un-rebuilt sabotage is vacuous either way. Both were re-checked with
`dune build` first — see `project_build_stdlib_missing_copies` in repo memory
for the general trap.)

## Why it matters

`bench/RESULTS.md`'s "DataFrame Min/Max: not migrated" section and
`specs/todos/2026-08-10-simd-vector-types-compiled-path.md` both cite this
describe block as the safety net that makes a future migration attempt safe.
It only functions as one if someone remembers to run the file by hand. Those
two references have been softened to say "manual-only" pending this item.

## Fix direction

Two options, roughly equal effort:

1. **Add a `test/dune` rule** that runs `march test
   test/stdlib/test_dataframe.march` under the `runtest` alias, judging by
   exit code. Most faithful — keeps the file in its current `describe`/`test`
   format, and the `march test` runner already reports failures usefully.
   Check first whether other `test/stdlib/*.march` files are in the same
   situation and do them together.
2. **Convert to the `test_stdlib_march.ml` shape** (wrap in
   `pub fn main()`, add the `run_stdlib_test "test_dataframe.march"
   "TestDataFrame"` entry). More churn, and loses the per-test reporting the
   `describe`/`test` format gives.

Whichever route, do it for all 37 at once — a per-file fix leaves the same
hole open everywhere else. Note most of the unwired files have NO `fn main`
and use top-level `describe`/`test` blocks, so option 1 (a dune rule per file,
or one rule globbing the directory) is the lower-churn path; option 2 would
mean restructuring 37 files.

Expect some of them to fail once actually run — they have not been enforced,
so drift is likely. Budget for fixing real failures, and land the wiring only
once green, or the `runtest` alias goes red for everyone.
