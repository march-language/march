# LANDED 2026-08-18 — registry-drift guard added to `test_stdlib_march.ml`

**Status: shipped.** Added a self-checking assertion, `check_registry_drift`,
run as the first Alcotest test case (group `"registry"`) in
`test/test_stdlib_march.ml`:

- It computes the true on-disk set (`Sys.readdir` over `test/stdlib`, filtered
  to `test_*.march`) and the true *registered* set — parsed directly out of
  `test_stdlib_march.ml`'s own source (every `run_stdlib_test "test_FOO.march"`
  literal, with `(* ... *)` comments stripped first so a commented-out
  registration, e.g. `test_flow.march`, isn't mistaken for a live one). The
  registered set is derived rather than hand-duplicated so the check can never
  itself drift from the real registration list.
- Any on-disk file present in neither the registered set nor a documented
  allowlist (`known_unregistered_stdlib_test_files`) fails the test with a
  message naming the orphaned file(s) and explaining how to fix it.

**Fatal, not advisory — via an explicit, documented allowlist.** The sibling
todo `specs/todos/2026-08-11-test-stdlib-march-files-not-in-ci.md` found 37 of
94 `test/stdlib/*.march` files wired into no automated runner; re-auditing
today found the same shape (36 files unregistered by the naive grep in that
todo, plus `test_flow.march` — its own registration is present but
`(* commented out *)`, invisible to grep but caught correctly by this guard's
comment-stripping — 37 total, matching that todo's count even as the total
file count grew 94 -> 97). Making the whole check fail on that pre-existing
gap would turn `test_stdlib_march.exe` (and `dune runtest`) permanently red,
which is explicitly against the guidance in that todo ("land the wiring only
once green, or the `runtest` alias goes red for everyone").

Instead of loosening the check to advisory-only (which would also silently
tolerate *new* drift — the exact failure mode this guard exists to catch),
the pre-existing 37 are enumerated in `known_unregistered_stdlib_test_files`
with a comment pointing at the 2026-08-11 todo. Any file NOT in that allowlist
is enforced as a hard failure. The check also flags (non-fatally, via stderr)
allowlist entries that are no longer accurate — already registered, or no
longer on disk — so the list can be trimmed as the other todo's backlog gets
wired up, without needing another sweep to notice.

**Sabotage-probe verified both directions**, per the task brief:
- Fail case: created an unregistered `test/stdlib/test_zzz_scratch_probe.march`
  — `test_stdlib_march.exe -e` exited 1, `[FAIL] registry`, message named
  `test_zzz_scratch_probe.march` exactly and explained the fix.
- Pass case: removed the scratch file — exited 0, `[OK] registry`, `61 tests
  run` (60 pre-existing + the new registry check), unchanged otherwise.

---

## Original todo (retained)

A test `.march` file can silently drop out of the build (nothing checks that
every `test/stdlib/test_*.march` is registered in `test_stdlib_march.ml` — this
is how `test/stdlib/test_json.march` went dead for a while, wired into no
runner). A directory-vs-registry assertion would catch it.

---
