(** TRMC eligibility analysis tests (lib/tir/trmc.ml).

    Phase 1 is analysis-only: these pin the CLASSIFICATION, not any rewrite.
    The cases below are the shapes that actually decided the design — in
    particular [test_join_point_tail_call], which pins the bug the first
    version of the walk had (a tail call inside a lowered match's join point
    reported as unreachable). See
    specs/todos/2026-08-07-trmc-tail-recursion-modulo-cons.md. *)

open March_tir

let v name ty : Tir.var = { v_name = name; v_ty = ty; v_lin = Tir.Unr }
let list_int = Tir.TCon ("List", [Tir.TInt])

let fn ?(kind = Tir.FnNormal) name params body : Tir.fn_def =
  { fn_name = name; fn_params = params; fn_ret_ty = list_int;
    fn_body = body; fn_kind = kind }

let module_of fns : Tir.tir_module =
  { tm_name = "T"; tm_fns = fns; tm_types = []; tm_externs = [];
    tm_exports = []; tm_tests = []; tm_io_fns = [] }

let verdict_of_fn m name =
  match List.find_opt (fun r -> String.equal r.Trmc.r_fn name)
          (Trmc.analyze_module m) with
  | Some r -> Trmc.string_of_verdict (Trmc.verdict_of r)
  | None -> "no-recursion"

let check_verdict msg expected m name =
  Alcotest.(check string) msg expected (verdict_of_fn m name)

(* let t = self(xs) in alloc Cons(h, t)  — the canonical TRMC shape. *)
let test_modulo_cons_eligible () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let t = v "t" list_int and h = v "h" Tir.TInt in
  let body =
    Tir.ELet (t, Tir.EApp (self, [Tir.AVar (v "xs" list_int)]),
              Tir.EAlloc (Tir.TCon ("List.Cons", []),
                          [Tir.AVar h; Tir.AVar t]))
  in
  let m = module_of [fn "f" [v "xs" list_int] body] in
  check_verdict "modulo-cons is eligible" "eligible" m "f";
  match Trmc.analyze_module m with
  | [r] ->
    Alcotest.(check (list (pair string int)))
      "hole is field 1 of List.Cons" [("List.Cons", 1)] r.Trmc.r_modcons
  | _ -> Alcotest.fail "expected exactly one report"

(* A plain tail call needs no TRMC. *)
let test_already_tail () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let body = Tir.EApp (self, [Tir.AVar (v "xs" list_int)]) in
  check_verdict "plain tail call" "already-tail"
    (module_of [fn "f" [v "xs" list_int] body]) "f"

(* self() under a non-constructor consumer is out of reach for v1. *)
let test_non_trmc () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let t = v "t" list_int in
  let body =
    Tir.ELet (t, Tir.EApp (self, [Tir.AVar (v "xs" list_int)]),
              Tir.EApp (v "List.length" (Tir.TFn ([list_int], Tir.TInt)),
                        [Tir.AVar t]))
  in
  check_verdict "call feeding a non-constructor" "non-trmc"
    (module_of [fn "f" [v "xs" list_int] body]) "f"

(* Node(self(l), self(r)): only the LAST call can own the hole; the first
   stays a real recursive call, so the function is partially transformable. *)
let test_branching_recursion_is_mixed () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let t1 = v "t1" list_int and t2 = v "t2" list_int in
  let body =
    Tir.ELet (t1, Tir.EApp (self, [Tir.AVar (v "l" list_int)]),
      Tir.ELet (t2, Tir.EApp (self, [Tir.AVar (v "r" list_int)]),
        Tir.EAlloc (Tir.TCon ("Tree.Node", []),
                    [Tir.AVar t1; Tir.AVar t2])))
  in
  let m = module_of [fn "f" [v "xs" list_int] body] in
  check_verdict "two recursive calls in one ctor" "mixed" m "f";
  match Trmc.analyze_module m with
  | [r] ->
    Alcotest.(check (list (pair string int)))
      "only the last call owns the hole" [("Tree.Node", 1)] r.Trmc.r_modcons;
    Alcotest.(check int) "the earlier call remains real" 1 r.Trmc.r_other
  | _ -> Alcotest.fail "expected exactly one report"

(* REGRESSION: lower_match hoists a match fall-through into a join point,
   so a plain tail call can end up inside ELetRec([jp], ..) in a let RHS.
   Treating that RHS as a value computation misreported List.last's tail
   call as unreachable — and moved 43 functions into "non-trmc" that were
   simply already tail-recursive. *)
let test_join_point_tail_call () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let jp =
    fn ~kind:Tir.FnJoinPoint "$jp0" []
      (Tir.EApp (self, [Tir.AVar (v "t" list_int)]))
  in
  let jp_var = v "$jp0" (Tir.TFn ([], list_int)) in
  let body =
    Tir.ELet (v "$jp_clo" (Tir.TFn ([], list_int)),
              Tir.ELetRec ([jp], Tir.EAtom (Tir.AVar jp_var)),
              Tir.ECallPtr (Tir.AVar jp_var, []))
  in
  check_verdict "tail call inside a join point stays a tail call"
    "already-tail" (module_of [fn "f" [v "xs" list_int] body]) "f"

(* The same join-point path must not launder a NON-tail call into a tail one:
   a FnNormal nested definition is not a continuation. *)
let test_normal_nested_fn_is_not_a_join_point () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let nested =
    fn ~kind:Tir.FnNormal "g" [] (Tir.EApp (self, [Tir.AVar (v "t" list_int)]))
  in
  let g_var = v "g" (Tir.TFn ([], list_int)) in
  let body =
    Tir.ELet (v "gc" (Tir.TFn ([], list_int)),
              Tir.ELetRec ([nested], Tir.EAtom (Tir.AVar g_var)),
              Tir.ECallPtr (Tir.AVar g_var, []))
  in
  check_verdict "ordinary nested fn does not inherit tail position"
    "non-trmc" (module_of [fn "f" [v "xs" list_int] body]) "f"

(* A value flowing through an intervening let that does not mention it is
   still a valid hole; one that is rebound or read is not. *)
let test_intervening_let_blocks_when_used () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let t = v "t" list_int and u = v "u" Tir.TInt in
  let body =
    Tir.ELet (t, Tir.EApp (self, [Tir.AVar (v "xs" list_int)]),
      Tir.ELet (u, Tir.EApp (v "List.length" (Tir.TFn ([list_int], Tir.TInt)),
                             [Tir.AVar t]),
        Tir.EAlloc (Tir.TCon ("List.Cons", []), [Tir.AVar u; Tir.AVar t])))
  in
  check_verdict "hole read before the constructor is not TRMC-able"
    "non-trmc" (module_of [fn "f" [v "xs" list_int] body]) "f"

(* ── Phase 2: the EAllocHole / ESetField IR nodes ────────────────────────────
   Nothing constructs these yet (Phase 3 does), so they are exercised here from
   hand-built TIR.  Two things are gated:
     1. the emitted LLVM is well-typed (run through the same verifier the
        native-fixture gate uses), and
     2. the hole's slot is genuinely LEFT UNWRITTEN at allocation and written
        only by the fill — the property that makes a hole a hole.
   Runtime behaviour is NOT proven here; that arrives with Phase 3, when the
   transformation actually emits these nodes into runnable programs. *)

let list_int_ty = Tir.TCon ("List", [Tir.TInt])

(* main() = let c = alloc_hole List.Cons(42, _) hole=1 in
            let n = alloc List.Nil() in
            c.1 <- n;
            case c of Cons(h, _) -> println(h) *)
let trmc_hole_module () : Tir.tir_module =
  let c = v "c" list_int_ty and n = v "n" list_int_ty in
  let h = v "h" Tir.TInt and t = v "t" list_int_ty in
  let body =
    Tir.ELet (c, Tir.EAllocHole (None, Tir.TCon ("List.Cons", []),
                                 [Tir.ALit (March_ast.Ast.LitInt 42)], 1),
      Tir.ELet (n, Tir.EAlloc (Tir.TCon ("List.Nil", []), []),
        Tir.ESeq (Tir.ESetField (Tir.AVar c, 1, Tir.AVar n),
          Tir.ECase (Tir.AVar c,
            [ { Tir.br_tag = "Cons"; br_vars = [h; t];
                br_body = Tir.EApp (v "println" (Tir.TFn ([Tir.TInt], Tir.TUnit)),
                                    [Tir.AVar h]) } ],
            None))))
  in
  { tm_name = "TrmcHole";
    tm_fns = [ { fn_name = "main"; fn_params = []; fn_ret_ty = Tir.TUnit;
                 fn_body = body; fn_kind = Tir.FnNormal } ];
    tm_types = [ Tir.TDVariant ("List", [("Nil", []); ("Cons", [Tir.TInt; list_int_ty])]) ];
    tm_externs = []; tm_exports = []; tm_tests = []; tm_io_fns = [] }

let test_alloc_hole_emits_verifiable_ir () =
  let ir = March_tir.Llvm_emit.emit_module (trmc_hole_module ()) in
  let path = Filename.temp_file "march_trmc_hole" ".ll" in
  let oc = open_out path in
  output_string oc ir; close_out oc;
  let result = Test_helpers.verify_llvm_ir_file path in
  Sys.remove path;
  match result with
  | `Ok -> ()
  | `NoTool -> ()   (* counted elsewhere: no opt/llvm-as on PATH *)
  | `Invalid out ->
    Alcotest.failf "EAllocHole/ESetField emitted invalid LLVM IR:\n%s" out

(* The hole must be left UNWRITTEN by the allocation and written by the fill.
   This is what distinguishes a real hole from "EAlloc with a null argument":
   if EAllocHole ever started zero-filling the slot explicitly, the IR would
   still verify and still run, but the node would have stopped being a hole and
   Phase 3's ownership reasoning would be silently wrong.

   Field slots live at header + 8*i, so field 0 is offset 16 and field 1 —
   the hole in this fixture — is offset 24.  In the emitted IR a field store is
   two lines, a `getelementptr i8, ptr %X, i64 <off>` followed by a `store`, so
   the offsets are counted by pairing each gep with the line after it. *)
let field_store_offsets (ir : string) : int list =
  let lines = Array.of_list (String.split_on_char '\n' ir) in
  let gep_off line =
    (* "  %fp3 = getelementptr i8, ptr %hp1, i64 16" -> Some 16 *)
    match String.rindex_opt line ',' with
    | None -> None
    | Some c ->
      let tail = String.trim (String.sub line (c + 1) (String.length line - c - 1)) in
      if String.length tail > 4 && String.sub tail 0 4 = "i64 " then
        int_of_string_opt (String.trim (String.sub tail 4 (String.length tail - 4)))
      else None
  in
  let is_gep line =
    match String.index_opt line 'g' with
    | _ ->
      let n = String.length line and sub = "getelementptr" in
      let m = String.length sub in
      let rec go i = i + m <= n && (String.sub line i m = sub || go (i + 1)) in
      go 0
  in
  let is_store line =
    let l = String.trim line and sub = "store " in
    String.length l >= String.length sub && String.sub l 0 (String.length sub) = sub
  in
  let acc = ref [] in
  Array.iteri (fun i line ->
    if is_gep line && i + 1 < Array.length lines && is_store lines.(i + 1) then
      match gep_off line with Some off -> acc := off :: !acc | None -> ()
  ) lines;
  List.rev !acc

let test_hole_slot_is_written_once () =
  let ir = March_tir.Llvm_emit.emit_module (trmc_hole_module ()) in
  let offsets = field_store_offsets ir in
  let count off = List.length (List.filter (( = ) off) offsets) in
  (* Field 0 (offset 16) is stored by the allocation itself. *)
  Alcotest.(check bool) "field 0 is stored at allocation" true (count 16 >= 1);
  (* The hole (offset 24) is stored EXACTLY once — by ESetField, never by
     EAllocHole.  Two stores would mean the allocation pre-filled it. *)
  Alcotest.(check int) "the hole's slot is stored exactly once (the fill)"
    1 (count 24)

(* ── Phase 2: the nodes must SURVIVE the pass pipeline ───────────────────────
   The two tests above go straight from hand-built TIR to [emit_module], which
   skips every intermediate pass.  That leaves the EAllocHole/ESetField arms in
   ~20 files (mono, defun, perceus, escape, dce, cprop, inline, ...) written but
   unexercised — a pass that silently dropped or mangled a hole would not be
   caught anywhere.

   This pushes a hole-bearing module through the same sequence the real driver
   uses (mono -> defun -> perceus -> escape) and checks the nodes come out the
   other side intact, with IR that still verifies.

   It also pins the ownership rule Phase 4 depends on: ESetField MOVES the
   stored value into the object, so Perceus must NOT treat the store as that
   value's last use and drop it there.  Getting this wrong is a double-free of
   a cell the parent now owns through its field. *)

let count_nodes (m : Tir.tir_module) : int * int =
  let holes = ref 0 and sets = ref 0 in
  let rec go e =
    match e with
    | Tir.EAllocHole _ -> incr holes
    | Tir.ESetField _ -> incr sets
    | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> go a; go b
    | Tir.ELetRec (fns, b) -> List.iter (fun fd -> go fd.Tir.fn_body) fns; go b
    | Tir.ECase (_, brs, def) ->
      List.iter (fun br -> go br.Tir.br_body) brs;
      Option.iter go def
    | _ -> ()
  in
  List.iter (fun (fd : Tir.fn_def) -> go fd.Tir.fn_body) m.Tir.tm_fns;
  (!holes, !sets)

(* Every EDecRC naming [name], anywhere in the module. *)
let decrc_count (m : Tir.tir_module) (name : string) : int =
  let n = ref 0 in
  let hit a = match a with
    | Tir.AVar v -> String.equal v.Tir.v_name name
    | _ -> false
  in
  let rec go e =
    match e with
    | Tir.EDecRC a | Tir.EAtomicDecRC a | Tir.EFree a -> if hit a then incr n
    | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> go a; go b
    | Tir.ELetRec (fns, b) -> List.iter (fun fd -> go fd.Tir.fn_body) fns; go b
    | Tir.ECase (_, brs, def) ->
      List.iter (fun br -> go br.Tir.br_body) brs;
      Option.iter go def
    | _ -> ()
  in
  List.iter (fun (fd : Tir.fn_def) -> go fd.Tir.fn_body) m.Tir.tm_fns;
  !n

let run_pipeline (m : Tir.tir_module) : Tir.tir_module =
  m
  |> March_tir.Mono.monomorphize
  |> March_tir.Defun.defunctionalize
  |> March_tir.Perceus.perceus
  |> March_tir.Escape.escape_analysis

let rec rc_ops (e : Tir.expr) : int =
  match e with
  | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
  | Tir.EFree _ -> 1
  | Tir.ELet (_, a, b) | Tir.ESeq (a, b) -> rc_ops a + rc_ops b
  | Tir.ELetRec (fns, b) ->
    List.fold_left (fun n fd -> n + rc_ops fd.Tir.fn_body) (rc_ops b) fns
  | Tir.ECase (_, brs, def) ->
    List.fold_left (fun n br -> n + rc_ops br.Tir.br_body)
      (Option.fold ~none:0 ~some:rc_ops def) brs
  | _ -> 0

let module_rc_ops (m : Tir.tir_module) : int =
  List.fold_left (fun n (fd : Tir.fn_def) -> n + rc_ops fd.Tir.fn_body) 0
    m.Tir.tm_fns

let test_nodes_survive_pass_pipeline () =
  let before = trmc_hole_module () in
  Alcotest.(check (pair int int)) "fixture starts with one of each"
    (1, 1) (count_nodes before);
  let after = run_pipeline before in
  (* Non-vacuousness: a survival test is worthless if the passes never touched
     the module.  Perceus starts from RC-free TIR, so a nonzero RC-op count
     afterwards proves the pipeline actually ran over this fixture. *)
  Alcotest.(check int) "fixture starts RC-free" 0 (module_rc_ops before);
  Alcotest.(check bool) "the pipeline actually ran (Perceus inserted RC ops)"
    true (module_rc_ops after > 0);
  Alcotest.(check (pair int int))
    "EAllocHole and ESetField survive mono -> defun -> perceus -> escape"
    (1, 1) (count_nodes after)

let test_pipeline_output_still_verifies () =
  let after = run_pipeline (trmc_hole_module ()) in
  let ir = March_tir.Llvm_emit.emit_module after in
  let path = Filename.temp_file "march_trmc_pipeline" ".ll" in
  let oc = open_out path in
  output_string oc ir; close_out oc;
  let result = Test_helpers.verify_llvm_ir_file path in
  Sys.remove path;
  match result with
  | `Ok | `NoTool -> ()
  | `Invalid out ->
    Alcotest.failf "post-pipeline IR failed the LLVM verifier:\n%s" out

(* Ownership: `n` is stored into `c` by ESetField and never read again.  If
   Perceus treated the store as `n`'s last use it would drop it there, leaving
   `c`'s field pointing at freed memory.  The store is a MOVE — `c`'s own
   lifetime releases the value — so no drop of `n` may be emitted at all. *)
let test_setfield_is_an_ownership_move () =
  let after = run_pipeline (trmc_hole_module ()) in
  Alcotest.(check int)
    "no drop is emitted for the value moved into the hole"
    0 (decrc_count after "n")

(* An actor message type must never be TRMC'd: the hole-fill is a plain
   non-atomic store, which is only safe while the cell is thread-local. *)
let test_actor_msg_type_is_refused () =
  let msg_ty = Tir.TCon ("Counter_Msg", []) in
  let self = v "f" (Tir.TFn ([msg_ty], msg_ty)) in
  let t = v "t" msg_ty and h = v "h" Tir.TInt in
  let body =
    Tir.ELet (t, Tir.EApp (self, [Tir.AVar (v "xs" msg_ty)]),
              Tir.EAlloc (Tir.TCon ("Counter_Msg.Bump", []),
                          [Tir.AVar h; Tir.AVar t]))
  in
  let fd =
    { Tir.fn_name = "f"; fn_params = [v "xs" msg_ty]; fn_ret_ty = msg_ty;
      fn_body = body; fn_kind = Tir.FnNormal }
  in
  Alcotest.(check bool) "actor message type is not transformed"
    true (Trmc.transform_fn fd = None)

(* REPL/JIT must apply the same transform as the compiled path, or a function
   behaves one way in the REPL and another when compiled.  repl_jit may re-lower
   a module the driver already transformed, so the transform has to be
   idempotent — running it twice must not produce a second $dps helper.

   The fixture uses a genuinely ELIGIBLE function: on an empty module both
   sides are trivially zero and the assertion holds no matter how broken the
   transform is. *)
let test_transform_is_idempotent_on_a_transformed_module () =
  let self = v "f" (Tir.TFn ([list_int], list_int)) in
  let t = v "t" list_int and h = v "h" Tir.TInt in
  let body =
    Tir.ELet (t, Tir.EApp (self, [Tir.AVar (v "xs" list_int)]),
              Tir.EAlloc (Tir.TCon ("List.Cons", []),
                          [Tir.AVar h; Tir.AVar t]))
  in
  let m = module_of [fn "f" [v "xs" list_int] body] in
  Trmc.enabled := true;
  let once = Trmc.transform_module m in
  let twice = Trmc.transform_module once in
  Trmc.enabled := false;
  (* Non-vacuousness: the first pass must actually have added the helper. *)
  Alcotest.(check int) "first transform adds the $dps helper"
    2 (List.length once.Tir.tm_fns);
  Alcotest.(check int) "transforming twice adds nothing further"
    (List.length once.Tir.tm_fns) (List.length twice.Tir.tm_fns)

(* ── Phase 2: the JS backend ─────────────────────────────────────────────────
   [Js_emit.emit_tagged_alloc_hole] and the [ESetField] arm had no coverage at
   all: every other TRMC test goes through Llvm_emit.  JS has no
   uninitialized-memory hazard to mirror, so a hole is simply a field holding
   [null] until the fill overwrites it — which means the JS backend can be
   gated the strong way, by RUNNING the emitted program. *)

let js_of_hole_module () =
  let (js, _srcmap) = March_tir.Js_emit.emit_module (trmc_hole_module ()) in
  js

let contains hay sub =
  let n = String.length sub and m = String.length hay in
  let rec go i = i + n <= m && (String.sub hay i n = sub || go (i + 1)) in
  go 0

(* Shape, not just spelling: the allocation must emit the FILLED field and
   leave the hole as [null], and the fill must be an in-place property write on
   that same object, sequenced with [undefined] so its value is unit (a bare
   assignment expression would evaluate to the stored value and silently change
   the meaning of an ESetField in value position). *)
let test_js_emits_hole_and_fill () =
  let js = js_of_hole_module () in
  Alcotest.(check bool)
    "allocation fills field 0 and leaves the hole null" true
    (contains js "{ $: \"Cons\", _0: 42, _1: null }");
  Alcotest.(check bool)
    "the fill is a property write sequenced to undefined" true
    (contains js "(c._1 = n, undefined)")

(* Executing the emitted module proves what a substring cannot: that the hole
   is allocated, filled, and read back — main() prints the 42 stored in field 0
   of the cell whose field 1 was a hole.  Skipped (rather than failed) when
   node or the JS runtime shim is unavailable, exactly as the LLVM tests above
   skip on a missing verifier; the substring test runs unconditionally, so the
   JS emission is never left with zero coverage. *)
let find_js_runtime () =
  List.find_opt Sys.file_exists
    [ "runtime/march_runtime.mjs";
      "../runtime/march_runtime.mjs";
      "../../runtime/march_runtime.mjs";
      "../../../runtime/march_runtime.mjs" ]

let copy_file src dst =
  let ic = open_in_bin src in
  let n = in_channel_length ic in
  let buf = really_input_string ic n in
  close_in ic;
  let oc = open_out_bin dst in
  output_string oc buf; close_out oc

let test_js_hole_program_runs_under_node () =
  let have_node = Sys.command "command -v node > /dev/null 2>&1" = 0 in
  match (have_node, find_js_runtime ()) with
  | (false, _) | (_, None) ->
    (* Announce the skip.  A silent [()] here reports GREEN for a test that
       never ran, which is how a JS-backend regression would reach main
       unnoticed on a node-less runner. *)
    Printf.eprintf
      "[trmc-js] SKIP: node=%b runtime_shim=%b — hole execution NOT verified\n%!"
      have_node (find_js_runtime () <> None)
  | (true, Some runtime) ->
    let dir = Filename.temp_file "march_trmc_js" "" in
    Sys.remove dir; Unix.mkdir dir 0o700;
    let prog = Filename.concat dir "hole.mjs" in
    let out = Filename.concat dir "out.txt" in
    let oc = open_out prog in
    output_string oc (js_of_hole_module ()); close_out oc;
    copy_file runtime (Filename.concat dir "march_runtime.mjs");
    let rc =
      Sys.command (Printf.sprintf "node %s > %s 2>&1"
                     (Filename.quote prog) (Filename.quote out))
    in
    let stdout_txt =
      let ic = open_in out in
      let n = in_channel_length ic in
      let s = really_input_string ic n in
      close_in ic; s
    in
    List.iter Sys.remove [prog; out; Filename.concat dir "march_runtime.mjs"];
    Unix.rmdir dir;
    if rc <> 0 then
      Alcotest.failf "emitted JS failed to run (exit %d):\n%s" rc stdout_txt;
    Alcotest.(check string) "the filled hole is read back and printed"
      "42" (String.trim stdout_txt)

let suites = [
  "trmc", [
    Alcotest.test_case "modulo-cons is eligible"        `Quick test_modulo_cons_eligible;
    Alcotest.test_case "plain tail call"                `Quick test_already_tail;
    Alcotest.test_case "non-constructor consumer"       `Quick test_non_trmc;
    Alcotest.test_case "branching recursion is mixed"   `Quick test_branching_recursion_is_mixed;
    Alcotest.test_case "join-point tail call"           `Quick test_join_point_tail_call;
    Alcotest.test_case "normal nested fn is not a jp"   `Quick test_normal_nested_fn_is_not_a_join_point;
    Alcotest.test_case "intervening use blocks hole"    `Quick test_intervening_let_blocks_when_used;
    Alcotest.test_case "actor msg type refused"          `Quick test_actor_msg_type_is_refused;
    Alcotest.test_case "transform is idempotent"         `Quick test_transform_is_idempotent_on_a_transformed_module;
  ];
  "trmc-ir", [
    Alcotest.test_case "alloc-hole emits verifiable IR"  `Quick test_alloc_hole_emits_verifiable_ir;
    Alcotest.test_case "hole slot written once by fill"  `Quick test_hole_slot_is_written_once;
  ];
  "trmc-pipeline", [
    Alcotest.test_case "nodes survive the pass pipeline"  `Quick test_nodes_survive_pass_pipeline;
    Alcotest.test_case "post-pipeline IR verifies"        `Quick test_pipeline_output_still_verifies;
    Alcotest.test_case "ESetField is an ownership move"   `Quick test_setfield_is_an_ownership_move;
  ];
  "trmc-js", [
    Alcotest.test_case "js emits hole and fill"           `Quick test_js_emits_hole_and_fill;
    Alcotest.test_case "emitted js runs under node"       `Quick test_js_hole_program_runs_under_node;
  ]
]
