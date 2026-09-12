# CI and tooling fixes: six open todos, re-grounded against today's tree

**Date:** 2026-09-11
**Status:** proposed; nothing here has landed
**Method:** every claim below was checked on 2026-09-11 by opening the cited
file or running a read-only grep/wc. Where a todo describes state that has since
changed, the section says so and gives the current numbers.

**Todos this covers:**

| Todo | Filed | Verdict today |
|---|---|---|
| [`2026-09-08-ci-check-generated-stdlib-html-in-sync`](todos/2026-09-08-ci-check-generated-stdlib-html-in-sync.md) | 09-08 | two-thirds already built (bot + nightly diff); one real gap left |
| [`2026-08-03-pagefind-index-conflicts-every-parallel-pr`](todos/2026-08-03-pagefind-index-conflicts-every-parallel-pr.md) | 08-03 | staleness half closed; the conflict half is caused by our own PR gate |
| [`2026-07-24-quarantined-tests-coverage-that-is-currently-dark-inventory-2026`](todos/2026-07-24-quarantined-tests-coverage-that-is-currently-dark-inventory-2026.md) | 07-24 | inventory accurate (2 dark); the nightly wiring around it has rotted |
| [`2026-08-05-runtime-source-list-duplication`](todos/2026-08-05-runtime-source-list-duplication.md) | 08-05 | CAS site solved; five list sites remain, and the sets legitimately differ |
| [`2026-08-17-forge-test-silent-skip-on-compile-failure`](todos/2026-08-17-forge-test-silent-skip-on-compile-failure.md) | 08-17 | reproduced today; parse-error-shaped, type errors already fail |
| [`2026-08-10-march-lean-oracle-out-of-sync`](todos/2026-08-10-march-lean-oracle-out-of-sync.md) | 08-10 | invisible to this repo's CI; corpus has grown 277 -> 303 |

---

## 0. What is already true in the tree (verify before building)

- **Stdlib HTML self-heals on main.** `.github/workflows/gen-stdlib-docs.yml`
  triggers on pushes to `main` touching `stdlib/**` (22-28), runs
  `scripts/gen-stdlib-docs.sh`, regenerates `docs/pagefind/` in the same run
  (74-75), commits both (77-92). `git log --grep='regenerate API docs'
  origin/main`: 20 bot commits 2026-08-10..09-09; the last eight runs all
  `success`, ~3 min each.
- **A nightly regenerate-and-diff already exists.** `nightly.yml:68`
  `stdlib-docs-smoke` (added `d0649d6d`, 2026-08-12) regenerates and runs
  `git diff --exit-code --stat docs/docs/stdlib` (83-89). Green on the 09-09,
  09-10 and 09-11 nightlies.
- **The generator is byte-deterministic on unchanged input.** Bot commits
  `6622c090` and `1738399a` changed **zero** files under `docs/docs/stdlib/`
  (only pagefind); `a9706580` changed 119 because it added real content
  (`Actor.is_draining/list/stop`). Every page carries the full sidebar, so one
  new function touches all 117 module pages.
- **Pagefind staleness is closed.** `docs/pagefind/.source-digest` exists;
  `scripts/gen-docs-search-index.sh --check` compares it to a digest over
  `git ls-files docs` `*.md|*.html` minus `docs/pagefind/` (74-85, 97-113);
  `ci.yml:64-65` runs `--check` in `doc-lint`; `sync-docs-search-index.yml`
  regenerates and pushes on pushes to main touching `docs/**` minus the index,
  with a 3-attempt rebase loop (104-128). The index is 225 tracked files.
- **Production is still legacy Jekyll over `main:/docs`.** `docs/CNAME` =
  `march-lang.org`; `deploy-pages.yml` publishes `_site` to the *external*
  `march-language/march-language.github.io` (`external_repository:`), so its
  Pagefind step never reaches production. `gen-stdlib-docs.sh:10-17` states
  this correctly now; the todo addendum's complaint about that header is stale,
  while `gen-docs-search-index.sh:16-17` still accuses it.
- **Two tests are dark, not five.** Aliases defined: `test/dune:2146
  task_burst_await_quarantined` (that test is *also* on `runtest`; alias kept
  for soaking, 2131-2144), `:2638 signal_term_suppress_quarantined`, `:5656
  node_discovery_quarantined`. `forge/test/dune` defines none (49-62 records
  the 08-08 revival). `nightly.yml:40-45` still loops over six names.
- **The CAS runtime digest is no longer a hand list.** `lib/cas/cas.ml:188-194`
  `Sys.readdir`s the runtime dir. Remaining hand lists: `bin/main.ml:2802-2843`,
  `bin/toolchain.ml:768-800` (cross-compile; the todo's "second list at ~3044"
  moved here), `test/test_helpers.ml:683-689`, `test/dune` (147 rules name
  `march_runtime.c`; 153 lines name `march_extras.c`, 150 `march_ctx_escape.c`),
  `demo/dune` (8 rules). `runtime/*.c` is 25 files.
- **`forge test` builds one entry.** `forge/lib/cmd_test.ml:186 List.hd
  test_files`; siblings arrive via `MARCH_LIB_PATH` (163-192).
  `lib/resolver/resolver.ml:480-486`: a discovered file that fails to *parse*
  prints `[lib] <path>:<line>: parse error` and is dropped. Type errors in a
  kept module are fatal (`bin/main.ml:1935-1938`).
- **No workflow mentions march-lean** (`grep -rn march-lean .github/` empty).
  In-tree mentions: `test/test_ty_json.ml:3`, `test/test_eval.ml:2932`, specs.
  Corpus: 146 accept + 157 reject = 303 fixtures, top `t185`.

---

## 1. Generated stdlib HTML in sync with `stdlib/*.march`

### The gap

The todo asks for a CI job that fails when a stdlib function is added without
regenerating `docs/docs/stdlib/`. Two of its three sketched pieces exist (§0:
bot on main, nightly diff). What neither can see is a generator that *runs*
but *emits less than the source declares*: both compare generator output to
generator output. The `fold_f32` / `mem_peak_bytes` omission is that shape.

### Current state, grounded

- Module name is not the filename: `stdlib/audio.march:19 mod Js.Audio` ->
  `Js.Audio.html`; `forge_nb.march:6 mod Forge` -> `Forge.html`;
  `rrb_vec.march:29 mod RRB` -> `RRB.html`. 117 `.march`; 117 module pages +
  `index.html` + `search-index.json` = the bot's 119-file commits. A symbol
  check must key off the `mod` declaration.
- Anchors are stable and greppable: `id="fn-<name>"`, `id="type-<Name>"`
  (seen in `a9706580`'s `Actor.html` diff).
- `scripts/check-docs.sh:98` counts `stdlib/*.march` for Check B only; nothing
  reads a generated page back against its source.
- A red `gen-stdlib-docs.yml` run on main is silent until 04:00 UTC, when the
  nightly's `::error::... dispatch the 'Regenerate Stdlib Docs' workflow` fires.

### Candidate fixes

**A. PR-time full regeneration + diff (the todo's literal acceptance).**
Rejected: every stdlib PR would commit 117 sidebar-bearing pages, so two
concurrent stdlib PRs conflict across all of them (§2's disease, relocated);
it makes the bot pointless; ~3-4 min plus a `march_doc` clone per PR.

**B. Source-vs-output symbol-set check (chosen).** `Check D` in
`scripts/check-docs.sh`: per `stdlib/<f>.march`, read the top-level `mod Name`,
collect public `fn`/`type` names (skip `pfn`), assert
`docs/docs/stdlib/<Name>.html` exists and contains each anchor. Run it in two
places: last step of `gen-stdlib-docs.yml` **before** `git push` (the bot
refuses to publish an incomplete page set), and in nightly `stdlib-docs-smoke`.
**Not** in PR `doc-lint`: on a stdlib PR it is red until the bot runs, which is
A again. Catches the omission half; stale prose stays with the nightly diff.
Also: give `gen-stdlib-docs.yml` an `if: failure()` step summary so a red bot
run is visible on the commit that caused it.

### Test plan / acceptance

- RED 1: delete one `<div class="item" id="fn-...">` from a generated page;
  `check-docs.sh` exits 1 naming module and symbol.
- RED 2: add `fn zzz_probe() do 0 end` to `stdlib/system.march` without
  regenerating; fails on `System.html`/`zzz_probe`.
- GREEN: current tree passes. Before trusting the extractor, confirm
  `grep -c '^mod ' stdlib/*.march` is 1 everywhere (convention, not verified).
- Amended acceptance: "the bot cannot push a page set that omits a public
  symbol; an omission is red within one nightly".

**Effort:** S. **Risk:** low; possible false positives on symbols `march_doc`
anchors differently (operators). Measure on the 117 pages first.

---

## 2. Pagefind index conflicts between parallel PRs

### The gap

Two PRs that each regenerate `docs/pagefind/` produce disjoint hash-named
files plus a textual conflict in `pagefind-entry.json`. Staleness is solved
(§0); the conflicts remain because `ci.yml:64-65` makes `--check` a **PR
gate**, so any PR editing `docs/**/*.md` must regenerate to go green. Since
2026-08-16, 23 human commits on `origin/main` touched `docs/pagefind/` versus
18 bot commits: the gate is what recruits humans into writing a bot-owned file.

### Current state, grounded

- The commit-it constraint holds (§0; `gen-docs-search-index.sh:5-17`).
- The index is not reproducible (61-64), so a byte diff can never be the
  merge resolution.
- Both post-merge writers work: `sync-docs-search-index.yml` (fast `--check`
  67-74; regenerate/commit/push with retry 104-128; latest `bc6aa266` 09-10)
  and `gen-stdlib-docs.yml` (74-75).
- No `.gitattributes` at the root; `CONTRIBUTING.md`/`README.md` do not
  mention `pagefind`.

### Candidate fixes (the three asked for, then the chosen one)

**(a) Generate in CI/deploy, stop committing.** Blocked while production is
`main:/docs` under legacy Jekyll with no post-build hook. Available only if
the Pages source moves to an Actions deployment: a site-serving decision.

**(b) `.gitattributes merge=ours` / custom driver.** The todo's 09-08 addendum
measured `merge=ours` still conflicting and a custom driver working only when
configured locally. GitHub's server-side merge reads no local driver, and this
repo merges via the PR button (every recent main commit is `... (#NNN)`).

**(c) Post-merge regenerate-and-push bot.** Exists; closed staleness; cannot
stop two PRs from both carrying an index.

**(d) Make the bots the only writers (chosen).**
1. `ci.yml doc-lint`: run `--check` only when `github.event_name !=
   'pull_request'`. On PRs run an *inverse* gate instead: `git diff --name-only
   origin/$BASE...HEAD -- docs/pagefind | grep -q .` fails with "the search
   index is bot-owned; drop `docs/pagefind/` from this PR
   (`git checkout origin/main -- docs/pagefind`)". Two PRs can then never both
   touch the directory: the conflict class is gone by construction.
2. `sync-docs-search-index.yml` becomes the single enforcement point; its
   3-attempt failure is the only red for a stale index. The push-to-main
   `ci.yml` run may be stale for ~1-3 min until the bot lands: keep that step
   `continue-on-error: true` with a `::warning::`.
3. Header hygiene: drop `gen-docs-search-index.sh:16-17`'s now-false claim;
   add the two-line resolution recipe to the header and `CONTRIBUTING.md`.

Cost: live search lags a docs merge by one bot run (already true for
merge-interaction staleness); contributors lose an ability they did not need.

### Test plan / acceptance

- RED: a branch modifying any file under `docs/pagefind/` fails `doc-lint`
  with the inverse-gate message; restoring the directory passes even though
  its `.md` edit leaves `--check` stale.
- GREEN: merge two docs-only PRs back-to-back; one bot sync each; `--check`
  green on main afterwards (the path already observed 18 times since 08-16).
- `git log --author='Gilliam' --since=<land date> -- docs/pagefind` stays empty.

**Effort:** S. **Risk:** low; PR `doc-lint` no longer proves index freshness,
which it never could across merges (`sync-docs-search-index.yml:13-18`).

---

## 3. Quarantined tests: what is dark, and the wiring that rotted

### The gap

The inventory is correct: two tests dark (`signal_term_suppress`,
`node_discovery`), both on the same pre-write torn-output race. What rotted is
everything meant to *act* on it: the nightly loop names three aliases that no
longer exist, so its "all passed, un-quarantine" signal can never fire.

### Current state, grounded

- Defined: `task_burst_await_quarantined` (2146; test also on `runtest`),
  `signal_term_suppress_quarantined` (2638), `node_discovery_quarantined`
  (5656). Removed 2026-08-08 (`edf7274d`): `node_call_loopback_quarantined`,
  `rpc_auto_enroll_quarantined`, `forge/test/build_check_quarantined`.
- `nightly.yml:40-45` iterates six names. `dune build @<undefined alias>` is a
  hard error, so three iterations always land in `failed=`, the `::notice::All
  quarantined tests passed` branch is unreachable, and the job concludes
  `success` regardless (`continue-on-error: true`; failures only aggregated
  into a string; the 09-11 nightly shows `quarantined: success`).
- `test/dune:2142, 2631, 2636` point at `specs/todos.md`, which does not exist.
  `check-docs.sh` lints docs, not `dune` comments, so these rot freely.
- The race itself is documented at `test/dune:2612-2636` and `5639-5654`.

### Candidate fixes

**A. Fix the three names by hand.** One line; rotted once already within two
weeks of 07-24 and will again.

**B. Derive the list and machine-check the inventory (chosen).**
1. `nightly.yml`: replace the literal list with `grep -ho '(alias
   [a-z_]*_quarantined)' test/dune forge/test/dune`, so the loop is exactly
   the set of defined quarantine aliases.
2. Rename `task_burst_await_quarantined` -> `task_burst_await_soak` (it is a
   soak convenience for a test on `runtest`), so derived set = dark set.
3. `Check E` in `check-docs.sh`: `*_quarantined` aliases in the dune files
   must equal the non-struck rows of the inventory todo, and each quarantine
   comment must point at an existing file (fixing the three `specs/todos.md`
   pointers to the inventory's real path).
4. A real signal: per-alias pass/fail to `$GITHUB_STEP_SUMMARY`; when all
   pass, `::notice::` plus open-or-update one tracking issue via `gh issue`
   (idempotent by title).

### Test plan / acceptance

- RED 1: add `(rule (alias zz_probe_quarantined) (action (system "exit 1")))`
  to `test/dune`; a `workflow_dispatch` nightly reports `zz_probe_quarantined:
  still failing`, and `Check E` fails (no inventory row).
- RED 2: strike a live inventory row without deleting the alias; `Check E` fails.
- GREEN: after the rename, `Check E` passes with exactly two aliases; the
  nightly summary lists exactly two.

**Effort:** S. **Risk:** low. Fixing the torn-output race (the only thing that
un-quarantines the two) is L and out of scope.

---

## 4. Runtime C source lists

### The gap

Adding a runtime `.c` file still means editing several hand lists; a miss
fails at link time or not at all. The todo counted six sites; today it is
five, and (unrecorded by the todo) the sets **legitimately differ per
consumer**, which rules out the naive "one glob everywhere".

### Current state, grounded

| Site | Shape | Count |
|---|---|---|
| `bin/main.ml:2802-2843` | `Filename.concat runtime_dir "<f>"` + `opt_file2` guards; http family conditional on `march_http.c`; dispatch/reload/blake3/cap_lattice/tweetnacl skipped under `--compile-so` | 23 `Filename.concat runtime_dir "` |
| `bin/toolchain.ml:768-800` | the same list, copied for cross-compile | 22 |
| `test/test_helpers.ml:683-689` | `extra_src_list`, 13 names + `march_runtime.c`, for the REPL/JIT `.so` | 1 list |
| `test/dune` | per-rule `(deps ...)` and `(run %{cc} ...)`, list spelled twice | 147 rules |
| `demo/dune` | same | 8 rules |
| `lib/cas/cas.ml:188-194` | **solved**: `Sys.readdir` over `.c`/`.h` | 0 |

Differences a manifest must encode:
- `march_gc.c`, `march_heap.c`, `march_message.c` appear in **zero** OCaml
  sources under `bin/ lib/ forge/ lsp/` but in 149 `test/dune` lines and all 8
  `demo/dune` rules: the not-yet-default per-process arena
  (`runtime/march_runtime.c:522-525`), linked only by C unit-test harnesses. No
  `.c` `#include`s another `.c` (grep empty): a real link-set difference.
- `march_runtime_wasm.c` is a separate wasm32 runtime (its header); a bare
  `(glob_files ../runtime/*.c)` would link it into every native test.
- Every `test/dune` rule already globs headers (`(glob_files ../runtime/*.h)`,
  e.g. 321, 419, 488); only the `.c` set is enumerated.

### Candidate fixes

**A. Generate every list from one manifest** (`runtime/sources.list` ->
emitter -> `Runtime_sources` OCaml module + generated dune include + freshness
rule, the `cap_lattice`/`emit_c_table` pattern). Removes the duplication.
Cost: 155 dune rules whose *action* lines also enumerate files (a named dep
`%{rt}` would carry the whole glob, wasm included), plus threading a generated
module through two drivers. M-L, and the roles above must be designed first.

**B. `(glob_files ../runtime/*.c)` in test/demo rules.** Unsound as-is (wasm,
arena). Would need `runtime/wasm/` and `runtime/arena/` subdirectories, which
moves files the driver locates by name (`bin/main.ml:2798-2799`) and re-keys
the CAS digest.

**C. Role-tagged manifest policed by a check (chosen; the todo's option 3,
upgraded).** `runtime/sources.list`: one file per line under `# role: core |
http | hcr | jit | unit-test-only | wasm`. `scripts/check-runtime-sources.sh`
in `ci.yml doc-lint` (seconds):
1. every `runtime/*.c` is in the manifest exactly once;
2. `bin/main.ml` and `bin/toolchain.ml` each name every `core`/`http`/`hcr`
   file and nothing tagged `unit-test-only`/`wasm`;
3. `test_helpers.ml` `extra_src_list` ⊇ `jit`;
4. every `test/dune`/`demo/dune` rule block naming `march_runtime.c` names
   every `core` file in both `(deps)` and action (awk over `(rule` blocks;
   report the `(targets ...)` on failure).
"undefined symbol `_march_ctx_escape`" becomes "rule
`test_broadcast_migrate_leak_runner` omits core file `march_ctx_escape.c`".
Generation (A) is a follow-up once roles have been stable.

### Test plan / acceptance

- RED 1: `touch runtime/zz_probe.c`: check 1 fails.
- RED 2: remove `march_ctx_escape.c` from the `core` block: check 2 fails on
  both drivers.
- RED 3: delete `../runtime/march_ctx_escape.c` from one `test/dune` rule's
  `(deps)`: check 4 names that rule's target.
- GREEN: current tree, 25 files classified; the count of rules checked
  (147 + 8) is printed so a broken awk is visible.

**Effort:** M (the awk over 626 `(rule` stanzas needs care). **Risk:** low;
read-only, the build is untouched.

---

## 5. `forge test` silently drops a test module that fails to parse

### The gap

`forge test` compiles one entry and relies on auto-discovery for the rest. A
sibling test file that fails to **parse** is dropped with a stderr line, the
compile exits 0, and the suite reports fewer tests with `0 failures`.
Reproduced today with the built compiler; type errors do **not** do this.

### Current state, grounded

- `cmd_test.ml:186 let entry = List.hd test_files`; `60-62` runs `march
  --compile --test ... <entry>` with `MARCH_LIB_PATH=<libs>:<test/>` (169-183);
  `63-65` fails only on non-zero compiler exit.
- `resolver.ml:480-486`: phase-1 discovery parses every file; `Error msg ->
  Printf.eprintf "[lib] %s\n%!" msg; None` — dropped, not added to `errors`.
  The pruning rationale (494-506) is about *type* errors in unreachable
  modules; an unparsable file has no module name to be reachable by.
- Parsed test siblings are kept unconditionally (`has_global_effect_decl`,
  110-119, includes `DDescribe`/`DTest`/`DSetup*`; 526-536 describes the
  `forge test` first-file-as-entry convention) and their type errors are fatal
  (`bin/main.ml:1935-1938`).
- Repro (scratchpad; `_build/default/bin/main.exe` built 2026-09-10;
  `resolver.ml`/`cmd_test.ml` last changed 07-29/07-30, so current):
  `MARCH_LIB_PATH=<d>/test march --compile --test -o out test/a_test.march`,
  sibling `b_test.march` varied:

  | sibling | build rc | stderr | run |
  |---|---|---|---|
  | valid | 0 | — | `Finished: 2 tests, 0 failures` |
  | missing `)` | **0** | `[lib] .../b_test.march:5: parse error` | `Finished: 1 test, 0 failures` |
  | `2 + "x"` | 1 | `expected Int but got String` | not built |

### Candidate fixes

**A. Resolver-wide: discovered-file parse errors fatal.** One line at
resolver.ml:486, but every `MARCH_LIB_PATH` consumer (LSP `extra_lib_paths`,
`forge build`, plain `--compile`) then fails on any unparsable scratch file on
the path. The tolerance was deliberate (494-506).

**B. forge-side pre-flight**: `march --check` per discovered test file before
compiling. N spawns and N full typechecks (no parse-only mode); redoes work.

**C. Test-mode strictness (chosen).** `?(strict_parse=false)` on
`Resolver.resolve_imports`; when true, a phase-1 parse failure is appended to
`errors` with the parser's span instead of `eprintf`+`None`. `bin/main.ml`
passes `~strict_parse:!do_test`: a `--test` build has no reason to tolerate an
unparsable sibling; LSP and non-test paths keep today's behaviour. `forge
test` needs no change; it already fails on non-zero exit.

### Test plan / acceptance

- RED (pre-fix): the parse-error dir builds rc=0 with one test; post-fix it
  exits 1 with a positioned diagnostic and no binary.
- Controls unchanged: valid -> 2 tests; type error -> rc 1.
- Fixtures: `test/imports/` gains a two-file `--test` case with a broken
  sibling (mirrors `entry_imports_ill_typed.march`); `forge/test/test_build_check.ml`
  gains a hermetic `forge test` case via the `MARCH_TEST_BIN` pattern
  (`forge/test/dune:49-62`) asserting non-zero exit and the diagnostic text.
- `scripts/run-tests.sh compiler` and the forge suite green. Changelog: "a
  `forge test` suite with an unparsable test file now fails instead of running
  fewer tests".

**Effort:** S-M. **Risk:** low; scoped to `--test`.

---

## 6. march-lean differential oracle out of sync

### The gap

`march-language/march-lean` re-checks this repo's `specs/lang/types` corpus
with an independent Lean implementation of the error-level checks. Adding an
ERROR-level check here is a two-repo change, and nothing here notices when the
second half is skipped. The oracle has found real bugs before (todo: PR #136,
issue #82), so drift is lost bug-finding.

### Current state, grounded

- Nothing in `.github/` references march-lean, `repository_dispatch`, or `gh
  workflow run`. Cross-repo contracts live only in test comments:
  `test/test_ty_json.ml:3` (JSON shape), `test/test_eval.ml:2932-2938`
  (property tests labelled by Lean theorem).
- Corpus: 146 + 157 = **303** fixtures, top **`t185`**; the todo's 277/`t165`
  is ~26 behind. Grant fixtures: 3 reject, 4 accept.
  `reject/t166_grant_narrow_violated_by_helper.march` exists; `t170` is now
  `t170_native_u8_arr_not_sendable.march`, **not** the
  `t170_fn_grant_violated_by_helper` the todo names. The Lean side must
  re-baseline from the corpus on disk, not from the todo's list.
- Lean-side facts (no grant check in `CapCheck.lean`, ledgers ending ~t140,
  unpushed branch) cannot be verified from here and are not restated as
  current; `specs/2026-08-04-provable-sandbox-design.md:368, 448` carry the
  same 08-10 snapshot. No Lean toolchain is available locally.

### Candidate fixes

**A. Run the harness in this repo's nightly.** Clone march-lean, install
`elan`/`lake`, build (~9.6k lines, no Mathlib), run
`scripts/conformance-harness.sh --corpus-dir specs/lang/types`,
`continue-on-error`. Puts the result where march contributors look, but adds a
second toolchain and cache to a nine-job nightly, and a red is nobody's job.

**B. `repository_dispatch` to march-lean (chosen, with C).** A ~15-line
workflow, `on: push: branches: [main] paths: [specs/lang/types/**,
lib/typecheck/**, lib/caps/**]`, POSTing `repository_dispatch` with
`{march_sha}` using a PAT secret (the org already holds one for
`deploy-pages.yml`, `PAGES_DEPLOY_TOKEN`). The Lean build runs where its cache
lives; visible in march-lean's Actions and, via a badge in the corpus README,
here.

**C. Write the two-repo rule down (chosen, with B).** One paragraph where new
`tNNN` fixtures are documented: "an ERROR-level check or new reject fixture is
a change to two repos; after merging, confirm the dispatched march-lean run is
green or file the ledger skip there". Free, and independent of any secret.

Lean-side work (grant check in `CapCheck.lean`, ledger refresh against 303
fixtures, a *ledgered* skip for the per-function stage-C check) belongs to
march-lean and is not scheduled here.

### Test plan / acceptance

- RED for B: `workflow_dispatch` with a fake SHA from a branch; confirm
  march-lean receives a `repository_dispatch` run carrying it. Then remove the
  secret in a fork and confirm the step fails loudly (`curl --fail`) rather
  than skipping.
- GREEN: the next merge touching `specs/lang/types/**` produces a march-lean
  run within minutes; its verdict on `t166`, the new `t170`, `t171..t185`
  replaces the todo's "predicted, NOT verified" line.
- For C: put the note under a path `check-docs.sh` lints (`docs/`,
  `specs/features/`), or add a deliberate `doc-lint:ignore-file`.

**Effort:** S here (M-L in march-lean). **Risk:** the secret; and a dispatch
nobody acts on leaves the oracle as dark as today, which is why C is not
optional.
