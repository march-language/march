# The determinism oracle's full corpus runs as two shards on main

## Fixed 2026-10-13 (`scripts/determinism-oracle.sh`, `.github/workflows/ci.yml`)

The `determinism` CI job ran the full corpus (`--corpus all`) in one job with a 60-minute
step limit. The corpus grew from ~417 to 498 programs and the step hit the limit on every
push to `main` from 2026-10-12 on (runs 38270931831, 38326774779, 38406169533): the job
was red although the oracle had found no difference, which also made it impossible for
`main` to show a green run. The `--self-test` step passed each time; PR runs (small
corpus) were never affected.

- `determinism-oracle.sh --shard K/N` keeps every Nth program of the sorted list, dealt
  round-robin so each shard gets a mix of cheap and heavy programs. `examples_topology_app`
  (the program the #805 drift showed on) is in every shard.
- On a push, `ci.yml` runs `--corpus all --shard 1/2` and `--shard 2/2` as a matrix. A pull
  request still runs the small corpus as the single shard. `fail-fast` is off so one
  shard's difference does not hide the other's.

Checked: the two shards partition the 498-program corpus (249 and 250 programs, no overlap
apart from the topology app, nothing missing); a bad `--shard` (`0/2`, `3/2`, `x`, `1/0`)
exits 2; `--corpus small --shard 1/2` runs end to end (15 programs, DETERMINISTIC).
