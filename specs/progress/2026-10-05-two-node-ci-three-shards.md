# CI: the `two-node` job is three shards

**Date:** 2026-10-05

## Symptom

After #790 fixed `control_artifact_digest`, main run 37317973656 (40354afb0)
failed `two-node (2/2)` with "The action 'Two-node scenarios (2/2)' has timed
out after 50 minutes" (51 min of job time). PR #785's run 37318079911 and
#793's run timed out on the same shard.

## Cause: the list outgrew two shards, hidden by an earlier red

From #776 + #778 merging (2026-10-05 ~02:30Z) until #790 landed, every shard
stopped at its first failing scenario (`for s in $list; do ... || exit 1`).
Shard 2 stopped at `control_artifact_digest`, early in its list, so no run in
that window showed how long the whole list took. Once the scenario passed, the
whole 38-scenario list ran and went past 50 min. Every scenario that ran
reported `ok`.

## Fix

Three shards (`matrix.shard: [1, 2, 3]`, `scripts/two-node.sh --list K/3`), as
the job's own comment prescribes, rather than raising the timeout. The three
lists together cover all 76 scenarios exactly once
(`for k in 1 2 3; do scripts/two-node.sh --list $k/3; done | sort` against
`ls test/two_node`). Costs one more Linux runner per CI run for about the same
job-minutes. `.github/workflows/README.md` and the `two-node.sh` header are
updated to match.
