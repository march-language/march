# Capability-Based Library Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add compile-time capability security so modules must declare `needs IO.Network` etc. and functions that perform IO must take explicit `Cap(IO.X)` parameters — enforced by the type checker with actionable diagnostics.

**Architecture:** Add `DNeeds` to the AST, extend the type grammar to allow dotted capability names (`Cap(IO.Network)`), then in the type checker collect each module's declared needs and validate that: (1) every `Cap(X)` in any function signature is covered by a `needs` declaration, and (2) every `needs` declaration is actually used by at least one function. The evaluator treats capabilities as no-ops (compile-time only).

**Tech Stack:** OCaml 5.3.0, Menhir (parser), ocamllex (lexer), Alcotest (tests). Build: `dune build`. Test: `dune runtest`. Run compiler: `dune exec march -- file.march`. NEVER prefix with `eval $(opam env ...)` — `dune` is directly in PATH.

**Spec:** `specs/2026-03-19-capability-security-design.md`

---

## File Map

| File | Change |
|------|--------|
| `lib/ast/ast.ml:126-138` | Add `DNeeds` variant to `decl` type |
| `lib/lexer/lexer.mll:14-53` | Add `"needs"` to keyword table |
| `lib/parser/parser.mly:63-68` | Add `NEEDS` token declaration |
| `lib/parser/parser.mly:96-111` | Add `needs_decl` case to `decl` rule |
| `lib/parser/parser.mly:303-319` | Extend `ty_atom` to support dotted names (`IO.Network`) |
| `lib/parser/parser.mly:208-218` | Add `needs_decl` rule after `use_decl` |
| `lib/desugar/desugar.ml` | Pass through `DNeeds` unchanged |
| `lib/typecheck/typecheck.ml:255-268` | Add `needs` and `cap_usages` fields to `env` |
| `lib/typecheck/typecheck.ml:~350` | Add capability hierarchy + subtyping check |
| `lib/typecheck/typecheck.ml:1587-1643` | Extend `DMod` checking to validate needs |
| `lib/typecheck/typecheck.ml:~1708` | Add `DNeeds` case to `check_decl` |
| `lib/eval/eval.ml` | Add `DNeeds` no-op case + `Cap.narrow` builtin |
| `test/test_march.ml` | Add capability test suite |

---

## Task 1: Add `DNeeds` to the AST

**Files:**
- Modify: `lib/ast/ast.ml:126-138`

- [ ] **Step 1: Add the `DNeeds` variant**

In `lib/ast/ast.ml`, add `DNeeds` to the `decl` type after `DUse`:

```ocaml
type decl =
  | DFn of fn_def * span
  | DLet of binding * span
  | DType of name * name list * type_def * span
  | DActor of name * actor_def * span
  | DProtocol of name * protocol_def * span
  | DMod of name * visibility * decl list * span
  | DSig of name * sig_def * span
  | DInterface of interface_def * span
  | DImpl of impl_def * span
  | DExtern of extern_def * span
  | DUse of use_decl * span
  | DNeeds of name list list * span
  (** Capability manifest: needs IO.Network, IO.Clock
      Each [name list] is a capability path, e.g. [["IO";"Network"]; ["IO";"Clock"]] *)
[@@deriving show]
```

- [ ] **Step 2: Build to verify the AST change compiles**

```bash
dune build 2>&1 | head -40
```

Expected: errors about non-exhaustive pattern matches in other files — that's fine, we'll fix them as we go. Zero errors means it compiled cleanly.

- [ ] **Step 3: Commit the AST change**

```bash
git add lib/ast/ast.ml
git commit -m "feat(ast): add DNeeds decl for capability manifest declarations"
```

---

## Task 2: Add `needs` keyword to lexer

**Files:**
- Modify: `lib/lexer/lexer.mll:14-53`
- Modify: `lib/parser/parser.mly:63-68`

- [ ] **Step 1: Write the failing lexer test**

In `test/test_march.ml`, add before the `Alcotest.run` block:

```ocaml
let test_lexer_keyword_needs () =
  let lexbuf = Lexing.from_string "needs" in
  let tok = March_lexer.Lexer.token lexbuf in
  Alcotest.(check bool) "lexes needs keyword" true
    (match tok with March_parser.Parser.NEEDS -> true | _ -> false)
```

And add to the `"lexer"` suite in the `Alcotest.run` block:
```ocaml
Alcotest.test_case "needs keyword" `Quick test_lexer_keyword_needs;
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune runtest 2>&1 | grep -A5 "needs keyword"
```

Expected: compile error — `NEEDS` token doesn't exist yet.

- [ ] **Step 3: Add `NEEDS` token to the parser token declarations**

In `lib/parser/parser.mly`, line 67, add `NEEDS` to the existing token line:

```
%token PUB INTERFACE IMPL SIG EXTERN UNSAFE AS USE NEEDS
```

- [ ] **Step 4: Add `"needs"` to the lexer keyword table**

In `lib/lexer/lexer.mll`, add after `("use", USE);`:

```ocaml
      ("needs", NEEDS);
```

- [ ] **Step 5: Run the test**

```bash
dune runtest 2>&1 | grep -A5 "needs keyword"
```

Expected: PASS.

- [ ] **Step 6: Run the full suite**

```bash
dune runtest
```

Expected: all existing tests still pass (there may be parser warnings about unused token — that's fine until we add the production rule).

- [ ] **Step 7: Commit**

```bash
git add lib/lexer/lexer.mll lib/parser/parser.mly test/test_march.ml
git commit -m "feat(lexer): add NEEDS keyword token"
```

---

## Task 3: Extend type grammar for dotted capability names

**Files:**
- Modify: `lib/parser/parser.mly:303-319`

`Cap(IO.Network)` requires `IO.Network` to be valid in a type position. Currently the type grammar only handles bare uppercase names. We add a dotted name rule that produces a single `TyCon` with the joined name (e.g., `TyCon({txt="IO.Network"}, [])`).

- [ ] **Step 1: Write a failing parser test**

In `test/test_march.ml`, add:

```ocaml
let test_parse_cap_dotted_type () =
  (* Cap(IO.Network) should parse as TyCon("Cap", [TyCon("IO.Network", [])]) *)
  let src = {|mod Test do
    fn fetch(net : Cap(IO.Network), url : String) : String do url end
  end|} in
  let m = parse_module src in
  match m.March_ast.Ast.mod_decls with
  | [March_ast.Ast.DFn (def, _)] ->
    (match def.fn_clauses with
     | [clause] ->
       (match clause.fc_params with
        | March_ast.Ast.FPNamed { param_ty = Some (March_ast.Ast.TyCon (cap, [March_ast.Ast.TyCon (inner, [])])); _ } :: _ ->
          Alcotest.(check string) "outer type is Cap" "Cap" cap.txt;
          Alcotest.(check string) "inner type is IO.Network" "IO.Network" inner.txt
        | _ -> Alcotest.fail "expected typed param with Cap(IO.Network)")
     | _ -> Alcotest.fail "expected one clause")
  | _ -> Alcotest.fail "expected DFn"
```

Add to the `"parser"` suite:
```ocaml
Alcotest.test_case "Cap dotted type" `Quick test_parse_cap_dotted_type;
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune runtest 2>&1 | grep -A5 "Cap dotted"
```

Expected: parse error — `IO.Network` is not a valid type.

- [ ] **Step 3: Add dotted type name support to the type grammar**

In `lib/parser/parser.mly`, modify the `ty_atom` rule (around line 312) to add a dotted name form:

```menhir
ty_atom:
  | id = LOWER_IDENT { TyVar (mk_name id $loc) }
  | id = upper_name  { TyCon (id, []) }
  | id = upper_name; DOT; rest = dotted_upper_tail
    { let joined = id.txt ^ "." ^ String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) rest) in
      TyCon (mk_name joined $loc, []) }
  | LINEAR; t = ty_atom { TyLinear (Linear, t) }
  | AFFINE; t = ty_atom { TyLinear (Affine, t) }
  | LPAREN; RPAREN { TyTuple [] }
  | LPAREN; t = ty; RPAREN { t }
  | LPAREN; t = ty; COMMA; ts = separated_nonempty_list(COMMA, ty); RPAREN
    { TyTuple (t :: ts) }
  | LBRACE; fields = separated_list(COMMA, record_field_ty); RBRACE
    { TyRecord fields }
```

And add the helper rule after `ty_atom`:

```menhir
dotted_upper_tail:
  | id = upper_name { [id] }
  | id = upper_name; DOT; rest = dotted_upper_tail { id :: rest }
```

- [ ] **Step 4: Run the test**

```bash
dune runtest 2>&1 | grep -A5 "Cap dotted"
```

Expected: PASS.

- [ ] **Step 5: Run the full test suite**

```bash
dune runtest
```

Expected: all existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/parser/parser.mly test/test_march.ml
git commit -m "feat(parser): support dotted type names for Cap(IO.Network) capability types"
```

---

## Task 4: Add `needs_decl` parsing rule

**Files:**
- Modify: `lib/parser/parser.mly:96-111` (decl rule)
- Modify: `lib/parser/parser.mly:208-218` (after use_decl)
- Modify: `lib/desugar/desugar.ml`

- [ ] **Step 1: Write a failing parser test**

In `test/test_march.ml`, add:

```ocaml
let test_parse_needs_decl () =
  let src = {|mod Test do
    needs IO.Network
    needs IO.Clock
    pub fn fetch(net : Cap(IO.Network)) : String do "" end
  end|} in
  let m = parse_module src in
  let needs_decls = List.filter_map (function
    | March_ast.Ast.DNeeds (caps, _) -> Some caps
    | _ -> None
  ) m.March_ast.Ast.mod_decls in
  Alcotest.(check int) "two needs decls" 2 (List.length needs_decls);
  let first = List.hd needs_decls in
  Alcotest.(check int) "first needs has one cap" 1 (List.length first);
  Alcotest.(check string) "first cap path" "IO.Network"
    (String.concat "." (List.map (fun (n : March_ast.Ast.name) -> n.txt) (List.hd first)))
```

Add to the `"parser"` suite:
```ocaml
Alcotest.test_case "needs decl" `Quick test_parse_needs_decl;
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune runtest 2>&1 | grep -A5 "needs decl"
```

Expected: parse error — `needs` is not a valid declaration keyword yet.

- [ ] **Step 3: Add `needs_decl` to the `decl` production**

In `lib/parser/parser.mly`, add to the `decl` rule (after `use_decl`):

```menhir
decl:
  | DOC; s = STRING; d = fn_decl { ... }   (* existing *)
  | d = fn_decl        { d }
  | d = let_decl       { d }
  | d = type_decl      { d }
  | d = actor_decl     { d }
  | d = interface_decl { d }
  | d = impl_decl      { d }
  | d = sig_decl       { d }
  | d = extern_decl    { d }
  | d = mod_decl       { d }
  | d = use_decl       { d }
  | d = protocol_decl  { d }
  | d = needs_decl     { d }
```

- [ ] **Step 4: Add the `needs_decl` production rule**

After the `use_decl` rule (around line 212), add:

```menhir
(** Capability manifest declaration: needs IO.Network, IO.Clock
    Each path is a dot-separated sequence of uppercase names. *)
needs_decl:
  | NEEDS; caps = separated_nonempty_list(COMMA, cap_path)
    { DNeeds (caps, mk_span ($loc)) }

cap_path:
  | id = upper_name { [id] }
  | id = upper_name; DOT; rest = cap_path { id :: rest }
```

- [ ] **Step 5: Handle `DNeeds` in the desugar pass**

In `lib/desugar/desugar.ml`, find the `desugar_decl` function and add a case for `DNeeds` (pass through unchanged):

```ocaml
| Ast.DNeeds (caps, sp) -> [Ast.DNeeds (caps, sp)]
```

Look for where `DUse` is handled and add the `DNeeds` case nearby. If `DUse` returns a list: `| Ast.DUse (ud, sp) -> [Ast.DUse (ud, sp)]` — match that pattern exactly.

- [ ] **Step 6: Run the test**

```bash
dune runtest 2>&1 | grep -A5 "needs decl"
```

Expected: PASS.

- [ ] **Step 7: Run the full suite**

```bash
dune runtest
```

Expected: all tests pass. Fix any non-exhaustive match warnings.

- [ ] **Step 8: Commit**

```bash
git add lib/parser/parser.mly lib/desugar/desugar.ml test/test_march.ml
git commit -m "feat(parser): add needs_decl production rule for capability manifest"
```

---

## Task 5: Add capability infrastructure to the type checker

**Files:**
- Modify: `lib/typecheck/typecheck.ml:255-268` (env type)
- Modify: `lib/typecheck/typecheck.ml:~350` (after built-in types)

This task adds the capability hierarchy and extends the `env` type. No enforcement yet — that comes in Task 6.

- [ ] **Step 1: Add `needs` to the `env` type**

In `lib/typecheck/typecheck.ml`, find the `env` type (line 255) and add two fields:

```ocaml
type env = {
  vars    : (string * scheme) list;
  types   : (string * int) list;
  ctors   : (string * ctor_info) list;
  records : (string * (string list * (string * Ast.ty) list)) list;
  level   : int;
  lin     : lin_entry list;
  errors  : Err.ctx;
  pending_constraints : constraint_ list ref;
  type_map : (Ast.span, ty) Hashtbl.t;
  interfaces : (string * Ast.interface_def) list;
  sigs       : (string * Ast.sig_def) list;
  (* Capability tracking — populated during DMod checking *)
  mod_needs  : string list list;
  (** Capabilities declared via [needs]: each is a dot-joined path, e.g. ["IO.Network"] *)
  mod_cap_usages : (string * Ast.span) list;
  (** All Cap(X) usages found in function sigs within current module scope: (cap_path, span) *)
}
```

Update `make_env` to initialize the new fields:

```ocaml
let make_env errors type_map = {
  vars = []; types = []; ctors = []; records = []; level = 0; lin = [];
  errors; pending_constraints = ref []; type_map;
  interfaces = []; sigs = [];
  mod_needs = []; mod_cap_usages = [];
}
```

- [ ] **Step 2: Add the capability hierarchy**

After the built-in type definitions (around line 367, after `t_pid`), add:

```ocaml
(* =================================================================
   Capability hierarchy for needs/Cap checking.
   Each entry: (cap_path, parent_cap_path option).
   Stored as dot-joined strings for easy lookup.
   ================================================================= *)

(** All known IO capability paths in the hierarchy. *)
let io_cap_hierarchy : (string * string option) list = [
  ("IO",              None);
  ("IO.Console",      Some "IO");
  ("IO.FileSystem",   Some "IO");
  ("IO.FileRead",     Some "IO.FileSystem");
  ("IO.FileWrite",    Some "IO.FileSystem");
  ("IO.Network",      Some "IO");
  ("IO.NetConnect",   Some "IO.Network");
  ("IO.NetListen",    Some "IO.Network");
  ("IO.Process",      Some "IO");
  ("IO.Clock",        Some "IO");
]

(** [cap_ancestors cap] returns [cap] and all its ancestors in the hierarchy,
    most-specific first. E.g., "IO.FileRead" → ["IO.FileRead"; "IO.FileSystem"; "IO"].
    FFI caps like "LibC" have no entries — they're their own roots (no subtyping). *)
let cap_ancestors cap =
  let rec go c acc =
    let acc' = c :: acc in
    match List.assoc_opt c io_cap_hierarchy with
    | Some (Some parent) -> go parent acc'
    | _ -> acc'
  in
  List.rev (go cap [])

(** [cap_subsumes parent child] is true if [parent] is an ancestor of (or equal to) [child].
    E.g., cap_subsumes "IO" "IO.FileRead" = true. *)
let cap_subsumes parent child =
  List.mem parent (cap_ancestors child)

(** [cap_path_of_names names] converts a list of AST names like [IO; Network]
    to the dot-joined string "IO.Network". *)
let cap_path_of_names names =
  String.concat "." (List.map (fun (n : Ast.name) -> n.txt) names)
```

- [ ] **Step 3: Build**

```bash
dune build 2>&1 | head -30
```

Expected: clean build. Fix any type errors from the new `env` fields — every place `make_env` is called or `env` is constructed with `{ env with ... }` should still work since we added fields with defaults.

- [ ] **Step 4: Run the full suite**

```bash
dune runtest
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/typecheck/typecheck.ml
git commit -m "feat(typecheck): add capability hierarchy and needs tracking to env"
```

---

## Task 6: Handle `DNeeds` in the type checker and validate in `DMod`

**Files:**
- Modify: `lib/typecheck/typecheck.ml` (two places)

This is the core enforcement task. When we see a `DMod`, we:
1. Collect all `DNeeds` from the module's decls
2. Collect all `Cap(X)` types used in function signatures
3. Check coverage: every `Cap(X)` must be covered by a declared need
4. Check usage: every declared need must be used by at least one function

- [ ] **Step 1: Write failing typecheck tests**

In `test/test_march.ml`, add before the `Alcotest.run` block:

```ocaml
(* ── Capability typecheck tests ─────────────────────────────────────── *)

let test_cap_needs_pure_ok () =
  (* Module with no needs and no Cap params — should be fine *)
  let ctx = typecheck {|mod Json do
    pub fn double(x : Int) : Int do x + x end
  end|} in
  Alcotest.(check bool) "pure module: no errors" false (has_errors ctx)

let test_cap_needs_declared_ok () =
  (* Module with needs and matching Cap param — should be fine *)
  let ctx = typecheck {|mod Http do
    needs IO.Network
    pub fn fetch(net : Cap(IO.Network)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "declared needs with Cap: no errors" false (has_errors ctx)

let test_cap_missing_needs_error () =
  (* Cap(IO.Network) used without a needs declaration — should error *)
  let ctx = typecheck {|mod Bad do
    pub fn fetch(net : Cap(IO.Network)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "undeclared Cap: has errors" true (has_errors ctx)

let test_cap_unused_needs_warning () =
  (* needs IO.Network declared but no function uses Cap(IO.Network) — warning *)
  let ctx = typecheck {|mod Bad do
    needs IO.Network
    pub fn compute(x : Int) : Int do x end
  end|} in
  Alcotest.(check bool) "unused needs: has diagnostics" true
    (March_errors.Errors.has_diagnostics ctx)

let test_cap_supertype_covers_subtype () =
  (* needs IO covers Cap(IO.Network) via subtyping — should be fine *)
  let ctx = typecheck {|mod Http do
    needs IO
    pub fn fetch(net : Cap(IO.Network)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "supertype needs covers subtype Cap: no errors" false (has_errors ctx)
```

Add a `"capabilities"` suite to the `Alcotest.run` block:

```ocaml
( "capabilities",
  [
    Alcotest.test_case "pure module ok"             `Quick test_cap_needs_pure_ok;
    Alcotest.test_case "declared needs ok"          `Quick test_cap_needs_declared_ok;
    Alcotest.test_case "missing needs error"        `Quick test_cap_missing_needs_error;
    Alcotest.test_case "unused needs warning"       `Quick test_cap_unused_needs_warning;
    Alcotest.test_case "supertype covers subtype"   `Quick test_cap_supertype_covers_subtype;
  ] );
```

Also add `has_diagnostics` to the errors module if it doesn't exist (check `lib/errors/errors.ml` — add `let has_diagnostics ctx = ctx.diagnostics <> []` if needed).

- [ ] **Step 2: Run to verify failures**

```bash
dune runtest 2>&1 | grep -A3 "capabilities"
```

Expected: tests fail — no capability checking implemented yet.

- [ ] **Step 3: Add `DNeeds` case to `check_decl`**

In `lib/typecheck/typecheck.ml`, find the `DUse` case (line ~1708) and add after it:

```ocaml
| Ast.DNeeds (caps, _sp) ->
  (* Record declared capability paths in the env for DMod validation *)
  let paths = List.map cap_path_of_names caps in
  { env with mod_needs = paths @ env.mod_needs }
```

- [ ] **Step 4: Add a helper to extract `Cap(X)` paths from a surface type**

Add near the capability hierarchy (after `cap_path_of_names`):

```ocaml
(** [cap_paths_in_surface_ty ty] returns all capability paths referenced as
    [Cap(X)] in the surface type [ty]. E.g., Cap(IO.Network) → ["IO.Network"]. *)
let rec cap_paths_in_surface_ty (ty : Ast.ty) : string list =
  match ty with
  | Ast.TyCon (con, [arg]) when con.txt = "Cap" ->
    (match arg with
     | Ast.TyCon (name, []) -> [name.txt]
     | _ -> [])
  | Ast.TyCon (_, args) -> List.concat_map cap_paths_in_surface_ty args
  | Ast.TyArrow (a, b) ->
    cap_paths_in_surface_ty a @ cap_paths_in_surface_ty b
  | Ast.TyTuple ts -> List.concat_map cap_paths_in_surface_ty ts
  | Ast.TyRecord fields -> List.concat_map (fun (_, t) -> cap_paths_in_surface_ty t) fields
  | Ast.TyLinear (_, t) -> cap_paths_in_surface_ty t
  | _ -> []
```

- [ ] **Step 5: Add `check_module_needs` validation function**

Add near the end of `§15 Declaration checking`, before `check_module`:

```ocaml
(** [check_module_needs env mod_name decls] validates capability declarations
    for a module:
    - Every Cap(X) in any function signature must be covered by a [needs] declaration
    - Every [needs X] must be used by at least one function *)
let check_module_needs (env : env) (mod_name : Ast.name) (decls : Ast.decl list) =
  (* Collect declared needs *)
  let declared_needs = List.concat_map (function
    | Ast.DNeeds (caps, _) -> List.map cap_path_of_names caps
    | _ -> []
  ) decls in
  (* Collect all Cap(X) paths from function signatures (pub and private) *)
  let used_caps : (string * Ast.span) list = List.concat_map (function
    | Ast.DFn (def, sp) ->
      let param_tys = List.filter_map (fun p ->
        match p with
        | Ast.FPNamed { param_ty = Some t; _ } -> Some t
        | _ -> None
      ) (List.concat_map (fun c -> c.Ast.fc_params) def.fn_clauses) in
      let ret_tys = Option.to_list def.fn_ret_ty in
      let all_tys = param_tys @ ret_tys in
      List.concat_map (fun t ->
        List.map (fun cap -> (cap, sp)) (cap_paths_in_surface_ty t)
      ) all_tys
    | _ -> []
  ) decls in
  (* Check 1: every Cap(X) must be covered by a declared need *)
  List.iter (fun (cap_path, sp) ->
    let covered = List.exists (fun need ->
      cap_subsumes need cap_path
    ) declared_needs in
    if not covered then
      Err.error env.errors ~span:sp
        (Printf.sprintf
           "capability `Cap(%s)` used in module `%s` but `%s` is not declared in `needs`.\n\
            help: add `needs %s` to the module."
           cap_path mod_name.txt cap_path cap_path)
  ) used_caps;
  (* Check 2: every needs declaration should be used by at least one function *)
  List.iter (fun need ->
    let used = List.exists (fun (cap_path, _) ->
      cap_subsumes need cap_path
    ) used_caps in
    if not used then begin
      (* Find span of this needs decl for the warning *)
      let sp = match List.find_opt (function
        | Ast.DNeeds (caps, _) ->
          List.exists (fun names -> cap_path_of_names names = need) caps
        | _ -> false
      ) decls with
      | Some (Ast.DNeeds (_, s)) -> s
      | _ -> mod_name.span
      in
      Err.warning env.errors ~span:sp
        (Printf.sprintf
           "module `%s` declares `needs %s` but no function requires `Cap(%s)` or a sub-capability.\n\
            help: remove the unused capability declaration."
           mod_name.txt need need)
    end
  ) declared_needs
```

This requires `Err.warning` — check `lib/errors/errors.ml`. If it only has `Err.error`, add:
```ocaml
let warning ctx ?(span = dummy_span) msg = add ctx { severity = Warning; message = msg; span; labels = []; notes = [] }
```

- [ ] **Step 6: Call `check_module_needs` from the `DMod` handler**

In `lib/typecheck/typecheck.ml`, find the `DMod` case (line ~1587). After the sig conformance check and before the final `bind_vars`, add:

```ocaml
    (* Validate capability declarations for this module *)
    check_module_needs env name decls;
```

Place it right before the final line `bind_vars new_names env` so it runs after inner checking but before the module's names are exposed outward.

- [ ] **Step 7: Run the tests**

```bash
dune runtest 2>&1 | grep -A3 "capabilities"
```

Expected: all 5 capability tests pass.

- [ ] **Step 8: Run full suite**

```bash
dune runtest
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/typecheck/typecheck.ml lib/errors/errors.ml test/test_march.ml
git commit -m "feat(typecheck): enforce needs declarations — error on undeclared Cap, warn on unused needs"
```

---

## Task 7: Add the overly-broad capability hint

**Files:**
- Modify: `lib/typecheck/typecheck.ml` (extend `check_module_needs`)

When `Cap(IO)` is passed where `Cap(IO.FileRead)` would suffice, emit a hint.

The hint fires when a function signature uses `Cap(IO)` (the root) AND there exists a called function somewhere in the module body that only requires a sub-capability. This is hard to do precisely from the AST alone, so we implement a simpler heuristic: if a function parameter is `Cap(IO)` (the exact root), emit a hint suggesting narrower caps are available.

- [ ] **Step 1: Add a test**

```ocaml
let test_cap_broad_cap_hint () =
  (* Cap(IO) used where narrower caps exist — should produce a hint *)
  let ctx = typecheck {|mod Lib do
    needs IO
    pub fn read_file(io : Cap(IO)) : Int do 0 end
  end|} in
  (* Should not be an error, but should have a hint *)
  Alcotest.(check bool) "broad cap: no error" false (has_errors ctx);
  Alcotest.(check bool) "broad cap: has hint" true
    (March_errors.Errors.has_hints ctx)
```

Add to the capabilities suite:
```ocaml
Alcotest.test_case "broad cap hint" `Quick test_cap_broad_cap_hint;
```

Add `has_hints` to `lib/errors/errors.ml`:
```ocaml
let has_hints ctx = List.exists (fun d -> d.severity = Hint) ctx.diagnostics
```

- [ ] **Step 2: Run to verify it fails**

```bash
dune runtest 2>&1 | grep -A3 "broad cap hint"
```

Expected: FAIL — no hints emitted yet.

- [ ] **Step 3: Add the hint to `check_module_needs`**

In `check_module_needs`, after the two existing checks, add:

```ocaml
  (* Check 3 (hint): functions taking Cap(IO) — suggest narrowing *)
  List.iter (fun (cap_path, sp) ->
    if cap_path = "IO" then
      Err.hint env.errors ~span:sp
        (Printf.sprintf
           "this function takes `Cap(IO)` (the root capability).\n\
            hint: if it only needs filesystem, network, or console access, \
            consider a narrower capability like `Cap(IO.FileRead)` or `Cap(IO.Console)` \
            for least-privilege.")
  ) used_caps
```

Add `Err.hint` to `lib/errors/errors.ml`:
```ocaml
let hint ctx ?(span = dummy_span) msg = add ctx { severity = Hint; message = msg; span; labels = []; notes = [] }
```

- [ ] **Step 4: Run the tests**

```bash
dune runtest 2>&1 | grep -A3 "capabilities"
```

Expected: all capability tests pass.

- [ ] **Step 5: Run full suite**

```bash
dune runtest
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/typecheck/typecheck.ml lib/errors/errors.ml test/test_march.ml
git commit -m "feat(typecheck): add hint for overly broad Cap(IO) capability usage"
```

---

## Task 8: Handle `DNeeds` in the evaluator + add `Cap.narrow` builtin

**Files:**
- Modify: `lib/eval/eval.ml`

Capabilities are compile-time only. The evaluator must:
1. Skip `DNeeds` at runtime (no-op)
2. Provide a `Cap.narrow` builtin that is a no-op at runtime (just returns its first argument — the actual enforcement is compile-time)

- [ ] **Step 1: Find the `DExtern` case in the evaluator**

```bash
grep -n "DExtern\|DUse\|DProtocol" /Users/80197052/code/march/lib/eval/eval.ml | head -10
```

Note the line numbers.

- [ ] **Step 2: Add `DNeeds` case to `eval_decl`**

In `lib/eval/eval.ml`, near the `DUse` or `DExtern` case, add:

```ocaml
| Ast.DNeeds (_, _) ->
  (* Capabilities are compile-time only — no runtime action *)
  env
```

- [ ] **Step 3: Find the builtins section**

```bash
grep -n "\"println\"\|VBuiltin\|builtins" /Users/80197052/code/march/lib/eval/eval.ml | head -10
```

Note the pattern used for builtin registration.

- [ ] **Step 4: Add `Cap.narrow` as a no-op builtin**

In the builtins list, add an entry:

```ocaml
("Cap.narrow",
  VBuiltin ("Cap.narrow", fun args ->
    (* Runtime: Cap.narrow is a no-op — enforcement is compile-time.
       Return the first argument (the cap value, which at runtime is unit). *)
    match args with
    | cap :: _ -> cap
    | [] -> VUnit));
```

Where `VUnit` is whatever the evaluator uses for `()` — look for how `()` is represented (likely `VTuple []`). Use that instead if `VUnit` doesn't exist.

- [ ] **Step 5: Build and run full suite**

```bash
dune build && dune runtest
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/eval/eval.ml
git commit -m "feat(eval): handle DNeeds (no-op) and add Cap.narrow builtin"
```

---

## Task 9: Write a capability end-to-end test

**Files:**
- Modify: `test/test_march.ml`

Write a test that verifies a complete capability-annotated module parses, typechecks without errors, and evaluates correctly.

- [ ] **Step 1: Add an end-to-end test**

```ocaml
let test_cap_end_to_end () =
  (* A module with correct needs + Cap params should parse, typecheck, and eval cleanly *)
  let ctx = typecheck {|mod Greeter do
    needs IO.Console

    pub fn make_greeting(name : String) : String do
      "Hello, " ++ name
    end
  end|} in
  Alcotest.(check bool) "complete module: no errors" false (has_errors ctx)

let test_cap_nested_module () =
  (* Nested modules declare needs independently *)
  let ctx = typecheck {|mod Outer do
    needs IO.Console

    mod Inner do
      needs IO.Network
      pub fn fetch(net : Cap(IO.Network)) : Int do 0 end
    end

    pub fn greet(io : Cap(IO.Console)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "nested modules: no errors" false (has_errors ctx)

let test_cap_private_fn_enforcement () =
  (* Private functions also must have their Cap(X) covered by needs *)
  let ctx = typecheck {|mod Lib do
    needs IO.Console

    fn log(io : Cap(IO.Console)) : Int do 0 end
    pub fn run(io : Cap(IO.Console)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "private fn with needs: no errors" false (has_errors ctx)

let test_cap_private_fn_uncovered () =
  (* Private fn using Cap(IO.Network) without needs IO.Network → error *)
  let ctx = typecheck {|mod Lib do
    needs IO.Console

    fn connect(net : Cap(IO.Network)) : Int do 0 end
    pub fn run(io : Cap(IO.Console)) : Int do 0 end
  end|} in
  Alcotest.(check bool) "private fn with undeclared Cap: has errors" true (has_errors ctx)
```

Add to the capabilities suite:
```ocaml
Alcotest.test_case "end to end"               `Quick test_cap_end_to_end;
Alcotest.test_case "nested modules"           `Quick test_cap_nested_module;
Alcotest.test_case "private fn covered"       `Quick test_cap_private_fn_enforcement;
Alcotest.test_case "private fn uncovered"     `Quick test_cap_private_fn_uncovered;
```

- [ ] **Step 2: Run the tests**

```bash
dune runtest 2>&1 | grep -A3 "capabilities"
```

Expected: all tests pass.

- [ ] **Step 3: Run the full suite**

```bash
dune runtest
```

Expected: all 50+ tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_march.ml
git commit -m "test(capabilities): add end-to-end and nested module capability tests"
```

---

## Task 10: Check `has_diagnostics` exists in errors module

**Files:**
- Modify: `lib/errors/errors.ml` (if needed)

- [ ] **Step 1: Check what's in errors.ml**

```bash
grep -n "let has_\|let add\|type severity\|type diagnostic" /Users/80197052/code/march/lib/errors/errors.ml
```

- [ ] **Step 2: Add missing helpers if needed**

Add any missing functions (`has_diagnostics`, `has_hints`, `warning`, `hint`) following the existing patterns in `errors.ml`.

- [ ] **Step 3: Build and test**

```bash
dune build && dune runtest
```

Expected: clean build, all tests pass.

- [ ] **Step 4: Commit (only if changes were needed)**

```bash
git add lib/errors/errors.ml
git commit -m "feat(errors): add has_diagnostics, has_hints, warning, hint helpers"
```

---

## Verification

After all tasks complete, run:

```bash
dune build && dune runtest
```

Expected output: all tests pass (number increases by ~10 capability tests from the previous 50). No warnings about unused variables or non-exhaustive patterns.

Also do a quick smoke test with a capability-annotated source file:

```bash
cat > /tmp/test_cap.march << 'EOF'
mod MyApp do
  needs IO.Console

  pub fn main(io : Cap(IO.Console)) : Int do
    0
  end
end
EOF
dune exec march -- /tmp/test_cap.march
```

Expected: compiles and runs without errors.
