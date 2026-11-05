# Compiled --test builds: an actor with spawn-captured capabilities died with "RC underflow" (2026-11-04)

conduit's compiled suite (`forge test --release`, March 0.6.0, 0.7.0 and main) aborted before
printing a result with `march: RC underflow (rc was 0)` or a SIGBUS, whenever a Postgres was
reachable. Every crashing test went through depot's `Pool` actor. The interpreter was correct.
Release builds never run the code involved.

## Cause

In a `--test` build (`Flags.cap_mocking`), `Cap_passing` captures an actor's capabilities at
the spawn site, `set_actor_caps($raw_actor, $spawn_caps)`, and the dispatch reads the record
back on every message with `actor_caps($actor)`. The design note in `cap_passing.ml` said
`$caps` was a plain record that Perceus never refcounts. That stopped being true when records
became refcounted (`Kind.needs_rc (TRecord _)` is true). The dispatch now `dec_rc $caps` in
every arm that uses no capability, but `march_actor_caps` handed back the meta's own reference.
So the second message freed the record, and a later one underflowed or hit reused memory.

What it takes to trigger:

- An actor where one handler reaches an interceptable capability (`Pool`'s `Shutdown` →
  `Db.close` → NetConnect) and other handlers don't (`PoolInit`, `Checkout`).
- Two or more messages, with the handler that uses the capability never sent.
- A test-only build. With a `main` in the program, Perceus doesn't release `$caps` in the
  dispatch (not investigated further).

Whether a given run aborts depends on what the freed cell's rc word holds. The same binary
failed 3 runs in 6 under load and 0 in 10 on an idle machine.

## Fix

`march_actor_caps` increfs the record it returns, so every read is an owned reference and the
meta keeps its own (`set_actor_caps` still consumes the spawn site's one). In a dispatch where
Perceus doesn't release `$caps`, the only effect is a higher count on a record the meta
retains for the actor's lifetime anyway. The RC notes in `cap_passing.ml` (spawn side and
dispatch side) now say this.

## Tests

- `test/test_actor_caps.c` (`test_actor_caps_runner`): a fake actor with a meta. It checks the
  record's rc after set, after each of 100 reads plus releases, and with two reads
  outstanding. It fails on v0.7.0's runtime (`rc == 2` assertion) and passes with the fix.
- `test/cap_mock/cap_mock_actor_many`: the shape end to end, as a test-only build sending 50
  messages to the capability-free handler. It is timing-dependent on the old runtime, which is
  why the C test exists.
- conduit's suite with the fixed compiler: 249/249, three runs, against a live Postgres.

## How it was found

Bisected conduit's suite by `--filter` (all Postgres live tests), then depot's `Pool` alone in a
test (crashes) vs from a `main` (fine). Then reduced `Pool` handler by handler: removing
`Shutdown`, which no test sends, made it pass. Its `$cap_IO_NetConnect` parameter led to the
dispatch's `actor_caps` read in `MARCH_DUMP_TXT=tir-perceus`.
