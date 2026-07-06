# Widening Slice 3 — Actors, Messaging & Supervision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development to execute this plan task-by-task.

**Goal:** Widen the Core March references to cover **actors/processes**: actor declaration, `spawn`, `send`/`receive`, mailbox + the deterministic `run_until_idle` semantics, `Pid`/message typing, actor lifecycle (`kill`/`is_alive` + epoch-based restart invalidation), and a **lighter supervision cut** (`one_for_one` + epoch restart). Operational rules in `core-march.md`, typing rules in `core-march-types.md`, witnessed by conformance corpora. Three real gaps found (actor-affinity not statically enforced; `Actor.call` timeout unenforced; `get_actor_field`/`pid_of_int` compiled-backend crash) are documented + filed, NOT fixed (they're significant design/runtime work, unlike slice 2's one-arm visibility fix — this is a DOCS slice).

**Architecture:** The survey's headline finding: `run_until_idle()` output is fully deterministic AND byte-identical between interpreted and compiled (no divergence, verified 3× across scenarios). So deterministic actor programs are value-witnessable. **Dual corpus:** the deterministic OPERATIONAL actor programs (spawn/send/`run_until_idle` → known output, interp==compiled) go in the **golden corpus** (`specs/lang/golden/`, which exists to diff the two backends — `verify.sh`); the message-TYPING accept/reject programs go in the `types/` corpus (`--check`). What's OUT: true M:N scheduler interleaving, `Task.race`/`any` winner identity, preemption timing, distributed/clustering — documented in prose (a `--check` or single-run corpus can't witness a race).

**Tech Stack:** Markdown; `lib/eval/eval.ml` (actor eval — the operational source of truth), `lib/typecheck/typecheck.ml` (actor decl + Pid typing), `runtime/march_scheduler.c`/`march_runtime.c` (compiled runtime, cited for context) are sources of truth; `_build/default/bin/main.exe` is the oracle (`--check`, interpret, AND `--compile`+run for golden witnesses); the survey `.superpowers/sdd/actors-survey.md` is the authoritative catalog (mechanism cites, determinism transcripts, the findings, a 6-task breakdown).

## Global Constraints

- **Base = current `origin/main`** (fetch + `git pull --ff-only`; rebase if it moved). Branch: `docs/core-march-types-skeleton`.
- **The survey is the catalog, RE-VERIFY every citation + behavior live.** `.superpowers/sdd/actors-survey.md` has the cites (`DActor` typecheck `:6742–6821`, `spawn` `:4185–4203`, eval `:7194–7263`; `send` `:7265–7304`; `receive` `:3076–3091` + drain `:7519–7597`; `Pid[state]` `:983,6821`; supervision `:1501–1745`). Lines DRIFT — `grep -n` the construct live and cite the live line; re-run every probe.
- **⚠️ BINARY PROVENANCE (survey lesson):** ALWAYS probe with the WORKTREE's `_build/default/bin/main.exe` (`$PWD/_build/default/bin/main.exe`), NEVER the main-repo `/Users/80197052/code/march/_build/...` — the survey hit false crash positives (hang, SIGSEGV) from a STALE main-repo binary that vanished against the correct worktree binary. Verify `ls -la _build/default/bin/main.exe` mtime is recent before trusting any crash/hang.
- **DOCS slice — no compiler changes.** Only `specs/`. The three findings (affinity-not-enforced, call-timeout-unenforced, `get_actor_field`/`pid_of_int` compiled crash) are documented + FILED, not fixed. A gap needing a compiler change is a FILED finding.
- **Determinism discipline for the golden corpus:** every `specs/lang/golden/` actor program MUST be deterministic — spawn/send then `run_until_idle()` (or receive-mediated), producing a FIXED output independent of scheduling. Verify each with `specs/lang/golden/verify.sh` (runs interp AND compiled, diffs — the perfect witness for "actors are interp==compiled"). Do NOT add a golden program whose output depends on scheduler interleaving (it would flake). Environment: use both backends (`--compile -o /tmp/x <f> && /tmp/x`).
- **⚠️ OBSERVE STATE VIA A HANDLER THAT PRINTS, NEVER via external `get_actor_field`/`pid_of_int` (compiled-backend CRASH — plan-review finding).** A golden program must reveal its result through a message HANDLER that `println`s (verified interp==compiled). Do NOT read actor state from outside via `get_actor_field(pid, "field")` or `pid_of_int` — those are BROKEN in the compiled runtime: `march_get_actor_field` (`runtime/march_runtime.c:~3329`) is a hard stub returning `None` unconditionally, and `march_pid_of_int` (`~:3324`) does an unsafe untagged int→pointer cast — so a compiled program using them SIGSEGVs / prints garbage (confirmed: `examples/supervision_strategies.march` exits 139 compiled). This is a THIRD filed finding (see Task 5). Any golden that needs to observe restart/state must do so via `is_alive`, a monitor/`DOWN` message, or a handler-print — NOT `get_actor_field`.
- **Corpus numbering:** `specs/lang/golden/` continues `gNN` (verify current highest — was g34; new actor goldens start ~g35). `specs/lang/types/` continues `tNN` (was accept t38 / reject t27; new start accept t39 / reject t28). Re-confirm with `ls`.
- **Faithfulness caveats preserved.** Findings to the appropriate section; the interp==compiled determinism is a POSITIVE finding (unlike slice 1's divergence) — state it as a verified property, cross-ref the golden witnesses.
- **Process:** no `git stash`; explicit `git add <path>` by name; no Co-Authored-By. Commit per task.

---

## Task 1: Actor declaration + spawn typing

**Files:** `specs/lang/core-march-types.md` (new section, e.g. §2.6 "Actors: declaration, spawn, and Pid typing"); `specs/lang/types/{accept,reject}/*.march`.

**Deliverable:** Document the TYPING of actor declaration + spawn (re-grep `DActor`/`actor` in `typecheck.ml` ~:6742–6821; `spawn` ~:4185–4203):
- Actor declaration `actor Name do state {…} init {…} on Msg(…) do … end end` — what's checked (state type, init, handler signatures). Cite.
- `spawn`: resolved by LITERAL actor name at compile time (computed-expression spawn is REJECTED — capture the live message). Returns `Pid[state]` where the type parameter is the actor's **STATE type**, not a message type (cite `:983,6821`).
- **Corpus (types/, accept start t39 / reject start t28):** ≥1 `accept/` (a valid actor + `spawn` yielding a `Pid`); ≥1 `reject/` (spawn of a computed expression / non-literal actor name — capture the live message). Update `specs/lang/types/INDEX.md`.

**Verify:** `MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/types/check_types.sh` all-pass; `scripts/check-docs.sh` 0; every reject reproduced live; citations re-grepped live.

**Commit:** `docs(spec): widen typing reference — actor declaration + spawn + Pid[state] typing`.

---

## Task 2: Actor operational — spawn / send / receive / mailbox / run_until_idle

**Files:** `specs/lang/core-march.md` (new section); `specs/lang/golden/*.march` (+ `INDEX.md`).

**Deliverable:** Document the OPERATIONAL actor semantics (re-grep in `eval.ml`: spawn `:7194–7263`, send `:7265–7304`, receive `:3076–3091` + drain `:7519–7597`):
- `spawn` creates an `actor_inst` in the `actor_registry`; returns a `VPid`.
- `send(pid, msg)` is a PURE ASYNC enqueue onto the actor's mailbox (OCaml `Queue.t` interpreted; green-thread mailbox compiled — cite `march_scheduler.c` for context). Non-blocking.
- `receive()` pops the mailbox or raises `BlockedOnReceive` (re-queued for retry); handler dispatch pattern-matches the message.
- **`run_until_idle()` — the determinism anchor:** processes all pending messages to a FIXED point; document that its output is DETERMINISTIC and (survey-verified) **byte-identical interpreted vs compiled** — state this as a verified property, cross-ref the golden witnesses.
- **Golden corpus (start ~g35 — re-confirm with `ls specs/lang/golden/`):** ≥2 deterministic actor programs — a spawn+send+`run_until_idle` that prints a fixed result; a `receive()`-mediated follow-up. Each MUST pass `specs/lang/golden/verify.sh` (interp==compiled MATCH). Add rows to `specs/lang/golden/INDEX.md`. Do NOT add a program whose output depends on interleaving.

**Verify:** `MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/golden/verify.sh` → all MATCH (interp==compiled), exit 0; `scripts/check-docs.sh` 0; every `eval.ml` citation re-grepped live.

**Commit:** `docs(spec): widen operational reference — actor spawn/send/receive/run_until_idle (+ golden witnesses)`.

---

## Task 3: Message typing + the actor-affinity finding + the message-name namespace

**Files:** `specs/lang/core-march-types.md` (extend §2.6); `specs/lang/types/*.march`; `specs/todos.md` (file the affinity finding).

**Deliverable:**
- **Message payload typing:** a message constructor's payload IS type-checked via ordinary constructor typing — `send(c, Inc("not an int"))` where `Inc` expects `Int` → REJECTS (`expected 'Int' but got 'String'`, capture live). Document this as the rule.
- **The actor-affinity finding (document + FILE):** `Pid[a]`'s type parameter is the actor's STATE type, NOT its message type — so sending a message that a DIFFERENT actor handles to a `Pid` typechecks (exit 0) and SILENTLY DROPS at runtime (both backends — verify live). Document this precisely as a known non-guarantee (a `Pid` does not statically constrain which messages it accepts). **FILE it** in `specs/todos.md` as an open `- [ ]` gap with a minimal repro + the cited reason (`Pid[state]` typing, `typecheck.ml:983,6821`); note that fixing it (typing Pids by accepted message set) is a significant type-system design decision, deferred.
- **The message-name flat global namespace (design point):** handler/message names live in one flat global namespace; a collision requires `Actor_Msg.Report`-style qualification. Document as a design point (analogous to the no-per-module-type-namespace point), NOT a bug.
- **Corpus (types/):** ≥1 `accept/` (a correctly-typed message payload sent); ≥1 `reject/` (a wrong-payload-shape send — the `Inc("x")` case; capture live). The affinity non-guarantee is NOT a clean reject (it typechecks) — document in prose + file, don't force into the harness.

**Verify:** `check_types.sh` all-pass; `check-docs.sh` 0; the payload reject reproduced live; the affinity silent-drop reproduced live (both backends); the affinity finding filed OPEN `- [ ]`.

**Commit:** `docs(spec): widen typing reference — message payload typing + actor-affinity non-guarantee (filed) + message-name namespace`.

---

## Task 4: Actor lifecycle — kill / is_alive + epoch-based Cap/send_checked invalidation

**Files:** `specs/lang/core-march.md` (extend the operational actor section); golden corpus; `specs/lang/core-march-types.md` if a typing aspect fits.

**Deliverable:** Document (re-grep the lifecycle ops in `eval.ml`):
- `kill(pid)` / `is_alive(pid)`: lifecycle; a killed actor's `is_alive` is false; sends to a dead actor (behavior — verify: silently dropped? error?).
- **Epoch-based `Cap`/`send_checked` restart invalidation:** an epoch-tagged capability to an actor is invalidated across a restart (the `revoke_cap`/epoch mechanism — re-grep). Document how a stale `Cap` after restart is rejected (`send_checked`). Cite.
- **Golden corpus:** ≥1 deterministic lifecycle witness (spawn → kill → is_alive → deterministic output), verify.sh MATCH.

**Verify:** `verify.sh` all MATCH; `check_types.sh`/`check-docs.sh` 0; lifecycle behaviors verified live (both backends where relevant); citations live.

**Commit:** `docs(spec): widen operational reference — actor lifecycle (kill/is_alive) + epoch Cap invalidation`.

---

## Task 5: Supervision (lighter cut) — supervisor declaration + one_for_one + epoch restart

**Files:** `specs/lang/core-march.md` (supervision section); golden corpus; `specs/todos.md` (file BOTH the `Actor.call` timeout finding AND the `get_actor_field`/`pid_of_int` compiled-crash finding).

**Deliverable:** Document the LIGHTER supervision cut (re-grep supervision in `eval.ml` ~:1501–1745):
- Supervisor declaration + `one_for_one` strategy (a child crash restarts just that child). Note `one_for_all`/`rest_for_one` exist but this cut focuses on `one_for_one` (mention the others exist, defer their detail).
- **Two supervision subsystems — distinguish them, don't conflate:** the STATIC `actor Name do ... supervise ... end` declaration form exposes all three strategies (`one_for_one`/`one_for_all`/`rest_for_one`), whereas the DYNAMIC `Supervisor.spec`/registry API is the `one_for_one`-only path. Re-grep to confirm which strategies each surface actually implements before writing the claim; scope this Task's `one_for_one` witness to whichever form you golden-test.
- The **epoch-based restart invalidation** interaction (cross-ref Task 4): a restart bumps the epoch, invalidating stale `Cap`s (`send_checked` to the old epoch rejects).
- **FILE the `Actor.call` timeout finding:** `Actor.call`'s timeout is UNENFORCED (`runtime/march_runtime.c:1809-1810` — `(void)timeout_ms; /* not yet enforced */`; re-grep to re-pin). File in `specs/todos.md` as an open `- [ ]` with the cite; note fixing it is runtime work, deferred.
- **FILE the `get_actor_field`/`pid_of_int` compiled-crash finding (plan-review Critical):** external actor-state inspection via `get_actor_field`/`pid_of_int` CRASHES compiled (`examples/supervision_strategies.march` exits 139 / SIGSEGV) — `march_get_actor_field` (`runtime/march_runtime.c:~3329`, re-grep) is a hard stub returning `None` unconditionally, and `march_pid_of_int` (`~:3324`, re-grep) does an unsafe untagged int→pointer cast. File in `specs/todos.md` as an open `- [ ]` with both cites; note it means the external-inspection idiom is interp-only and the compiled backend diverges (crash vs. `None`).
- **Golden corpus (ROUTE AROUND the crash bug):** ≥1 DETERMINISTIC supervision witness — a supervised child that crashes + restarts under `one_for_one`, producing a FIXED output. **Observe the restart via a handler that PRINTS from inside the actor (or via `is_alive`/monitor), NEVER via external `get_actor_field`/`pid_of_int`** (those crash compiled — see the finding above). Design the program so the restart + result are deterministic under `run_until_idle`, not timing-dependent. **Before relying on any observation path in the golden witness, run it BOTH interp AND compiled and confirm byte-identical output** (the whole point of golden is interp==compiled — a path that crashes or diverges compiled is disqualified). verify.sh MATCH. If no deterministic restart witness survives the compiled-parity gate, document the restart semantics in prose + note why it's not golden-testable (like the OUT-of-scope races) rather than forcing a flaky or compiled-crashing program.

**Verify:** `verify.sh` all MATCH; `check_types.sh`/`check-docs.sh` 0; the supervision + epoch behaviors verified live; BOTH the call-timeout finding AND the `get_actor_field`/`pid_of_int` compiled-crash finding filed OPEN; the golden witness's observation path confirmed clean compiled (no 139/SIGSEGV); supervision citations live.

**Commit:** `docs(spec): widen references — supervision (one_for_one + epoch restart) + file Actor.call timeout & get_actor_field/pid_of_int compiled-crash gaps`.

---

## Task 6: Consolidate + corpus + closeout

**Files:** both references (finalize); `specs/lang/golden/INDEX.md`, `specs/lang/types/INDEX.md`; `specs/lang/index.md`; the `specs/lang/actors.md` tutorial; `specs/progress.md`, `specs/todos.md`.

**Deliverable:**
- Finalize both references' actor sections: coherent reads, cross-references between operational (spawn/send/run_until_idle/lifecycle/supervision) and typing (actor decl/Pid/message) resolve; findings collected + `specs/todos.md`-linked; state the interp==compiled determinism property prominently (with the golden witnesses).
- **Reconcile `specs/lang/actors.md`** (the consolidation-era tutorial): verify its claims against live behavior (spawn/send/receive/run_until_idle, the affinity non-guarantee, supervision). Fix stale/false claims (the survey found the earlier interfaces/modules tutorials had several); re-verify its code examples parse + run (`--check` + run). Add cross-refs to the new operational/typing actor sections. (If actively edited by a concurrent session, file a doc-freshness item instead.)
- Update both `INDEX.md`s (golden gNN rows, types tNN rows) + counts; confirm `verify.sh` (golden) and `check_types.sh` (types) both green.
- **Bookkeeping:** `specs/progress.md` — the slice-3 milestone (actors/messaging/supervision in both references, the deterministic-and-interp==compiled property, N golden + M types programs, findings). `specs/todos.md` — Done entry for the slice; confirm ALL THREE findings stay OPEN `- [ ]` (affinity non-enforcement, `Actor.call` timeout unenforced, `get_actor_field`/`pid_of_int` compiled crash); the message-name namespace is a design point (not a todo); note the next widening slice (session-types/protocols, or effects/capabilities) as queued.

**Verify:** `verify.sh` (golden) + `check_types.sh` (types) all green; `scripts/check-docs.sh` 0; both references coherent; `actors.md` reconciled; findings OPEN `- [ ]`.

**Commit:** `docs(spec): widening-slice-3 closeout — actors/messaging/supervision`.

---

## Self-review checklist (run before executing)

1. **Determinism discipline:** every golden actor program is deterministic (spawn/send/`run_until_idle` → fixed output); NONE depend on scheduler interleaving. verify.sh MATCH (interp==compiled) is the gate.
2. **Binary provenance:** all probes use the WORKTREE binary, never the main-repo one (survey's false-crash lesson).
3. **Findings filed, not fixed:** actor-affinity non-guarantee + `Actor.call` timeout + `get_actor_field`/`pid_of_int` compiled crash are documented + FILED open; the message-name namespace is a documented design point. No compiler changes.
4. **Dual corpus:** operational value-witnesses → `golden/` (interp==compiled); message-typing accept/reject → `types/`. Not mixed up.
5. **Capture-not-guess** every reject; **re-grep** every citation live.
6. **Scope boundary:** core actors + `one_for_one` supervision IN; scheduler races, `Task.race` winner, preemption timing, distributed OUT (documented in prose, not tested).
