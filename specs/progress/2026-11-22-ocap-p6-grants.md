# ocap phase 6: dependency grants

Plan: specs/plans/2026-11-22-ocap-p6-grants-plan.md. Design:
`specs/2026-11-10-object-capability-design.md` §3, §5, §10, §15, §18, §21, §17 row 6 (grant
syntax, packages, caches and `forge audit` from `specs/2026-11-09-dependency-grants-and-restrict-design.md`
§4 and §6, where the 2026-11-10 design wins on callbacks). Language reference:
`specs/lang/capabilities.md`, "Dependency grants: `grant` in `forge.toml`"; forge side in
`docs/tooling.md` ("Limiting a Dependency") and `docs/capability-audit.md` ("Grants").

A project's `forge.toml` limits each dependency with `grant = [...]`, a scope list in `needs`
syntax. The compiler checks the dependency's reached code against it by kind (and literal
targets under a scoped grant), and `ByGrant(<package>)` frames enforce the rest at run time,
the same in the interpreter, `--jit`, the REPL, compiled code and `--target js`. A build with no
grants compiles to the same IR as before.

## What landed, by task

- **Task 1, the grants file and packages** (`905875ad0`). `March_caps.Dep_grants`
  (`lib/caps/dep_grants.ml`): the grants file (one package per line, four tab-separated fields
  `<package>\t<lib root, absolute>\t<manifest>:<line>\t<scope text>`, `#` comments, `()` for
  `grant = []`), loaded from `--dep-grants FILE` else `MARCH_DEP_GRANTS`; the scope text parsed
  with the real parser as `mod G__ do needs <text> end` (no grammar change); package membership
  by the longest granted root containing a file's real path, memoised; a digest for cache keys.
  With no file nothing is read and every consumer is the identity.
- **Task 2, layers and conflicts** (`9e4acb124`). `Authority.grant_layer(pkg, text)` and
  `Authority.enter_grant(layer)`, which pushes only when a layer with the same limit and text is
  not already anywhere in the authority (intersection is idempotent, so this is exact and keeps
  recursion in and out of a package from growing the list). New codes `dep_grant_exceeded`,
  `dep_grant_scope`, `dep_grant_invalid`, `dep_module_conflict`, each with an `--explain` page.
  Under grants the resolver makes a module defined in two places (app vs dep, dep vs dep, dep vs
  stdlib) and a granted root inside the entry's source directory or another lib directory
  `dep_module_conflict` (Q2); without grants it keeps first-one-wins. `--check-json` now also
  prints the resolver's errors. `run_errors` gained a `-- DEP:` header.
- **Task 3, the static check** (`24a857940`, fix rounds `558cc81c2`, `5e15062f8`,
  `20c6aa4fa`). `Typecheck.check_dep_grants`: per granted package one bound point
  `<pkg>$grant` (`Dep_grant` origin) whose reach is every package function referenced from
  outside the package (calls, value uses, an interface method on a package type keyed by its
  first argument's solved type), plus the package's module-level code; judged by kind against
  the grant (`dep_grant_exceeded`, naming the dependency, the manifest line, the capability and
  the chain). The reach walk resolves imports and aliases itself (the shared `Cap_rows` does not:
  `specs/todos/2026-11-22-cap-rows-miss-import-alias-refs.md`). Under a scoped grant,
  `lib/typecheck/scoped_literal_check.ml` (Q3) reports a literal host, path or name outside the
  scope (`dep_grant_scope`). The checker fills `Dep_grants.proven` with the package functions
  whose reach lies within the grant. The grants digest is a `grants:<hex>` tag in the compile,
  check, depend-mode and interpreter cache keys (absent with no grants).
- **Task 4, native frames** (`8b9ef6550`, fix rounds `693b61af3`, `cc735ef4e`).
  `Auth_rt.grants`, after `frames`, in the native, `--jit`, REPL-JIT and JS pipelines: each
  package function becomes a wrapper `f` (layer cell, `enter_grant`, `f$grant(args)`,
  `cap_restore`) unless the grant is unscoped, the function is proven, and it reaches no actor
  spawn, no call of a function value and no unresolved interface method
  (`reaches_indirect_or_dispatch`). A direct call from a kept package function's own body to a
  kept function of the same package goes to the `$grant` body. Module-level lambdas, and named
  function values in module-level code (rewritten to eta lambdas), get a grant prologue, so a
  value parked at top level runs under its caller ∩ the grant. Actor handlers and `_spawn` are
  wrapped (never proven). One layer fn per package, `<pkg hex-escaped>$grant$auth_layer`.
- **Task 5, the interpreter** (`64ef328d1`, `639cfd907`). `Eval.granted_call` wraps every
  package function closure; a call made while the package's layer is already in force calls
  straight through. Module-level `let`s run under the grant, and values they make carry the
  grant frame. Package impl methods and default methods are framed; actors declared in a package
  spawn under the spawner's authority with the grant entered. `march dap` installs the grants.
- **Task 6, conformance** (`a7a3ffe38`, `e652da644`, with fixes `70f1d4088`, `465195888`,
  `613894054`). `run_cap_conformance` gained a repeatable `-- DEP:` header and
  `CAP_CONFORMANCE_ONLY`; 19 `grant_*` dependency fixtures run in all five modes (the JS target
  skips the two that need tasks; the REPL skips the actor one). The fixtures found three bugs,
  each fixed in its own commit: the REPL could not load `MARCH_LIB_PATH` modules (nor in
  dependency order, nor with their impls); a package function calling `Authority.check` was
  proven and its frame dropped; a library module's `let` naming its own function did not
  compile.
- **Task 7, forge** (`ca36da097`, `8a585a57e`, `f7a16cdc8`). `grant = [...]` on `[deps]`,
  `[dev-deps]`, `[dev-only-deps]` and `[test-deps]` entries, inline or as sections; TOML
  literal strings. forge writes the root project's grants (Q1) as the content-addressed
  `.forge/dep-grants-<md5>` only when a dependency in scope has one, and sets
  `MARCH_DEP_GRANTS` in every prefix that sets `MARCH_LIB_PATH`; an unplaceable grant is an
  error; `forge clean` sweeps old files. `forge audit` prints each grant (or `no grant`) and a
  nested manifest's grant as "not applied"; `forge.caps.lock` records grants, and a widened or
  removed grant is an escalation while a narrowed or added one is not. `march repl FILE` runs
  the grant checks on its entry before loading it.
- **Task 8, benchmarks and docs.** `bench/grant_enter.march`, `bench/grant_enter_static.march`
  and their dependency `bench/grant_enter_dep/`, registered in the bench gate with a new
  per-bench environment (`bench_envs` in `test/test_bench_gate.ml`: the dependency is copied
  beside the bench's temp dir and a grants file written for it; every other bench is compiled
  exactly as before). `scripts/bench-grants.sh` builds the framed, static and ungranted
  variants, checks their frame decisions and output, and prints ns per boundary call.

## Decisions worth knowing

- **A dependency with no grant** is unchanged: limited by its own `needs` and its caller's
  authority, no frame, no cost (design §10). `forge audit` shows `no grant`.
- **Callbacks keep the caller's authority**; values the dependency makes and hands back keep the
  dependency's narrowed one (design §5). Transitive dependencies reached from a granted one run
  under its grant, and under their own too.
- **Packages are decided by real path**, by the longest granted root (decision 5). A file
  spelled under a granted root that resolves outside it is `dep_grant_invalid` (Task 7 fix,
  `Dep_grants.conflicts`), checked by both the spelled and the real location.
- **Only the root manifest grants** (Q1): `specs/todos/2026-11-22-ocap-nested-manifest-grants.md`.
- **`dep_module_conflict` only under grants** (Q2), so builds without grants are unchanged.
- **Literal targets are checked for grants only** (Q3); the helper takes any scoped bound
  (`specs/todos/2026-11-17-ocap-scoped-fn-needs-literal-check.md`).

## Soundness fixes found in review

- Task 3: imports, aliases and `import X; spawn(Worker)` escaped the reach; a bare method name
  counted every package's same-named impl; `proven` used rows that miss import spellings.
- Task 4: module-level named fn values escaped a scoped grant (C1, now eta lambdas with a
  prologue); interpolation's `to_string` dispatch into an app impl from a dropped frame (I2,
  `reaches_indirect_or_dispatch`); layer names were not injective (`a-b` vs `a_b`, I1).
- Task 5: eager default method bodies ran ungranted; actor grants were keyed by spawn name
  rather than by definition.
- Task 6: a package's own `Authority.check` takes its kind at run time and has an empty row, so
  it was "proven"; it is now never proven.
- Task 7: a symlink under a granted root escaped the package (membership is now symlink-proof).
- Final review: an `extern` reached through dispatch the static reach misses ran under a grant
  without `IO.Foreign`, since nothing checked externs at run time (C1: now package-wide
  statically, plus `Authority.foreign_guard` before every extern call under a grant frame,
  compiled and interpreted); an interface default body inherited by an app impl ran ungranted
  and passed `--check` (I2: an impl method belongs to the file its code is written in,
  `Dep_grants.impl_method_file`); `march repl FILE`'s preload check failed open on a crashed
  child (M4: `Dep_grants.preload_check_verdict` fails closed). Filed: the stdlib-initialiser
  slot (M5), the REPL's library interfaces.

## IR identity with no grants

Ruling R5: `scripts/oracle-base.sh ir` cannot report zero for a stdlib change (every `.ll`
embeds the absolute stdlib path, and any new stdlib function shifts the global fresh-name
counter), so each task ran a same-path A/B instead: both compilers frozen
(`MARCH_ORACLE_EXE`), one pinned `MARCH_STDLIB`, private `HOME`, `scripts/ir-oracle.sh` over
the 528-program corpus. Task 2 (the stdlib additions) was identical after fresh-name
normalisation; Task 3 and every later A/B were raw-identical, 528/528. The final-head
`oracle-base.sh ir` run is recorded in the PR.

## Performance

| Measurement | Result |
|---|---|
| `scripts/perf-ab.sh --runs 15` vs `origin/main` (`fib tree_transform binary_trees list_ops list_ops_nested json_stream println_loop`), load about 6.5 on 14 cores | all 7 within noise on cpu and wall; allocation counters identical |
| Framed boundary call (`grant_enter` vs no grants file, 11 interleaved runs, `--opt 2`) | about 16 ns per call (12 ns on minima), budget 50 ns |
| Frame dropped (`grant_enter_static`) | about 2 ns per call on medians, 1 ns on minima: noise |
| Calls inside the package | the 1e9 internal calls cost the same in all three builds |

`--check` wall time over the 35 `examples/*.march` (each run in a fresh directory with an empty
CAS, warm stdlib cache, `MARCH_LIB_PATH` set in both arms, 3 interleaved rounds, load about 6):
87.80 s without a grants file and 88.52 s with one (a scoped grant on a package the examples
do not use), medians; about 20 ms (0.8%) per file, the membership `realpath`s and module claims.
Exit codes were identical in every pair.

Under an unscoped grant a proven package function that calls `println` keeps its native frame:
the prelude's `println` is generic and calls `show(x)`, an unresolved interface method before
mono (`specs/todos/2026-11-23-needs-frames-interface-call-keep-rule.md`).

## Follow-ups filed

`2026-11-22-ocap-nested-manifest-grants`, `2026-11-22-grant-app-impl-callback-authority`,
`2026-11-22-grant-untagged-package-code`, `2026-11-22-cap-rows-miss-import-alias-refs`,
`2026-11-22-cap-ceiling-same-type-name-impl-overattribution`, `2026-11-23-dap-launch-dep-grants`,
`2026-11-23-interface-eager-default-sigbus`, `2026-11-23-repl-load-not-grant-checked`,
`2026-11-23-tui-reload-untested`, `2026-11-23-forge-audit-grants-compared-as-text`,
`2026-11-23-grant-url-entry-points-hardcoded`, `2026-11-23-resolver-errors-ignored-check-cmd-lsp`,
`2026-11-23-grant-dispatch-type-first-arg-only`, `2026-11-23-needs-frames-interface-call-keep-rule`;
appended to `2026-11-17-ocap-framed-mutual-tail-recursion` (kept grant frames are not tail
positions; `grant_callback_reentry` at 1,000 deep, target 10,000; the redundant frames) and
`2026-11-17-ocap-scoped-fn-needs-literal-check` (the helper exists, on for grants only).
