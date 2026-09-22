# Groundwork for the distributed-authority-and-deploys plan

**Date:** 2026-09-21
**Status:** Specced; nothing built
**Parent:** [2026-09-21-distributed-authority-and-deploys-plan.md](2026-09-21-distributed-authority-and-deploys-plan.md)
(the design; section and decision numbers below refer to it)

The parent plan's build order starts at "fix the migration bugs" and "unforgeable
references". Both, and most later steps, assume small pieces of infrastructure that do not
exist yet, and one measurement that can reorder the whole plan. This file specs those
pieces so they can land first, each as its own PR, without any of the design landing with
them. Nothing here changes user-visible language semantics except G3 (a new typecheck
rule that only the stdlib can trip) and G2's test.

| # | Item | Size | Blocks |
|---|---|---|---|
| G1 | Performance measurement: boundary-call cost, and the per-proc epoch read | 1 day | steps 6–12; may reorder the plan |
| G2 | Pin the `Cap` unification fact with a test | 1 hour | step 2 (D31) |
| G3 | Stdlib-only builtins | ½ day | steps 2 and 6 |
| G4 | forge TOML parser: positions, no silent drops | 1 day | step 7 |
| G5 | `Project.entry`: one entry-file rule | 2 hours | steps 7, 8, 10 |
| G6 | `forge/lib/procs.ml`: process supervision | 1–2 days | steps 3, 8 |
| G7 | Extract the multi-host deploy drivers | ½ day | steps 8, 10 |
| G8 | Fold two findings into the running migration-bug fix | (message) | step 1 |
| G9 | File the parent plan's todos and commit | 1 hour | everything |

G1 first, because its result can change the order of everything after it. G2–G7 are
independent of each other and of G1.

---

## G1. Measure the boundary-call cost (parent II.7)

**Why.** D8 makes hot-reloadable builds the production builds. Every call across a
hot-swap boundary already goes through `march_dispatch_enter`/`leave`
(lib/tir/llvm_emit_call.ml:372-456), and D33 adds a TLS read plus a `march_proc` field
load to resolve the caller's epoch. If the existing cost is large, Model B (the ORC JIT,
specs/todos/2026-07-31-p2-runtime-hot-code-reloading.md) has to precede steps 6–12.
Nobody has measured it since the boundary scheme landed.

**What.**

1. Two programs: `bench/list_ops.march` (exists; closure/HOF-heavy) and a new
   `bench/actor_ping.march`: two actors exchanging 1,000,000 messages through
   `send`/`on`, with the handler calling one module-level helper (so every message crosses
   the actor-dispatch boundary and one ordinary boundary).
2. Build each four ways, all `--opt 2`, all compiled (never interpreted; see
   specs/benchmarks.md): plain; `--hot-reload`; `--hot-reload` with a prototype
   `march_dispatch_enter_unit` that reads `march_sched_current()->code_epoch` (add the
   field to `march_proc`, runtime/march_scheduler.h:198, initialised to 0, nothing else
   writes it) and passes it to `enter_gen`; and the same with the read hoisted out of
   the actor loop (read once per message in `actor_green_thread`,
   runtime/march_runtime.c:3357, passed to the dispatch call). The fourth variant is the
   fallback II.7 names if the third is measurable.
3. Five runs each, on an idle machine (check the load average first; a loaded box
   invalidates the numbers), reporting median wall time. Run the plain variant first and
   discard it: the first timed variant pays a warm-up penalty.

**Acceptance.** A table in `specs/progress/` with the four medians per benchmark, and
one sentence per threshold from the parent's II.7: `--hot-reload` versus plain above
about 10 % on `list_ops` → Model B first; `enter_unit` versus `enter` measurable on
`actor_ping` → hoist the read. The prototype code is not merged; the numbers are.

---

## G2. Pin the `Cap` unification fact

**Why.** The parent's D31 was written assuming `Cap(IO.NetListen)` would not unify with
`Cap(IO)`. Checked on 2026-09-21: it does; a narrowed cap passes where `Cap(IO)` is
expected and the checker only emits the least-privilege hint. D31 still holds because a
signature `Cap(IO)` position counts toward the callee's own capability closure
(`env.own_cap_closures`, lib/typecheck/typecheck_env.ml), so a narrowed caller that
reaches such a function carries `IO` in its closure and fails the grant walk. That is the
load-bearing fact, and nothing tests it in that shape.

**What.** One test in test/test_cap_ceiling.ml (or the file that holds
`check_main_grant` cases): a module with `fn wants_io(c : Cap(IO))`, a helper
`fn narrow(c : Cap(IO.NetListen)) do wants_io(c) end`, and `fn main(c :
Cap(IO.NetListen))` calling `narrow`. Expect the grant error naming the chain
`main → narrow → wants_io` and the cap `IO`. A second case with `main(c : Cap(IO))`
passes.

**Acceptance.** Both cases green; the test's comment states the fact in one line so the
next reader does not re-derive it.

---

## G3. Stdlib-only builtins

**Why.** Two things in the parent need builtins that user code cannot call: the raw
forging builtins once `pid_of_int`, `actor_whereis` and friends take an
`Actor.Introspect` cap (II.1), and `epoch_hold`/`epoch_release` (II.4.4). Nothing in the
typechecker gates a builtin on the caller's module today (grep for
`stdlib_only`/`prelude-only` finds nothing; the nearest precedent is Check 6 in
lib/typecheck/typecheck_caps.ml, which restricts proof-cap minting to the declaring
module).

**What.**

1. A set `Typecheck_builtins.stdlib_only : string list` next to `builtin_cap_table`
   (lib/typecheck/typecheck_builtins.ml:91). Initially empty; II.1 and II.4.4 populate it.
2. A check in `check_module_needs`' decl walk (typecheck_caps.ml:263), beside Check 1b:
   a call or value reference to a name in the set from a module whose source path is not
   under the stdlib root is an error: ``` `pid_of_int` is internal to the standard
   library; use `Actor.list(cap)` (see Actor.introspect) ```. The suggestion text is a
   second field of the set entry. "Under the stdlib root" is the same predicate the
   diagnostic filter uses to decide a span is stdlib (bin/main.ml, the filter the parent
   warns about), factored into one function so the two cannot drift.
3. The REPL path (`check_module_with_env`) runs it too; the REPL is user code.

**Acceptance.** With a throwaway entry in the set, a user program calling it fails with
the message, a stdlib module calling it passes, and `forge search` still lists the
builtin (search is not the gate). Then empty the set again; the mechanism lands with no
entries.

---

## G4. forge TOML parser: positions, and no silent drops

**Why.** `forge/lib/toml.ml` tracks no line numbers, swallows a `Parse_error` per line
by dropping the pair (toml.ml:173), ignores a `[section` header with no `]`
(:157, :163), and no consumer rejects an unknown key. `forge topology check` has to say
`topology.toml:12: unknown key 'replica'`; today it could only say "something is wrong".
This also fixes `forge.toml`, where a misspelled key has always been a silent no-op.

**What.**

1. `Toml.value` and each `(key, value)` pair carry a `line : int`; sections carry the
   header's line. `parse` returns them; the accessors (`get_section`, `get_string`,
   `get_table`, `get_string_list`, `get_all_sections`) keep their signatures and gain
   `_at` variants that also return the line.
2. A malformed line or unterminated header is a `Parse_error` with the line number,
   surfaced by `Project.load_from_dir` as `forge.toml:<line>: <msg>` (project.ml:342).
   No pair is dropped silently.
3. `Toml.check_keys ~section ~known doc` returns `(key, line)` for every key not in
   `known`. `Project.load_from` calls it for every section it owns (`[package]`,
   `[project]`, `[deps]`, `[hot-reload]`, `[[hot-reload.env]]`, `[ffi]`, …) and
   **warns** on unknown keys in this PR (an error would break every project with a stray
   key at once); the topology sections, when they arrive, make it an error from day one.
4. Inline tables (`{ role = "...", capacity = 8 }`) and arrays of inline tables must
   parse, since the topology's `[roles]` and `hosts` use them; check the existing
   `InlineTable` support covers nested arrays inside inline tables and add it if not.

**Acceptance.** forge/test/test_forge.ml cases: a bad line reports its number; an unknown
`[package]` key warns with the line; `hosts = [{ host = "a", labels = ["db"] }, "b"]`
round-trips. Existing forge tests unchanged.

---

## G5. One entry-file rule

**Why.** The default entry file is computed in four places and they disagree:
`lib/<name>.march` in forge/lib/cmd_build.ml:718, cmd_check.ml:31 and cmd_run.ml:54;
`src/<name>.march` in cmd_deploy_hot.ml:1160 and :1410. A project that works with
`forge build` can fail `forge deploy hot` with "no such file", and the topology adds a
fifth consumer (the generated `main` goes into the entry module).

**What.** `Project.entry : project -> (string, string) result`: `proj.entrypoint` if
set; else the first of `lib/<name>.march`, `src/<name>.march` that exists; else an error
naming both. All five sites call it. `forge deploy hot`'s behaviour changes only for
projects that have `lib/<name>.march` and not `src/<name>.march`, which today fail.

**Acceptance.** A forge test creating each layout and asserting all four commands agree
(`build`, `check`, `run --dry-run` if there is one, and the deploy path's build step via
`Cmd_deploy_hot.build_so` on a project with no server).

---

## G6. `forge/lib/procs.ml`: process supervision

**Why.** forge runs exactly one foreground process per command, through `Sys.command`
on a shell string (cmd_run.ml:103, cmd_test.ml:45). Three parent features need several
long-lived processes started, watched and stopped together: `forge run --processes`
(II.3), the `local` reconciler backend (II.6), and `forge test --upgrade-from` (II.8).

**What.** A module with:

- `spawn : name:string -> env:(string * string) list -> argv:string array ->
  log:log_sink -> proc`, via `Unix.create_process_env` (no shell), stdout and stderr
  captured to per-process log files under `.forge/run/<name>.log` and, with
  `--follow`, multiplexed to the terminal with a `[name]` prefix.
- `wait_any`, `wait_all ~timeout`, `stop : proc -> grace_ms:int -> unit` (SIGTERM,
  then SIGKILL after the grace), and `stop_all` in reverse start order.
- A process group: forge puts every child in its own process group and, on its own
  SIGINT/SIGTERM or on any child's unexpected exit when `--fail-fast`, stops the rest.
  This is the part that is easy to get wrong and the reason it is one module.
- `free_port : unit -> int` (bind port 0, read it back, close): the launcher assigns
  cluster ports and `MARCH_HOT_RELOAD_SOCKET` paths per process.

No topology knowledge here; the launcher that decides *what* to run comes with step 3.

**Acceptance.** A hermetic forge test (same shape as forge/test/test_build_check.ml,
which the dune file documents) starting three `sleep`-style March programs, killing one,
and asserting `--fail-fast` stops the other two within the grace period and their logs
are complete. Sandbox note from the repo's memory: `kill` from a sandboxed test can be a
no-op; the test must re-check with `pgrep`-equivalent (`Unix.kill pid 0`) rather than
trust the exit code of the kill.

---

## G7. Extract the multi-host deploy drivers

**Why.** `rolling_deploy` and `simultaneous_deploy` are local closures inside
`deploy_env` (forge/lib/cmd_deploy_hot.ml:1426-1432), so nothing else can run a step on
N hosts with a health gate between them. `forge deploy --plan`, `forge host init` and the
`ssh` backend all need exactly that. "Simultaneous" is also sequential today (`List.map`,
:1420), which is fine but should be named honestly.

**What.** `forge/lib/hosts.ml`:

- `type host = { name : string; ssh : string; socket : string; pubkey : string; labels
  : string list }` built from `[[hot-reload.env]]` today and from the topology overlay
  later (one constructor each).
- `run_on : strategy:[ `Rolling of health | `All ] -> hosts -> (host -> ('a, string)
  result) -> ('a, string) result list`, where `health` is the existing
  `http_health_check` closure. `Rolling` stops at the first failure; `All` runs every
  host and reports each. Both sequential; the type leaves room for a concurrent `All`.
- `deploy_env` becomes: build the host list, fetch the shared epoch, `run_on` with
  `deploy_one`. Canary is `run_on` twice. Behaviour is unchanged; the extraction is the
  whole PR.

**Acceptance.** The existing deploy tests pass unchanged; a new unit test drives `run_on`
with a fake step and asserts the stop-on-failure and report-all semantics.

---

## G8. Two findings for the running migration-bug fix

Not code in this repo: a message to the session working on
"Fix HCR migration: queued msgs hit new code+old state". It was spawned before two
things were known:

1. **A fourth bug.** The migrate message is sent under the actor's overflow policy; when
   the mailbox is full it is dropped and freed by the dtor
   (runtime/march_runtime.c:4724 and the DROPPED handling near :4895), so the actor never
   migrates. The marker must bypass overflow policies.
2. **The shape of the fix.** The parent's II.4.6 specifies the activation order (publish
   with `live = 0`, marker into every user mailbox as a `march_mbox_node` flag, then flip
   `live`/`current`) and the per-actor `code_epoch` on `march_proc` read by a
   `march_dispatch_enter_unit` in the actor loop. The bug fix should be the first slice of
   that (per-actor pinned version, moved at the marker), not a patch the unified model
   later replaces. Also fold in the `publish_epoch` epoch-after-`live` ordering fix
   (runtime/march_dispatch.c:364).

**Acceptance.** The session acknowledges the scope; its progress entry lists four bugs.

---

## G9. File the todos and commit the plan

The parent plan is uncommitted, and the repo's convention is one `specs/todos/` file per
open item. File: one todo per parent build step (2–12; step 1 is the running task),
one per groundwork item G1–G7, and one for the four bugs (cross-linking the running
task). Each todo carries its `[P1]`–`[P3]` tag, links its parent section, and lists its
acceptance test. Commit the two plans and the todos together, with a CHANGELOG
`### Documentation` line.

---

## What is deliberately not groundwork

- **The self-link in ClusterNode, the `Entry` alias, parameterised `init`.** They are
  prerequisites of step 3, but they are design work with user-visible effects, so they
  stay in step 3 where their tests live.
- **Model B itself.** G1 decides whether it comes first; it is not started on
  speculation.
- **Certificates, link integrity.** Step 11; nothing earlier depends on them.
