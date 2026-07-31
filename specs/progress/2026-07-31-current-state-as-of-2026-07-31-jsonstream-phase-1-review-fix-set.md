# Current State (as of 2026-07-31, JsonStream phase 1 review-fix set)


**Counts:** `test/stdlib/test_json_stream.march` 212 → 217 (interpreted, via
`march test`); `run_stdlib`'s `json_stream` alcotest group (which runs the
whole march test file as one alcotest case) unchanged in group count. No
other suite touched.

Four Minor findings from the whole-branch review of JsonStream phase 1
(PR #134) fixed:

1. **`max_token_bytes = 0` number/string asymmetry.** `value_start` created
   a number token's first `PNum` unconditionally, while `push_piece` always
   checked `max_token_bytes` for strings — so at `maxt=0` a 1-digit number
   was accepted but a 1-char string was rejected with `ETokenLimit`. Fixed
   by a new `num_start` helper (`stdlib/json_stream.march`) that checks
   `1 > maxt` at number-token creation, matching `push_piece`'s check for
   strings. At any `maxt >= 1` the two kinds already agreed; this only
   affected the degenerate `0` case. 4 new tests pin both directions at
   `maxt=0` and `maxt=1`.
2. **Partial-token memory-accounting doc precision.** The design spec's
   "constant memory" paragraph implied a tighter bound than phase 1
   actually delivers: the partial-token buffer accumulates as one cons cell
   + one string piece **per content byte**, not one byte. Documented in
   `specs/2026-07-30-json-streaming-design.md` (still bounded by
   `max_token_bytes`, still flat across document size — this is a precision
   fix to the stated constant factor, not a correctness bug). Phase 2's
   block-scanning tokenizer removes this shape outright; noted as an input
   to that design in `specs/todos.md`'s phase 2 open item.
3. **Stale plan-narration comment removed** at `open_container`'s doc
   comment (previously described implementation-task history — "Task 2
   implements open_container..." — rather than current behavior).
4. **`start_ndjson_with` gained test coverage.** Was public with zero tests;
   new test exercises non-default `JsonLimits` (a `max_depth` a later
   record trips) in ndjson mode, confirming limits and ndjson compose.

Verification: `march test test/stdlib/test_json_stream.march` — 217/217
green, exit 0. `test_stdlib_march.exe test json_stream -e` (compiled stdlib
test binary) — green, exit 0.
