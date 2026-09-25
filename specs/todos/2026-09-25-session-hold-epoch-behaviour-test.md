# `[P3]` No behavioural test of SessionNode's HoldEpoch / ReleaseEpoch

**Filed** 2026-09-25, split out of the DD review's step-6 test-gap item (closed in
`specs/progress/2026-09-25-dd-review-step6-untested-behaviours.md`). Only
`stdlib/session_node.march` names `HoldEpoch`/`ReleaseEpoch`; the hosted-API test
checks generated call counts, not behaviour. Deferred because D27 (session drains,
branch claude/trusting-germain-d9e48d) was rewriting the hold code.

**Do.** A compiled session test through the reload socket: a session spanning a
deploy holds its endpoint's epoch (PINS shows the old epoch pinned by it) and
releases it when the session ends (the old epoch's pins reach 0); it must go red with
the hold or the release removed.
