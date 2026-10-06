# A multi-host lab for choreography and multi-node deploys

`scripts/lab/` and `examples/lab_app/`; how to run it and what each scenario proves:
docs/lab.md.

## What was built

- **Hosts** (`scripts/lab/up.sh`, `down.sh`, `image/`): four `debian:bookworm-slim`
  containers, lab-1..lab-4, on a private Docker network, each with sshd and a stand-in
  `systemctl`. The image and the stand-in are forge/test/test_deploy_e2e.ml's, plus
  `enable` recorded and a first process (`boot.sh`) that starts the enabled units, so
  `docker stop`/`start` is a power cycle the node comes back from by itself. Each host is
  capped at `LAB_HOST_MEMORY` (1536m): a node that runs away is OOM-killed inside the
  lab, not wherever the Docker VM's OOM killer looks first (the VM is shared with other
  projects' containers).
- **The runner** (`scripts/lab/run.sh`, `lib.sh`): forge from this machine against the
  containers, hermetic (`LAB_DIR` holds a private `HOME`, the project copy, keys and
  logs; the compiler reads the checkout's `runtime/` and `stdlib/`). A missing
  prerequisite (Docker, its daemon, zig, the cross sysroot, ssh) exits 2 with a banner.
  Each scenario runs in a subshell; `LAB_XFAIL=<todo>` in a scenario file makes its
  failure an XFAIL and its pass an XPASS (a failure, so the marker goes when the bug is
  fixed); a scenario run above `LAB_MAX_LOAD` (20) is UNRELIABLE, whatever it did; every
  OOM kill the Docker VM logged during a scenario is noted.
- **The app** (`examples/lab_app`): `Order`, three roles with a `loop` and a
  `choose by Stock`; Stock bound to a function on every `work` node, Ledger to an actor
  placed `{ on = "books", count = 1 }`, role grants on both; an `ingress` pool whose
  hook starts sessions from a Driver actor (so sessions after a hot deploy run new code)
  and writes counters to a stats file every second; a probe file of live heap objects
  on every node; traffic paced by a file the lab writes; `[control]` with three
  candidates.
- **Scenarios**: `deploy`, `hot_role`, `restart_persist`, `failover` (this PR);
  `protocol_change`, `partition`, `leader_kill`, `cert_rotate`, `soak` follow.

## Results (2026-10-05, main at 53d66f068, load 5-13)

`scripts/lab/run.sh deploy hot_role restart_persist failover`, load 7-14:

```
PASS  deploy (181s)
XFAIL hot_role (67s): waiting for: a control-plane leader
XFAIL restart_persist (367s): waiting for: Stock replies from lab-2 again
      (after the restore-before-offers, topology and `forge topology status` checks passed)
XFAIL failover: the Ledger moved lab-4 -> lab-3 in 1 s with no session failed; the
      returning lab-4 offered it from 0 s, both for 24 of 92 half-second samples, and
      sessions stopped once it was back on lab-4
```

(`restart_persist` and `failover` each began with a fresh deploy, ~3 minutes, because a
node had passed `LAB_RESET_MB` or been OOM-killed.)

## Findings

Each filed with its repro; the scenarios that hit one are marked or worked around:

- `specs/todos/2026-10-05-lab-topology-reread-closes-ctl-control.md` (P1): a pushed
  topology closes `Ctl.Control` on every node; the control plane never has a leader
  after the first deploy. `hot_role` XFAIL.
- `specs/todos/2026-10-05-lab-cert-mode-offer-to-offer-session-hangs.md` (P1): a session
  whose Stock and Ledger are on different hosts hangs for ever, nearly always in
  certificate mode. The lab defaults to a shared secret (`LAB_AUTH=certs` for the other).
- `specs/todos/2026-10-05-lab-leaderless-agents-leak.md` (P1): every node grows ~13k
  objects/s with no leader and no traffic.
- `specs/todos/2026-10-05-lab-simultaneous-restart-memory-burst.md` (P1): nodes
  restarted together can take ~1 GB each in 30 s.
- `specs/todos/2026-10-05-lab-restarted-node-offers-invisible.md` (P1): a restarted
  node's offers are open but no initiator sees them for minutes. `restart_persist` XFAIL
  at its last step (its restore checks pass first).
- `specs/todos/2026-10-05-lab-rejoining-node-offers-count-role-at-once.md` (P2): a
  restarted node offers a `count = 1` role a second after it starts; two nodes offer it
  for the settle period. `failover` XFAIL.
- `specs/todos/2026-10-04-lab-control-topology-step-races-report.md` (P2): a topology
  step halts when the Agent asks before the runner re-read the topology.
- `specs/todos/2026-10-05-lab-forge-cluster-deploy-retry-and-leader-change.md` (P2): a
  halted first cluster deploy records nothing; following a release gives up on
  `ERR no_leader`. The lab's first deploy is `--via ssh`.
- `specs/todos/2026-10-04-lab-control-wiring-none-ctor-ambiguous.md` (P2): a branch
  labelled `none` breaks the `[control]` wiring.

Because of the memory findings, scenarios after `deploy` start on a fresh deploy whenever
a node is down or above `LAB_RESET_MB` (`lab_fresh_cluster`), and traffic is one session
a second.
