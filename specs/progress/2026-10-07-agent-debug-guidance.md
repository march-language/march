# DONE 2026-10-07: agent debugging guidance (skills, CLAUDE.md, hook, doc-lint)

Agents get their instructions from `CLAUDE.md` (always loaded), `.claude/skills/*`
(on demand) and `.claude/hooks/*` (automatic). None of them mentioned the triage
and observability tools that landed the week of 2026-10-05 (`scripts/triage.sh`,
the determinism oracle, `--dump-impl-hashes`, the `alloc-contract`/`cas-hash`
timing stamps, `--rc-trace` + `scripts/gc-trace-report.py`).

## What landed

- **`.claude/skills/march-debug/SKILL.md`**: organised by symptom → first command
  → how to read it → what not to do. Covers `scripts/triage.sh`,
  `MARCH_DUMP_TXT` vs `--dump-phases`, the four optional-pass switches (and that
  `MARCH_NO_TRMC` does not exist), `MARCH_SANITIZE=1`, `--debug-info`,
  `--dump-provenance`, `MARCH_REPR_AUDIT=1`, the `--rc-trace` leak workflow,
  `MARCH_DEBUG_CASFLAGS=1|2` and clearing `artifacts-v2`, `--timings` and
  `scripts/compile-time-bench.sh`, the four oracles with what each is blind to,
  `UPDATE_SNAPSHOTS=1`, `--check-json`. Every flag and env var was checked against
  `march --help` / a source grep on `main` (c31ef539a) before being written down.
- **`.claude/skills/steward/SKILL.md`**: PR-driving guidance. Known flaky checks
  with a policy for each (the macOS `all` shard's timeout, `cluster_sessions`,
  ASan `cluster_takeover`, the ASan time-scale mechanism, the now-deterministic
  `@vault-scale` and `observe_sched`, the four one-sighting flake todos); the
  one-re-run rule; reading CI logs (`gh run view --log` truncates; grep `File "`
  for golden failures in the macOS `all` log); what CI enforces (CHANGELOG,
  progress entry, tree-sitter rule, doc-lint, bench-gate registration, refine
  audit baseline for new native fixtures); attribution footers; and the standard
  preamble for a `spawn_task` prompt.
- **`CLAUDE.md`**: the bench-gate registration rule in "Build & test" and a short
  "When something breaks" section pointing at `scripts/triage.sh` and the two
  skills. Pipeline step 1 already named `March_parser.Parse.module_` (D0, #806).
- **`march-lang` skill**: the test-harness snippet built `Token_filter.make`
  inline; it now calls `March_parser.Parse.module_`.
- **`.claude/hooks/post-failure-hint.sh`**: after a Bash call whose command
  contains `march … --compile`, `run-tests.sh`, `dune runtest` or `dune build`
  and which failed, it adds one line of context: "scripts/triage.sh and the
  march-debug skill exist; see CLAUDE.md 'When something breaks'". Silent
  otherwise. Registered as a second `PostToolUse` Bash hook next to
  `post-commit-reminder.sh`, **and** under `PostToolUseFailure`: current Claude
  Code reports a non-zero Bash exit as a separate failure event rather than a
  `PostToolUse` with an exit code, so a `PostToolUse`-only registration would
  never fire. The script accepts both payload shapes (`tool_exit_code`, an exit
  code inside `tool_response`, or the failure event's `error` text). Tested by
  hand with six fabricated payloads: failure with each shape prints the hint;
  success, an unrelated failing command, a payload with no exit code and
  non-JSON input print nothing; all exit 0.
- **doc-lint (`scripts/check-docs.sh`)**: the two new skill files are in the
  current-docs list, and Check A now also extracts `scripts/*.sh|*.py` pointers.
  Proved red: renaming `scripts/triage.sh` to `scripts/triage2.sh` in the
  march-debug skill gives `DEAD PATH: … references missing 'scripts/triage2.sh'`.
  (A first perturbation to `triage-renamed.sh` stayed green because Check A
  skips lines containing "renamed"; that exemption is intended.)
