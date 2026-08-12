(* Per-function capability rows — R1 stage C.  See cap_rows.mli for the
   design rationale (why deps/unknown exist, and why an opaque ARGUMENT does
   not set unknown while an opaque HEAD does). *)

module A = March_ast.Ast

type arg_shape =
  | ASParams of string list
  | ASName of string
  | ASInline
  | ASOpaque

type seed = {
  sd_params : string list;
  sd_deps : string list;
  sd_unknown : bool;
  sd_calls : (string * arg_shape list) list;
}

let empty_seed =
  { sd_params = []; sd_deps = []; sd_unknown = false; sd_calls = [] }

let merge_seed (a : seed) (b : seed) : seed =
  {
    sd_params =
      (if List.length b.sd_params > List.length a.sd_params then b.sd_params
       else a.sd_params);
    sd_deps = List.sort_uniq compare (a.sd_deps @ b.sd_deps);
    sd_unknown = a.sd_unknown || b.sd_unknown;
    sd_calls = a.sd_calls @ b.sd_calls;
  }

(* ── the seed walk ─────────────────────────────────────────────────────── *)

(* How a name currently in scope was bound.  [CParams] is the only
   classification that can produce a dep; [COpaque] is the only one whose
   INVOCATION produces [unknown]. *)
type cls =
  | CParams of string list  (** a parameter of the owner, or an alias of one *)
  | CName of string  (** an alias of a (possibly) top-level function name *)
  | CCharged
      (** a value whose whole reach was already charged to the owner at the
          site that built it: a lambda literal, or the result of a named call
          ([let m = map(g)] charges [g] where [g] is supplied) *)
  | COpaque  (** a value with no traceable creation site *)

let rec pat_binders (p : A.pattern) : string list =
  match p with
  | A.PatVar n -> [ n.A.txt ]
  | A.PatWild _ | A.PatLit _ -> []
  | A.PatCon (_, ps) -> List.concat_map pat_binders ps
  | A.PatTuple (ps, _) | A.PatOr (ps, _) | A.PatAtom (_, ps, _) ->
    List.concat_map pat_binders ps
  | A.PatRecord (fields, _) -> List.concat_map (fun (_, p) -> pat_binders p) fields
  | A.PatAs (p, n, _) -> n.A.txt :: pat_binders p

let seed_of_body (params : string list) (body : A.expr) : seed =
  let deps = ref [] and unknown = ref false and calls = ref [] in
  let add_deps ps = deps := ps @ !deps in
  let lookup scope (n : string) : cls option = List.assoc_opt n scope in
  (* An argument passed to a callee this walk could not identify.  Only the
     parameter case is charged: a name is already a free-variable edge, a
     lambda is already walked, and an opaque value is deliberately not
     charged (see the .mli). *)
  let charge_unknown_callee shapes =
    List.iter (function ASParams ps -> add_deps ps | _ -> ()) shapes
  in
  let rec cls_of_rhs scope (e : A.expr) : cls =
    match e with
    | A.ELam _ -> CCharged
    | A.EVar n -> (
      match lookup scope n.A.txt with Some c -> c | None -> CName n.A.txt)
    | A.EAnnot (inner, _, _) | A.EDbg (Some inner, _) -> cls_of_rhs scope inner
    | A.EApp (A.EVar _, _, _) -> CCharged
    | _ -> COpaque
  and shape scope (e : A.expr) : arg_shape =
    match e with
    | A.ELam _ -> ASInline
    | A.EVar n -> (
      match lookup scope n.A.txt with
      | Some (CParams ps) -> ASParams ps
      | Some (CName g) -> ASName g
      | Some CCharged | Some COpaque -> ASOpaque
      | None -> ASName n.A.txt)
    | A.EAnnot (inner, _, _) -> shape scope inner
    | _ -> ASOpaque
  (* Classify the head of an application, then walk head and arguments. *)
  and app scope (f : A.expr) (args : A.expr list) =
    let shapes = List.map (shape scope) args in
    (match f with
     | A.EVar n -> (
       match lookup scope n.A.txt with
       | Some (CParams ps) ->
         add_deps ps;
         charge_unknown_callee shapes
       | Some (CName g) -> calls := (g, shapes) :: !calls
       | Some CCharged -> charge_unknown_callee shapes
       | Some COpaque ->
         unknown := true;
         charge_unknown_callee shapes
       | None -> calls := (n.A.txt, shapes) :: !calls)
     | A.ELam _ -> ()  (* immediately applied; its body is walked below *)
     | _ ->
       unknown := true;
       charge_unknown_callee shapes);
    (match f with A.EVar _ -> () | _ -> go scope f);
    List.iter (go scope) args
  and go scope (e : A.expr) : unit =
    match e with
    | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()
    | A.EDbg (Some inner, _) -> go scope inner
    | A.EApp (f, args, _) -> app scope f args
    | A.EPipe (l, r, sp) -> (
      (* Desugar rewrites pipes before the typechecker sees them; the LSP's
         analysis route can still reach this arm.  Treat it as the
         application it becomes so a pipe into a parameter is not lost. *)
      match r with
      | A.EVar _ -> app scope r [ l ]
      | A.EApp (g, args, _) -> app scope g (args @ [ l ])
      | _ ->
        ignore sp;
        go scope l;
        go scope r)
    | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) ->
      List.iter (go scope) args
    | A.ELam (ps, body, _) ->
      let scope =
        List.map (fun (p : A.param) -> (p.A.param_name.A.txt, COpaque)) ps @ scope
      in
      go scope body
    | A.EBlock (es, _) -> block scope es
    | A.ELet (b, _) -> go scope b.A.bind_expr
    | A.EMatch (scrut, branches, _) ->
      go scope scrut;
      List.iter
        (fun (br : A.branch) ->
           let scope =
             List.map (fun n -> (n, COpaque)) (pat_binders br.A.branch_pat) @ scope
           in
           Option.iter (go scope) br.A.branch_guard;
           go scope br.A.branch_body)
        branches
    | A.ERecord (fields, _) -> List.iter (fun (_, ex) -> go scope ex) fields
    | A.ERecordUpdate (base, fields, _) ->
      go scope base;
      List.iter (fun (_, ex) -> go scope ex) fields
    | A.EField (ex, _, _) -> go scope ex
    | A.EIf (c, t, f, _) ->
      go scope c;
      go scope t;
      go scope f
    | A.ECond (arms, _) ->
      List.iter
        (fun (ce, be) ->
           go scope ce;
           go scope be)
        arms
    | A.EAnnot (ex, _, _) | A.ESpawn (ex, _) | A.EAssert (ex, _)
    | A.ESigil (_, ex, _) ->
      go scope ex
    | A.ESend (a, b, _) ->
      go scope a;
      go scope b
    | A.ELetFn (name, ps, _, body, _) ->
      let inner =
        (name.A.txt, CCharged)
        :: List.map (fun (p : A.param) -> (p.A.param_name.A.txt, COpaque)) ps
        @ scope
      in
      go inner body
    | A.ELetQ (p, result, cont, _) ->
      go scope result;
      let scope = List.map (fun n -> (n, COpaque)) (pat_binders p) @ scope in
      go scope cont
  and block scope (es : A.expr list) : unit =
    match es with
    | [] -> ()
    | A.ELet (b, _) :: rest ->
      go scope b.A.bind_expr;
      let c = cls_of_rhs scope b.A.bind_expr in
      (* A destructuring binder gets the opaque classification: only a bare
         [PatVar] can be said to hold the RHS itself. *)
      let bound =
        match b.A.bind_pat with
        | A.PatVar n -> [ (n.A.txt, c) ]
        | p -> List.map (fun n -> (n, COpaque)) (pat_binders p)
      in
      block (bound @ scope) rest
    | e :: rest ->
      go scope e;
      block scope rest
  in
  let scope = List.map (fun p -> (p, CParams [ p ])) params in
  go scope body;
  {
    sd_params = params;
    sd_deps = List.sort_uniq compare !deps;
    sd_unknown = !unknown;
    sd_calls = !calls;
  }

let seed_of_bodies (bodies : (string list * A.expr) list) : seed =
  List.fold_left
    (fun acc (params, body) -> merge_seed acc (seed_of_body params body))
    empty_seed bodies

(* ── the fixpoint ──────────────────────────────────────────────────────── *)

type row = { caps : string list; deps : string list; unknown : bool }

let empty_row = { caps = []; deps = []; unknown = false }

let solve ?(with_rows = true) ~(own_caps : (string, string list) Hashtbl.t)
    ~(refs : (string, string list) Hashtbl.t)
    ~(seeds : (string, seed) Hashtbl.t) () : (string, row) Hashtbl.t =
  let caps : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  Hashtbl.iter (fun k v -> Hashtbl.replace caps k v) own_caps;
  let deps : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  let unknown : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  Hashtbl.iter
    (fun k (s : seed) ->
       if s.sd_deps <> [] then Hashtbl.replace deps k s.sd_deps;
       if s.sd_unknown then Hashtbl.replace unknown k ())
    seeds;
  (* Resolution is unchanged from the pre-stage-C closure: try the referring
     key's module prefix first (a bare reference from inside a nested module),
     then the raw name (an already-dotted reference, or an entry-level bare
     one).  Membership in [caps] is the "is a known function" test because
     every recording site writes a caps entry, even an empty one. *)
  let resolve (owner : string) (r : string) : string option =
    let qualified =
      match String.rindex_opt owner '.' with
      | Some i -> String.sub owner 0 i ^ "." ^ r
      | None -> r
    in
    if Hashtbl.mem caps qualified then Some qualified
    else if Hashtbl.mem caps r then Some r
    else None
  in
  let changed = ref true in
  let add_deps key ps =
    let prior = Option.value ~default:[] (Hashtbl.find_opt deps key) in
    let merged = List.sort_uniq compare (ps @ prior) in
    if merged <> List.sort_uniq compare prior then begin
      Hashtbl.replace deps key merged;
      changed := true
    end
  in
  while !changed do
    changed := false;
    Hashtbl.iter
      (fun fn_qname rs ->
         (* Capabilities: identical to the pre-stage-C fixpoint.  The
            [sort_uniq] before [normalize] is load-bearing — [normalize] does
            not drop exact duplicates, so without it the value never compares
            equal to the previous one and the loop spins forever. *)
         let own = Option.value ~default:[] (Hashtbl.find_opt caps fn_qname) in
         let from_refs =
           List.concat_map
             (fun r ->
                match resolve fn_qname r with
                | None -> []
                | Some key -> Option.value ~default:[] (Hashtbl.find_opt caps key))
             rs
         in
         let merged =
           Cap_lattice.normalize (List.sort_uniq compare (own @ from_refs))
         in
         if List.sort compare merged <> List.sort compare own then begin
           Hashtbl.replace caps fn_qname merged;
           changed := true
         end;
         (* An untraceable invocation anywhere in the reach poisons every
            caller: a discharge point that can reach the invoker cannot be
            certified under a narrow grant. *)
         if with_rows && not (Hashtbl.mem unknown fn_qname) then
           if
             List.exists
               (fun r ->
                  match resolve fn_qname r with
                  | Some key -> Hashtbl.mem unknown key
                  | None -> false)
               rs
           then begin
             Hashtbl.replace unknown fn_qname ();
             changed := true
           end)
      refs;
    (* Effect polymorphism: passing one's own parameter into a callee's dep
       position makes it this function's dep too. Skipped entirely when only
       [caps] will be read — see [with_rows] in the .mli. *)
    if with_rows then
    Hashtbl.iter
      (fun fn_qname (s : seed) ->
         List.iter
           (fun (callee, shapes) ->
              match resolve fn_qname callee with
              | None -> ()
              | Some key ->
                let callee_deps =
                  Option.value ~default:[] (Hashtbl.find_opt deps key)
                in
                if callee_deps <> [] then begin
                  let callee_params =
                    match Hashtbl.find_opt seeds key with
                    | Some cs -> cs.sd_params
                    | None -> []
                  in
                  List.iteri
                    (fun i sh ->
                       match List.nth_opt callee_params i with
                       | Some p when List.mem p callee_deps -> (
                         match sh with
                         | ASParams ps -> add_deps fn_qname ps
                         | ASName _ | ASInline | ASOpaque -> ())
                       | _ -> ())
                    shapes
                end)
           s.sd_calls)
      seeds
  done;
  let rows : (string, row) Hashtbl.t = Hashtbl.create 64 in
  Hashtbl.iter
    (fun k cs ->
       Hashtbl.replace rows k
         {
           caps = cs;
           deps = Option.value ~default:[] (Hashtbl.find_opt deps k);
           unknown = Hashtbl.mem unknown k;
         })
    caps;
  (* A function with seeds but no caps entry (no recording site wrote one)
     would otherwise vanish from the row table. *)
  Hashtbl.iter
    (fun k _ ->
       if not (Hashtbl.mem rows k) then
         Hashtbl.replace rows k
           {
             caps = [];
             deps = Option.value ~default:[] (Hashtbl.find_opt deps k);
             unknown = Hashtbl.mem unknown k;
           })
    seeds;
  rows
