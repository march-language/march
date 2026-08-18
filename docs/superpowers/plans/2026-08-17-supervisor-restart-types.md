# Supervisor Restart Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a `supervise` block declare each child's restart policy, and give programs an explicit way to retire a supervised child, so a worker that finishes its job is not resurrected forever.

**Architecture:** The reason plumbing already exists — PR #284 threaded `march_death_reason` through `do_actor_death` and the notify call is already guarded by `reason != MARCH_DEATH_NORMAL`. This plan adds a per-child `restart_type` carried from surface syntax through lowering into `march_sup_child`, consults it in `march_supervisor_notify` before the restart budget is touched, honours it in the batch-strategy respawn loops, and adds an `Actor.stop(pid)` builtin that exits a child NORMAL so any child can be deliberately retired.

**Tech Stack:** menhir grammar + ocamllex, OCaml AST/typecheck/TIR lowering, C11 runtime, OCaml interpreter, Alcotest + native March goldens, dune.

**Spec:** `specs/2026-08-17-supervisor-restart-types-design.md`. Read it before Task 1 — §1 explains why this change is much smaller than its todo implies.

## Global Constraints

- `--root .` is MANDATORY on every dune command. Worktrees live inside the main repo; a bare `dune build` silently builds `/Users/80197052/code/march`.
- After editing `runtime/*.c` or `runtime/*.h`: `dune build --root . @bin/warm-cache`. `dune build bin/main.exe` does NOT restage `_build/default/runtime`, so the edit silently will not be in the binary. After editing `stdlib/*.march`: `dune build --root . @install`.
- Clear the CAS before comparing compiled behaviour: `rm -rf .march/cas/artifacts-v2/`.
- Use `DUNE_CACHE=disabled dune build --root . --force` for anything you intend to trust. Never hand-write into `_build/` — it writes through a hardlink into the user-global dune cache.
- Never `git stash` (shared stash stack across worktrees; four prior incidents). Copy files aside instead.
- Stage explicitly by filename. Never `git add -A`, `git add .`, `git add *`, `git commit -am`. No `Co-Authored-By` lines.
- Never `eval $(opam env ...)`. Never pipe `march --compile` — redirect to a file, judge by `$?`. Never judge ANY exit code through a pipe (`cmd | tail` returns `tail`'s status); note `grep -c` exits 1 on zero matches, which is a no-match, not a failure.
- `timeout` does not exist on this macOS box. Foreground only. `run_stdlib` takes ~4 min and `run_codegen` ~11 min; the harness auto-backgrounds past 120s — that is normal, read the redirect file, do NOT re-launch.
- Know which driver owns a test: `test_trmc` is in `run_codegen.exe`, not `run_compiler.exe`.
- Known non-regressions, do not chase: `native/signal_watch` (dune shared-cache poisoning; decisive test is `DUNE_CACHE=disabled`), `native_closure_param_shadows_import` / `native_actor_stress` / `adversarial-regressions 48` (SIGKILL under host load). Check `uptime` first and re-run in isolation.
- Every task updates `specs/todos/` and `specs/progress/` in the same commit that lands the change, per `CLAUDE.md`, and adds a `CHANGELOG.md` bullet under `## [Unreleased]` when user-visible.

## Semantics — the normative table

| Restart type | `MARCH_DEATH_CRASH` | `MARCH_DEATH_KILLED` | `MARCH_DEATH_NORMAL` |
|---|---|---|---|
| `permanent` (default) | restart | restart | no restart |
| `transient` | restart | restart | no restart |
| `temporary` | no restart | no restart | no restart |

Decided 2026-08-17: `transient` matches `stdlib/dist_supervisor.march`'s `should_restart` (`:53-65`) and OTP — it restarts on `Killed`. Retiring a child is `Actor.stop(pid)`, which exits NORMAL, mirroring OTP's `supervisor:terminate_child`.

### READ THIS: `permanent` and `transient` are behaviourally identical in the local plane

That is a direct consequence of the two decisions above. In OTP the ONLY difference between `permanent` and `transient` is restart-on-normal-exit, and March's `permanent` deliberately does not restart on normal exit (the `reason != MARCH_DEATH_NORMAL` guard already ships, and changing it would alter every existing `supervise` block).

So today `transient` is vocabulary parity, not behaviour: it exists so a child spec reads the same locally and under `DistSupervisor`, and it will diverge if March ever adopts OTP's restart-on-normal `permanent`.

**Do not "fix" this by making `permanent` restart on normal exit** — that is an explicitly rejected breaking change. **Do not quietly drop `transient`** either. Document it: the actors chapter and the progress entry must both say plainly that `transient` is currently indistinguishable from `permanent` locally and why. Shipping a keyword whose behaviour a reader cannot observe, without saying so, is the failure mode to avoid here.

The two deliverables that carry real behaviour are **`temporary`** and **`Actor.stop`**.

## File Map

- `lib/lexer/lexer.mll` — four new keywords beside the existing `strategy`/`max_restarts` entries (`:77-80`).
- `lib/parser/parser.mly` — `supervise_child` (`:637`) gains an optional trailing modifier; new tokens.
- `lib/ast/ast.ml` — `restart_type` variant; `supervise_field` (`:291`) gains `sf_restart`.
- `lib/tir/lower_actor.ml` — `restart_type_int` mirroring `strategy_int` (`:356`); thread into the register-child call.
- `runtime/march_runtime.h` / `runtime/march_runtime.c` — `march_sup_child.restart_type`; `march_actor_register_child` ABI; the notify filter; batch respawn skip; `march_actor_stop`.
- `lib/typecheck/typecheck.ml`, `lib/tir/llvm_builtins.ml`, `lib/tir/defun.ml`, `lib/eval/eval.ml`, `stdlib/actor.march` — the five sites a new builtin touches (`actor_unregister` is the template).
- `test/native/` — six goldens, each run compiled AND interpreted.
- `test/test_codegen.ml`, `test/native/*.ll` — ABI declaration updates.

---

### Task 1: Surface syntax — lexer, parser, AST

**Files:**
- Modify: `lib/lexer/lexer.mll:77-80`
- Modify: `lib/parser/parser.mly:637` (`supervise_child`) and the `%token` declarations
- Modify: `lib/ast/ast.ml:291` (`supervise_field`)
- Test: `test/test_compiler.ml`

**Interfaces:**
- Produces: `Ast.restart_type = Permanent | Transient | Temporary`, and `supervise_field` gains `sf_restart : restart_type`. Tasks 2-4 consume both.

- [ ] **Step 1: Confirm the keywords are free**

```bash
for k in restart permanent transient temporary; do
  printf "%-10s lexer=%s\n" "$k" "$(grep -c "\"$k\"" lib/lexer/lexer.mll)"
done
```
Expected: all zero. I checked this and all four are unused, but confirm — if any is taken, STOP and report rather than reserving a word already in use. Note `stdlib/dist_supervisor.march` uses `Permanent`/`Transient`/`Temporary` as *capitalised constructors*, which do not collide with lowercase keywords; verify that reading.

- [ ] **Step 2: Write the failing parser test**

In `test/test_compiler.ml`, beside the existing supervise-block parse tests, add a test that this parses and yields the expected AST:

```march
mod M do
  actor W do
    state { n : Int }
    init  { n: 0 }
    on Go() do { n: state.n + 1 } end
  end
  actor S do
    state { a : Int, b : Int, c : Int }
    init  { a: 0, b: 0, c: 0 }
    supervise do
      strategy one_for_one
      max_restarts 5 within 60
      W a
      W b restart transient
      W c restart temporary
    end
  end
end
```

Assert `sf_restart` is `Permanent`, `Transient`, `Temporary` for `a`, `b`, `c` respectively. Copy the assertion style from the nearest existing supervise-parse test rather than inventing one.

- [ ] **Step 3: Run it and confirm it fails**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e > /tmp/t1.log 2>&1; echo "exit=$?"
```
Expected: FAIL — the grammar has no `restart` modifier yet, so this is a parse error.

- [ ] **Step 4: Add the AST type**

In `lib/ast/ast.ml`, beside `restart_strategy`:

```ocaml
(** Per-child restart policy. See specs/2026-08-17-supervisor-restart-types-design.md.
    Permanent and Transient are behaviourally identical in the local plane today —
    both restart on Killed and Crash, neither on Normal — because March's Permanent
    deliberately does not restart on normal exit. Transient exists for parity with
    stdlib/dist_supervisor.march's RestartStrategy. *)
and restart_type = Permanent | Transient | Temporary
```

and extend the record:

```ocaml
and supervise_field = {
  sf_name    : name;
  sf_ty      : ty;
  sf_restart : restart_type;
}
```

- [ ] **Step 5: Add the keywords**

In `lib/lexer/lexer.mll`, beside `("strategy", STRATEGY);` and `("one_for_one", ONE_FOR_ONE);`:

```ocaml
      ("restart",   RESTART);
      ("permanent", PERMANENT);
      ("transient", TRANSIENT);
      ("temporary", TEMPORARY);
```

- [ ] **Step 6: Extend the grammar**

Declare the four tokens beside the existing supervise tokens, then replace `supervise_child` (`lib/parser/parser.mly:637`):

```
supervise_child:
  | actor_type = upper_name; field_name = lower_name;
    r = option(child_restart)
    { (field_name, TyCon (actor_type, []),
       match r with Some t -> t | None -> Permanent) }

child_restart:
  | RESTART; t = restart_type_tok  { t }

restart_type_tok:
  | PERMANENT  { Permanent }
  | TRANSIENT  { Transient }
  | TEMPORARY  { Temporary }
```

Then update `supervise_block` (`:622`), which currently destructures 2-tuples:

```
    { let names = List.map (fun (n, _, _) -> n) children in
      let tyfields = List.map (fun (n, t, r) ->
        { sf_name = n; sf_ty = t; sf_restart = r }) children in
      ... }
```

- [ ] **Step 7: Run the test and the grammar gate**

```bash
dune build --root . test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e > /tmp/t1.log 2>&1; echo "exit=$?"
grep -c "^  \[FAIL\]" /tmp/t1.log
dune build --root . @grammar-check --force > /tmp/t1-gram.log 2>&1; echo "exit=$?"
```
Expected: exit 0, zero FAILs. `@grammar-check` MUST use `--force` — without it it can exit 0 on a stale log. If menhir reports new shift/reduce conflicts beyond the 10 already documented as pre-existing, STOP and report the count.

- [ ] **Step 8: Commit**

```bash
git add lib/lexer/lexer.mll lib/parser/parser.mly lib/ast/ast.ml test/test_compiler.ml
git commit -m "parser: optional restart modifier on supervise children"
```

---

### Task 2: Thread the restart type to the runtime

**Files:**
- Modify: `lib/tir/lower_actor.ml:356` (`strategy_int` neighbourhood) and the register-child call site
- Modify: `runtime/march_runtime.h:484` neighbourhood (declaration) and `runtime/march_runtime.c` (`march_sup_child` at `:1783`, `march_actor_register_child`)
- Modify: `test/test_codegen.ml`, `test/native/*.ll` goldens declaring the symbol

**Interfaces:**
- Consumes: `Ast.restart_type` from Task 1.
- Produces: `march_actor_register_child(void *supervisor, void *child, void *spawn_clo, int64_t word_idx, int64_t restart_type)` and `march_sup_child.restart_type` (`int32_t`, 0 permanent / 1 transient / 2 temporary). Tasks 3-4 read the field.

- [ ] **Step 1: Find every site that declares the symbol**

```bash
grep -rn "march_actor_register_child" --include='*.c' --include='*.h' --include='*.ml' --include='*.ll' . | grep -v _build
```
This is an ABI change to a symbol codegen emits. Record the full list in your report — a missed `.ll` golden or `test_codegen.ml` preamble string fails only in CI, where dune's sandbox stages just the declared deps.

- [ ] **Step 2: Add the struct field**

In `march_sup_child` (`runtime/march_runtime.c:1783`), after `word_idx`:

```c
    /* Restart policy: 0 permanent, 1 transient, 2 temporary. Set once at
     * registration and never mutated, so unlike crash_streak/last_crash_ms
     * it needs no g_supervise_mu protection to read. NOTE sup_children grows
     * via realloc, which does NOT zero new memory — this must be assigned
     * explicitly at registration, same as the two backoff fields. */
    int32_t restart_type;
```

- [ ] **Step 3: Extend the C entry point**

Change `march_actor_register_child` to take `int64_t restart_type` as a fifth parameter and store `child_slot->restart_type = (int32_t)restart_type;` in the same block that explicitly initialises `crash_streak` and `last_crash_ms`. Update the `runtime/march_runtime.h` declaration to match.

- [ ] **Step 4: Emit it from lowering**

In `lib/tir/lower_actor.ml`, beside `strategy_int` (`:356`):

```ocaml
  let restart_type_int (r : Ast.restart_type) : int =
    match r with
    | Ast.Permanent -> 0
    | Ast.Transient -> 1
    | Ast.Temporary -> 2
  in
```

Add the argument to the register-child call, reading `sf_restart` from the matching `supervise_field` (the lookup at `:316` already finds the field by name).

- [ ] **Step 5: Update the ABI declarations**

Update every site from Step 1: `test/test_codegen.ml`'s preamble strings and each `test/native/*.ll` golden that declares `march_actor_register_child`.

- [ ] **Step 6: Rebuild and run**

```bash
DUNE_CACHE=disabled dune build --root . @bin/warm-cache --force > /tmp/t2-build.log 2>&1; echo "exit=$?" > /tmp/t2-build.exit
rm -rf .march/cas/artifacts-v2/
./_build/default/test/run_codegen.exe -e > /tmp/t2-cg.log 2>&1; echo "exit=$?" > /tmp/t2-cg.exit
dune build --root . @test/runtest > /tmp/t2-rt.log 2>&1; echo "exit=$?" > /tmp/t2-rt.exit
```
Read the `.exit` sidecars. Expected: all exit 0, zero FAILs, zero golden diffs. **Behaviour must be unchanged at this point** — the field is carried but not yet consulted, so the three existing supervision goldens must byte-match.

- [ ] **Step 7: Commit**

```bash
git add lib/tir/lower_actor.ml runtime/march_runtime.c runtime/march_runtime.h test/test_codegen.ml test/native
git commit -m "runtime: carry per-child restart type through registration"
```

---

### Task 3: Consult the restart type

This is the behavioural core. Two call sites, and **the second is the one that gets missed**.

**Files:**
- Modify: `runtime/march_runtime.c` — `march_supervisor_notify` (`:3495`), `march_one_for_all_restart`, `march_rest_for_one_restart`
- Modify: `lib/eval/eval.ml` — `notify_supervisor` (`:2496`) and its caller (`:2573`)
- Test: `test/native/supervisor_restart_temporary.march` + `.expected`, `test/native/supervisor_restart_batch_temporary.march` + `.expected`, `test/dune`

**Interfaces:**
- Consumes: `march_sup_child.restart_type` from Task 2.
- Produces: the semantics in the normative table above.

- [ ] **Step 1: Write the failing goldens**

`test/native/supervisor_restart_temporary.march` — a `one_for_one` supervisor with one `restart temporary` child. Crash it via `panic()` in a handler; assert it is NOT respawned (its pid slot stays dead / `is_alive` false) and the supervisor survives.

`test/native/supervisor_restart_batch_temporary.march` — a `one_for_all` supervisor with two children, the second `restart temporary`. Crash the FIRST child; assert the first is respawned and **the temporary one is not**. This is the §4.5 case; without it, a `temporary` child silently resurrects whenever a sibling crashes.

Model both on `test/native/supervisor_one_for_all_restart.march`. Register the rules in `test/dune` by copying the nearest existing `native_supervisor_*` rule and changing the names.

- [ ] **Step 2: Run them and record the red**

```bash
DUNE_CACHE=disabled dune build --root . @bin/warm-cache --force
rm -rf .march/cas/artifacts-v2/
dune build --root . @test/runtest > /tmp/t3-red.log 2>&1; echo "exit=$?"
grep -E '^File "' /tmp/t3-red.log
```
Expected: BOTH new goldens diff — `temporary` is not yet consulted, so both children restart. Record the actual output; this is the red half of the cycle and the reviewer will ask for it.

- [ ] **Step 3: Filter in the notify path**

In `march_supervisor_notify`, after `child` is resolved and **before** the `g_supervise_mu` leaf-lock section that does the `crash_streak` read-modify-write:

```c
    /* Restart policy. Filtered BEFORE the leaf-lock section on purpose: a
     * death that will not restart must not advance crash_streak or charge
     * the restart budget, or retiring several temporary children in a row
     * could escalate a healthy supervisor toward max_restarts.
     *
     * terminal_reason is set by do_actor_death under g_tbl_mu before it
     * calls us (see its terminal_set claim), so it is readable here. The
     * fallback is deliberately conservative: an unknown reason restarts a
     * permanent child, preserving today's behaviour rather than silently
     * retiring something. */
    march_death_reason r = crashed_meta->terminal_set
        ? crashed_meta->terminal_reason : MARCH_DEATH_CRASH;
    int should_restart =
          child->restart_type == 2 ? 0                          /* temporary */
        : (r != MARCH_DEATH_NORMAL);                            /* permanent, transient */
    if (!should_restart) return;
```

Note this expresses the normative table exactly: `permanent` and `transient` share a branch because they are identical locally (see the semantics section), and `MARCH_DEATH_NORMAL` is already filtered by the caller — the check is belt-and-braces for any future caller.

- [ ] **Step 4: Skip temporary children in the batch respawn**

In `march_one_for_all_restart` and `march_rest_for_one_restart`, in the loop that calls `march_respawn_child` for each slot, skip any child whose `restart_type == 2`:

```c
        if (sup_meta->sup_children[i].restart_type == 2) continue;  /* temporary: killed, not revived */
```

Leave the *kill* alone — those kills are internal machinery, not a user retiring a child, and the strategies already suppress recursive notify by nulling `cm->supervisor` first.

- [ ] **Step 5: Mirror it in the interpreter**

In `lib/eval/eval.ml`, apply the same filter in `notify_supervisor` (`:2496`) / its caller (`:2573`), using the reason the interpreter already computes for `Down` messages, and the same skip in its batch-restart paths. Both backends must agree — the registry work established that identical source behaving differently across backends is its own bug class.

- [ ] **Step 6: Run the goldens both ways**

```bash
DUNE_CACHE=disabled dune build --root . @bin/warm-cache --force
rm -rf .march/cas/artifacts-v2/
dune build --root . @test/runtest > /tmp/t3-green.log 2>&1; echo "exit=$?" > /tmp/t3-green.exit
grep -cE '^File "' /tmp/t3-green.log
./_build/default/test/run_stdlib.exe -e > /tmp/t3-stdlib.log 2>&1; echo "exit=$?" > /tmp/t3-stdlib.exit
```
Expected: exit 0, zero golden diffs, zero FAILs. **The three pre-existing supervision goldens must byte-match** — that is the proof that existing blocks are unaffected.

Also run each new fixture interpreted and diff against the same `.expected`, following the `interp_actor_registry_restart` pattern in `test/dune`.

- [ ] **Step 7: Commit**

```bash
git add runtime/march_runtime.c lib/eval/eval.ml test/dune test/native/supervisor_restart_temporary.march test/native/supervisor_restart_temporary.expected test/native/supervisor_restart_batch_temporary.march test/native/supervisor_restart_batch_temporary.expected
git commit -m "supervisor: honour per-child restart type on both backends"
```

---

### Task 4: `Actor.stop` — retire a child deliberately

**Files:**
- Modify: `runtime/march_runtime.c`, `runtime/march_runtime.h`
- Modify: `lib/typecheck/typecheck.ml:2613` neighbourhood, `lib/tir/llvm_builtins.ml:842` and `:1542`, `lib/tir/defun.ml:97`, `lib/eval/eval.ml:4409` neighbourhood
- Modify: `stdlib/actor.march:105` neighbourhood
- Test: `test/native/supervisor_restart_stop_retires.march` + `.expected`, `test/dune`

**Interfaces:**
- Consumes: Task 3's filter — `Actor.stop` works by exiting NORMAL, which that filter already declines to restart for every type.
- Produces: `Actor.stop(pid) : Unit`, C symbol `march_actor_stop`.

- [ ] **Step 1: Write the failing golden**

`test/native/supervisor_restart_stop_retires.march` — a `one_for_one` supervisor with a default (`permanent`) child. Call `Actor.stop(pid)` on it; assert it is NOT respawned and the supervisor survives. Contrast with `kill()` on the same shape, which MUST still restart it. Both assertions in one fixture, so the test distinguishes stop from kill rather than merely observing a stop.

- [ ] **Step 2: Run it and record the red**

Expected: fails to compile — `Actor.stop` does not exist. That is the correct red for this step; record it.

- [ ] **Step 3: Add the runtime function**

Beside `march_kill` (`runtime/march_runtime.c:3951`):

```c
/* Retire an actor: a deliberate, orderly stop. Unlike march_kill (which
 * reports MARCH_DEATH_KILLED and therefore restarts a permanent or transient
 * child), this reports MARCH_DEATH_NORMAL, which no restart type restarts.
 * This is March's equivalent of OTP's supervisor:terminate_child — the way to
 * take a supervised child out of service without fighting its supervisor. */
void march_actor_stop(void *actor) {
    do_actor_death(actor, MARCH_DEATH_NORMAL, NULL, 0);
}
```

Declare it in `runtime/march_runtime.h` beside `march_kill`.

- [ ] **Step 4: Wire the builtin through all five sites**

Use `actor_unregister` as the template — grep it to see every site at once:

```bash
grep -rn "actor_unregister" lib/typecheck/typecheck.ml lib/tir/llvm_builtins.ml lib/tir/defun.ml lib/eval/eval.ml runtime/march_runtime.h
```

- `lib/typecheck/typecheck.ml` — `("actor_stop", Mono (TArrow (t_pid, t_unit)));` beside the other `actor_*` entries. Check the exact `t_pid`/`t_unit` names used nearby.
- `lib/tir/llvm_builtins.ml` — a `{ march_name = "actor_stop"; c_name = Some "march_actor_stop"; ret_ty = None; in_is_builtin = true; declare_sig = Some "declare void @march_actor_stop(ptr %actor)" }` entry, plus `PDeclare "march_actor_stop"` in the declaration list at `:1542`.
- `lib/tir/defun.ml:97` — add `"actor_stop"` to the builtin-names list.
- `lib/eval/eval.ml` — an interpreter builtin beside `actor_unregister` that marks the actor dead the same way a normal exit does, so the interpreter's own supervisor filter declines to restart it.
- `stdlib/actor.march` — a `fn stop(pid)` wrapper beside `fn unregister(name)` (`:105`), with a docstring saying it retires a supervised child without triggering a restart, and contrasting it with `kill`.

Missing any one of these five is the documented failure mode for adding a builtin here.

- [ ] **Step 5: Rebuild and run**

```bash
dune build --root . @install
DUNE_CACHE=disabled dune build --root . @bin/warm-cache --force
rm -rf .march/cas/artifacts-v2/
dune build --root . @test/runtest > /tmp/t4-rt.log 2>&1; echo "exit=$?" > /tmp/t4-rt.exit
./_build/default/test/run_stdlib.exe -e > /tmp/t4-stdlib.log 2>&1; echo "exit=$?" > /tmp/t4-stdlib.exit
./_build/default/test/run_eval.exe -e > /tmp/t4-eval.log 2>&1; echo "exit=$?" > /tmp/t4-eval.exit
```
`@install` is required because you edited `stdlib/*.march`; without it the module change is not staged and you will see "Module `Actor` does not export `stop`" against your own new code.

Expected: all exit 0, zero FAILs, zero golden diffs. Run the new fixture interpreted too.

- [ ] **Step 6: Commit**

```bash
git add runtime/march_runtime.c runtime/march_runtime.h lib/typecheck/typecheck.ml lib/tir/llvm_builtins.ml lib/tir/defun.ml lib/eval/eval.ml stdlib/actor.march test/dune test/native/supervisor_restart_stop_retires.march test/native/supervisor_restart_stop_retires.expected
git commit -m "actor: add Actor.stop to retire a supervised child"
```

---

### Task 5: Remaining coverage, docs, close-out

**Files:**
- Test: `test/native/supervisor_restart_transient_crash.march`, `supervisor_restart_permanent_default.march`, `supervisor_restart_budget_unspent.march` (+ `.expected`, + `test/dune` rules)
- Modify: `docs/actors.md` AND `specs/lang/actors.md` (drifted duplicates — both, byte-identical)
- Modify: `CHANGELOG.md`
- Modify: `stdlib/dist_supervisor.march` (comment only)
- Move: `specs/todos/2026-08-12-supervisor-restart-types-and-child-specs.md` → `specs/progress/`

- [ ] **Step 1: The three remaining goldens**

- `supervisor_restart_transient_crash.march` — a `restart transient` child that `panic()`s IS restarted.
- `supervisor_restart_permanent_default.march` — a child with no modifier behaves exactly as today: `kill()` restarts it, `panic()` restarts it.
- `supervisor_restart_budget_unspent.march` — retire three `temporary` children in a row under `max_restarts 2 within 60`; assert the supervisor is still alive. This is the §2 budget-accounting guard: if the filter were placed after the streak update, this escalates and kills the supervisor.

Run each compiled and interpreted against the same `.expected`.

- [ ] **Step 2: Document, including the awkward part**

Add a "Restart types" section to the actors chapter, in BOTH `docs/actors.md` and `specs/lang/actors.md`, byte-identical. It must contain:
- the normative table from this plan;
- that `permanent` is the default and existing blocks are unaffected;
- that March's `permanent` does NOT restart on normal exit, unlike OTP's — an Erlang reader will assume otherwise and nothing will catch it;
- that **`transient` is currently indistinguishable from `permanent` locally**, why (March has no restart-on-normal), and that it exists for parity with `DistSupervisor`;
- `Actor.stop` as the way to retire a child, contrasted with `kill`.

Verify parity:
```bash
diff <(sed -n '/## Restart types/,/^## /p' docs/actors.md) <(sed -n '/## Restart types/,/^## /p' specs/lang/actors.md)
```
Expected: no output.

- [ ] **Step 3: Fix the distributed plane's stale claim**

`stdlib/dist_supervisor.march:7` says "Restart strategies (matching local supervisor semantics)". That was aspirational — local had none. It is now *nearly* true, with one difference: `DistSupervisor`'s `Permanent` restarts on `Normal` (`:56`, `Permanent -> true`), the local one does not. Amend the comment to state that difference explicitly. Do not change its code.

- [ ] **Step 4: CHANGELOG**

A `### Added` bullet for the restart modifier and `Actor.stop`, leading with what a user can now do (retire a worker that has finished) rather than the mechanism. Mention the `permanent`/`transient` equivalence so it is not discovered as a surprise.

- [ ] **Step 5: Full verification**

```bash
uptime
DUNE_CACHE=disabled dune build --root . --force > /tmp/t5-build.log 2>&1; echo "exit=$?" > /tmp/t5-build.exit
scripts/run-tests.sh > /tmp/t5-suite.log 2>&1; echo "exit=$?" > /tmp/t5-suite.exit
dune build --root . @test/runtest > /tmp/t5-rt.log 2>&1; echo "exit=$?" > /tmp/t5-rt.exit
bash scripts/actor-load.sh > /tmp/t5-load.log 2>&1; echo "exit=$?" > /tmp/t5-load.exit
bash scripts/check-docs.sh > /tmp/t5-dl.log 2>&1; echo "exit=$?" > /tmp/t5-dl.exit
dune build --root . @types-check --force > /tmp/t5-types.log 2>&1; echo "exit=$?" > /tmp/t5-types.exit
dune build --root . @grammar-check --force > /tmp/t5-gram.log 2>&1; echo "exit=$?" > /tmp/t5-gram.exit
dune build --root . test/run_snapshots.exe && ./_build/default/test/run_snapshots.exe -e > /tmp/t5-snap.log 2>&1; echo "exit=$?" > /tmp/t5-snap.exit
git diff --stat test/snapshots/
```

Report each individually. Both CI-only gates MUST use `--force` — without it `@types-check` exits 0 on a zero-byte log and proves nothing; report each log's byte count as evidence it ran. `actor-load.sh` must show all four scenarios PASS.

**A TIR snapshot diff is expected here** — unlike the race-fix branch, this plan changes lowering (`lower_actor.ml` emits a new argument). Review the diff and confirm it is only the added register-child argument, then regenerate deliberately with `UPDATE_SNAPSHOTS=1 ./_build/default/test/run_snapshots.exe -e` and include the regenerated files in the commit. If the diff shows anything beyond that argument, STOP and report.

- [ ] **Step 6: Close out and commit**

`git mv specs/todos/2026-08-12-supervisor-restart-types-and-child-specs.md specs/progress/2026-08-17-supervisor-restart-types.md` and rewrite it as a completed record: what shipped, the normative table, the `permanent`/`transient` equivalence and why, the `Actor.stop` decision and its OTP lineage, and what stayed out of scope (`shutdown`, `type`, `significant`).

```bash
git add test/dune test/native specs/progress/2026-08-17-supervisor-restart-types.md docs/actors.md specs/lang/actors.md CHANGELOG.md stdlib/dist_supervisor.march test/snapshots
git commit -m "docs+specs: restart types shipped; close the child-spec todo"
```

---

## Self-Review Notes

- **Spec coverage:** design §3 syntax → Task 1; §4.1-4.3 plumbing → Task 2; §4.4 filter + §4.5 batch respawn + §4.6 interpreter → Task 3; `Actor.stop` (§2 retirement) → Task 4; §5 test matrix → Tasks 3-5; §6 risks → guarded by the budget golden (Task 5), the batch golden (Task 3), and the unchanged existing goldens (Task 3 Step 6).
- **Deliberately out of scope:** `shutdown` timeouts (needs `2026-08-12-graceful-shutdown-and-drain`), OTP's `type`/`significant`, and changing `permanent` to restart on normal exit (rejected breaking change).
- **Riskiest tasks:** Task 3 (the batch-respawn skip is the easiest thing in this plan to omit, and no single-child test catches it) and Task 2 (ABI change to a codegen-emitted symbol — a missed `.ll` golden fails only in CI).
- **Ordering:** strictly sequential. Task 2 depends on Task 1's AST, Task 3 on Task 2's struct field, Task 4 on Task 3's filter, Task 5 on all.
- **Unlike the preceding race-fix plan, everything here is deterministically testable** — this is single-threaded policy, not a concurrency window. There is no structural-argument escape hatch; every acceptance criterion gets a golden that fails before its fix.
