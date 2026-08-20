# `native_signal_watch` has a ~7% output-ordering flake

Filed 2026-08-20, found while verifying the NativeArray bounds-check fix
(`specs/progress/2026-08-20-nativearray-get-set-unchecked-oob-compiled.md`),
whose `dune runtest` run this test reddened. It is **not** related to that
change — see the control below.

## The flake

`test/native/signal_watch.expected` pins:

```
before raise
after raise
caught usr2
```

Two different wrong outputs were observed:

```
before raise
after raisecaught usr2          <- handler's write lands mid-line, no newline
```
```
before raise
caught usr2
after raise                      <- handler observed BEFORE the main thread's line
```

So both the interleaving *and* the ordering of the handler's output against the
main thread's are unpinned. The fixture raises SIGUSR2 and expects the handler's
line to appear strictly after `after raise`, which is only true if the handler's
delivery is deferred to a drain point that happens to fall there.

## Measurement — the change under test is exonerated

Both binaries built from the same tree, differing only in the runtime, then run
INTERLEAVED (so contention is shared evenly across arms — the box was at load
average ~8 on 14 cores at the time):

| runtime | mismatched |
|---|---|
| baseline (no bounds check) | 4/60 |
| with the bounds check | 4/60 |

Identical. Neither binary even links the new check (`strings | grep -c
"out of bounds (len="` is 0 for both), and `signal_watch.march` never mentions
`NativeArray`, so the change is mechanically inert here.

Worth recording the trap: an earlier, smaller sample read 0/20 baseline vs 2/20
fixed, which looks alarming and is not significant — at a ~7% rate, 0/20 happens
about 12% of the time by chance. A 20-run spot check cannot resolve a flake of
this size; the interleaved 60-run pair could.

## Fix

Make the assertion insensitive to the delivery point, or make the delivery point
deterministic. Either pin only that all three lines appear (order-free, as
`native_actor_monitor_down_reason`'s rule does with per-line `grep -Eq`), or
have the fixture drain signals at an explicit synchronisation point before
printing `after raise` so the ordering is guaranteed rather than typical.

Prefer the second if the ordering is meant to be part of the contract — an
order-free assertion would stop pinning "the handler does not run before the
raise returns", which may be the property the fixture exists to check. Read
`specs/progress/2026-08-11-signal-watch-stage-b.md` (Signal.watch Stage B)
before choosing.

## Acceptance

200 consecutive runs with no mismatch, on a loaded box (an idle box hides it —
the observed rate roughly tracks contention).
