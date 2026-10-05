---
layout: docs
title: Multi-host Lab
nav_order: 10.96
permalink: /docs/lab/
---

# The multi-host lab

`scripts/lab/` deploys a real topology app to four Linux containers on a private Docker
network and checks what happens when it is changed, restarted, cut off and failed over.
Each container is a separate host: it has its own sshd, its own disk and its own
stand-in for systemd. The real `forge` runs on your machine and reaches the hosts the way
it reaches production hosts: over ssh for `forge host init` and restarts, and through the
in-cluster control plane for hot deploys.

The two-node scenarios under `test/two_node/` run their nodes as processes on one
machine, wired by hand. The lab is slower and closer to a deployment. It runs on demand,
not in per-PR CI.

```bash
scripts/lab/run.sh                     # every scenario, in order
scripts/lab/run.sh deploy hot_role     # these, in this order
scripts/lab/run.sh --list              # the scenarios
scripts/lab/down.sh                    # remove the containers and the network
```

## Prerequisites

- Docker with its daemon running. The hosts are `debian:bookworm-slim` with sshd; the
  image is built from `scripts/lab/image/` on first use, which needs network access for
  `apt`.
- `zig`, which forge uses to cross-build each host's base image, and the cross sysroot
  for the containers' architecture (`scripts/fetch-cross-sysroot.sh arm64` or `amd64`;
  `MARCH_CROSS_SYSROOT_ARM64` / `_AMD64` point elsewhere).
- `ssh` and `ssh-keygen`.
- About 8 GB of memory in the Docker VM: each host is capped at `LAB_HOST_MEMORY` (default
  2g), and the lab is best run with no other containers busy.
- A quiet machine. Most scenarios assert on timing (SWIM's suspect timeout, the
  placement settle period, drain deadlines). `run.sh` reads the 1-minute load average
  before and after each scenario and reports a scenario that ran above `LAB_MAX_LOAD`
  (default 20) as **unreliable** instead of passed or failed.

A missing prerequisite stops the run with exit status 2 and a banner saying nothing was
tested. The lab never passes without testing.

`run.sh` builds the compiler, forge and `test/hcr_deploy.exe` from the checkout first
(`LAB_NO_BUILD=1` skips that) and points them at the checkout's `runtime/` and `stdlib/`.
Everything forge and the compiler write (caches, the deploy key, the cluster operator
key, the project copy, the logs) goes under `LAB_DIR` (default
`/tmp/march-lab-<checkout name>`), with a private `HOME`, so nothing touches your own
`~/.march` or `~/.cache/march`.

## The hosts

`scripts/lab/up.sh` creates the network `march-lab` and four containers, `lab-1` to
`lab-4`. On the network the hosts reach each other by name. From your machine, lab-N's
sshd is at `127.0.0.1:22200+N` and a control candidate's API at `127.0.0.1:22300+N`
(`LAB_PORT_BASE` moves both). The containers stay up after a run; `down.sh` removes them.

The stand-in `systemctl` runs a unit's `ExecStart` as its user with its environment, logs
to `/var/log/<unit>.log`, and records `enable`. The container's first process starts every
enabled unit and then sshd, so `docker stop` / `docker start` is a power cycle that the
node comes back from by itself, as it would under systemd.

## The app

[examples/lab_app](https://github.com/march-language/march/tree/main/examples/lab_app)
is a three-role choreography over two pools:

```march
@[endpoints]
protocol Order do
  role Stock needs IO.Mut
  role Ledger needs IO.Console
  loop do
    want: Shop -> Stock : Int
    choose by Stock:
      have -> Stock -> Shop : String
              book: Stock -> Ledger : Int
              booked: Ledger -> Shop : String
      out  -> Stock -> Shop : String
              skip: Stock -> Ledger : Int
              stop
    end
  end
end
```

| Role | Bound to | Placed |
|---|---|---|
| `Shop` | initiated by the `ingress` pool's hook | lab-1 |
| `Stock` | a function, `Work.stock` | every node of the `work` pool: lab-2, lab-3, lab-4 |
| `Ledger` | an actor that keeps a running total, `Work.LedgerActor` | `{ on = "books", count = 1 }`: one of lab-3, lab-4 |

The topology's `[control]` section makes the hosts labelled `control` (lab-2, lab-3, lab-4)
control-plane candidates; one of them is meant to lead.

Nodes authenticate each other with one shared cluster secret by default. `LAB_AUTH=certs`
makes an operator key first (`forge cluster keygen`), so `forge host init` issues every
node a certificate naming the roles its pool offers and initiates.
It is not the default yet because of a finding below (sessions hang in certificate mode).

The `ingress` hook starts sessions continuously and writes counters to
`/var/lib/march/lab_app/lab-stats` on lab-1 every second: sessions `started`,
`finished`, `drained` (ended at a loop boundary by a hot deploy), `refused` (no offer
would take a role), `failed` (anything else), `skipped` (too many already running), and
each reply it saw by branch, tag and node (`have:stock-v1@work-lab-3`). The lab paces it
through `/var/lib/march/lab_app/lab-traffic` (`<every ms> <most in flight>`, `0` pauses).
Every node writes its live heap objects to `/var/lib/march/lab_app/lab-probe` every 5 s.

## Scenarios

| Scenario | What it does | What it asserts |
|---|---|---|
| `deploy` | New hosts; `forge host init --env lab`; the first `forge deploy --env lab --via ssh` (every pool restarts onto a base image cross-built for the hosts' target, then the topology is pushed to each node) | `Order.Ledger` is offered on exactly one books host; Stock replies come back from all three work hosts and Ledger totals from the Ledger host; once the cluster has formed no session fails or is refused (sessions that never end are noted as a finding); `forge topology status` says every node runs what forge deployed |
| `hot_role` | Changes the Stock reply's tag and runs `forge deploy` on the cluster backend (through the control plane); a stand-in `ssh` records any attempt | a leader answers; the plan needs no ssh; the release completes; the new tag comes back from every work host; no session fails or is refused during the rollout; the old tag stops; a counter the new code keeps in the node's Vault keeps counting (the patch shares the old code's runtime) |
| `restart_persist` | A hot deploy, then `docker restart` of lab-2 | lab-2 answers with the new tag from its first reply after the restart (its persisted patches are restored before its offers open); it reports the pushed topology; `forge topology status` says it runs what forge deployed |
| `failover` | `docker stop` of the host offering `Ledger`; later `docker start` | the other books host offers it within the SWIM suspect timeout (3 s) plus a margin; totals resume; the returning host does not take it back inside the 15 s settle period; one host offers it at the end |

Each scenario's log is `LAB_DIR/logs/scenario-<name>.log`, and every forge run's output
is kept as `LAB_DIR/logs/forge-<n>-<scenario>.log`. Notes a scenario makes along the way
(how long a failover took, which nodes it restarted) are printed at the end.

### Expected failures and workarounds

A scenario that fails because of a filed bug is marked expected-fail: its file says
`LAB_XFAIL=<the todo>` and `LAB_XFAIL_AT=<the failure's text>`, and `run.sh` reports
that failure as `XFAIL` with the todo while the run still succeeds. Any other failure of
the scenario is a `FAIL`. If it passes, `run.sh` reports `XPASS` and fails, so the marker is removed once
the bug is fixed. A scenario that cannot run in this lab's configuration (one that
needs certificates, with a shared secret) is reported `SKIP`.

Every node grows by about 1 MB a second on its own today, and more with each session, and
the hosts are capped at `LAB_HOST_MEMORY`. So each scenario after `deploy` starts by
deploying the lab again from nothing when any node is no longer running or uses more than
`LAB_RESET_MB` (default 500), and says so in the notes. (Restarting the nodes instead does
not work today: see the findings.) Traffic is one session every two seconds outside
`deploy`, and `restart_persist` pauses it while forge builds its patch. `run.sh` also notes every OOM kill the Docker VM logged during a
scenario.

## Findings

What the lab has found so far, each filed with its repro:

- [`2026-10-05-lab-topology-reread-closes-ctl-control.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-05-lab-topology-reread-closes-ctl-control.md):
  a pushed topology closes `Ctl.Control` on every node, so after the first deploy the
  control plane has no leader for good. `hot_role` is
  expected-fail on it; `restart_persist` deploys `--via ssh` meanwhile.
- [`2026-10-05-lab-restarted-node-offers-invisible.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-05-lab-restarted-node-offers-invisible.md):
  a restarted node's offers are open but no initiator sees them ("no access point is
  registered"). `restart_persist` is expected-fail on it, at its last step.
- [`2026-10-05-lab-rejoining-node-offers-count-role-at-once.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-05-lab-rejoining-node-offers-count-role-at-once.md):
  a restarted node offers a `count = 1` role a second after it starts, so two nodes offer
  it for the settle period. `failover` is expected-fail on it.
- [`2026-10-05-lab-cert-mode-offer-to-offer-session-hangs.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-05-lab-cert-mode-offer-to-offer-session-hangs.md):
  a session whose two offered roles (Stock, Ledger) are on different hosts can hang for
  ever, nearly always in certificate mode and occasionally with a shared secret.
- [`2026-10-05-lab-leaderless-agents-leak.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-05-lab-leaderless-agents-leak.md):
  with no leader, every node grows by ~13k heap objects a second with no traffic at all.
- [`2026-10-05-lab-simultaneous-restart-memory-burst.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-05-lab-simultaneous-restart-memory-burst.md):
  nodes restarted together can each allocate ~1 GB in 30 s and be OOM-killed.
- [`2026-10-04-lab-control-topology-step-races-report.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-04-lab-control-topology-step-races-report.md):
  a release's topology step halts when the Agent checks the node's report before the
  placement loop has re-read the topology.
- [`2026-10-05-lab-forge-cluster-deploy-retry-and-leader-change.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-05-lab-forge-cluster-deploy-retry-and-leader-change.md):
  a halted first `forge deploy` records nothing (the retry restarts every node again), and
  following a release gives up on `ERR no_leader`.
- [`2026-10-04-lab-control-wiring-none-ctor-ambiguous.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-04-lab-control-wiring-none-ctor-ambiguous.md):
  a protocol branch labelled `none` breaks the control-plane wiring of a `[control]` app;
  the lab's branch is called `out`.
- The per-session leaks already filed
  ([`2026-10-01-session-node-vault-tables-leak.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-10-01-session-node-vault-tables-leak.md),
  [`2026-09-28-linux-per-session-memory-growth.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-09-28-linux-per-session-memory-growth.md)):
  at a session every 300 ms the first lab nodes reached 1.5-2 GB in four minutes, so the
  lab paces traffic at one session a second.

## Security

The control port (7947) and sshd are published on `127.0.0.1` only, and the hosts sit on
a private Docker network. Keep it that way: the lab's deploy and operator keys live in
`LAB_DIR` in the clear, and its hosts accept anything signed with them. The control
API's write verbs are authenticated and an activation is bound to the bytes the operator
signed (#776, #778), but certificate rollback after a restart (#779) was still open when
the lab was written.
