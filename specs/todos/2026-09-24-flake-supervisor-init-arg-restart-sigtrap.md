# `[P3]` Flake: compiled native tests die with SIGTRAP under load (two sightings)

Seen 2026-09-23 during local verification of PR #604 (whose change the program does not
exercise: its only IO is Console output). One run of `dune build --root . @runtest`
failed with the test process killed by SIGTRAP; re-running the same binary passed 46 of
46 times with output matching its `.expected`, at load average 20–35.

A SIGTRAP from a compiled March program usually means code reached a compiler-inserted
trap (an LLVM `unreachable`/`llvm.trap`, e.g. a non-exhaustive match or an assertion),
not a timeout — so this should not be dismissed as load noise even though it did not
reproduce. The supervisor restart path re-runs a child's `init` with its captured
arguments (the D24 respawn closure), and supervisor/actor lifetime code was changing in
the same window (proc-struct reclamation, #592 and #609).

## Next sighting

Capture the full output and the exit status. If it recurs, run the program in a loop
under load (and under ASAN in the Linux container) to reproduce, and check which trap
fired (`MARCH_BACKTRACE=full`, or the fatal-fault report line if it prints one).

## Second sighting, 2026-09-24: `native_erased_type_id`

During local verification of PR #629 (erased-render quoting), one run of
`native_erased_type_id` inside dune died with `signal TRAP` while building in parallel
with another golden. It did not recur in 3 cache-disabled dune reruns, 30 direct runs or
45 concurrent runs.

Two different compiled programs, each trapping once under heavy parallel load and never
on rerun, make "load noise" a weak explanation: a timeout or a slow scheduler produces a
wrong result or a kill, not a trap. Something that only fails under contention — a race
that reaches a compiler-inserted trap or an `abort()` path in the runtime (the fatal-fault
report prints for SIGSEGV/SIGBUS; check whether SIGTRAP reaches it) — fits better. Both
programs start actors or scheduler threads. Treat the two sightings as possibly one bug.
