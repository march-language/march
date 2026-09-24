# `[P2]` `@[endpoints]`: the frontend's time grows steeply with the number of protocols in one module

**Logged 2026-09-24** while writing `test/session/drain_peers.march` (D27 drains,
[../progress/2026-09-24-dd-d27-session-drains.md](../progress/2026-09-24-dd-d27-session-drains.md)).

`march --check` (typecheck only, nothing run) of one module holding N `@[endpoints]`
protocols, each generating a `<P>_Msg`, one role module per role (with the scripted and
chaos peers) and `<P>_Run`, on the 14-core Mac at load 10-15:

| protocols in the module | `--check` |
|---:|---:|
| 3 (`test/session/stream_peers.march`) | 2 s |
| 3 (three same-role protocols, trivial main) | 7 s |
| 5 | 48 s |
| 6 | 483 s |

The protocol declarations alone are cheap (three protocols with an empty `main`: 1-7 s);
the cost appears with a `main` and helper functions that call into the generated modules,
and it is far worse than linear in the protocol count. A first bisection over the
fixture's user functions did not isolate one culprit: dropping any two of the five
`*_seeds` functions from the six-protocol file left it over 150 s. The fixture was split
into two three-protocol files (`drain_peers.march`, `drain_peers_multi.march`) to keep
`dune runtest` fast; that is a workaround, not a fix.

**What to do.** Profile the typechecker on the six-protocol version (the pre-split file is
the union of the two fixtures): the suspects are per-module work that rescans every
nested module's declarations (a generated module count of ~20 with hundreds of
functions each), and the internal-error ratchet or capability walk over generated code.
Acceptance: the six-protocol union typechecks in under 10 s, and the two fixtures can
be one file again.
