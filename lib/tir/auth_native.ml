(* Native and JIT programs judge capability operations with the C copy of
   the run-time authority's policy (ocap phase 4, Task 4b;
   runtime/march_authority.c).  The interpreter and the JS target run the
   March policy in stdlib/authority.march.

   The seam is this pass: every direct call of one of the Authority policy
   functions below becomes a call of the C builtin with the same arguments
   and result.  It runs right after [Auth_rt.frames] (whose layer builders
   call [Authority.frame_layer]) and before Mono, so the March bodies,
   no longer called, are never monomorphised or emitted: a program that does
   capability operations links [Authority.check] and these runtime symbols,
   not the parser and matcher.

   The C code builds and reads the March values of [Authority.Layer],
   [Authority.CapEntry], [Authority.Arg], [CapLimit], [CapError], [Result] and
   [List] by their declared constructor tags.  A program that declares a
   type with the same short name as one of them makes that name collide
   (both declarations take global constructor tags, [Collision_set]); such a
   program keeps the March policy, which the compiler lowers consistently
   whatever the tags.  The answer is the same either way. *)

let table : (string * string) list =
  [ ("Authority.parse", "cap_rt_parse");
    ("Authority.admits", "cap_rt_admits");
    ("Authority.subset", "cap_rt_subset");
    ("Authority.frame_layer", "cap_rt_frame_layer");
    ("Authority.launch_init", "cap_rt_launch_init");
    ("Authority.check_layers", "cap_rt_check_layers");
    ("Authority.check_slow", "cap_rt_check_slow") ]

(* The builtins this pass introduces. *)
let builtins : string list = List.map snd table

(* The short type names whose constructor tags the C code relies on. *)
let shapes = [ "Layer"; "CapEntry"; "Arg"; "CapLimit"; "CapError"; "Result"; "List" ]

let rec map_expr (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.EApp (f, args) ->
    (match List.assoc_opt f.Tir.v_name table with
     | Some b -> Tir.EApp ({ f with Tir.v_name = b }, args)
     | None -> e)
  | Tir.ELet (v, a, b) -> Tir.ELet (v, map_expr a, map_expr b)
  | Tir.ELetRec (fns, b) -> Tir.ELetRec (List.map map_fn fns, map_expr b)
  | Tir.ECase (s, brs, d) ->
    Tir.ECase
      (s, List.map (fun (br : Tir.branch) -> { br with Tir.br_body = map_expr br.Tir.br_body }) brs,
       Option.map map_expr d)
  | Tir.ESeq (a, b) -> Tir.ESeq (map_expr a, map_expr b)
  | Tir.EAtom _ | Tir.ECallPtr _ | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
  | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EFree _ | Tir.EIncRC _ | Tir.EDecRC _
  | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _ | Tir.EReuse _ | Tir.EAllocHole _ | Tir.ESetField _ ->
    e

and map_fn (f : Tir.fn_def) : Tir.fn_def = { f with Tir.fn_body = map_expr f.Tir.fn_body }

(** Whether [m] can use the C policy: none of [shapes] collides. *)
let applicable (m : Tir.tir_module) : bool =
  let cs = Collision_set.compute m.Tir.tm_types in
  not (List.exists (fun s -> Hashtbl.mem cs s) shapes)

let retarget (m : Tir.tir_module) : Tir.tir_module =
  if not (applicable m) then m
  else { m with Tir.tm_fns = List.map map_fn m.Tir.tm_fns }
