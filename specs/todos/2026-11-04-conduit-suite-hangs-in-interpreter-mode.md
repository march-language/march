# `[P3]` conduit's test suite hangs in interpreter mode (v0.7.0)

Found 2026-11-04. `MARCH_TEST_INTERPRETER=1 forge test` in conduit (v0.1.8, depot 0.3.3)
printed results for part of the run, then made no progress for 90 minutes inside `march test
.../test/test_conduit.march`, until it was killed. A live Postgres `conduit_test` database was
reachable, so the Postgres live tests were running for real. Not reduced yet. The compiled
suite's crash in the same setup was a separate bug
(`specs/progress/2026-11-04-actor-caps-read-returns-owned-reference.md`). The hang may be in
depot's `Pool` actor under the interpreter, or anywhere else.

Next step: run with `--filter` per test (as was done for the compiled crash) to find the test
that hangs.
