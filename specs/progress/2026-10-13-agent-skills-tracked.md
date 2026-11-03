# DONE 2026-10-13: every agent skill is in the repo, indexed in CLAUDE.md, and current

Six skills used on this project lived only in one machine's `~/.claude/commands/`:
`compiler-builtin`, `compiler-rc`, `march-test`, `march-docs`, `forge-search` and `forge-add`.
Another contributor or a fresh checkout did not get them, and nothing in the repo named them.
`CLAUDE.md` mentioned only `march-debug` and `steward`. The tracked `/build-test` command was a
Rust template (`cargo build && cargo test`).

## What changed

- **Tracked:** the six are now `.claude/skills/<name>/SKILL.md`, in the repo's skill format
  (`name` + `description` frontmatter).
- **Indexed:** `CLAUDE.md` has an "Agent skills" table naming every skill and command and when
  to use it. Its project layout no longer lists the deleted `rc_types`; `kind` holds those
  predicates.
- **Guarded:** `scripts/check-docs.sh` now lints the six new skills and `/build-test` for dead
  source pointers, as it already did `march-lang`, `march-debug` and `steward`. A dead pointer
  added to `compiler-rc` turns it red, as checked.

## Brought up to date, each claim checked against the code or the tool's `--help`

- **`compiler-builtin`** was a four-edit, two-file recipe from April. Rewritten from the
  `observe_query` builtin (`39918c418`) and the code as it is now:
  - the typechecker's `builtin_bindings` and `builtin_cap_table`, and the stdlib-only gate;
  - `eval_builtins`;
  - the runtime and `runtime/sources.list`;
  - the `llvm_builtins` row plus its separate `PDeclare`;
  - `Builtin_table` and `Builtin_name`, with the exhaustive matches in `llvm_emit` and
    `alloc_contract`;
  - Defun's `builtin_names`, `extern_borrow_table`, `impure_builtins` and `cap_symbols`;
  - the JS backend;
  - the tests that move with it: the preamble goldens, `test_builtin_compiled_lowering`'s total
    accounting, `test_stdlib_only` and the refinement audit baseline.
- **`compiler-rc`**:
  - **Module map:** `insert_rc_expr` is in `perceus_core.ml`; `needs_rc` and `borrowable` are in
    `Kind`.
  - **New "ask the instrumentation" section:** `scripts/triage.sh`, `--verify-tir`'s RC-balance
    check, `--rc-trace` with `gc-trace-report.py`, `march query fn --at`, `--bisect-pass`,
    `--reduce` and `MARCH_DUMP_TXT`.
  - **Phase dumps:** `forge compile` always dumps phases.
  - **Bug table:** rows for the bugs found since July.
  - **Staging and the cache:** the staged runtime and the `artifacts-v2` cache.
  - **Safety:** the lldb-attach warning.
- **`march-test`:** the property config uses the current record syntax (`num_runs: 1000`). It
  also covers how the compiler repo runs `test/stdlib/*.march`, and that a new file must be
  registered in `test/test_stdlib_march.ml`.
- **`march-docs`:** `forge doc` (not `forge march_doc.doc`), and the doctest forms the extractor
  supports (`...>` continuation, `** panic:`, `let` chaining).
- **`forge-search`:** `--plain` (not `-p/--pretty`), and `--callers`.
- **`forge-add`:** the real tables (`[deps]`, `[dev-deps]`, `[test-deps]`, `[dev-only-deps]`),
  `--test`, `--dev-only`, the capability-baseline refusal and `--accept-caps`, and `forge deps`
  (there is no `forge deps install`).
- **`/build-test`:** the compiler repo (`dune build --root .`, `scripts/run-tests.sh`, the
  goldens, doc-lint) and a forge project (`forge check`, `build`, `lint --strict`, `test`).

The user-level copies in `~/.claude/` are outside the repo and were left in place. They now
duplicate the tracked ones, and the user-level `march-lang` is older than the repo's.
