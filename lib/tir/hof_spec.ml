(** Higher-order-function specialization and unboxed known calls
    (specs/plans/2026-09-30-float-closure-unboxing.md).

    Every closure call goes through one erased ABI in which a Float crosses
    heap-boxed. Inside a higher-order function such as [List.fold_left] the
    call [f(acc, h)] is an [ECallPtr] on a PARAMETER, so nothing at that site
    knows which lambda it is and it must use the erased ABI: a Float fold over a
    list paid ~90 ns per element of boxing (bench/float_closure_calls.march).

    Two passes, run at two points of [Contract_pipeline]:

    {b [specialize]} (after Defun, before Known_call). For a call
    [g(..., c, ...)] where [c] is bound to a closure allocation of a known
    apply fn [A], and [g] passes that parameter UNCHANGED to every self-call (a
    "static argument", as fold_left does with [f]), clone [g] as
    [g$hspec$N] and redirect the call to it. In the clone, every
    [ECallPtr(f, args)] becomes [EApp(A, f :: args)] -- exactly the form
    [Known_call] produces for a closure whose allocation it can see -- and the
    self-calls go to the clone. The closure is still passed as before, so no
    ownership changes: the only difference is that the callee is known.

    {b [redirect_unboxed]} (after Opt, beside [Native_map_inline]). A direct
    call [EApp(A, clo :: args)] to an apply fn whose callback signature is
    concretely Float/Int (at least one Float) is redirected to a clone of [A]
    whose name lacks ["$apply$"]. [Tir_names.is_apply_fn] is what makes the
    emitter box, so the clone is emitted with native [double]/[i64] parameters
    and return, and the call passes them unboxed. This is the same mechanism
    as [Native_map_inline]'s [$mapfast$] clone, with a different marker
    ([$ufast$]) so the two passes can never mint the same name. It runs after
    Perceus, on an already-RC-annotated [fn_def], so the clone's ownership
    behaviour is the apply fn's exactly.

    Both are skipped under hot reload: a specialized clone bakes a lambda into
    a copy of another function, which the HCR boundary/identity machinery does
    not know about. *)

module SMap = Map.Make (String)

(* ── shared helpers ─────────────────────────────────────────────────── *)

let is_clo_alloc_name (n : string) = Tir_names.is_clo_struct n

(** Names bound anywhere in [e] (lets, letrec fns and their params, case
    binders). Used to refuse rewriting a parameter that the body rebinds. *)
let rec binders (e : Tir.expr) (acc : string list) : string list =
  match e with
  | Tir.ELet (v, e1, e2) -> binders e2 (binders e1 (v.Tir.v_name :: acc))
  | Tir.ELetRec (fns, body) ->
    let acc = List.fold_left (fun acc (fd : Tir.fn_def) ->
        let acc = fd.Tir.fn_name :: acc in
        let acc = List.fold_left (fun a (p : Tir.var) -> p.Tir.v_name :: a) acc fd.Tir.fn_params in
        binders fd.Tir.fn_body acc) acc fns in
    binders body acc
  | Tir.ECase (_, brs, def) ->
    let acc = List.fold_left (fun acc (b : Tir.branch) ->
        let acc = List.fold_left (fun a (v : Tir.var) -> v.Tir.v_name :: a) acc b.Tir.br_vars in
        binders b.Tir.br_body acc) acc brs in
    (match def with Some d -> binders d acc | None -> acc)
  | Tir.ESeq (e1, e2) -> binders e2 (binders e1 acc)
  | _ -> acc

(** Every self-call [EApp(name, args)] in [e] passes [AVar p] at index [i]. *)
let rec static_at (name : string) (i : int) (p : string) (e : Tir.expr) : bool =
  let ok_app (f : Tir.var) args =
    f.Tir.v_name <> name
    || (match List.nth_opt args i with
        | Some (Tir.AVar v) -> v.Tir.v_name = p
        | _ -> false)
  in
  match e with
  | Tir.EApp (f, args) -> ok_app f args
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> static_at name i p e1 && static_at name i p e2
  | Tir.ELetRec (fns, body) ->
    List.for_all (fun (fd : Tir.fn_def) -> static_at name i p fd.Tir.fn_body) fns
    && static_at name i p body
  | Tir.ECase (_, brs, def) ->
    List.for_all (fun (b : Tir.branch) -> static_at name i p b.Tir.br_body) brs
    && (match def with Some d -> static_at name i p d | None -> true)
  | _ -> true

(** [p] is called indirectly somewhere in [e] (otherwise specializing buys nothing). *)
let rec calls_ptr (p : string) (e : Tir.expr) : bool =
  match e with
  | Tir.ECallPtr (Tir.AVar v, _) -> v.Tir.v_name = p
  | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> calls_ptr p e1 || calls_ptr p e2
  | Tir.ELetRec (fns, body) ->
    List.exists (fun (fd : Tir.fn_def) -> calls_ptr p fd.Tir.fn_body) fns || calls_ptr p body
  | Tir.ECase (_, brs, def) ->
    List.exists (fun (b : Tir.branch) -> calls_ptr p b.Tir.br_body) brs
    || (match def with Some d -> calls_ptr p d | None -> false)
  | _ -> false

(* ── specialize ─────────────────────────────────────────────────────── *)

(** Body-size budget for a function to be cloned. Larger than [Inline]'s
    threshold because a clone is emitted once per distinct lambda, not once
    per call site. *)
let size_budget = 200

(** At most this many clones per higher-order function per module. *)
let max_clones_per_fn = 16

(** Static closure parameters of [fd]: indices [i] whose parameter has a
    function type, is never rebound in the body, is passed unchanged to every
    self-call, and is called indirectly at least once. *)
let static_closure_params (fd : Tir.fn_def) : int list =
  let bound = binders fd.Tir.fn_body [] in
  List.concat (List.mapi (fun i (p : Tir.var) ->
      match p.Tir.v_ty with
      | Tir.TFn _ when not (List.mem p.Tir.v_name bound)
                    && static_at fd.Tir.fn_name i p.Tir.v_name fd.Tir.fn_body
                    && calls_ptr p.Tir.v_name fd.Tir.fn_body -> [ i ]
      | _ -> []) fd.Tir.fn_params)

(** Clone body: self-calls go to [clone_name]; [ECallPtr(p, args)] becomes the
    [Known_call] form [EApp(apply, p :: args)]. [p] is never rebound (checked by
    [static_closure_params]), so no scope tracking is needed. *)
let rec rewrite_clone ~(orig : string) ~(clone_name : string) ~(p : string)
    ~(apply_var : Tir.var) (e : Tir.expr) : Tir.expr =
  let go = rewrite_clone ~orig ~clone_name ~p ~apply_var in
  match e with
  | Tir.EApp (f, args) when f.Tir.v_name = orig -> Tir.EApp ({ f with Tir.v_name = clone_name }, args)
  | Tir.ECallPtr (Tir.AVar v, args) when v.Tir.v_name = p -> Tir.EApp (apply_var, Tir.AVar v :: args)
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = go fd.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (b : Tir.branch) -> { b with Tir.br_body = go b.Tir.br_body }) brs,
               Option.map go def)
  | other -> other

type spec_state = {
  fns : (string, Tir.fn_def) Hashtbl.t;                (* every top-level fn *)
  statics : (string, int list) Hashtbl.t;              (* candidate -> static indices *)
  clones : (string * int * string, string) Hashtbl.t;  (* (g, i, apply) -> clone *)
  per_fn : (string, int) Hashtbl.t;                    (* g -> clones minted *)
  mutable counter : int;
  mutable new_fns : Tir.fn_def list;
  (* Clones minted but whose bodies have not yet had their own call sites
     rewritten, each with the closure parameter it knows: (name, param, apply). *)
  mutable pending : (string * string * string) list;
}

let rec has_tvar (t : Tir.ty) : bool =
  match t with
  | Tir.TVar _ -> true
  | Tir.TInt | Tir.TFloat | Tir.TBool | Tir.TString | Tir.TUnit -> false
  | Tir.TTuple ts | Tir.TCon (_, ts) -> List.exists has_tvar ts
  | Tir.TRecord fs -> List.exists (fun (_, t) -> has_tvar t) fs
  | Tir.TFn (ps, r) -> List.exists has_tvar ps || has_tvar r
  | Tir.TPtr t -> has_tvar t

(** Specialize only on a lambda whose signature is concrete. A let-generalized
    lambda (`let keep = fn (p, x) -> p`, parameters still [TVar] after Mono)
    takes erased Float arguments under an ownership protocol that only the
    indirect-call path implements (the callee takes its own reference to a
    caller-kept box, [march_clo_param_own] / [march_clo_float_arg]); making
    the call direct leaked one box per call
    (test/native/closure_call_arg_ownership_probe.march's "erased lambda"
    legs). The [$clo] parameter is an opaque pointer and is not checked. *)
let concrete_apply (st : spec_state) (apply : string) : bool =
  match Hashtbl.find_opt st.fns apply with
  | Some fd ->
    (match fd.Tir.fn_params with
     | _clo :: rest ->
       not (has_tvar fd.Tir.fn_ret_ty)
       && not (List.exists (fun (p : Tir.var) -> has_tvar p.Tir.v_ty) rest)
     | [] -> false)
  | None -> false

(** The clone of [g] for closure index [i] bound to apply fn [apply], minting it
    on first use; [None] once [g]'s clone budget is spent. *)
let clone_for (st : spec_state) (g : Tir.fn_def) (i : int) (apply : string) : string option =
  if not (concrete_apply st apply) then None else
  match Hashtbl.find_opt st.clones (g.Tir.fn_name, i, apply) with
  | Some n -> Some n
  | None ->
    let used = Option.value ~default:0 (Hashtbl.find_opt st.per_fn g.Tir.fn_name) in
    if used >= max_clones_per_fn then None
    else begin
      st.counter <- st.counter + 1;
      Hashtbl.replace st.per_fn g.Tir.fn_name (used + 1);
      let name = Printf.sprintf "%s$hspec$%d" g.Tir.fn_name st.counter in
      Hashtbl.replace st.clones (g.Tir.fn_name, i, apply) name;
      let p = (List.nth g.Tir.fn_params i).Tir.v_name in
      let apply_var = { Tir.v_name = apply; v_ty = Tir.TPtr Tir.TUnit; v_lin = Tir.Unr } in
      let body = rewrite_clone ~orig:g.Tir.fn_name ~clone_name:name ~p ~apply_var g.Tir.fn_body in
      st.new_fns <- { g with Tir.fn_name = name; fn_body = body } :: st.new_fns;
      st.pending <- (name, p, apply) :: st.pending;
      Some name
    end

(** Rewrite call sites in [e]. [env] maps a variable to the apply fn of the
    closure allocation it is bound to (directly or through a copy). *)
let rec rewrite_calls (st : spec_state) (env : string SMap.t) (e : Tir.expr) : Tir.expr =
  let go = rewrite_calls st in
  match e with
  | Tir.ELet (v, (Tir.EAlloc (Tir.TCon (clo, _), Tir.AVar fn_ptr :: _) as rhs), body)
    when is_clo_alloc_name clo ->
    Tir.ELet (v, rhs, go (SMap.add v.Tir.v_name fn_ptr.Tir.v_name env) body)
  | Tir.ELet (v, (Tir.EAtom (Tir.AVar src) as rhs), body) when SMap.mem src.Tir.v_name env ->
    Tir.ELet (v, rhs, go (SMap.add v.Tir.v_name (SMap.find src.Tir.v_name env) env) body)
  | Tir.EApp (f, args) when Hashtbl.mem st.statics f.Tir.v_name ->
    let g = Hashtbl.find st.fns f.Tir.v_name in
    let pick = List.find_map (fun i ->
        match List.nth_opt args i with
        | Some (Tir.AVar a) ->
          (match SMap.find_opt a.Tir.v_name env with
           | Some apply -> clone_for st g i apply
           | None -> None)
        | _ -> None) (Hashtbl.find st.statics f.Tir.v_name) in
    (match pick with
     | Some clone -> Tir.EApp ({ f with Tir.v_name = clone }, args)
     | None -> e)
  | Tir.ELet (v, e1, e2) ->
    (* A let rebinding a tracked name shadows it in the body. *)
    Tir.ELet (v, go env e1, go (SMap.remove v.Tir.v_name env) e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go env e1, go env e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = go env fd.Tir.fn_body }) fns,
                 go env body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (b : Tir.branch) ->
        let env = List.fold_left (fun m (v : Tir.var) -> SMap.remove v.Tir.v_name m) env b.Tir.br_vars in
        { b with Tir.br_body = go env b.Tir.br_body }) brs,
        Option.map (go env) def)
  | other -> other

let specialize (m : Tir.tir_module) : Tir.tir_module =
  let st = { fns = Hashtbl.create 256; statics = Hashtbl.create 64; clones = Hashtbl.create 16;
             per_fn = Hashtbl.create 16; counter = 0; new_fns = []; pending = [] } in
  List.iter (fun (fd : Tir.fn_def) ->
      Hashtbl.replace st.fns fd.Tir.fn_name fd;
      if fd.Tir.fn_kind = Tir.FnNormal && Inline.node_count fd.Tir.fn_body <= size_budget then
        match static_closure_params fd with
        | [] -> ()
        | idx -> Hashtbl.replace st.statics fd.Tir.fn_name idx)
    m.Tir.tm_fns;
  if Hashtbl.length st.statics = 0 then m
  else begin
    (* Only rewrite call sites in functions reachable from the program's
       roots. Every program lowers the whole stdlib, and cloning for call
       sites in functions DCE will drop anyway cost ~8% compile time (939
       clones on a small program) for nothing. [reachable_fns] fails open, so
       a module with no entry point still gets every call site considered. *)
    let reachable = Dce.reachable_fns m in
    let fns' = List.map (fun (fd : Tir.fn_def) ->
        if Dce.StringSet.mem fd.Tir.fn_name reachable
        then { fd with Tir.fn_body = rewrite_calls st SMap.empty fd.Tir.fn_body }
        else fd) m.Tir.tm_fns in
    (* Inside a clone the static closure parameter IS a known closure, so a
       call that hands it on to another candidate (TRMC's [map] entry calling
       its [map$dps] loop, a wrapper calling fold_left) can be specialized too.
       Worklist over the clones; it terminates because every clone mint counts
       against its function's [max_clones_per_fn] budget. *)
    let rewritten = Hashtbl.create 16 in
    let rec drain () =
      match st.pending with
      | [] -> ()
      | (name, p, apply) :: rest ->
        st.pending <- rest;
        if not (Hashtbl.mem rewritten name) then begin
          Hashtbl.replace rewritten name ();
          match List.find_opt (fun (fd : Tir.fn_def) -> fd.Tir.fn_name = name) st.new_fns with
          | None -> ()
          | Some fd ->
            (* Compute first: rewriting may mint more clones onto [st.new_fns]. *)
            let body = rewrite_calls st (SMap.singleton p apply) fd.Tir.fn_body in
            st.new_fns <- List.map (fun (f : Tir.fn_def) ->
                if f.Tir.fn_name = name then { f with Tir.fn_body = body } else f) st.new_fns
        end;
        drain ()
    in
    drain ();
    { m with Tir.tm_fns = fns' @ List.rev st.new_fns }
  end

(* ── redirect_unboxed ───────────────────────────────────────────────── *)

let is_scalar = function Tir.TFloat | Tir.TInt -> true | _ -> false

(** An apply fn whose every parameter after [$clo], and whose return, is Float
    or Int, with at least one Float: the shape where the erased ABI boxes and
    the native ABI does not. *)
let unboxable (fd : Tir.fn_def) : bool =
  Tir_names.is_apply_fn fd.Tir.fn_name
  && (match fd.Tir.fn_params with
      | _clo :: (_ :: _ as rest) ->
        let tys = fd.Tir.fn_ret_ty :: List.map (fun (p : Tir.var) -> p.Tir.v_ty) rest in
        List.for_all is_scalar tys && List.mem Tir.TFloat tys
      | _ -> false)

(** ["f$apply$7"] -> ["f$ufast$7"]: the ["$apply$"] marker spliced out, so
    [Tir_names.is_apply_fn] is false for the clone. *)
let ufast_name (apply : string) : string =
  let marker = "$apply$" in
  let ml = String.length marker and nl = String.length apply in
  let rec find i = if i + ml > nl then None else if String.sub apply i ml = marker then Some i else find (i + 1) in
  match find 0 with
  | Some i -> String.sub apply 0 i ^ "$ufast$" ^ String.sub apply (i + ml) (nl - i - ml)
  | None -> apply ^ "$ufast$0"

let rec redirect (tbl : (string, Tir.fn_def) Hashtbl.t) (made : (string, Tir.fn_def) Hashtbl.t)
    (e : Tir.expr) : Tir.expr =
  let go = redirect tbl made in
  match e with
  | Tir.EApp (f, (_ :: _ as args)) when Hashtbl.mem tbl f.Tir.v_name ->
    let fd = Hashtbl.find tbl f.Tir.v_name in
    let name = ufast_name fd.Tir.fn_name in
    if not (Hashtbl.mem made name) then Hashtbl.replace made name { fd with Tir.fn_name = name };
    Tir.EApp ({ f with Tir.v_name = name }, args)
  | Tir.ELet (v, e1, e2) -> Tir.ELet (v, go e1, go e2)
  | Tir.ESeq (e1, e2) -> Tir.ESeq (go e1, go e2)
  | Tir.ELetRec (fns, body) ->
    Tir.ELetRec (List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = go fd.Tir.fn_body }) fns, go body)
  | Tir.ECase (a, brs, def) ->
    Tir.ECase (a, List.map (fun (b : Tir.branch) -> { b with Tir.br_body = go b.Tir.br_body }) brs,
               Option.map go def)
  | other -> other

let redirect_unboxed (m : Tir.tir_module) : Tir.tir_module =
  let tbl = Hashtbl.create 64 in
  List.iter (fun (fd : Tir.fn_def) -> if unboxable fd then Hashtbl.replace tbl fd.Tir.fn_name fd) m.Tir.tm_fns;
  if Hashtbl.length tbl = 0 then m
  else begin
    let made = Hashtbl.create 16 in
    let fns' = List.map (fun (fd : Tir.fn_def) -> { fd with Tir.fn_body = redirect tbl made fd.Tir.fn_body }) m.Tir.tm_fns in
    let existing = Hashtbl.create 64 in
    List.iter (fun (fd : Tir.fn_def) -> Hashtbl.replace existing fd.Tir.fn_name ()) fns';
    let extra = Hashtbl.fold (fun n fd acc -> if Hashtbl.mem existing n then acc else fd :: acc) made [] in
    let extra = List.sort (fun (a : Tir.fn_def) b -> compare a.Tir.fn_name b.Tir.fn_name) extra in
    { m with Tir.tm_fns = fns' @ extra }
  end
