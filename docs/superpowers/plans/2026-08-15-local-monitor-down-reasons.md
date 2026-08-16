# Local Monitor Down Reasons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make local monitors deliver `Down(monitor_ref, target_pid, reason)` identically in the interpreter and compiled runtime.

**Architecture:** Replace the compiled runtime’s side-band `down_count` with a reserved boxed control message carrying the monitor reference, target Pid, and a reason payload. Thread a terminal-reason enum through compiled death paths, and update the interpreter’s existing `Down` value to the same three-field shape. Keep Down delivery outside user mailbox shedding policies.

**Tech Stack:** OCaml interpreter/typechecker/TIR lowering, C11 runtime and scheduler, March stdlib/docs, Alcotest and native March fixtures, dune.

**Spec:** `docs/superpowers/specs/2026-08-15-local-monitor-down-reasons-design.md`

## Global Constraints

- Use `--root .` on every dune command.
- Do not use `git stash`; compare edited files by copy if red/green verification requires reverting.
- After runtime C edits run `dune build --root . @bin/warm-cache`; after stdlib edits run `dune build --root . @install`.
- Down is control-plane traffic and must bypass bounded-mailbox drop policies.
- Update the todo/progress ledger, Unreleased changelog, and both language-doc copies where the actor monitor section exists.
- Use explicit file names with `git add`; never use `git add -A`, `.`, `*`, or `-am`.

## File Map

- Modify `runtime/march_runtime.c`: terminal-reason storage, reserved Down construction, monitor delivery, dead-target monitor behavior, and mailbox-size accounting.
- Modify `runtime/march_scheduler.c` and `runtime/march_scheduler.h` only if the control-plane enqueue needs a distinct scheduler API; preserve ordinary send semantics.
- Modify `lib/eval/eval.ml`: interpreter Down shape and reason constructors.
- Modify `lib/typecheck/typecheck.ml`, `lib/tir/llvm_builtins.ml`, and `lib/tir/llvm_toplevel.ml` as needed to register the reserved Down ABI and its reason constructors without colliding with user actor-message tags.
- Modify `share/march/actor.march` and `stdlib/dist_link.march` only for the public local monitor/reason surface and documentation alignment.
- Modify `test/test_supervision.ml`, `test/test_stdlib_suite.ml`, and add a native fixture under `test/native/` for compiled payload assertions.
- Modify `specs/todos/2026-08-12-monitor-down-carries-no-reason.md`, add a progress entry under `specs/progress/`, modify `CHANGELOG.md`, and update `docs/actors.md` plus `specs/lang/actors.md` if their monitor sections differ.

### Task 1: Establish failing interpreter and compiled witnesses

**Files:**
- Modify: `test/test_supervision.ml`
- Modify: `test/test_stdlib_suite.ml`
- Create: `test/native/actor_monitor_down_reason.march`
- Modify: the owning test registration files discovered from `test/dune` and native fixture manifests

**Interfaces:**
- The tests require interpreter `Down` values shaped as `VCon ("Down", [VInt ref; VInt target; reason])`.
- The native fixture requires a watcher actor that calls `receive()` and pattern-matches `Down(ref, target, reason)`.

- [x] **Step 1: Write the failing interpreter assertions.**

Change the existing `test_down_message_format` assertion to require the monitor ref, target pid, and a reason constructor/value. Add separate cases for explicit kill and crash so the test distinguishes `Killed` from `Crash("bang")`; add an already-dead target case that checks the documented fallback reason.

- [x] **Step 2: Run the focused interpreter tests and verify the expected failure.**

Run: `dune exec --root . test/run_tests.exe -- --help` to identify the repository’s test executable if needed, then run the exact supervision/stdlib test target from `test/dune` with its Alcotest filter.

Expected: the new assertions fail because the interpreter currently emits `Down(ref, reason)` and strings rather than the three-field reason value.

- [x] **Step 3: Write the native fixture before runtime changes.**

Create a small actor program with a worker that panics under a handler and a watcher that receives `Down(ref, target, Crash(msg))`; print `ref`, target identity, and the reason tag. Include a second worker killed explicitly and assert `Killed`. The fixture must fail on the current compiled runtime because it only exposes mailbox depth and drops unknown control values.

- [x] **Step 4: Run the fixture and record the red failure.**

Build/run it through the repository’s native actor fixture driver after `dune build --root . @bin/warm-cache`. Expected: no matching three-field Down value is observed.

- [x] **Step 5: Commit only the failing witnesses.**

Run `git diff --check`, then stage the named test files and commit with `test(actor): pin local monitor down payload`.

### Task 2: Implement interpreter parity

**Files:**
- Modify: `lib/eval/eval.ml`
- Modify: `test/test_supervision.ml`
- Modify: `test/test_stdlib_suite.ml`

**Interfaces:**
- Add an interpreter reason representation matching `Normal | Killed | Crash(String)`.
- Queue `Down(ref, target_pid, reason)` for both death and already-dead monitor registration.

- [x] **Step 1: Implement the smallest reason constructor representation.**

Use `VCon ("Normal", [])`, `VCon ("Killed", [])`, and `VCon ("Crash", [VString msg])` inside the `Down` payload. Preserve the existing crash message and map `crash_actor ... "killed"` to `Killed` only at the explicit kill call site rather than guessing from arbitrary strings.

- [x] **Step 2: Run the focused interpreter tests.**

Run the exact Alcotest filters from Task 1. Expected: the new interpreter payload tests pass while unrelated tests remain unchanged.

- [x] **Step 3: Refactor only duplicated message construction.**

Extract one local helper for constructing the `Down` value and use it for death delivery and already-dead registration. Re-run the same focused tests.

- [x] **Step 4: Commit the interpreter implementation.**

Stage `lib/eval/eval.ml` and the two test files explicitly and commit with `feat(actor): add reasoned interpreter monitor down`.

### Task 3: Implement compiled reason plumbing and control-plane delivery

**Files:**
- Modify: `runtime/march_runtime.c`
- Modify: `runtime/march_scheduler.c` and `runtime/march_scheduler.h` if required for control-plane enqueue
- Modify: `runtime/march_runtime.h`
- Modify: `lib/tir/llvm_builtins.ml`, `lib/tir/llvm_toplevel.ml`, and `lib/typecheck/typecheck.ml` for the reserved ABI/type surface

**Interfaces:**
- Define a C terminal reason enum and reason-aware death entry point, e.g. `do_actor_death(void *actor, march_death_reason reason, const char *message)`.
- Store the terminal reason/message in `march_actor_meta` before detaching monitors.
- Construct a boxed reserved Down message with fields `(monitor_ref, target_pid, reason)` and enqueue it through a control-plane scheduler path that cannot be dropped by user mailbox policy.

- [x] **Step 1: Add the reserved ABI constants and type registrations.**

Choose tag values outside the user actor-message range, register the Down/reason constructors in the compiler’s builtin constructor metadata, and ensure the generated match code can inspect the boxed message. Add compile-time checks that the reserved tag cannot be allocated by ordinary constructor numbering.

- [x] **Step 2: Run the native fixture before the runtime path is wired.**

Run the fixture from Task 1 after `dune build --root . @bin/warm-cache`. Expected: it still fails, now demonstrating that type/lowering registration alone does not deliver a message.

- [x] **Step 3: Add reason storage and thread reasons through every death caller.**

Pass `Killed` from `march_kill`, `Crash` plus the panic text from the supervised crash-trap branch, and `Normal` from the normal loop-exit path. Set the reason before `registry_retire_actor`; keep supervisor restart behavior unchanged.

- [x] **Step 4: Replace `down_count` with control-plane Down enqueue.**

Construct one message per monitor node, retain/copy the target Pid and crash string according to the existing RC contract, enqueue it even when the watcher’s user mailbox is at capacity, and remove `down_count` from `mailbox_size`. Ensure already-dead `march_monitor` emits the stored reason and target identity.

- [x] **Step 5: Run the native fixture and focused compiled tests.**

Run `dune build --root . @bin/warm-cache`, then the native actor monitor fixture and the compiler/codegen tests owning monitor builtins. Expected: the fixture observes both `Killed` and `Crash(message)` with the correct monitor ref and target Pid.

- [x] **Step 6: Commit the compiled runtime implementation.**

Run `git diff --check`; stage only the runtime/compiler files and commit with `feat(actor): deliver reasoned compiled monitor downs`.

### Task 4: Add mailbox-limit and lifecycle regression coverage

**Files:**
- Modify: `test/test_stdlib_suite.ml`
- Modify: `test/test_supervision.ml`
- Modify: `test/native/actor_monitor_down_reason.march`
- Modify: the relevant test manifests

**Interfaces:**
- A watcher configured with `drop_new` at capacity must still receive Down.
- `mailbox_size` must count the actual queued Down message exactly once.

- [x] **Step 1: Add the bounded-mailbox failing regression test if the control-plane path is not yet covered.**

Fill the watcher mailbox to its configured limit, kill the monitored actor, and assert that the watcher’s next received message is Down rather than an overflow drop.

- [x] **Step 2: Run the focused test and verify it passes.**

Run the relevant stdlib/native test target. Expected: the test passes with one Down message and no side-band count.

- [x] **Step 3: Add repeated-monitor and already-dead assertions.**

Assert that multiple monitors receive distinct refs and the same target identity/reason, and that registering after death immediately delivers the stored reason.

- [x] **Step 4: Run the actor test drivers owned by `test/dune`.**

Run the monitor/supervision Alcotest executables, not a neighboring driver; check each exit code directly without piping output.

- [x] **Step 5: Commit the regression coverage.**

Stage explicit test files and commit with `test(actor): cover monitor down delivery semantics`.

### Task 5: Update docs, ledger, and verify the full change

**Files:**
- Modify: `docs/actors.md`
- Modify: `specs/lang/actors.md`
- Modify: `CHANGELOG.md`
- Rename: `specs/todos/2026-08-12-monitor-down-carries-no-reason.md` to a completed progress entry under `specs/progress/`
- Modify: `scripts` outputs only if doc-index generation is required by the repository checks

**Interfaces:**
- Docs must state `Down(ref, target_pid, reason)`, the three local reasons, mailbox-limit bypass, and backend parity.

- [x] **Step 1: Update both actor documentation copies.**

Replace the old count-only monitor description and any two-field examples with the three-field signal and a short `receive()` pattern-match example.

- [x] **Step 2: Add the Unreleased changelog entry.**

Describe reason-carrying local monitor Down messages and control-plane delivery in one user-visible bullet.

- [x] **Step 3: Move the todo to progress.**

Use `git mv` for the completed todo, preserving its acceptance details and adding the implementation date, files, tests, and backend-parity result after verification.

- [x] **Step 4: Run documentation and full actor verification.**

Run `scripts/check-docs.sh`, regenerate the search index if the script requires it, run the interpreter/compiler/codegen/stdlib actor suites, and run the native monitor fixture. Capture direct exit codes and report any known host-load flakes separately.

- [x] **Step 5: Review the final diff and commit documentation.**

Run `git diff --check`, inspect `git diff --stat` and `git status --short`, stage only the named documentation/ledger files, and commit with `docs(actor): document local monitor down reasons`.

