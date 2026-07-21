# FQN impl-coherence — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the impl-coherence check from falsely rejecting two distinct same-short-name types (e.g. `AeLib.AeDir` vs `AeLib2.AeDir`) that each declare their own `impl Eq(...)`, while keeping all genuine overlap rejections.

**Architecture:** The coherence check in `register_impl_shape` compares impl head types by BARE name, so `AeLib.AeDir` and `AeLib2.AeDir` both look like `TCon("AeDir")` and collide. Stage 1 threads the impl's **declaring module** into `register_impl_shape`, resolves each head to its **declaring-module identity** (`decl_module` for a locally-declared bare head, the `.`-prefix for a qualified head, `None`/conservative otherwise), stores that identity on each `env.impls` entry, and treats two heads as overlapping **only if they do not resolve to two distinct concrete modules**. The stored `inst_ty` stays BARE so `discharge_constraints` is untouched. No codegen/mangling change → goldens byte-identical.

**Tech Stack:** OCaml 5.3.0, dune, Alcotest. March compiler (`lib/typecheck/typecheck.ml`), LSP (`lsp/lib/analysis.ml`), witness harness (`specs/lang/types/`, `dune build @types-check`).

## Global Constraints

- opam switch `march`; `dune`/`opam` are on PATH. **NEVER** prefix commands with `eval $(opam env ...)`.
- Work INSIDE the worktree; build with `dune build --root .` and run `./_build/default/bin/main.exe` with **NO `cd`** to the main repo (main is on a different branch lacking this code).
- Branch: `claude/fqn-impl-coherence-636503`.
- Stage this feature only; do NOT change `mangle_ty`, lowering, or eval dispatch in Stage 1 (those are Stages 2–3). Goldens/CAS must stay byte-identical.
- Stage files explicitly by name at commit (no `git add -A`/`.`/`-am`). No `Co-Authored-By` lines.
- After a feature change, update `specs/todos.md` + `specs/progress.md` in the same commit (project rule in CLAUDE.md).

---

### Task 1: Coherence keys on declaring-module identity

**Files:**
- Modify: `lib/typecheck/typecheck.ml` — `impls` field (`:503`), `base_env` seed (`:2254-2258`), `register_impl_shape` (`:5924-6005`), discharge read (`:6113-6116`), check_decl DImpl re-reg (`:8396-8401`), pass-1 fold call sites (`:9556`, `:9610`, `:9611`, `:9618`, `:9847`).
- Modify: `lsp/lib/analysis.ml` — impls destructure sites (`:3498`, `:4672`).
- Test: `test/test_compiler.ml` (new coherence unit tests).
- Test fixtures: `specs/lang/types/accept/t88_impl_distinct_modules.march` (new), existing `reject/t79`, `reject/t80`, `accept/t83`, `accept/t85`.

**Interfaces:**
- Produces: `register_impl_shape : ?decl_module:string -> env -> Ast.impl_def -> env` (new optional `decl_module`, default `""`).
- Produces: `env.impls : (ty * Ast.span * string option) list StrMap.t` (3rd element = resolved declaring-module of the head type, `None` when unresolved).
- Consumes (unchanged): `env.types : int StrMap.t` (holds both bare `T` and qualified `Mod.T` keys — verified 2026-07-20).

- [ ] **Step 1: Write failing witness — two distinct same-name types accept**

Create `specs/lang/types/accept/t88_impl_distinct_modules.march`:

```march
-- Coherence accept: two DISTINCT types that share the short name `Thing`,
-- declared in different (nested) modules, may each implement the same
-- interface — they are different types, so their heads do NOT overlap.
-- Regression for the bare-name coherence key (AeLib.AeDir vs AeLib2.AeDir).
mod Top do
  interface Speak(a) do
    fn speak : a -> String
  end
  mod NA do
    type Thing = TA
    impl Speak(Thing) do
      fn speak(_self) do "from-A" end
    end
    fn mk() do TA end
  end
  mod NB do
    type Thing = TB
    impl Speak(Thing) do
      fn speak(_self) do "from-B" end
    end
    fn mk() do TB end
  end
  fn main() do 0 end
end
```

- [ ] **Step 2: Run the witness harness — confirm it currently FAILS**

Run: `dune build @types-check 2>&1 | grep -E "t87|Overlapping|passed, .* failed"`
Expected: `[accept/t88_impl_distinct_modules.march] FAIL — should typecheck but was rejected` (today the bare-name key rejects it).

- [ ] **Step 3: Widen the `impls` entry tuple to carry the head's declaring module**

In `lib/typecheck/typecheck.ml`, change the field (`:503`):

```ocaml
  impls      : (ty * Ast.span * string option) list StrMap.t;
```

Update the doc comment just below it to note the 3rd element:
`(** iface_name → (bare impl head type, decl span, resolved declaring-module of
    the head type — None when unresolved). Head type stays BARE so
    [discharge_constraints] is unaffected; the module is used ONLY by the
    coherence overlap test. *)`

In `base_env` (`:2254-2258`), add `None` to the seeded built-in tuple:

```ocaml
    impls      = List.fold_left (fun m (k, v) ->
                   let lst = Option.value ~default:[] (StrMap.find_opt k m) in
                   (* Built-ins carry [dummy_span]; the coherence check reads it
                      to phrase a user-impl-over-builtin conflict specially. *)
                   StrMap.add k ((v, Ast.dummy_span, None) :: lst) m) StrMap.empty builtin_impls;
```

- [ ] **Step 4: Add the declaring-module resolver + `decl_module` param + module-aware overlap test**

Replace the head of `register_impl_shape` (`:5924`) signature line:

```ocaml
let register_impl_shape ?(decl_module="") env (idef : Ast.impl_def) =
```

Immediately after `let lst = Option.value ~default:[] (StrMap.find_opt key env.impls) in` (`:5969`), insert the resolver + this impl's module:

```ocaml
  (* Resolve the head type's DECLARING MODULE (verified 2026-07-20):
     - qualified head "Mod.T" → the "Mod" prefix (the type's real module,
       regardless of where the impl is written — keeps orphan impls colliding);
     - bare head "T" declared locally by the impl's own module → decl_module
       ([decl_module ^ ".T"] is registered in env.types by the pass-1 prebind);
     - otherwise None → conservative (treated as overlapping, no false negative,
       e.g. two modules both implementing the SAME imported type). *)
  let head_type_module =
    match idef.impl_ty with
    | Ast.TyCon (n, _) ->
      let name = n.txt in
      (match String.rindex_opt name '.' with
       | Some i -> Some (String.sub name 0 i)
       | None ->
         if decl_module <> ""
            && StrMap.mem (decl_module ^ "." ^ name) env.types
         then Some decl_module
         else None)
    | _ -> None
  in
  let modules_distinct m1 m2 =
    match m1, m2 with Some a, Some b -> a <> b | _ -> false in
```

- [ ] **Step 5: Make the overlap `find_opt` and the register/no-op branch module-aware**

Replace the overlap match block (`:5986-6005`). New `find_opt` predicate adds the module guard; the `Some`/`None` branches carry `head_type_module`:

```ocaml
  match List.find_opt
          (fun (t, s, m_old) ->
             s <> sp && s <> Ast.dummy_span
             && types_overlap t inst_ty
             && not (modules_distinct m_old head_type_module))
          lst with
  | Some (_, prev_sp, _) ->
    Err.error env.errors ~span:sp
      (Printf.sprintf
         "Overlapping implementation: `impl %s(%s)` conflicts with the \
          implementation at %s:%d:%d — their heads overlap.\n\
          A type may implement an interface at most once (coherence). If you \
          meant a different behavior, wrap the type in a newtype and implement \
          the interface on that."
         key (pp_ty inst_ty)
         prev_sp.Ast.file prev_sp.Ast.start_line prev_sp.Ast.start_col);
    env   (* keep the first impl — deterministic *)
  | None ->
    (* No conflict. Register (unless our own same-span entry is already present
       from a Pass-1 re-registration, in which case this is a no-op). *)
    if List.exists (fun (t, s, _) -> s = sp && types_overlap t inst_ty) lst
    then env
    else { env with impls =
             StrMap.add key ((inst_ty, sp, head_type_module) :: lst) env.impls }
```

- [ ] **Step 6: Fix the discharge read for the new tuple arity**

In `discharge_constraints` (`:6113-6115`), change the destructure:

```ocaml
             | Some impl_tys -> List.exists (fun (impl_ty, _, _) ->
                 impl_matches_ty (repr impl_ty) ty) impl_tys
```

- [ ] **Step 7: Fix the pass-2 re-registration tuple (check_decl DImpl)**

In `check_decl`'s `DImpl` arm (`:8401`), add `None` (pass 2 only re-registers for discharge; the coherence module was already resolved in pass 1):

```ocaml
       StrMap.add key ((inst_ty, idef.impl_iface.span, None) :: lst) env.impls) } in
```

- [ ] **Step 8: Thread `decl_module` at the four pass-1 fold call sites**

`check_module_core` public `DMod` fold (`:9556`):

```ocaml
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
```

`check_module_core` entry-module top-level `DImpl` (`:9610`):

```ocaml
      | Ast.DImpl (idef, _) ->
        register_impl_shape env idef ~decl_module:m.Ast.mod_name.txt
```

`check_module_core` private `DMod` fold (`:9611`/`:9618`) — capture the name and thread it:

```ocaml
      | Ast.DMod (mname, _, inner_decls, _) ->
        (* Interface implementations declared in sibling modules must be
           visible unit-wide regardless of the order modules are checked in:
           CInterface constraints discharge at declaration boundaries, so an
           impl that is only registered when its defining module is reached
           cannot satisfy constraints from modules checked earlier. *)
        List.fold_left (fun e d -> match d with
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
            | _ -> e
          ) env inner_decls
```

`check_module_with_env` public `DMod` fold (`:9847`):

```ocaml
            | Ast.DImpl (idef, _) -> register_impl_shape e idef ~decl_module:mname.Ast.txt
```

- [ ] **Step 9: Fix LSP destructure sites for the new tuple arity**

In `lsp/lib/analysis.ml`, update the two sites that destructure `impls` values. At `:3498` and `:4672`, change any `(ty, span)` pattern over an impls entry to `(ty, span, _)`. Read each site first; e.g.:

```ocaml
      (* was: List.map (fun (ty, sp) -> ...) *)
      List.map (fun (ty, sp, _) -> (* ... existing body ... *)) final_env.Tc.impls
```

Also update the comment at `:3493` (`[Tc.impls] values are now [(ty * span * string option)]`).

- [ ] **Step 10: Build and confirm the accept witness now passes + no other witness regressed**

Run: `dune build --root . bin/main.exe 2>&1 | tail -3`
Expected: build succeeds (no arity errors remain).

Run: `dune build @types-check 2>&1 | tail -20`
Expected: `t87` now `OK (typechecks)`; `reject/t79_impl_coherence_duplicate` and `reject/t80_impl_parametric_overlap` still `OK (rejected: ...)`; `accept/t83`, `accept/t85` still `OK`; final line `... 0 failed`.

- [ ] **Step 11: Add fast Alcotest unit tests mirroring the witnesses**

In `test/test_compiler.ml`, add (near the other interface tests, e.g. after `test_interface_method_with_impl`):

```ocaml
let test_impl_coherence_distinct_modules_ok () =
  (* Two DISTINCT same-short-name types in sibling nested modules may each
     implement the same interface — no false overlap. *)
  let ctx = typecheck {|mod Top do
    interface Speak(a) do
      fn speak : a -> String
    end
    mod NA do
      type Thing = TA
      impl Speak(Thing) do fn speak(_x) do "a" end end
    end
    mod NB do
      type Thing = TB
      impl Speak(Thing) do fn speak(_x) do "b" end end
    end
  end|} in
  Alcotest.(check bool) "distinct-module same-name impls: no error"
    false (has_errors ctx)

let test_impl_coherence_same_module_duplicate_err () =
  (* Two impls of the SAME interface for the SAME type in one module still
     overlap and are rejected (coherence unchanged). *)
  let ctx = typecheck {|mod M do
    interface Speak(a) do
      fn speak : a -> String
    end
    type Dog = Dog
    impl Speak(Dog) do fn speak(_x) do "woof" end end
    impl Speak(Dog) do fn speak(_x) do "bark" end end
  end|} in
  Alcotest.(check bool) "same-module duplicate impl: error"
    true (has_errors ctx)
```

Register them in the test list at the bottom of `test/test_compiler.ml` under an appropriate group (e.g. the interfaces group):

```ocaml
    Alcotest.test_case "impl coherence: distinct modules ok" `Quick test_impl_coherence_distinct_modules_ok;
    Alcotest.test_case "impl coherence: same-module dup err" `Quick test_impl_coherence_same_module_duplicate_err;
```

- [ ] **Step 12: Run the compiler + LSP test suites**

Run: `dune build test/run_compiler.exe && ./_build/default/test/run_compiler.exe -e 2>&1 | tail -15`
Expected: all pass, including the two new cases.

Run: `dune build @types-check && dune runtest --root . lsp 2>&1 | tail -15`
Expected: LSP tests pass (the `test_lsp.ml:867` `impls is a list` check still holds with the 3-tuple).

- [ ] **Step 13: Commit**

```bash
git add lib/typecheck/typecheck.ml lsp/lib/analysis.ml test/test_compiler.ml specs/lang/types/accept/t88_impl_distinct_modules.march
git commit -m "fix(typecheck): impl-coherence keys on declaring-module identity

Two distinct same-short-name types from different modules (AeLib.AeDir vs
AeLib2.AeDir) each implementing the same interface no longer trip a false
'Overlapping implementation'. register_impl_shape now threads the impl's
declaring module and resolves each head's declaring-module identity; heads
overlap only when they do NOT resolve to two distinct concrete modules. Head
type stays bare in env.impls so discharge is unaffected; no codegen change.
Witness accept/t87; reject/t79,t80 + accept/t83,t85 unchanged."
```

---

### Task 2: De-workaround the `adt_eq_native` fixture

**Files:**
- Modify: `test/imports/adt_eq_native/ae_lib.march`, `ae_lib2.march` (add per-module `impl Eq(AeDir)`), `ae_entry.march` (drop blanket `impl Eq(a)`).

**Interfaces:**
- Consumes: Task 1's coherence fix (distinct-module `impl Eq(AeDir)` now accepted).

- [ ] **Step 1: Add per-module `impl Eq(AeDir)` to `ae_lib.march`**

Edit `test/imports/adt_eq_native/ae_lib.march` — after the `AeDir` type, add:

```march
impl Eq(AeDir) do
  fn eq(x, y) do eq(x, y) end
end
```

- [ ] **Step 2: Add per-module `impl Eq(AeDir)` to `ae_lib2.march`**

Edit `test/imports/adt_eq_native/ae_lib2.march` — after its `AeDir` type, add the same block:

```march
impl Eq(AeDir) do
  fn eq(x, y) do eq(x, y) end
end
```

- [ ] **Step 3: Remove the blanket `impl Eq(a)` from `ae_entry.march`**

Edit `test/imports/adt_eq_native/ae_entry.march` — delete the blanket impl block (the `impl Eq(a) do fn eq(x, y) do eq(x, y) end end` and its comment). Leave the rest (imports, `check`, `main`) unchanged.

- [ ] **Step 4: Typecheck the fixture (no overlap error)**

Run: `MARCH_LIB_PATH=test/imports/adt_eq_native ./_build/default/bin/main.exe --check test/imports/adt_eq_native/ae_entry.march; echo "EXIT=$?"`
Expected: `EXIT=0`, no `Overlapping implementation` output.

- [ ] **Step 5: Compile + run the fixture natively (end-to-end proof)**

Run:
```bash
MARCH_LIB_PATH=test/imports/adt_eq_native ./_build/default/bin/main.exe --compile \
  -o /tmp/adt_eq_native_636503 test/imports/adt_eq_native/ae_entry.march && /tmp/adt_eq_native_636503
echo "EXIT=$?"
```
Expected: prints the `ok ...` lines then `all ok`, `EXIT=0`.

- [ ] **Step 6: Run the fixture's dune test rule**

Run: `dune build @runtest --root . 2>&1 | grep -iE "adt_eq_native|fail" | head` (or run the whole suite in Task 3).
Expected: no adt_eq_native failure.

- [ ] **Step 7: Commit**

```bash
git add test/imports/adt_eq_native/ae_lib.march test/imports/adt_eq_native/ae_lib2.march test/imports/adt_eq_native/ae_entry.march
git commit -m "test(imports): adt_eq_native uses per-module impl Eq(AeDir)

Drops the blanket impl Eq(a) workaround now that impl-coherence distinguishes
AeLib.AeDir from AeLib2.AeDir. Proves the fix end-to-end (compiled): each
module's own impl Eq(AeDir) coexists and the native structural-eq path
dispatches correctly."
```

---

### Task 3: Full-suite validation, golden byte-identity, docs

**Files:**
- Modify: `specs/todos.md` (move item to Done), `specs/progress.md` (capability + counts).

**Interfaces:**
- Consumes: Tasks 1–2.

- [ ] **Step 1: Run the full test suite (not `-q`)**

Run: `scripts/run-tests.sh 2>&1 | tail -30`
Expected: all suites green. Judge by exit code: `echo "SUITE_EXIT=$?"` must be `0` (rule failures can hide above a green Alcotest summary).

- [ ] **Step 2: Confirm codegen goldens + TIR snapshots are byte-identical**

Run: `dune build @types-check @runtest --root . 2>&1 | grep -iE "snapshot|golden|codegen|differs|FAIL" | head`
Then: `git status --porcelain test/snapshots/` — expected: EMPTY (Stage 1 changes no IR; no `UPDATE_SNAPSHOTS` needed).
If any snapshot/golden differs, STOP — Stage 1 must not change codegen; investigate before proceeding.

- [ ] **Step 3: Run the oracle (interp-vs-compile parity)**

Run: `dune build @oracle --root . 2>&1 | tail -15`
Expected: oracle green (0 divergences introduced).

- [ ] **Step 4: Update `specs/todos.md`**

Move the impl-coherence FQN item (or add one) to the Done section, e.g.:
`- [x] impl-coherence: distinguish same-short-name types by declaring module (Stage 1 of FQN dispatch identity — specs/plans/2026-07-20-fqn-impl-dispatch-identity.md)`

- [ ] **Step 5: Update `specs/progress.md`**

Add to the feature list, e.g.:
`- Interface impl coherence distinguishes same-short-name types from different modules (AeLib.AeDir vs AeLib2.AeDir) by declaring-module identity; two per-module impls of the same interface no longer false-overlap.`
Bump the "Current State" test count if the two new Alcotest cases + t87 witness changed it.

- [ ] **Step 6: Commit**

```bash
git add specs/todos.md specs/progress.md
git commit -m "docs(specs): record impl-coherence declaring-module identity (Stage 1)"
```

---

## Self-Review

**Spec coverage (Stage 1 slice of the design spec):**
- Thread declaring module into `register_impl_shape` → Task 1 Steps 4, 8. ✓
- Coherence identity from `decl_module`/qualified-prefix, `inst_ty` bare → Steps 4, 5. ✓
- Distinct-module heads don't overlap; t79/t80 still reject; t83/t85 still accept → Steps 1, 5, 10, 11. ✓
- `adt_eq_native` drops blanket workaround → Task 2. ✓
- Byte-identical goldens → Task 3 Step 2. ✓
- Docs freshness → Task 3 Steps 4–5. ✓
- Stages 2–3 (interp dispatch, native runtime ctor-tag dispatch) are explicitly OUT of this plan (see the design spec) — general-user-interface colliding dispatch still (correctly) rejects natively until Stage 3; that residual is expected here.

**Placeholder scan:** No TBD/TODO; every code step shows exact code. The only "read the site first" is LSP Step 9 (the surrounding body is site-specific) — the pattern change is fully specified.

**Type consistency:** `impls` is `(ty * Ast.span * string option)` at the field (Step 3), seed (Step 3), register (Step 5), discharge read (Step 6), re-reg (Step 7), and LSP (Step 9). `register_impl_shape`'s `?decl_module` is consumed at all four call sites (Step 8) and defined in Step 4. `head_type_module`/`modules_distinct` defined in Step 4, used in Step 5.
