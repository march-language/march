# `[P1]` Distributed deploys, build step 6: the unified epoch model and drains

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), sections 6.1-6.3, II.4, D10-D13, D27-D30, D32, D33.
Depends on step 5's decision.

**What.** `code_epoch` on `march_proc` and `march_dispatch_enter_unit` (D33; G1's
prototype is the starting point, not merged); per-epoch unit pins with a waiting
activation and three live versions per slot (D32); epoch holds (D28); message stamps on
`march_mbox_node` (D29) and the marker as a mailbox-node flag that bypasses overflow
policies; early advance (D30); `migrate_msg` and a source name for an actor's message
type; soft and hard drain deadlines. The HCR migration fix already on main (#564:
per-actor `hcr_pin`, markers, a drain deadline) is the first slice; build on it, see
`specs/todos/2026-09-22-dd-hcr-migration-bugs.md`.

**Acceptance.** II.4's tests: queued messages run on the pinned version; a held proc
defers its marker; a schema-changing deploy with messages already sent in the new
format keeps FIFO order via early advance; the hard deadline kills and the supervisor
restarts on new code; `PINS` and delivery-failure counters report it.
