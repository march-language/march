# Current State (as of 2026-07-31, JsonStream phase 1 — benchmark + compiled parity + docs)


**Counts:** `run_stdlib` 826 (unchanged in count — JsonStream's 212 interpreted
tests were added across Tasks 1–4 and are already reflected in this total;
this task added no new `describe`/`test` cases, only the benchmark and docs),
with only the pre-existing environmental `MARCH_SANITIZE`/adversarial-regressions
timeout failure (`test_compiled_sanitize_clean_exit`, killed after 30s under
load — not a JsonStream regression). `run_compiler` 619, `run_codegen` 520,
`run_eval` 256, `run_snapshots` 33 unchanged (no compiler-pipeline code
touched). `find stdlib -name '*.march' | wc -l` is now 112 (JsonStream's own
module, landed in Tasks 1–4, pushed the count from 111 — `scripts/check-docs.sh`
Check B caught four stale "111 stdlib modules" references — `README.md`,
`CLAUDE.md`, `docs/stdlib.md`, `.claude/skills/march-lang/SKILL.md` — bumped
to 112 in this commit).

**Task 5 closes out the JsonStream phase 1 plan** (tokenizer + drivers landed
Tasks 1–4, 212 tests green interpreted): benchmark, first-ever **compiled**
exercise of the module, and canonical docs.

**Totality-harness approach (carried from Tasks 1–4, unchanged, restated here
since Task 5 is where it gets a benchmark backing it):** every test document is
fed through the tokenizer at *every* possible byte-split point — not a
hand-picked sample of chunk boundaries — asserting the resulting event stream
is identical to feeding the whole document in one `feed` call. Truncation
sweeps drop the input at every prefix length and require either a clean
partial-event set or a final `ETruncated`, never a wrong answer. This is the
same style of exhaustive-over-a-dimension check as the every-byte-split
sweep, applied to the "where does the caller stop feeding" axis instead of
"where does the caller cut the chunks."

**Compiled parity: no divergence found**, closing this repo's most common bug
class (compiled-vs-interpreted mismatch) for this module on first contact.
Two checks:
1. `bench/json_stream.march` (20,000 synthetic NDJSON records, 64KB chunks):
   interpreted (n=200 sanity) and compiled agree — checksum `2800` at n=200,
   `280000` at n=20,000 (`20000 × 14`; see below for where 14 comes from).
2. A dedicated surrogate-pair probe (`"a😀b"`, i.e. `a😀b`) run
   through `JsonStream.fold` — interpreted and compiled both decode to
   `EvStr("a😀b")`, 6 UTF-8 bytes, byte-identical output. This specifically
   exercises the compiled `march_byte_to_char` path Task 4's string-content
   emission depends on, which had never been exercised by this module before
   Task 5.

**The benchmark's own per-record event count was wrong in the plan and was
computed empirically before use, per the plan's own instruction not to trust
prose arithmetic here.** The plan text guessed 13 events/record
(`checksum = 20000 × 13 = 260000`); a 1/2/3-record probe measured 14, 28, 42
— i.e. **14** events/record, not 13 (the record's `EvObjStart`, 4×`EvKey`,
3 scalar events, `EvArrStart`, 3×`EvNum`, `EvArrEnd`, `EvObjEnd` = 14). Fixed
both the benchmark's header comment and the expected checksum
(20000 × 14 = **280000**) before recording the baseline. The plan's timing
arithmetic was also wrong the same way it warned about: `System.monotonic_time()`
already returns milliseconds (see `stdlib/system.march`'s own doc comment and
every other `bench/*.march` file's usage), so the plan's `(t1 - t0) / 1000000`
divided milliseconds by a million and printed `ms=0` every run; fixed to
`t1 - t0` directly.

**Benchmark baseline (2026-07-31, Apple M-class, `--opt 2`, n=20,000
records):** `checksum=280000`, `ms=224-229` across three runs,
`/usr/bin/time -l` maximum resident set size ≈ 85 MB (85016576–85049344
bytes). **10× record-count spot-check** (n=200,000, same 64KB chunk size):
`checksum=2800000`, `ms=2373`, MaxRSS 840138752 bytes (≈801 MB) — RSS grew
≈9.9× against the 10× input-size increase (≈82 MB baseline delta above a
≈3 MB empty-program floor vs. ≈837 MB at 10×), i.e. RSS tracks the size of
the in-memory input string the benchmark holds by construction, not the
record count independent of that — consistent with the constant-memory
design claim for the tokenizer's own state (see `specs/benchmarks.md` for the
full writeup and what-to-watch notes for phase 2).

**Deferred, per the design's own scoping, not found during this task:** the
decoder-combinator layer (design Component 4, "separable — nothing in
Components 1–3 depends on it"). `specs/2026-07-30-json-streaming-design.md`
status flipped to phase 1 implemented; no decision-table deviations were
found during implementation. Phase 2 (SIMD structural scanning) is filed as
an open item in `specs/todos.md`, seeded with this task's benchmark baseline
as the number it must beat.
