# Widening Slice 4 — Session Types / Protocols (Channels) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Fresh implementer subagent per task, task review after each, whole-slice review at the end. Steps use `- [ ]`.

**Goal:** Widen the Core March conformance references to cover the **session-typed channel / protocol system** (`protocol … do … end`, `Chan(Role, Proto)`, `Chan.new/send/recv/choose/offer/close`, and MPST typing) — typing rules in `core-march-types.md`, operational rules in `core-march.md`, witnessed by the dual corpus. Fold in a **small compiler fix** (F1/F2: channel-payload tag-coercion miscompile) so binary Int/Bool session programs become golden-testable interp==compiled.

**Architecture:** The session-type plane is mature and rich (projection, duality, per-op session-state advancement, choose/offer, `SRec` loops, binary + MPST). The interpreter runtime is complete. The COMPILED backend has one small, well-localized payload miscompile (F1/F2 — asymmetric erased-i64 coercion between `chan_send` and `chan_recv` lowering) and a larger MPST segfault (F3, OUT of scope, filed). Task 1 fixes F1/F2 (like slice 2's visibility fix); Tasks 2–6 are docs + corpus only. Binary channels → golden witnesses (after Task 1); MPST → typing-only + prose + filed finding.

**Tech Stack:** Markdown references; `lib/typecheck/typecheck.ml` (session_ty, projection, channel-op typing — source of truth for typing), `lib/eval/eval.ml` (channel runtime — operational source of truth), `lib/tir/lower.ml` + `lib/tir/llvm_emit.ml` + `runtime/march_extras.c` (the compiled channel path — Task 1's fix locus), `_build/default/bin/main.exe` (oracle: `--check`, interpret, `--compile`+run). Survey `.superpowers/sdd/sessions-survey.md` is the authoritative catalog (mechanism cites, probe transcripts, findings F1–F8, corpus starts).

## Global Constraints

- **Slice is docs + ONE compiler fix.** ONLY Task 1 touches compiler code (`lib/tir/` and/or `runtime/`, plus its regression tests). Tasks 2–6 touch ONLY `specs/`. Any gap needing a compiler change other than F1/F2 is a FILED finding, not a fix.
- **Task 1 (the F1/F2 fix) MUST run the FULL suite green before landing** (`scripts/run-tests.sh`, all six runners, `--root .`), not just the corpus. It is the only task that can regress the compiler. Verify the fix with a VALUE-REVEALING **odd** Int payload program (interp==compiled), never a parity-only check (even payloads pass by luck — that is exactly how the existing tests went vacuously green).
- **Golden witnesses are gated on Task 1.** A binary channel program carrying an Int/Bool payload is only golden-eligible AFTER Task 1 makes it interp==compiled. Before Task 1, such a program DIVERGES (odd Int `43→21`, `true→false`). Do NOT add an Int/Bool golden witness in a task that runs before Task 1 lands.
- **MPST is OUT of the runnable slice** (F3: segfaults compiled, exit 139). Include MPST *typing* (`--check` accept/reject) + a prose note that compiled MPST is unimplemented/broken; add NO MPST golden witness.
- **⚠️ Determinism + golden discipline.** Session programs are deterministic (single-thread synchronous FIFO, role-sorted endpoints, no interleaving nondeterminism — survey §6). A golden program must produce byte-identical interp==compiled stdout (`verify.sh` diffs the two backends — there is no stored `.expected`). Run each golden BOTH backends and confirm identical before adding it.
- **F8 — participant HINT (hygiene note, NOT a golden blocker).** A `protocol` role that is not a declared `actor`/type emits a HINT — but it prints to **stderr** (`bin/main.ml:~1397` `Printf.eprintf`, re-grep), during the typecheck phase, NOT to program stdout. `verify.sh` diffs interp **stdout** vs compiled **stdout+stderr**; the HINT lands in neither compared slot (interp stderr → a separate `.interp.err` file; the compiled *runtime* does no typecheck so emits no HINT), so it does NOT break golden byte-identity (plan-review simulated this → MATCH). Common role names like `Client`/`Server` are already known env types and emit no HINT at all. So: declaring roles is harmless hygiene but NOT required for a golden to match. Still FILE F8 as a finding (it's diagnostic noise worth recording), but do not treat it as a corpus-construction gate.
- **Recv-before-send is a runtime failure, not a static one (F6).** Session programs must be written as manually-interleaved straight-line code (every `send` textually before its matching `recv`) — there is no scheduler. A misordered program typechecks but dies at runtime both backends. Golden programs must be correctly interleaved.
- **Faithfulness discipline (unchanged from prior slices):** every rule cited to a live `typecheck.ml`/`eval.ml`/`lower.ml`/`llvm_emit.ml`/`runtime` line (RE-GREP — lines drift with concurrent commits); capture-not-guess every reject message from the live compiler.
- **Process rules (verbatim):** NEVER `git stash` in this worktree (shared stack); stage files EXPLICITLY BY NAME (never `git add -A`/`.`/`-am`); NO `Co-Authored-By`; NEVER pipe `march --compile` output (redirect to a file, judge by `$?`, read separately); `dune build --root .`; dune/ocaml on PATH at `/Users/80197052/.opam/march/bin` (never `eval $(opam env …)`); foreground.

**Corpus start numbers (verified live):** golden next = **`g38`**; types accept next = **`t41`**; types reject next = **`t30`**. Both references have ZERO session content today (greenfield; `core-march.md` lists session types only as explicitly-deferred scope).

---

## Task 1: Fix F1/F2 — channel-payload tag coercion (COMPILER) + un-vacuum tests

**Files:** `lib/tir/lower.ml` and/or `lib/tir/llvm_emit.ml` (the `chan_send`/`mpst_send`/`chan_choose` payload-lowering/emit site — locate live); possibly `runtime/march_extras.c` (only if the fix belongs runtime-side); `test/test_compiler.ml` (un-vacuum the `test_session_*` value assertions).

**The bug (survey §4 F1, IR-confirmed):** `march_chan_send` is called with the payload as a **bare untagged `i64`** (the send lowering does not apply the erased-i64 tag), but `march_chan_recv`'s returned payload is put through the standard **conditional-untag** restore (`ptrtoint` → `and 1` → `select (ashr x,1) x`, `llvm_emit`). Asymmetric: send stores `43` raw; recv sees `43 & 1 == 1` → `ashr 43,1 = 21`. Every ODD Int corrupts as `(v-1)/2`; Bool (odd-tagged) flips `true→false`; even Ints and heap/String pass by luck. See the erased-i64 convention (conditional untag = `ashr iff odd`; heap ptrs verbatim) and the `record_put` uniform-handoff / `task_await` double-untag precedents.

**Deliverable:**
- **Make the send and recv payload coercions symmetric.** The plan-review located the exact fix (re-grep to re-pin all lines — they drift): today `chan_send` has NO dedicated emit arm and falls through the general `EApp` path (`llvm_emit.ml:~1682`), passing the payload as a raw `i64`, while `chan_recv`'s returned payload goes through the conditional-untag restore. **Fix = add a dedicated match arm for `chan_send` (and `chan_choose`, `mpst_send`) BEFORE the general `EApp` fallthrough, mirroring the existing `vault_set` (`llvm_emit.ml:~1612`) and `actor_reply` (`~:1660`) precedent arms, that coerces the payload via `emit_atom_as ctx "ptr"`.** `coerce ("i64","ptr")` (`llvm_ctx.ml:~502`) applies `(n<<1)|1` — the exact inverse of recv's conditional-untag — and short-circuits to identity (`~:474`) for values already `ptr` (so String/heap/ADT payloads pass verbatim, unchanged). Because the new arm is ADDITIVE and sits AHEAD of the shared path, `record_put`/`task_await`/every other builtin is untouched **by construction** (verify this — it's the whole safety argument). Do NOT bare `inttoptr` (corrupts per the erased-i64 note). `chan_choose` sends an atom label — confirm atoms still round-trip after the change. `mpst_send` gets the same arm for code-path consistency (MPST run is still OUT/F3). ~5–10 lines per builtin.
- **Un-vacuum the tests:** the in-repo `test_session_eval_send_recv` (`test/test_compiler.ml:~1728`) and `test_session_compile_*` (`:~2350–2434`) pass an EVEN payload (`42`) or never check a compiled value. Change them to assert an **ODD** value round-trips (e.g. `43→43`, or an echo `43→44`) **compiled**, so the F1 regression is caught. Add at least one compiled-value assertion that would have FAILED before this fix.
- Verify with a value-revealing program: `Chan.new` → `Chan.send(cc, 43)` → recv → print, BOTH interp AND compiled, confirm both print `43` (before the fix: interp `43`, compiled `21`). Also check a Bool (`true` round-trips compiled) and a String (still `ping-pong`).

**Verify:** the odd-Int + Bool value programs are interp==compiled after the fix; `scripts/run-tests.sh` (FULL six-runner suite, `--root .`) GREEN with no regressions (compare against a pre-fix baseline if any failure is ambiguous — see the pre-existing-failures memory note); the un-vacuumed `test_session_*` assertions pass and would fail on the old binary. `dune build --root .` clean.

**Commit:** `fix(codegen): tag channel payloads at the send site so Chan.send/recv round-trip odd Ints + Bools compiled (F1/F2) + un-vacuum session value tests`.

---

## Task 2: Typing reference — protocol decl + projection + duality (§ new) + accept corpus

**Files:** `specs/lang/core-march-types.md` (new section, e.g. §2.7 "Session types: protocols, projection, and channels"); `specs/lang/types/accept/t41+*.march`; `specs/lang/types/INDEX.md`; `specs/todos.md` (file F4).

**Deliverable:** Document the TYPING of protocols + channel endpoint types (re-grep live):
- `protocol Name do <steps> end` (`DProtocol`, `ast.ml:151`; `protocol_def`/`protocol_step` `:287–294` — the THREE steps: `ProtoMsg` (`Sender -> Receiver : T`), `ProtoLoop` (`loop do … end`), `ProtoChoice` (`choose by Role: label -> steps`)). Cite parser `parser.mly:615–627`.
- `session_ty` (`typecheck.ml:105–117`): `SSend`/`SRecv`/`SChoose`/`SOffer`/`SEnd`/`SRec`/`SVar`, and the MPST `SMSend`/`SMRecv`. `TChan of session_ty ref` (`:95`) — a linear endpoint wrapping a mutable session-state ref.
- **Projection** (`project_steps` `:5870`, `project_protocol` `:5951`): a global protocol projects onto each role's local `session_ty`; `ProtoLoop`→`SRec`, `ProtoChoice`→`SChoose` (chooser) / `SOffer` (others). Binary (2 roles): verifies `dual(proj_a) == proj_b` (`dual_session_ty` `:5936`, check `:5975`). MPST (>2 roles): verifies matching send/recv role pairs (`:5985+`). `Chan(Role,Proto)` resolves via `pi_projections` (surface-ty special case `:2287–2308` → `TLin(Linear, TChan(ref sty))`).
- **MPST typing IS documented** (projection/consistency), with a prose note that **compiled MPST is broken (F3, filed) — MPST is typing-only in this reference**.
- **FILE finding F4** (choose-with-structurally-identical-branches breaks binary duality — the MPST merge rule `:5906` leaks into the binary check; a legal binary protocol whose branches carry the same type is wrongly rejected `"the projection onto A and B are not duals"`). File in `specs/todos.md` as open `- [ ]` with the cite + minimal repro; note it's a real typing bug, deferred.

**Corpus (accept, `t41+`):** ≥2 `accept/` — a well-formed BINARY protocol + `Chan.new` + valid `Chan(Role,Proto)` annotation (roles declared to avoid the F8 HINT); ≥1 well-formed MPST protocol that `--check`s clean. Each verified live. Update `INDEX.md` (rows + ALL count sites).

**Verify:** `MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/types/check_types.sh` all-pass; `check-docs.sh` 0; every cite re-grepped live; F4 filed OPEN.

**Commit:** `docs(spec): widen typing reference — session-type protocols, projection, duality (+ MPST typing; F4 filed)`.

---

## Task 3: Typing reference — channel-op session typing + reject corpus

**Files:** `specs/lang/core-march-types.md` (extend the session section); `specs/lang/types/reject/t30+*.march`, maybe `accept/`; `specs/todos.md` (file F5).

**Deliverable:** Document the per-op session-state advancement typing (each op is a special-cased `EApp(EVar "Chan.X", …)` reading + advancing the `TChan` ref; re-grep):
- `Chan.new` (`:3428–3474`) → `(Chan(RoleA,P), Chan(RoleB,P))` (first two role projections; endpoints role-sorted). `Chan.send` (`:3478–3505`) requires `SSend(T,S)`, checks payload against `T`, returns `Chan` at `S`. `Chan.recv` (`:3509–3535`) requires `SRecv(T,S)` → `(T, Chan at S)`. `Chan.close` (`:3536–3560`) requires `SEnd`. `Chan.choose` (`:3562–3605`) requires `SChoose`, label = atom literal. `Chan.offer` (`:3607–3643`) requires `SOffer` → `(Atom, Chan at FIRST branch cont)`.
- **FILE finding F5** (`Chan.offer` always returns the FIRST branch's continuation regardless of the peer's runtime choice — a documented conservative approximation, a soundness gap: an `offer` over branches with different continuations is mis-typed). File OPEN with the cite (`:3607`) + note.
- Document linearity: channels are `TLin(Linear, …)` — a `let`-bound continuation is consume-once (generic linear tracker). Note the F7 holes go in Task 4 (operational), cross-ref.

**Corpus (reject, `t30+`):** capture LIVE (survey §3 harvested these — re-capture exact text): send-at-recv-state, close-before-End, invalid choose label, wrong payload type, unknown protocol, unknown role, non-dual protocol, linear-used-twice. ≥5 reject programs, each reproduced live with the pinned message. Optionally ≥1 accept for a full binary send/recv/close round-trip that `--check`s clean. Update `INDEX.md` + counts.

**Verify:** `check_types.sh` all-pass; every reject reproduced live with the pinned substring; `check-docs.sh` 0; F5 filed OPEN.

**Commit:** `docs(spec): widen typing reference — channel-op session typing (send/recv/choose/offer/close) + reject corpus (F5 filed)`.

---

## Task 4: Operational reference — channel runtime + GOLDEN witnesses

**Files:** `specs/lang/core-march.md` (new operational session section); `specs/lang/golden/g38+*.march`; `specs/lang/golden/INDEX.md`; `specs/todos.md` (file F3, F6, F7, F8).

**Deliverable:** Document the OPERATIONAL channel runtime (re-grep `eval.ml`):
- Values `VChan`/`VMChan` (`:50–51`); `chan_endpoint` crossed FIFO queues (`:63–73`, `a.out == b.in`). `chan_new` (`:2632`, endpoints role-sorted), `chan_send` (`:2645`, `Queue.push`, returns same endpoint), `chan_recv` (`:2655`, pops, HARD ERROR if empty), `chan_close` (`:2666`). `Chan.choose` IS `chan_send` of the label atom (`:5581`); `Chan.offer` IS `chan_recv` (`:5588`).
- **The runtime model in one line:** synchronous, single-threaded, non-blocking; `recv` does NOT suspend — empty queue = fatal error both backends; no scheduler; both endpoints run in the same straight-line thread; the programmer must order every `send` before its matching `recv`.
- **FILE F3** (MPST segfault compiled, exit 139 — `march_extras.c:1463+` MPST runtime not wired to the lowered rep; MPST interp-only). **FILE F6** (no-scheduler: recv-before-send deadlocks at runtime, not caught statically — a scope boundary: session types here are a linear protocol-conformance checker over a same-thread mailbox, not concurrent sessions). **FILE F7** (partial linearity: dropping an unclosed `SEnd` channel + reusing a linear *parameter* whose session state coincidentally matches both slip through the generic tracker — survey P8). **FILE F8** (participant HINT emitted to STDERR during typecheck for undeclared protocol roles — diagnostic noise; NOT a stdout/golden issue, per the corrected Global Constraint). All OPEN `- [ ]` with cites.
- State the interp==compiled property for the BINARY channel plane AFTER Task 1's fix (Int/Bool/String round-trips are now byte-identical), witnessed by the golden programs. Be precise: MPST DIVERGES compiled (F3) → not golden.

**Corpus (golden, `g38+`, ENABLED by Task 1):** ≥2 deterministic binary channel programs, each MATCH under `verify.sh` (interp==compiled): a send/recv Int round-trip printing a FIXED **odd** value (e.g. `43` — the value Task 1 fixed), and a `choose`/`offer` branch-selection printing a fixed result. **⚠️ The choose golden must use TYPE-DISTINCT branches — F4 (see Task 2) rejects a protocol whose branches carry the same type ("the projection onto A and B are not duals"). AND the taken branch's payload must be an Int/Bool (now fixed by Task 1) or a heap type; do not carry a Bool/Int payload if this witness could somehow run before Task 1.** (The F8 HINT is NOT a golden blocker — see Global Constraints; declaring roles is optional hygiene.) Run each BOTH backends first, confirm byte-identical + compiled exit 0, THEN add. Update `INDEX.md` (rows + ALL count sites — check every count line, a recurring miss).

**Verify:** `MARCH_BIN=$PWD/_build/default/bin/main.exe bash specs/lang/golden/verify.sh` all MATCH, exit 0 (run BACKGROUND to a file — >2 min, 39+ compiles); `check-docs.sh` 0; F3/F6/F7/F8 filed OPEN; the golden witnesses' odd-Int payload confirmed clean compiled.

**Commit:** `docs(spec): widen operational reference — channel runtime (sync FIFO, choose/offer, deadlock boundary) + golden witnesses (F3/F6/F7/F8 filed)`.

---

## Task 5: Findings ledger consolidation + F1/F2 Done entry

**Files:** `specs/todos.md`.

**Deliverable:** Reconcile the session findings roster (most are filed in-task by Tasks 2–4; this task ensures consistency + records the FIX):
- Confirm F4 (Task 2), F5 (Task 3), F3/F6/F7/F8 (Task 4) are each filed ONCE, OPEN `- [ ]`, with live cites — no duplicates.
- **Add a Done entry for F1/F2** (the channel-payload tag miscompile) — FIXED in this slice's Task 1 (commit hash), analogous to slice 2's visibility-fix Done entry. Cite the fix locus + the un-vacuumed tests.
- Confirm the roster reads coherently (6 open findings F3–F8, 1 fixed F1/F2).

**Verify:** `check-docs.sh` 0; `specs/todos.md` internally consistent (F1/F2 Done, F3–F8 OPEN, no dupes).

**Commit:** `docs(spec): session-types findings ledger — F1/F2 fixed (Done), F3–F8 open`.

---

## Task 6: Consolidate + corpus + closeout

**Files:** both references (finalize); `specs/lang/golden/INDEX.md`, `specs/lang/types/INDEX.md`; `specs/lang/index.md`; `specs/progress.md`, `specs/todos.md`.

**Deliverable:**
- Finalize both references' session sections: coherent reads; operational↔typing cross-references resolve; state the (post-fix) binary interp==compiled property with the golden witnesses; MPST clearly marked typing-only.
- Update both `INDEX.md`s (golden `g38+`, types `t41+`/`t30+`) + ALL count sites consistent; confirm `verify.sh` + `check_types.sh` + `check-docs.sh` all green.
- Wire nothing new into CI beyond the existing `types-check`/golden aliases (the new programs are picked up automatically).
- **Bookkeeping:** `specs/progress.md` — the slice-4 milestone (session types/protocols in both references, the F1/F2 compiler fix, binary interp==compiled property, N golden + M types programs, findings F3–F8 + F4/F5 typing gaps). `specs/todos.md` — Done entry for the slice; confirm F3–F8 stay OPEN, F1/F2 Done; note the next widening slice (effects/capabilities, or error-handling/`let?`) as queued. `specs/lang/index.md` — add a session-types entry if the umbrella indexes chapters.

**Verify:** `verify.sh` + `check_types.sh` + `check-docs.sh` all green; both references coherent; findings roster correct.

**Commit:** `docs(spec): widening-slice-4 closeout — session types / protocols / channels`.

---

## Self-review checklist (run before executing)

1. **Task 1 first + full-suite gated:** the F1/F2 fix lands and passes the six-runner suite BEFORE any Int/Bool golden witness is written. Golden witnesses (Task 4) come after Task 1.
2. **Value-revealing verification:** the fix is confirmed with an ODD Int payload (43, not 42) interp==compiled — never a parity check that even values pass by luck.
3. **MPST OUT of runnable:** typing-only + prose + F3 filed; no MPST golden witness.
4. **Dual corpus:** binary channel value-witnesses → `golden/` (interp==compiled, post-fix); protocol/channel-op accept+reject → `types/`. Not mixed up.
5. **F8 HINT is stderr, not a golden blocker:** the participant HINT prints to stderr during typecheck and does NOT affect `verify.sh` (which compares interp-stdout vs compiled-stdout+stderr — the HINT lands in neither slot). File F8 as noise; do not gate corpus construction on it.
6. **Findings filed, not fixed** (except F1/F2 which the user chose to fix): F3/F4/F5/F6/F7/F8 documented + FILED open; F1/F2 fixed + Done.
7. **Capture-not-guess** every reject; **re-grep** every citation live.
