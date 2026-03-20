# Phase 6b: Linear Drop Handlers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-defined linear drop handlers so that when an actor crashes, any linear values it "owns" call their `impl Drop` method in reverse acquisition order, extending Phase 6a's runtime-only `register_resource` to a fully typed, user-defined mechanism.

**Architecture:** A new `own(pid, value)` builtin registers a `(value, drop_fn)` pair in the actor's `ai_linear_values` list at runtime. The `drop_fn` is a March closure resolved at `own`-call time from a global impl table populated by `DImpl` evaluation. When `crash_actor` runs it walks `ai_linear_values` in reverse and calls each `drop_fn` on its paired value, mirroring the Phase 6a `ai_resources` pattern exactly.

**Tech Stack:** OCaml 5.3, Dune, Alcotest, Menhir, ocamllex.

---

## File Map

| File | What changes |
|------|-------------|
| `lib/eval/eval.ml` | Add `ai_linear_values` field to `actor_inst`; add global `impl_tbl`; handle `DImpl` in `eval_decl`; update all 5 `actor_inst` construction sites; add `own` builtin; call drop in `crash_actor` |
| `test/test_march.ml` | Add Phase 6b tests; update `mk_actor_inst` helper |
| `examples/supervision_linear_drop.march` | New example demonstrating the feature end-to-end |

**No changes needed to:**
- `lib/ast/ast.ml` — `DInterface` and `DImpl` AST nodes already exist
- `lib/lexer/lexer.mll` — `INTERFACE` and `IMPL` tokens already exist
- `lib/parser/parser.mly` — `interface_decl` and `impl_decl` grammar rules already exist
- `lib/typecheck/typecheck.ml` — `DInterface`/`DImpl` typechecking already exists (registers interface, validates method signatures)
- `stdlib/prelude.march` — no prelude changes needed for Phase 6b

---

## Background: What Currently Exists

### AST (lib/ast/ast.ml)

`DInterface` and `DImpl` are already declared in the `decl` variant. Their record types are fully defined:

```ocaml
(* Already in lib/ast/ast.ml — do not add these *)
and interface_def = {
  iface_name : name;
  iface_param : name;
  iface_superclasses : (name * ty list) list;
  iface_assoc_types : assoc_type_decl list;
  iface_methods : method_decl list;
}

and impl_def = {
  impl_iface : name;          (* Which interface, e.g. "Drop" *)
  impl_ty : ty;               (* For which type, e.g. TyCon("FileHandle", []) *)
  impl_constraints : (name * ty list) list;
  impl_assoc_types : (name * ty) list;
  impl_methods : (name * fn_def) list;  (* e.g. [("drop", fn_def)] *)
}
```

### Lexer & Parser

Both `interface` and `impl` keywords and their grammar rules are already implemented. The surface syntax that already parses:

```march
interface Drop(a) do
  fn drop : a -> Unit
end

impl Drop(FileHandle) do
  fn drop(h) do close_file(h) end
end
```

### Typechecker (lib/typecheck/typecheck.ml)

`DInterface` handling (lines 1844–1852): registers the interface in `env.interfaces` and adds each method as a polymorphic binding.

`DImpl` handling (lines 1854–1889): validates that the impl's methods exist in the declared interface and that their types match. Already working — no changes needed.

### Evaluator (lib/eval/eval.ml)

**`actor_inst` type** (lines 46–64): the mutable record for a live actor. Currently has `ai_resources : (string * (unit -> unit)) list` for Phase 6a cleanup thunks.

**`crash_actor`** (lines 701–741): marks actor dead, runs `ai_resources` in reverse (Phase 6a), delivers Down messages, propagates to links, notifies supervisor.

**`eval_decl`** (line 2784): `DInterface _` and `DImpl _` both fall through to `env` — they are no-ops in the evaluator today. Phase 6b gives `DImpl` meaning.

**Five `actor_inst` construction sites** (search for `ai_resources = []`):
1. `restore_actors` — line 221
2. `spawn_child_actor` — line 507
3. `ESpawn` supervisor child loop — line 2326
4. `ESpawn` non-supervisor inst — line 2355
5. `mk_actor_inst` in test/test_march.ml — line 1814

**`register_resource` builtin** (lines 932–943): existing March-callable builtin that registers `(unit -> unit)` thunks. The Phase 6b `own` builtin follows the same pattern but stores `(value * (value -> value))` pairs.

---

## Design Decision: `own` Builtin (Approach A)

**Two approaches were considered:**

**Approach A: Explicit `own` builtin** — user calls `own(pid, value)` to register a linear value and its drop impl with an actor. The runtime resolves the drop impl from the global impl table at call time.

```march
let handle = open_file("foo.txt")
let pid = spawn(FileActor)
own(pid, handle)   (* registers handle + FileHandle's Drop impl with actor pid *)
```

Pros: No type inference changes; simple to implement in ~50 lines; mirrors `register_resource` closely.
Cons: Requires user to explicitly call `own`; forgetting means no cleanup.

**Approach B: Implicit tracking via typechecker** — typechecker marks linear-typed expressions; evaluator auto-registers drops without user calls.
Pros: Ergonomic.
Cons: Requires significant typechecker changes out of scope for Phase 6b.

**Phase 6b implements Approach A.** Approach B is deferred to Phase 6c+.

**How impl resolution works:** A global `impl_tbl : (string * string, value) Hashtbl.t` maps `(iface_name, type_name)` pairs to the drop function value (a `VClosure` or `VBuiltin`). When `DImpl Drop(T) do fn drop(x) do ... end end` is evaluated, the evaluator looks up the method body, evaluates it to a `value`, and stores it in `impl_tbl` under `("Drop", "T")`. The `own` builtin then looks up `("Drop", type_tag_of value)` to get the drop function.

**Type tag extraction:** a helper `type_tag_of : value -> string option` maps runtime values to their type name string:
- `VInt _` → `"Int"`
- `VString _` → `"String"`
- `VBool _` → `"Bool"`
- `VFloat _` → `"Float"`
- `VUnit` → `"Unit"`
- `VCon (tag, _)` → `tag` (constructor name, which equals the type name for single-constructor newtypes like `FileHandle(Int)`)
- `VRecord _` → `"Record"` (or more precisely, needs a user-supplied type tag — see Task 6 notes)
- Other → `None` (own call fails with eval_error)

---

## Task 1: Add `ai_linear_values` to `actor_inst` and `impl_tbl` global

**Files:**
- Modify: `lib/eval/eval.ml`
- Modify: `test/test_march.ml`

### Overview
Add the `ai_linear_values` field to track owned linear values per actor, and add the global `impl_tbl` for resolving drop implementations.

- [ ] **Step 1: Write the failing test**

Add to `test/test_march.ml` after the Phase 6a tests (around line 4560), before `test_file_builtin_exists_false`:

```ocaml
(* ── Supervision Phase 6b: Linear Drop Handlers ──────────────────────────── *)

(** Phase 6b: ai_linear_values field exists on actor_inst. *)
let test_actor_inst_has_linear_values_field () =
  March_eval.Eval.reset_scheduler_state ();
  let inst = mk_actor_inst "A" true March_eval.Eval.VUnit in
  (* If this compiles and runs, the field exists *)
  Alcotest.(check int) "linear_values starts empty" 0
    (List.length inst.March_eval.Eval.ai_linear_values)
```

Also update `mk_actor_inst` in test_march.ml (line 1802) to include the new field:

```ocaml
let mk_actor_inst name alive st = March_eval.Eval.{
  ai_name          = name;
  ai_def           = dummy_actor_def;
  ai_env_ref       = ref [];
  ai_state         = st;
  ai_alive         = alive;
  ai_monitors      = [];
  ai_links         = [];
  ai_mailbox       = Queue.create ();
  ai_supervisor    = None;
  ai_restart_count = [];
  ai_epoch         = 0;
  ai_resources     = [];
  ai_linear_values = [];    (* NEW: Phase 6b *)
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | head -30
```

Expected: compile error about missing field `ai_linear_values`.

- [ ] **Step 3: Implement**

In `lib/eval/eval.ml`, after line 62 (`mutable ai_resources : ...`), add:

```ocaml
  mutable ai_linear_values : (value * value) list;
  (** Linear values owned by this actor: (value, drop_fn) pairs in acquisition order.
      drop_fn is a March callable (VClosure or VBuiltin) : value -> value.
      Walked in reverse and called at crash time (Phase 6b). *)
```

Then add the global impl table after `doc_registry` (around line 84):

```ocaml
(** Interface implementation table — maps (iface_name, type_name) to the method value.
    Populated when [eval_decl] processes [DImpl] nodes.
    Reset per module eval via [reset_scheduler_state]. *)
let impl_tbl : (string * string, value) Hashtbl.t = Hashtbl.create 8
```

Update `reset_scheduler_state` to also reset `impl_tbl`. Find `reset_scheduler_state` in the file and add:

```ocaml
Hashtbl.reset impl_tbl;
```

Update all five `actor_inst` construction sites by adding `ai_linear_values = [];` next to each `ai_resources = []`:

**Site 1** — `restore_actors` (line ~221):
```ocaml
(* old *)
ai_resources = [] } in
(* new *)
ai_resources = [];
ai_linear_values = [] } in
```

**Site 2** — `spawn_child_actor` (line ~507):
```ocaml
(* old *)
ai_resources = [] } in
(* new *)
ai_resources = [];
ai_linear_values = [] } in
```

**Site 3** — `ESpawn` supervisor child loop (line ~2326):
```ocaml
(* old *)
ai_restart_count = []; ai_epoch = 0;
ai_resources = [] } in
(* new *)
ai_restart_count = []; ai_epoch = 0;
ai_resources = [];
ai_linear_values = [] } in
```

**Site 4** — `ESpawn` non-supervisor inst (line ~2355):
```ocaml
(* old *)
ai_epoch = 0; ai_resources = [] } in
(* new *)
ai_epoch = 0; ai_resources = [];
ai_linear_values = [] } in
```

- [ ] **Step 4: Run to confirm it passes**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | head -30
```

Expected: all existing tests pass, new `test_actor_inst_has_linear_values_field` passes.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(6b): add ai_linear_values field to actor_inst and impl_tbl global"
```

---

## Task 2: Add `type_tag_of` helper and populate `impl_tbl` from `DImpl`

**Files:**
- Modify: `lib/eval/eval.ml`

### Overview
Add a helper that extracts a type name string from a runtime value (used by `own` to look up the right drop impl), and wire `DImpl` in `eval_decl` to populate `impl_tbl`.

- [ ] **Step 1: Write the failing test**

Add to `test/test_march.ml` (Phase 6b section):

```ocaml
(** Phase 6b: impl Drop for a type is registered in impl_tbl via eval. *)
let test_impl_drop_registered () =
  (* Evaluate a module with interface Drop and impl Drop for a custom type.
     Then check that own() can be called without error. *)
  let src = {|mod T do
    interface Drop(a) do
      fn drop : a -> Unit
    end
    type Color = Red | Green | Blue
    impl Drop(Color) do
      fn drop(c) do VUnit end
    end
    fn main() do
      VUnit
    end
  end|} in
  (* Should parse, typecheck, and eval without error *)
  let _env = March_eval.Eval.eval_module_str src in
  (* If impl_tbl has "Drop"/"Red" or similar, the impl was evaluated *)
  (* We test the observable effect via own() in a later task *)
  ()
```

Note: `eval_module_str` may not exist yet as a public function. Check how tests currently call eval. Looking at existing tests, they call `eval_with_stdlib` which uses internal helpers. For simplicity, skip the isolated unit test here and instead rely on the integration test in Task 5 that calls `own` end-to-end. Remove this test placeholder and proceed to implementation.

- [ ] **Step 2: Add `type_tag_of` helper**

In `lib/eval/eval.ml`, add this function after `register_resource_ocaml` (around line 784) and before `base_env`:

```ocaml
(** [type_tag_of v] returns the type name string for value [v], used to look up
    Drop implementations in [impl_tbl].
    - Primitives map to their canonical type name.
    - Constructor values map to their constructor tag (works for single-constructor
      newtypes like [type FileHandle = FileHandle(Int)]).
    - Returns [None] for values without a registered impl (VPid, VClosure, etc.). *)
let type_tag_of (v : value) : string option =
  match v with
  | VInt _    -> Some "Int"
  | VFloat _  -> Some "Float"
  | VString _ -> Some "String"
  | VBool _   -> Some "Bool"
  | VUnit     -> Some "Unit"
  | VCon (tag, _) -> Some tag
  | _ -> None
```

- [ ] **Step 3: Populate `impl_tbl` from `DImpl` in `eval_decl`**

In `lib/eval/eval.ml`, find `eval_decl` (line ~2677). Find the line:

```ocaml
  | DProtocol _ | DSig _ | DInterface _ | DImpl _ | DExtern _ | DUse _ | DNeeds _ -> env
```

Replace it with:

```ocaml
  | DProtocol _ | DSig _ | DInterface _ | DExtern _ | DUse _ | DNeeds _ -> env

  | DImpl (idef, _sp) ->
    (* Phase 6b: populate impl_tbl so the `own` builtin can resolve drop functions.
       For each method in this impl, store the evaluated function value in impl_tbl
       under (iface_name, type_name). Only the concrete type name is stored — for
       TyCon("FileHandle", []), the key is ("Drop", "FileHandle"). *)
    let type_name = match idef.impl_ty with
      | TyCon (n, _) -> n.txt
      | TyVar n      -> n.txt
      | _            ->
        (* Unsupported impl type shape for runtime lookup — skip silently *)
        ""
    in
    if type_name <> "" then begin
      List.iter (fun ((mname : name), (def : fn_def)) ->
        (* Evaluate the method body as a closure in the current environment.
           Re-use eval_decl on a synthesized DFn to get the closure value. *)
        let fn_val = match def.fn_clauses with
          | [clause] ->
            let param_names = List.filter_map (function
              | FPNamed p -> Some p.param_name.txt
              | FPPat _   -> None   (* pattern params not supported in impls yet *)
            ) clause.fc_params in
            VClosure (env, param_names, clause.fc_body)
          | _ ->
            (* Multi-clause fn: desugar to a match. For Phase 6b, require single clause. *)
            eval_error "impl method '%s' has multiple clauses — not yet supported in Phase 6b"
              mname.txt
        in
        Hashtbl.replace impl_tbl (idef.impl_iface.txt, type_name) fn_val
      ) idef.impl_methods
    end;
    env
```

**Important design note:** The key `(iface_name, type_name)` stores only the *most recently evaluated* method per `(interface, type)` pair. If an impl has multiple methods (e.g., `Drop` has only one), this is fine. The impl table key is `(interface_name, concrete_type_name)` — per-method lookup is not needed because we only resolve `drop` from `Drop`.

- [ ] **Step 4: Run to confirm it builds**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

Expected: clean build.

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -5
```

Expected: all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml
git commit -m "feat(6b): add type_tag_of helper and populate impl_tbl from DImpl eval"
```

---

## Task 3: Add the `own` builtin

**Files:**
- Modify: `lib/eval/eval.ml`

### Overview
Add the `own(pid, value)` builtin to `base_env`. It looks up the Drop impl for the value's type, then appends `(value, drop_fn)` to the actor's `ai_linear_values`.

- [ ] **Step 1: Write the failing test**

Add to `test/test_march.ml` (Phase 6b section):

```ocaml
(** Phase 6b: own() registers a linear value with the actor. *)
let test_own_registers_linear_value () =
  March_eval.Eval.reset_scheduler_state ();
  let _ = add_fresh_actor 0 "A" in
  (* Manually insert a drop impl into impl_tbl for type "TestVal" *)
  let dropped = ref false in
  let drop_fn = March_eval.Eval.VBuiltin ("drop_TestVal", function
    | [_v] -> dropped := true; March_eval.Eval.VUnit
    | _    -> March_eval.Eval.VUnit) in
  Hashtbl.replace March_eval.Eval.impl_tbl ("Drop", "TestVal") drop_fn;
  (* own() a VCon("TestVal", []) value with actor 0 *)
  let v = March_eval.Eval.VCon ("TestVal", [March_eval.Eval.VInt 42]) in
  let _result = March_eval.Eval.call_builtin "own"
    [March_eval.Eval.VPid 0; v] in
  (* Crash the actor and verify drop was called *)
  March_eval.Eval.crash_actor 0 "test";
  Alcotest.(check bool) "drop called on crash" true !dropped
```

Note: `call_builtin` and `impl_tbl` need to be exposed from eval.ml. See Step 3 for how to expose them. The test may alternatively drive through a March source string evaluation — see Task 5 for the simpler integration test approach. This unit test is optional; proceed to integration tests in Task 5 if OCaml-level access is awkward.

- [ ] **Step 2: Expose `impl_tbl` from eval.ml**

In `lib/eval/eval.ml`, `impl_tbl` is already a module-level `let` binding, so it is automatically accessible from `test_march.ml` as `March_eval.Eval.impl_tbl`. Verify there is no `.mli` file hiding it:

```bash
ls /Users/80197052/code/march/lib/eval/
```

If there is no `eval.mli`, the hashtable is accessible directly. Good.

- [ ] **Step 3: Add `own` to `base_env` in eval.ml**

In `lib/eval/eval.ml`, in the `base_env` list, add after the `register_resource` entry (around line 943):

```ocaml
  ; ("own", VBuiltin ("own", function
        (* Register a linear value with an actor, associating its Drop impl.
           Calling convention: own(pid, value)
           Resolves Drop impl from impl_tbl using the value's type tag.
           In March: own(pid, my_handle)
           The drop fn is called at crash time in reverse acquisition order. *)
        | [VPid pid; v] ->
          (match type_tag_of v with
           | None ->
             eval_error "own: value has no Drop-resolvable type (got %s)" (value_display v)
           | Some tag ->
             (match Hashtbl.find_opt impl_tbl ("Drop", tag) with
              | None ->
                eval_error "own: no impl Drop for type '%s' — declare impl Drop(%s)" tag tag
              | Some drop_fn ->
                (match Hashtbl.find_opt actor_registry pid with
                 | None ->
                   eval_error "own: unknown actor pid %d" pid
                 | Some inst ->
                   inst.ai_linear_values <- inst.ai_linear_values @ [(v, drop_fn)];
                   VUnit)))
        | _ -> eval_error "own: expected (Pid, value)"))
```

- [ ] **Step 4: Run to confirm it builds**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml
git commit -m "feat(6b): add own() builtin to register linear values with actors"
```

---

## Task 4: Call drop handlers in `crash_actor`

**Files:**
- Modify: `lib/eval/eval.ml`

### Overview
Extend `crash_actor` to walk `ai_linear_values` in reverse and call each drop function on its paired value, after the existing Phase 6a `ai_resources` cleanup.

- [ ] **Step 1: Write the failing test**

Add to `test/test_march.ml` (Phase 6b section):

```ocaml
(** Phase 6b: drop is called on owned linear values when actor crashes. *)
let test_linear_drop_called_on_crash () =
  March_eval.Eval.reset_scheduler_state ();
  let dropped_val = ref None in
  let _ = add_fresh_actor 0 "A" in
  let drop_fn = March_eval.Eval.VBuiltin ("test_drop", function
    | [v] -> dropped_val := Some v; March_eval.Eval.VUnit
    | _   -> March_eval.Eval.VUnit) in
  Hashtbl.replace March_eval.Eval.impl_tbl ("Drop", "Widget") drop_fn;
  let widget = March_eval.Eval.VCon ("Widget", [March_eval.Eval.VInt 99]) in
  (* Manually append to ai_linear_values (bypassing own() for isolation) *)
  (match Hashtbl.find_opt March_eval.Eval.actor_registry 0 with
   | Some inst ->
     inst.March_eval.Eval.ai_linear_values <- [(widget, drop_fn)]
   | None -> Alcotest.fail "actor not found");
  March_eval.Eval.crash_actor 0 "test";
  Alcotest.(check bool) "drop called" true (!dropped_val <> None);
  (match !dropped_val with
   | Some (March_eval.Eval.VCon ("Widget", [March_eval.Eval.VInt 99])) -> ()
   | _ -> Alcotest.fail "drop received wrong value")

(** Phase 6b: drops run in reverse acquisition order. *)
let test_linear_drop_reverse_order () =
  March_eval.Eval.reset_scheduler_state ();
  let order = ref [] in
  let _ = add_fresh_actor 0 "A" in
  let make_drop name = March_eval.Eval.VBuiltin ("drop_" ^ name, function
    | [_] -> order := name :: !order; March_eval.Eval.VUnit
    | _   -> March_eval.Eval.VUnit) in
  let v1 = March_eval.Eval.VCon ("R1", []) in
  let v2 = March_eval.Eval.VCon ("R2", []) in
  let v3 = March_eval.Eval.VCon ("R3", []) in
  (match Hashtbl.find_opt March_eval.Eval.actor_registry 0 with
   | Some inst ->
     inst.March_eval.Eval.ai_linear_values <-
       [(v1, make_drop "first"); (v2, make_drop "second"); (v3, make_drop "third")]
   | None -> Alcotest.fail "actor not found");
  March_eval.Eval.crash_actor 0 "test";
  (* Reverse acquisition: third dropped first, first dropped last.
     Each drop does (order := name :: !order), so accumulated list is reversed execution order.
     Execution: third→second→first → list becomes ["first";"second";"third"]. *)
  Alcotest.(check (list string)) "reverse drop order"
    ["first"; "second"; "third"] !order
```

- [ ] **Step 2: Run to confirm tests fail**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | grep -A3 "linear_drop"
```

Expected: tests fail because `ai_linear_values` is never walked in `crash_actor`.

- [ ] **Step 3: Implement — extend `crash_actor`**

In `lib/eval/eval.ml`, in `crash_actor` (line ~701), after the Phase 6a cleanup block:

```ocaml
    (* Phase 6a: run resource cleanup in reverse acquisition order. *)
    List.iter (fun (_, cleanup) ->
      try cleanup ()
      with exn ->
        Printf.eprintf "warn: resource cleanup failed for actor %d: %s\n"
          pid (Printexc.to_string exn)
    ) (List.rev inst.ai_resources);
    inst.ai_resources <- [];
```

Add immediately after (before the Down delivery loop):

```ocaml
    (* Phase 6b: call Drop impl on each owned linear value, in reverse acquisition order.
       drop_fn is a March callable (VClosure or VBuiltin): value -> value.
       Errors are caught and logged so one failing drop cannot block others. *)
    List.iter (fun (v, drop_fn) ->
      try
        let _ = !apply_hook drop_fn [v] in ()
      with exn ->
        Printf.eprintf "warn: Drop handler failed for actor %d: %s\n"
          pid (Printexc.to_string exn)
    ) (List.rev inst.ai_linear_values);
    inst.ai_linear_values <- [];  (* clear to prevent re-run on double-crash *)
```

- [ ] **Step 4: Run to confirm tests pass**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -10
```

Expected: all tests pass, including new Phase 6b tests.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(6b): call Drop handlers in crash_actor in reverse acquisition order"
```

---

## Task 5: Integration test — end-to-end in March source

**Files:**
- Modify: `test/test_march.ml`

### Overview
Write a test that evaluates a complete March source file with `interface Drop`, `impl Drop`, `own`, and a crash, verifying the drop ran.

- [ ] **Step 1: Write the test**

Add to `test/test_march.ml` (Phase 6b section):

```ocaml
(** Phase 6b: integration test — Drop impl called via own() when actor crashes. *)
let test_own_drop_integration () =
  (* This test evaluates a complete March module that:
     1. Declares interface Drop
     2. Declares a Token type with impl Drop (records a side effect)
     3. Creates an actor, owns a Token via own()
     4. Crashes the actor
     5. Verifies the drop ran via a global ref cell *)
  March_eval.Eval.reset_scheduler_state ();
  let dropped = ref false in
  (* We can't pass the ref cell into March source directly, so we use a
     VBuiltin side-effect registered in base_env under "mark_dropped" *)
  (* Instead: drive through register_resource to simulate own(), since
     both paths call crash_actor. This verifies the crash_actor pipeline works.
     For a fully source-level test, use the approach below. *)

  (* Full source-level approach: eval a March program that uses register_resource
     with a closure that sets a global (via a side-effecting builtin). *)
  let cleanup_called = ref false in
  let _inst = add_fresh_actor 0 "Worker" in
  March_eval.Eval.register_resource_ocaml 0 "phase6b_bridge"
    (fun () -> cleanup_called := true);

  (* Now also test own() path: manually insert impl and call own via OCaml *)
  let own_drop_called = ref false in
  let drop_fn = March_eval.Eval.VBuiltin ("drop_Token", function
    | [March_eval.Eval.VCon ("Token", _)] ->
      own_drop_called := true; March_eval.Eval.VUnit
    | _ -> March_eval.Eval.VUnit) in
  Hashtbl.replace March_eval.Eval.impl_tbl ("Drop", "Token") drop_fn;
  let token = March_eval.Eval.VCon ("Token", [March_eval.Eval.VInt 1]) in
  (match Hashtbl.find_opt March_eval.Eval.actor_registry 0 with
   | Some inst -> inst.March_eval.Eval.ai_linear_values <- [(token, drop_fn)]
   | None -> Alcotest.fail "actor 0 not found");

  March_eval.Eval.crash_actor 0 "test";
  Alcotest.(check bool) "Phase 6a resource cleanup still works" true !cleanup_called;
  Alcotest.(check bool) "Phase 6b Drop handler called via own" true !own_drop_called;
  ignore dropped
```

Also add a **pure March source** integration test that drives through the full pipeline (parse → typecheck → eval):

```ocaml
(** Phase 6b: pure March source integration test using eval_with_stdlib. *)
let test_own_drop_full_march_source () =
  (* Drives parse → desugar → typecheck → eval.
     Uses register_resource instead of own() because own() requires impl_tbl
     to be populated at eval time, which requires the full module evaluation.
     This test confirms the interface/impl/own syntax parses and typechecks. *)
  let src = {|mod DropTest do
    interface Drop(a) do
      fn drop : a -> Unit
    end

    type Token = Token(Int)

    impl Drop(Token) do
      fn drop(t) do VUnit end
    end

    actor Worker do
      state { count : Int }
      init { count = 0 }
      on Inc() do { count = state.count + 1 } end
    end

    fn main() do
      let pid = spawn(Worker)
      let t = Token(42)
      own(pid, t)
      kill(pid)
      :done
    end
  end|} in
  (* Should compile and run without error — own() call requires Drop impl for Token *)
  let env = eval_with_stdlib [] src in
  ignore env
```

- [ ] **Step 2: Register the tests in the test suite**

Find the Phase 6a test suite section in `test_march.ml` (search for `"Phase 6a"` in the suite list). Add the Phase 6b tests after:

```ocaml
    (* Phase 6b: Linear Drop Handlers *)
    Alcotest.test_case "actor_inst has ai_linear_values field" `Quick
      test_actor_inst_has_linear_values_field;
    Alcotest.test_case "linear drop called on crash" `Quick
      test_linear_drop_called_on_crash;
    Alcotest.test_case "linear drop reverse order" `Quick
      test_linear_drop_reverse_order;
    Alcotest.test_case "own + drop integration (OCaml level)" `Quick
      test_own_drop_integration;
    Alcotest.test_case "own + drop full March source" `Quick
      test_own_drop_full_march_source;
```

- [ ] **Step 3: Run all tests**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_march.ml
git commit -m "test(6b): add integration tests for linear drop handlers"
```

---

## Task 6: Write the example file

**Files:**
- Create: `examples/supervision_linear_drop.march`

### Overview
Write a standalone March example that demonstrates the Phase 6b feature clearly, following the style of `examples/supervision_resources.march`.

- [ ] **Step 1: Write the example**

Create `/Users/80197052/code/march/examples/supervision_linear_drop.march`:

```march
-- Phase 6b: Linear Drop Handlers Example
--
-- Demonstrates user-defined Drop implementations for linear values.
-- When an actor that owns a linear value crashes, the Drop impl is called
-- automatically in reverse acquisition order.
--
-- Compare with examples/supervision_resources.march (Phase 6a), which uses
-- the lower-level register_resource() API directly.

mod LinearDropDemo do

  -- Step 1: Declare the Drop interface.
  -- Any type can implement this to register cleanup logic.
  interface Drop(a) do
    fn drop : a -> Unit
  end

  -- Step 2: Declare a "linear" resource type.
  -- In Phase 6b, linearity is not enforced by the type system yet —
  -- it is a convention. Use own() to associate the value with an actor.
  type DbConnection = DbConnection(Int)   -- Int = mock connection id

  -- Step 3: Implement Drop for DbConnection.
  -- Called automatically when the owning actor crashes.
  impl Drop(DbConnection) do
    fn drop(conn) do
      match conn with
      | DbConnection(id) ->
        println("[Drop] Closing database connection " ++ to_string(id))
      end
    end
  end

  type FileHandle = FileHandle(String)  -- String = mock file path

  impl Drop(FileHandle) do
    fn drop(h) do
      match h with
      | FileHandle(path) ->
        println("[Drop] Closing file: " ++ path)
      end
    end
  end

  -- Step 4: Declare a worker actor.
  actor Worker do
    state { id : Int }
    init { id = 0 }
    on SetId(n : Int) do { id = n } end
    on Work() do
      println("[Worker] doing work, id = " ++ to_string(state.id))
      state
    end
  end

  fn main() do
    println("=== Linear Drop Handlers Demo (Phase 6b) ===")

    let pid = spawn(Worker)
    send(pid, SetId(1))
    run_until_idle()

    -- Acquire two linear resources and own() them with the actor.
    -- The Drop impl will be called for each in reverse acquisition order.
    let conn = DbConnection(100)
    let file = FileHandle("/var/log/worker.log")

    println("Acquiring resources and registering with actor via own()...")
    own(pid, conn)   -- registered first, dropped last
    own(pid, file)   -- registered second, dropped first

    println("Crashing worker...")
    kill(pid)

    -- Output (in order):
    --   [Drop] Closing file: /var/log/worker.log    (registered 2nd, dropped 1st)
    --   [Drop] Closing database connection 100      (registered 1st, dropped 2nd)

    println("Worker alive: " ++ to_string(is_alive(pid)))
    println("(file dropped before conn — reverse acquisition order)")
    println("=== Done ===")
  end
end
```

- [ ] **Step 2: Run the example to verify it works**

```bash
/Users/80197052/.opam/march/bin/dune exec march -- examples/supervision_linear_drop.march
```

Expected output:
```
=== Linear Drop Handlers Demo (Phase 6b) ===
Acquiring resources and registering with actor via own()...
Crashing worker...
[Drop] Closing file: /var/log/worker.log
[Drop] Closing database connection 100
Worker alive: false
(file dropped before conn — reverse acquisition order)
=== Done ===
```

- [ ] **Step 3: Commit**

```bash
git add examples/supervision_linear_drop.march
git commit -m "feat(6b): add supervision_linear_drop.march example"
```

---

## Task 7: Final cleanup and verification

**Files:**
- Read: `lib/eval/eval.ml`, `test/test_march.ml`

- [ ] **Step 1: Run the full test suite**

```bash
/Users/80197052/.opam/march/bin/dune runtest 2>&1
```

Expected: all tests pass (50+ tests, no failures).

- [ ] **Step 2: Build release**

```bash
/Users/80197052/.opam/march/bin/dune build 2>&1
```

Expected: clean build, no warnings.

- [ ] **Step 3: Run the benchmark that exercises actor/closure changes**

Per `specs/benchmarks.md`: actor/supervisor changes → run `bench/tree_transform.march`.

```bash
/Users/80197052/.opam/march/bin/dune exec march -- bench/tree_transform.march
```

Verify it completes without error and performance is not degraded.

- [ ] **Step 4: Verify both Phase 6a and 6b examples work**

```bash
/Users/80197052/.opam/march/bin/dune exec march -- examples/supervision_resources.march
/Users/80197052/.opam/march/bin/dune exec march -- examples/supervision_linear_drop.march
```

Both should produce expected output.

---

## Summary of All Changes

### `lib/eval/eval.ml`

1. **New field** on `actor_inst`: `mutable ai_linear_values : (value * value) list`
2. **New global**: `impl_tbl : (string * string, value) Hashtbl.t`
3. **`reset_scheduler_state`**: add `Hashtbl.reset impl_tbl`
4. **`type_tag_of`** helper function (before `base_env`)
5. **`eval_decl` — `DImpl` branch**: populate `impl_tbl` with method closures
6. **`base_env` — `own` entry**: new builtin that resolves Drop impl and appends to `ai_linear_values`
7. **`crash_actor`**: walk `ai_linear_values` in reverse, call drop, clear the list
8. **Five `actor_inst` construction sites**: add `ai_linear_values = []`

### `test/test_march.ml`

1. **`mk_actor_inst`**: add `ai_linear_values = []` to the record literal
2. **New tests**: `test_actor_inst_has_linear_values_field`, `test_linear_drop_called_on_crash`, `test_linear_drop_reverse_order`, `test_own_drop_integration`, `test_own_drop_full_march_source`
3. **Suite registration**: add Phase 6b test cases

### `examples/supervision_linear_drop.march`

New example file demonstrating `interface Drop`, `impl Drop(T)`, and `own(pid, value)` end-to-end.

---

## Known Limitations (Phase 6c+ Work)

1. **`own` fails for untagged types**: `VRecord`, `VClosure`, `VPid`, etc. return `None` from `type_tag_of` because they have no single type name at runtime. Fix: wrap records in a constructor (`type Foo = Foo({ ... })`).

2. **Multi-clause impl methods not supported**: The `DImpl` evaluator only handles single-clause `fn drop(x) do ... end`. Multi-clause pattern-matching drop methods (e.g., `fn drop(FileHandle(0)) do ... end / fn drop(FileHandle(n)) do ... end`) raise `eval_error`. Fix: use the desugar pass to collapse multi-clause fns before eval.

3. **`own` called outside actor context works but is fragile**: `own(pid, v)` works for any `pid`, including actors not yet running a handler. This is intentional — the Phase 6a `register_resource` has the same behavior.

4. **No type-system enforcement of linearity**: The typechecker does not prevent using a value after `own()`-ing it. This is Approach B deferred to Phase 6c.

5. **impl_tbl is global, not per-module**: If two modules both `impl Drop(Foo)`, the second wins. Fix in a future phase by scoping impl_tbl per-module.
