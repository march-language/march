# `forge/lib/procs.ml`: process supervision

**DONE 2026-09-22.** G6 of
[specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md).

forge ran exactly one foreground process per command, through `Sys.command`
on a shell string. `forge run --processes` (II.3), the local reconciler
backend (II.6) and `forge test --upgrade-from` (II.8) need several long-lived
processes started, watched and stopped together. `Procs` is that module. It
has no topology knowledge and no caller yet; the launcher comes with build
step 3.

## API (forge/lib/procs.mli)

- `spawn ~name ~env ~argv ~log`: no shell; `argv.(0)` resolved on PATH;
  the current environment plus `env`; stdin `/dev/null`; stdout and stderr to
  `<log.dir>/<name>.log`. With `log.follow = Some emit`, output goes through
  a pipe that forge tees to the log and to `emit` as `[name] line`. A program
  that cannot be executed exits 127 with the reason in its log.
- `wait_any`, `wait_all ~timeout`.
- `stop p ~grace_ms`: SIGTERM to the process group, SIGKILL after the grace,
  returns once reaped. `stop_all` stops in reverse start order.
- `supervise ?fail_fast ~grace_ms procs`: watches until all have exited.
  forge's own SIGINT/SIGTERM stops them all; with `fail_fast`, so does any
  exit that `stop` did not ask for. Restores the previous signal handlers.
- `free_port ()`: bind 127.0.0.1:0, read the port back, close.
- `default_log_sink ~root` is `.forge/run/`, not following.

## Deviation from the plan

The plan said `Unix.create_process_env`. It cannot make the child lead its
own process group, which the same section requires (so that a terminal
Ctrl-C reaches forge only and `stop` can signal a child's whole tree). `spawn`
uses `fork` + `setsid` + `execvpe` instead. It is still shell-free.

## Tests

`forge/test/test_procs.ml`, a new hermetic executable (the `test_entry_rule`
stanza: the just-built `march` with the staged runtime and stdlib). It
compiles a March program that prints `line 1` to `line 50`, then `ready`,
then sleeps.

| Case | Asserts |
|---|---|
| fail-fast stops the rest, logs complete | three copies; one SIGKILLed from outside; `supervise ~fail_fast:true ~grace_ms:2000` returns in under 2 s; the killed one reports SIGKILL, the other two SIGTERM; all three gone by `Unix.kill pid 0` (ESRCH); every log holds all 50 lines |
| without fail-fast the rest keep running | a `true` exiting does not stop the sleeper; `stop_all` reaps it |
| forge's own SIGTERM stops everything | a child sends SIGTERM to the test process; both sleepers are stopped |
| stop SIGKILLs after the grace | a shell that traps TERM is SIGKILLed after 300 ms |
| follow prefixes lines and still logs | stdout and stderr lines prefixed `[echo] `, an unterminated last line flushed, raw log intact |
| an unrunnable program exits 127 | with the reason in the log |
| free_port | the port binds |

7 of 7 (25 s). Perturbation: `stop` without its SIGTERM fails the first case
("stopped within the grace period (4.05s)").

Liveness is checked with `Unix.kill pid 0`, never by a kill's return value,
because a sandboxed `kill` can succeed and deliver nothing.
