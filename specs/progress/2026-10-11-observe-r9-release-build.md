# Observe R9: `forge release build` and the `bin/<app>` launcher

**Landed 2026-10-11.** Item R9 of `specs/plans/2026-09-28-observe-recon-shell-plan.md`
(design `specs/2026-09-24-observe-recon-shell-design.md` section 7.2).

- `forge release` is a `Cmd.group`; its default term is the old guarded tag flow
  (`forge release --bump minor` is unchanged), `forge release tag` is the same,
  and `forge release build [--target T] [--profile release|debug] [--tar]` is new
  (`forge/lib/cmd_release_build.ml`).
- Layout: `bin/<app>`, `lib/<app>` (+ `.hcr_manifest` / `.schemas.json` from a
  `--compile-so` build of the same source when `[hot-reload]` is set, since the
  baseline build does not write them), `lib/patches/`, `etc/{topology.json,policy,
  debug_policy,shell_policy,pubkey,env}`, `RELEASE`. Policies start empty;
  `release/etc/*` in the project overrides them. `etc/env` carries
  `MARCH_STOP_GRACE` (the topology's soft drain deadline).
- Launcher (`forge/lib/release_launcher.ml`, generated POSIX sh, `shellcheck`-clean):
  `start daemon stop restart pid version ping status eval rpc shell observe diagnose`.
  Never `eval`s input, `etc/env` is parsed as data, pidfile written by temp + `mv`,
  refuses to start/stop as a user other than the release directory's owner.
  Sockets: `run/<app>.sock` (reload), `.shell`, `.observe`, the same pair forge uses.
- `forge topology gen systemd --release-dir DIR`: `ExecStart=DIR/bin/<app> start`.
- `Cmd_deploy_hot.build_so_for` takes an optional target (cross release builds).

**Host requirements:** POSIX `sh`, `awk`, `sed`, `ls`, `id`; for `ping`/`status`/
`version`'s epoch and the `daemon` readiness wait, one of `nc -U`, `socat`, `python3`.

**Not done / known limits:** `eval` is a stub that says so (there is no fresh-process
evaluator in a bundle yet; `forge eval` does not exist). The runtime has no
`MARCH_CONTROL_SOCKET` or `MARCH_CRASH_DUMP`, so the launcher sets neither.
The persisted patch stack lives under `$HOME/.march/cas/hcr_state` (the runtime's
convention), not `lib/patches/`, which is only reserved. A drained `stop` is
`forge deploy --drain` (sh cannot sign).

**Tests:** `forge/test/test_release_build.ml` (real binaries: build, `daemon`,
`ping`, `version` shows `epoch=1`, `status`, `stop`, `restart`; SIGKILL escalation;
hot-reload sidecars; cross build `linux/amd64` yields an ELF; shellcheck; CLI shape)
and `forge/test/test_topology.ml` ("gen systemd --release-dir").
