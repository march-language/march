# `core-march.md` §4.16 claimed two things that stopped being true

Fixed 2026-09-17. Flagged inside
`specs/todos/2026-07-11-p2-compiler-docs-perceus-rc-refinement-types-core-march-widening.md`,
whose 2026-08-04 disposition noted the first and said it "should be corrected
separately in a different task". That todo stays open — its unblock conditions
are about metatheory that still does not exist. This is only the doc fix.

`specs/lang/core-march.md` is a CURRENT-TRUTH doc under `scripts/check-docs.sh`.
The lint guards source pointers and stdlib counts; it cannot see a prose claim
about the compiler go stale, which is how both of these survived.

## 1. "Atomic RC mode-selection … no code implements it today"

Half true, and the false half is the load-bearing one. What does not exist is
the GENERAL escape-analysis-driven pass `specs/atomic-rc-design.md` designs:
there is no `rc_mode` pass module under `lib/tir/` and no `rc_mode` field. But a narrower
selection ships and has for a long time —

```ocaml
let incrc_for (env : env) (v : Tir.var) (a : Tir.atom) : Tir.expr =
  if StringSet.mem v.Tir.v_name env.actor_sent
  then Tir.EAtomicIncRC a
  else Tir.EIncRC a
```

`lib/tir/perceus_core.ml`, with `decrc_for` alongside it, keyed on
`collect_actor_sent_vars` (the values reachable by `send()`), lowered by
`Llvm_emit` to C11 atomics — 21 atomic sites in `runtime/march_runtime.c`.

A reader checking whether March's RC is thread-safe would have concluded from
this sentence that nothing was, which is the opposite of the truth for exactly
the values where it matters.

Rewritten to say what is excluded (the general pass, and why), and to name the
narrower mechanism that ships plus why no rule is stated for it: the escape
argument that makes "sent to an actor" the right boundary is the same
metatheory the general pass is waiting on.

## 2. "not yet a standing CI gate; no broad sanitizer sweep exists over the corpus"

Written 2026-07-11 and true then. The `sanitize-gate` job has run
`specs/lang/golden/sanitize.sh` in CI since 2026-08-20, and as of 2026-09-16 it
sweeps three corpora — every golden program, a curated by-name set of
`test/native` fixtures, and the `scripts/two-node.sh` scenarios — 84 programs
(`specs/progress/2026-09-16-asan-gate-sweeps-the-two-node-scenarios.md`).

This one matters more than it reads: the sentence calls the gap "a documented
gap", so anyone auditing sanitizer coverage would have taken the doc's word for
it and rebuilt something that exists.

## Verification

`scripts/check-docs.sh` passes. No count or pointer changed; both edits are
prose, which is precisely why the lint was never going to catch them.

One wrinkle worth recording: the first draft wrote "there is no
`lib/tir/rc_mode.ml`" and doc-lint rejected it — Check A reads that as a
reference to a missing file and cannot tell "this path does not exist" from
"this path moved". Its escape hatches are the words `no longer exists` /
`removed` / `renamed` / `deleted` on the same line, or a
`doc-lint:ignore-file` marker, and none of them is honest about a file that
never existed. Rephrasing to name the directory instead (`no rc_mode pass
module under lib/tir/`) says the same thing and keeps the lint meaningful.
