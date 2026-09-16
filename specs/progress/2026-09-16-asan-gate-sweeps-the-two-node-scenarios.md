# The ASAN gate sweeps the two-node scenarios

**Landed 2026-09-16.** Phase 0 of the RC plan: close the hole that let a
use-after-free reach `main`'s CI.

## Why

On 2026-09-16 a closure deep drop released a node id that the members `Map`
still owned (`specs/progress/2026-09-15-closure-captures-released-by-the-hof-loop.md`).
Both corpora `specs/lang/golden/sanitize.sh` swept — 47 golden programs and 25
curated `test/native` ones — came back CLEAN, three runs each. What caught it
was `two-node[skew]`, a scenario the sanitizer had never compiled: two programs
as two OS processes over a real socket, with the actor plane and a live
connection in play. Ownership bugs that only appear when a value crosses that
boundary had no gate.

## What landed

- `specs/lang/golden/sanitize.sh` grows a third corpus: every scenario in
  `scripts/two-node.sh --list`, run with `MARCH_SANITIZE=1` and the harness's
  own deadline (`TWO_NODE_ASAN_TIMEOUT`, default 240 s — ASAN is 2-20x). A
  scenario that needs root it does not have (`partition`, iptables) exits 3 and
  is reported SKIP, not counted as a pass.
- Four programs join the curated native corpus: the three closure-ownership
  probes (each 5,000 iterations, not the multi-million ones the header
  excludes) and `node_discovery`, whose guard-page crash is why the closure
  deep-drop gate exists at all.
- `.github/workflows/ci.yml`: the two comments that describe the gate now
  describe three corpora.

## Verification

Both directions, in the `march-sbx-test-ubuntu` container (linux/arm64):

- **GREEN**: 81 programs swept, 81 clean, `partition` skipped, 178 s total —
  so the gate costs about two minutes more than before.
- **RED**: with the backed-out closure drop table restored (`c20d0fa62`'s
  `lib/tir` + `runtime`), the gate exits 1 — `two-node/skew` fails with an ASAN
  abort while the golden and native corpora report 80 clean. That is the 2026-09-16
  failure reproduced by the gate that now guards it.
