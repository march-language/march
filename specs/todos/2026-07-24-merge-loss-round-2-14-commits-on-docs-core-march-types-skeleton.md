# Merge-loss round 2 — 14 commits on `docs/core-march-types-skeleton` never reached `main` (2026-07-24)


**A second, distinct merge loss from the same branch as the 2026-07-18 audit
(which was recorded as COMPLETE).** `git merge-base --is-ancestor <sha> HEAD`
says NO for all of these; `git log --oneline main..e283d9b9` counts 14.

### Audit results (2026-07-24) — the branch holds 31 non-docs commits, not 13

Method: patch re-application is useless after months of drift (169/275 came
back "ambiguous"), so each commit was scored by **content presence** — what
fraction of its substantive added code lines exist anywhere in `lib/ bin/
runtime/ stdlib/ forge/ lsp/ js/` today. Calibrated against three known
outcomes: `e283d9b9` (restored this session) → 100%, `c30161d7` and
`4b4c70b3` (restored by the 2026-07-18 audit) → 100% / 90%. Script kept at
`scratchpad/content_audit.sh`.

**A low score means "this implementation is absent", NOT "the bug is live"** —
several were superseded by a different fix that IS in `main` (e.g. `5a648f9c`
to_string-via-Show scores 0% but was superseded by `6d2eed85`, and to_string
on containers verifiably works). Every claim below is a *behavioural* probe,
not a line count.

- [x] **CLASS BUG behind the deque case — confirmed live and split out
  2026-08-01, see `specs/todos/2026-08-01-lazy-stdlib-loading-boxed-vs-niche-representation-mismatch.md`.**
  Reproduced fresh via `ConsistentHash.get` (compiled returns a garbage
  pointer instead of the stored `Int`); point-fixed 6 more affected modules
  by adding them to `stdlib_file_list`, same as the original `deque.march`
  fix. The general class bug (nothing stops a *future* stdlib module from
  reintroducing this by omission) is still open — tracked in the new file,
  not here.

**Probed and NOT reproducing** (superseded, or the probe doesn't hit it):
`d2d0a3a3` (`examples/stats_basic.march` interp==compiled parity ok),
`895ebfee` (`bench/dataframe_bench.march` runs clean), `5a648f9c`
(to_string-on-container works, superseded by `6d2eed85`), `c30161d7`,
`4b4c70b3`, `b7140673`, `778d399c`, `a7f96dad` (all score PRESENT).

- [ ] **Still unprobed, ranked by risk** — each needs a behavioural test
  before any verdict: `f2b67001` (niche-erased Option FBIP reuse → RC
  underflow), `f2729935` / `6f047e02` (Perceus RC field-type resolution),
  `6dd1968c` (B18 TCO release-timing), `4a58e992` (Task.race/any/cancel —
  possibly superseded by the 2026-07-18 cancel-token work), `03498340`
  (node_discovery stack overflow; the torn-stdout half is superseded by
  `e73644aa`), `c430e330` (reject overlapping impls), `b267a436` (derived
  structural Show), `b84ae429` (monomorphism restriction), `fcfd78ba` +
  `3c8826a0` + `4ab998ea` (the three-stage uniform apply-fn ABI flip — these
  are a *sequence*; restoring one without the others is likely worse than
  restoring none), `d5562dfc`, `1a547481`, `21f4fbb2`, `8f624a50`,
  `7868160e`, `65eefa53`.

### Why the safety nets missed all of this

- [ ] **The differential oracle cannot see these crashes.**
  `bench/iolist_template.march` is `SKIPPED`; `string_pipeline` and
  `deque_ops` are `INTERP_TIMEOUT`. The sweep only compares programs where
  the tree-walking interpreter produced ground truth inside its 10s budget,
  so for every compute-heavy benchmark — exactly the ones most likely to
  exercise RC, FBIP and TCO — a compiled SIGBUS, hang, or wrong answer is
  invisible. The sweep reported **0 divergences** on the same day three bench
  programs were broken compiled. Give these an expected-stdout anchor and
  compare the compiled run against it directly, with no interpreter leg.
- [ ] **`march --compile` should write its intermediate `.ll` next to the
  OUTPUT, not next to the source.** Writing beside the source pollutes the
  tree and makes compiling from a read-only directory impossible. Found by
  the bench gate failing inside dune's sandbox.
- [ ] **Process gap, not just a backlog.** Two separate audits of this branch
  have now each declared completion while leaving real fixes behind. Before
  the next one, decide on a mechanical check (e.g. a CI job asserting no
  `fix(`/`feat(` commit on a merged branch is missing from `main`) rather than
  a third manual pass.
