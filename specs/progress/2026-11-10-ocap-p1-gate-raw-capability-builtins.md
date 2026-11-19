# Raw capability builtins are still callable from user code

Logged 2026-11-10 by ocap phase 1 (specs/plans/2026-11-10-ocap-p1-result-plan.md,
Task 5, deferred). Phase 1 put every check in the stdlib entry points
(`Authority.check`), so a program that calls a raw builtin directly
(`unix_time_ms(())`, `task_spawn(...)`, `file_read(p)`, `process_env(k)`)
bypasses the check and gets the old, never-refused type.

Today that bypasses nothing: no limit refuses at run time until ocap phase 4
(only the test hook `MARCH_TEST_REFUSE` did; ocap p4 Task 7 removed it). It becomes a hole the moment
phase 4 lands, so the gate belongs with phase 4 (or phase 2 for the handle
builtins it re-types).

What to do: add every `Checked { gated = true }` row of
`lib/caps/cap_ops.ml` (`Cap_ops.gated`) to the stdlib-only table
(`Typecheck_env.stdlib_only`), except the two the stdlib shadows (`println`,
`random_bytes`: a user call already reaches the checked stdlib function); give
the `stdlib_internal` diagnostic a machine-applicable rename to the row's first
entry point where the arity matches (`file_read` -> `File.read`,
`process_env` -> `Process.env`, `print` -> `IO.write`, `vault_new` ->
`Vault.new`, ...), none for unit-argument builtins (`unix_time(())`) or a
different shape (`task_spawn` -> `Task.async`, `print_stderr` adds no newline
where `IO.warn` does); then migrate the corpus (about 300 direct calls in
test/, bench/, examples/, most `task_spawn`, `unix_time`, `unix_time_ms`),
including the builtin-level tests in test/test_codegen.ml that call them on
purpose (they move behind a stdlib-spanned fixture). Check that the literal
path-scope check (`path_arg_builtins`, lib/typecheck/typecheck_caps.ml) still
fires on the `File.*` entry points after the rename.

## Done (2026-11-17, ocap phase 4 Task 8)

Every `Cap_ops.gated` row except `Cap_ops.shadowed_by_stdlib` (`println`,
`random_bytes`) is now in `Typecheck_env.stdlib_only`, its hint built from the
row's entry points (`Cap_ops.stdlib_only_hint`: "use `File.read`", "use
`Process.env` (or `System.env`)"). 44 builtins: the console writes and reads,
the file and directory conveniences, `dns_resolve`, the `process_*` operations,
the clock and UUID reads, `stdlib_random_bytes`, the signal operations, the four
task spawns and the five Vault opens.

- **Fix.** The `stdlib_internal` error on a call carries the call rewritten to
  the row's first entry point, wrapped so it keeps its type
  (`Typecheck.stdlib_only_fix`): `file_read(p)` -> `Authority.must(File.read(p))`,
  `print(s)` -> `Authority.ignore(IO.write(s))`. Offered only when the entry point
  is a drop-in: same parameters, and its `Result(T, CapError)` payload is the
  builtin's own result type (checked by a trial unification, so `dns_resolve`,
  whose entry point has a different error type, gets none). None for a builtin
  called with `()` (`unix_time(())`) or named as a value (`process_cwd`).
  `Cap_ops.rename_differs` lists the rows whose types line up but whose meaning
  does not: `print_stderr` (`IO.warn` adds a newline) and the four task spawns.
  A bare rename was tried first and backed out: `match File.read(p) do Ok(_) ->
  .. Err(e) -> .. end` still typechecks, so the rename silently moved a file
  error into the `Ok` arm (test/native/qualified_type_name_render caught it).
- **New entry points.** `task_spawn_steal` and `task_spawn_with_cancel` had none,
  so their rows named `Task.async`, which does neither. `Task.async_steal(pool, f)`
  and `Task.async_cancellable(f, token)` check `IO.Spawn` and spawn a zero-argument
  `f`, like `Task.async`.
- **Control wiring.** The compiler-generated control plane (`<control>`) reads the
  clock and spawns tasks with the raw builtins; the builtin gate now uses
  `span_may_name_internal`, as the `@[stdlib_internal]` gate already did.
- **Closures.** The per-function capability closures charge a call of a gated
  row's entry point as they charge the builtin (`entry_cap_table`,
  `Typecheck_caps.entry_caps_of_expr`; closure tables only, the diagnostic body
  scan is unchanged). Without it a function that writes through `File.write`
  had an empty closure (signature caps aside), so `march caps`, the hot-reload
  manifest's per-function `caps=` and the `--cap-sandbox` profile under-reported
  it: a module-level `let` writing through `File.write` got a sandbox profile
  with no `file-write*`.
- **Path scopes.** `path_arg_entries` maps each path builtin's entry points
  (`File.read`, `File.open`, `Csv.read_all`, `Dir.list`, ...) to it, so the literal
  path-scope check fires on `File.read("/etc/hosts")` under
  `needs IO.FileRead("/srv/data")` (it fired only on the raw builtin before).
- **Corpus.** 623 direct calls in 202 `.march` files (test/, bench/, examples/,
  specs/lang/, docs/assets/, forge/test/; the task report's count, which an
  earlier draft of this entry gave as 678 in 229; fix round 2 then migrated
  the callers CI found outside these): `forge fix` applied the renames and
  the `cap_result_unhandled` wraps (this ran with the bare-rename fix, so every
  site whose result was matched was re-checked and wrapped by hand); a script
  renamed the forms with no fix
  (`unix_time_ms(())`/`unix_time(())` to `System.now_ms()`/`System.now()`,
  `task_spawn(fn _ ->` to `Task.async(fn () ->`); the rest by hand. Programs
  built `--stdlib-source` keep their raw calls, and two builtin-level parity
  fixtures (`uuid_v7_dns_parity`, `process_handle_leak_probe`) now are. Four
  reject fixtures that pin a call-level rule for a direct builtin call
  (`cap_needs_10`, `deterministic_violation_1`, `pure_violation_1`,
  `role_grant_exceeded_1` and their spec twins) keep the raw call and also draw
  `stdlib_internal`. `bench/clock_loop.march` reads the clock through
  `System.now_ms()`.

Tests: `test_stdlib_only` `raw_capability_builtins_gated` (pinned against
`Cap_ops.gated` itself); `test/errors/stdlib_internal_4` (the rename fix,
verified machine-applicable).

Follow-ups filed: specs/todos/2026-11-17-ocap-raw-random-bytes-ungated.md
(since done: specs/progress/2026-11-17-ocap-raw-random-bytes-ungated.md, so
`println` is the one row left out),
specs/todos/2026-11-17-ocap-merged-needs-report-at-entry-points.md,
specs/todos/2026-11-17-ocap-tir-ceiling-misses-function-values.md.
