# Capture capabilities for the children of a NESTED supervisor

**Status:** specced 2026-09-03, not started. Parent: `specs/progress/2026-09-03-supervised-children-not-captured.md` (#405), whose "Still not covered" note this is; grandparent: `specs/progress/2026-09-02-lift-one-cap-per-actor.md` (#404), whose RC contract and null-safe dispatch this relies on.

## What the gap is, precisely

#405 gives a supervisor's spawn glue (`Sup_spawn`) its children's capabilities as parameters: `needed_caps` models the glue as calling each child's dispatch, the user's `spawn(Sup)` site threads the caps in, and the supervised-child pattern in `thread` builds each child's record inside the glue from those parameters. That works because `Sup_spawn` is only ever a CALL HEAD.

A supervisor that is itself a supervised child is different. `lower_actor.ml`'s `mk_reg_child_calls` (~L420–L447) emits, for every declared child `f` of type `Mid`,

```
let $reg_child_f = register_supervisor_child($spawned, $sup_child_ptr_f, Mid_spawn, <word_idx>, <restart>) in …
```

passing `Mid_spawn` AS A VALUE (`Tir.AVar child_spawn_fn_var`) so the runtime can re-run it on respawn (`march_respawn_child`, `runtime/march_runtime.c` ~L3227: it reads the `$clo_wrap` pointer out of the closure cell at offset 16 and calls it with the cell as its only argument). `scan`'s `mark` (`cap_passing.ml` ~L116) sees that `AVar` and puts `Mid_spawn` in `unsafe`, so `needed_caps` drops it: its arity is frozen. Frozen means it carries no parameters, so inside it the supervised-child pattern has nothing to supply — it sees `binds = []` and, per #405, deliberately sets no record (so the child stays NULL rather than getting a record of sentinels). `Mid`'s own record IS set, by the pattern inside `Top_spawn`; only `Mid`'s children — `Top`'s grandchildren — are uncaptured. Their dispatch reads NULL, takes #404's `None` arm, and runs unmocked. No crash; wrong answer under `--test` only.

Reproducer shape (compiled `--test`):

```march
actor Leaf do … on Say(s) do print_line("leaf:" ++ s) … end
actor Mid do state { l : Int }  supervise do strategy one_for_one  max_restarts 5 within 60  Leaf l end end
actor Top do state { m : Int }  supervise do strategy one_for_one  max_restarts 5 within 60  Mid m end end
-- inside with_cap(mock, …): spawn(Top); send(<Top.m.l>, Say("hi"))   → prints leaf:hi, expected MOCK[leaf:hi]
```

## Design: replace the frozen value with a closure that carries the caps

The value the runtime needs is "something it can call with no arguments to get a fresh `Mid`". It does not need that to be `Mid_spawn` itself. So:

1. **`Mid_spawn` stops being frozen.** In `scan`, the third argument of a `register_supervisor_child` call is NOT a value use of a top-level function: it is a reference `thread` is about to rewrite. Handle the `EApp (v, args)` case for `v.v_name = "register_supervisor_child"` specially — record the call head as usual, `atom` every argument EXCEPT the spawn-fn one (which is instead recorded as a call edge, `add f.calls owner sf.v_name`, so the glue's needs flow to the enclosing glue exactly as a plain call would). With that, `Mid_spawn` enters `need` with its children's caps (the supervised-child modelling from #405 already gives it those), and `Top_spawn` — which calls `Mid_spawn` as a call head in the supervised-child shape — picks them up transitively through the existing fixpoint. No new table.

2. **The spawn-site rewrites thread the child's spawn call.** #405's supervised-child pattern re-emits `child_call` unchanged (`T.ELet (raw, child_call, …)`), which was correct while a child's glue could never carry parameters. Now it can: use `go child_call` in BOTH arms of that pattern (captured and not), exactly as #405 did for the plain pattern's `spawn_call`. Missing this is an arity mismatch that dies at runtime, not a compile error — the same class as the SIGBUS in `scan`'s docstring.

3. **The respawn value becomes a closure.** In `thread`, a new `EApp` arm for `register_supervisor_child` whose third argument is `AVar sf` with `actor_of_spawn sf.v_name = Some _` and `Hashtbl.mem need sf.v_name` (a glue that now carries caps; one that carries none is left alone — a static function reference stays the cheapest thing to pass):

   ```
   let $respawn_f = letrec [ fn $respawn_f() : Ptr(Unit) = Mid_spawn(<supply c1>, …, <supply cn>) ]
                    in $respawn_f
   in register_supervisor_child($spawned, $sup_child_ptr_f, $respawn_f, <idx>, <restart>)
   ```

   Build the `fn_def` the way `lower_expr.ml`'s `ELam` case does (~L741–L815): `fn_params = []`, `fn_ret_ty = TPtr TUnit`, `fn_kind = FnLambda`, name from a fresh counter, and the `ELetRec ([fd], EAtom (AVar fn_var))` shape with `fn_var.v_ty = TFn ([], TPtr TUnit)` — that shape is what Defun's `lift_lambda` consumes. The body is the SAME threaded call the supervised-child pattern would emit for `Mid_spawn`, so the two cannot disagree; factor one helper for it. `<supply c>` is the enclosing glue's own `$cap_c` parameter (it has all of them by step 1), so the lambda's free variables are exactly those parameters; Defun captures them into the closure struct and Perceus dups them at the capture (they are also used by the child's record build in the same scope, so the capture is a non-last use → `inc_rc`; prove it in the dump).

   The lambda's apply function takes ONLY the closure cell: verified 2026-09-03 on `let f = fn -> k + 1` — Perceus dump shows `$lam…$apply$…(f)`, one argument. That matches `spawn_clo_fn_t (void *)` in `march_respawn_child`, and the return is the uniform ptr ABI, which for `Ptr(Unit)` is the pointer itself. No runtime ABI change.

4. **One runtime line, and it is load-bearing.** Every apply function drops its closure at entry (`Perceus.insert_apply_fn_clo_drop`, `perceus.ml` ~L304: the caller transfers ownership of the cell). `march_respawn_child` calls the closure on EVERY respawn of the same child slot. With today's immortal static reference that drop is a no-op; with a heap closure the FIRST respawn frees the cell and the SECOND is a use-after-free. So before the call:

   ```c
   march_incrc(child->spawn_clo);   /* the apply fn drops what it is handed; keep ours */
   void *raw = fn_ptr(child->spawn_clo);
   ```

   `march_incrc` is `IS_HEAP_PTR`-guarded (`march_runtime.c` ~L338), so it stays a no-op for the static reference that non-capturing children keep passing. `register_supervisor_child` stores the cell forever (the meta is never freed), which is the +1 the caller's owned argument hands it; nothing else changes. Edit `runtime/*.c` → remember `dune build bin/main.exe` does not restage the runtime; build a target with a runtime dep (`@test/runtest` or the golden's `.out`).

What this buys beyond the grandchild case: when `Mid` is respawned, its NEW children are spawned by `Mid_spawn(<caps>)` through the closure, so they get fresh, correct records from the same capabilities the original spawn site supplied — a better respawn story than #405's pointer carry-over gives `Mid` itself (which stays as it is: the carry-over copies `Mid`'s own record; the closure re-creates the grandchildren's).

### Rejected: inherit up the supervisor chain at read time

Have `march_actor_caps` walk `meta->supervisor` when `spawn_cap` is NULL, and project by field NAME (an erased record type routes `EField` through the shape-id lookup in `Llvm_emit_data.emit_field`). Needs every supervisor's record to be the UNION of its descendants' caps, a needs_rc-false erased type for the dispatch read (`TRecord []`?) whose by-name miss must be proved to yield the sentinel, and it gives a respawned nested supervisor's children borrowed records instead of their own. Three unproven mechanisms against one line of runtime; not worth it.

## RC contract additions (the parent's items 1–5 still hold)

6. **The closure is retained forever**, like the record: `register_supervisor_child` takes it owned and the meta never releases it. The per-respawn `march_incrc` balances the apply function's entry drop exactly; no other RC op touches the cell.
7. **Capability parameters captured by the closure** are dup'd at the capture (non-last use — the child's record build in the same glue is another use). Prove: `MARCH_DUMP_TXT=perceus` on the fixture shows `inc_rc $cap_IO_Console` feeding the `alloc $Clo_$respawn…` (or the record build, whichever comes second takes the parameter's own +1; the first must show the dup).

## Tests

### Golden `test/cap_mock/cap_mock_supervised_nested.march` (+ `.expected`, `test/dune` rule mirroring `cap_mock_supervised`, compiled `--test` only)

Three levels: `Top` supervises `Mid` supervises `Leaf` (Console). Inside `with_cap(mock, …)`: `spawn(Top)`, read the grandchild pid through the two state fields (`get_actor_field` twice, as `cap_mock_supervised`'s `child_of` does), send → `MOCK[leaf:in]`. Then `kill` `Mid` (not `Leaf`): the runtime respawns `Mid` through the closure, which spawns a NEW `Leaf`; read the new grandchild pid, send → `MOCK[leaf:again]`. Then `kill` `Mid` a SECOND time and send once more → `MOCK[leaf:third]` — this row is the one that only the runtime `march_incrc` makes possible (see red control B). Finally a `Top` spawned outside every block, sent to after they close → `leaf:out`.

**Red controls, both mandatory:**
- A. Disable the closure rewrite (step 3 falls through to passing `Mid_spawn`; keep step 1 so it stays threaded — then `Mid_spawn` has parameters and the runtime calls it with none: expect the original spawn to still mock `leaf:in` and the respawned rows to be wrong or to crash). If that is too ugly a red, disable step 1 instead: `leaf:in` goes real, which is the honest "nothing captured" red. Either way say which in the commit.
- B. Restore A, remove the runtime `march_incrc`: the first respawn works and the SECOND (`leaf:third`) is a use-after-free — locally it may print anything or die; the sanitize-gate CI leg is the definitive red for this control, so push the control commit to a scratch branch or run the ASAN Docker recipe (`ci/Dockerfile.ubuntu`, build only `bin/main.exe`) and quote it. A control whose red is only "it happened to still print MOCK" has not proven the inc is needed.

### Unit, `test/test_cap_dict.ml`, next to `supervisor_glue_carries_children_caps`

Lower the three-level module; assert `need["Top_spawn"] = need["Mid_spawn"] = ["IO.Console"]` and `Hashtbl.mem need "Leaf_spawn" = false` (a leaf's glue is still a plain value reference and still needs nothing).

### Existing guards that must stay green

`cap_mock_supervised` (single level — the closure rewrite must not fire for a child whose glue carries nothing, so its `register_supervisor_child` call is byte-identical in the lower dump), the other four `cap_mock_*`, `stream_replay`, the native supervisor goldens (`supervisor_*_restart`, `actor_registry_restart*`, `actor_crash_rc_restore`: they compile WITHOUT `--test`, so the pass does not run, but they exercise the runtime line under repeated respawn), and the TIR snapshots.

## Order of work

1. `scan` special case + `go child_call`; unit test. Every existing golden byte-identical (nothing is rewritten yet — `Mid_spawn` gains parameters only when something captures, and no existing fixture nests).
2. Closure rewrite + runtime inc; the nested golden, red controls A then B, then green.
3. RC proof from the Perceus dump (items 6–7); push and let sanitize-gate run the fixture.
4. Parent progress file's "Still not covered" bullet → done; this file to `specs/progress/`; CHANGELOG `### Fixed` ("a supervisor nested under another supervisor now passes its capabilities on to its own children, including after a restart").

Estimated size: ~50 lines in `cap_passing.ml`, 1 line + comment in the runtime, one fixture, one unit test.
