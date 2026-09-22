# Multi-host deploy drivers extracted into `forge/lib/hosts.ml`

**DONE 2026-09-22.** G7 of
[specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md).

`rolling_deploy` and `simultaneous_deploy` were local closures inside
`Cmd_deploy_hot.deploy_env`, so nothing else could run a step on N hosts with a
health gate between them. `forge deploy --plan`, `forge host init` and the ssh
reconciler backend all need that.

## What landed

- `Hosts.host = { name; ssh; socket; pubkey; labels }`, built by
  `of_hot_reload_env` (one `[[hot-reload.env]]` entry) and `of_flat_config`
  (the flat `[hot-reload]` host, named "default"). The topology overlay adds
  its own constructor later; `labels` is empty until then.
- `Hosts.run_on ?on_skip ~strategy hosts step`, returning each attempted host
  with its result:
  - `` `Rolling health ``: one host at a time; stops at the first failed step or
    failed health gate. A failed gate is that host's
    `Error "health_check_failed"`. Skipped hosts go to `on_skip` (default:
    the existing "skipping <host> (prior step failed)" line) and are not
    reported.
  - `` `All ``: every host, each reported. Sequential, as before. The old
    name "simultaneous" described no concurrency (`List.map`); the
    `[hot-reload] strategy = "simultaneous"` setting keeps its name.
- `deploy_env` now builds the host list, fetches the shared epoch, and calls
  `run_on` with `deploy_one`; canary is `run_on` `` `All `` on the canary hosts,
  the PING window, then `run_on` `` `All `` on the rest. `deploy_one` takes a
  `Hosts.host`. The health gate is the same `http_health_check` with the same
  messages.

Behaviour is unchanged. One difference in the returned list, invisible to
users: a rolling health failure used to record the host twice (its `Ok`, then
`Error "health_check_failed"`); it is now recorded once, as the error. Only
errors were ever counted or printed, so the output is the same.

`run_status` keeps its own host selection (with no `--env` it queries every
`[[hot-reload.env]]` entry, where `deploy_env` uses the flat host); unifying
the two would change behaviour, so it is left for the topology work.

## Tests

forge/test/test_forge.ml, group `hosts` (5 cases, fake step, no ssh):
`` `All `` runs and reports all three hosts when the middle one fails;
`` `Rolling `` stops after the failure, reports two, skips the third, and asks
the gate only after a success; a failed gate stops it and is the host's
result; all succeed; both config constructors. The existing forge suites pass
unchanged; no existing test drives `deploy_env` against real servers.
