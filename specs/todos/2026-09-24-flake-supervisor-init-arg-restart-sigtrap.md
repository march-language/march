# `[P3]` Flake: `native_supervisor_init_arg_restart` died once with SIGTRAP

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
