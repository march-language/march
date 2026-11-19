# ocap phase 4 Task 10 performance record: bookkeeping (2026-11-19)

Found by the ocap phase 4 Task 10 review:

- The Task 10 progress entry points at a gitignored perf file for its tables and
  IR classification, so the durable record lacks them. Copy the tables (they are
  in the PR A body) into the progress entry.
- The IR classification's class counts overlap (one program can fall in two
  classes) without saying so.
- `bench/cap_check_slow.march`'s ns/op includes about 12 ms of process startup,
  so the reported per-check cost is conservative; subtract a no-op baseline or
  say so beside the figure.
