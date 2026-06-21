(* Refinement checking (Phases A1b + A2, minimal vertical slice).

   A post-typecheck pass over the AST: it collects functions whose parameters
   carry an `{Int | predicate}` refinement, then walks every call site and, for
   each refined parameter, discharges a verification condition through the A0
   Z3 bridge (`March_refine`).

   A1b: Int/Bool predicates over the binder `_`, literal / refined-local args.
   A2 : the `len` measure and cross-argument predicates, so bounds such as
        `{Int | _ >= 0 && _ < len(xs)}` are checkable when the length is known
        (a list literal) or symbolically related.

   Soundness stance: an argument we cannot reflect (an unconstrained variable,
   a complex expression) is conservatively SKIPPED — no false positives.
   Scope: direct (named) calls only, no path sensitivity. *)

module A = March_ast.Ast
module Smt = March_refine.Smt
module Refine = March_refine.Refine
module Err = March_errors.Errors

(* A refined parameter: position, predicate binder, predicate expression. *)
type rparam = { idx : int; binder : string; pred : A.expr }

(* A function's signature: parameter names by position + its refined params. *)
type fn_sig = { param_names : string list; refined : rparam list }
type sigs = (string, fn_sig) Hashtbl.t

let binder_name : A.name option -> string = function
  | None -> "_"
  | Some n -> n.A.txt

let is_int_base : A.ty -> bool = function
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> true
  | _ -> false

(* Length of a list literal (a Cons/Nil ECon chain); None if not a literal. *)
let rec list_len (e : A.expr) : int option =
  match e with
  | A.ECon ({ A.txt = "Nil"; _ }, _, _) -> Some 0
  | A.ECon ({ A.txt = "Cons"; _ }, [ _; tl ], _) ->
    (match list_len tl with Some n -> Some (n + 1) | None -> None)
  | _ -> None

(* Registered measure names for this compilation: the builtin `len` plus any
   user function annotated `@[measure]`.  Set once per [check_module]. *)
let registered_measures : string list ref = ref []
let is_measure (m : string) : bool = m = "len" || List.mem m !registered_measures

(* Measures known to be non-negative (so `m(x) >= 0` is a sound axiom).  `len`
   always; a user measure when its body is syntactically non-negative. *)
let measure_nonneg : string list ref = ref []
let is_nonneg_measure (m : string) : bool = m = "len" || List.mem m !measure_nonneg

(* Conservative syntactic non-negativity of a measure body: every return path is
   a non-negative literal, a sum/product of non-negatives, or a call to a measure
   already known non-negative (incl. the measure itself, inductively). *)
let measure_body_nonneg (self : string) (known : string list) (body : A.expr) : bool =
  let rec go e =
    match e with
    | A.ELit (A.LitInt n, _) -> n >= 0
    | A.EApp (A.EVar { A.txt = ("+" | "*"); _ }, [ a; b ], _) -> go a && go b
    | A.EApp (A.EVar { A.txt = m; _ }, [ _ ], _)
      when m = self || m = "len" || List.mem m known -> true
    | A.EIf (_, t, e, _) -> go t && go e
    | A.ECond (arms, _) -> List.for_all (fun (_, b) -> go b) arms
    | A.EMatch (_, brs, _) -> List.for_all (fun (br : A.branch) -> go br.A.branch_body) brs
    | A.EBlock (es, _) -> (match List.rev es with last :: _ -> go last | [] -> false)
    | _ -> false (* variables, subtraction, arbitrary calls: unknown sign *)
  in
  go body

(* ── Measure axioms (M-a): datatype model + recursion-equation preamble ───── *)
(* ctor name -> field sorts as the measure sees them (recursive self -> SData adt,
   type params / other ADTs -> opaque "Elem", Int/Bool concrete). *)
let ctor_field_sorts : (string, Smt.sort list) Hashtbl.t = Hashtbl.create 32
let adt_ctors : (string, string list) Hashtbl.t = Hashtbl.create 16
(* measures we soundly axiomatize: name -> its argument ADT name. *)
let axiom_measures : (string, string) Hashtbl.t = Hashtbl.create 16
let is_axiom_measure m = Hashtbl.mem axiom_measures m
let measure_preamble : string ref = ref ""

let smt_sort_of_field (self : string) (t : A.ty) : Smt.sort =
  match t with
  | A.TyCon ({ A.txt = "Int"; _ }, []) -> Smt.SInt
  | A.TyCon ({ A.txt = "Bool"; _ }, []) -> Smt.SBool
  | A.TyCon ({ A.txt; _ }, _) when txt = self -> Smt.SData self
  | _ -> Smt.SData "Elem"

let rec register_adts (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DType (_, name, _, A.TDVariant variants, _)
      | A.DAlwaysLinearType (_, name, _, A.TDVariant variants, _) ->
        Hashtbl.replace adt_ctors name.A.txt
          (List.map (fun (v : A.variant) -> v.A.var_name.A.txt) variants);
        List.iter
          (fun (v : A.variant) ->
            Hashtbl.replace ctor_field_sorts v.A.var_name.A.txt
              (List.map (smt_sort_of_field name.A.txt) v.A.var_args))
          variants
      | A.DMod (_, _, ds, _) -> register_adts ds
      | _ -> ())
    decls

(* The single matched argument's name + its ADT, if the measure's first param is
   a registered ADT. *)
let measure_param_adt (fd : A.fn_def) : (string * string) option =
  match fd.A.fn_clauses with
  | { A.fc_params = A.FPNamed p :: _; _ } :: _ -> (
      match p.A.param_ty with
      | Some (A.TyCon (adt, _)) when Hashtbl.mem adt_ctors adt.A.txt ->
        Some (p.A.param_name.A.txt, adt.A.txt)
      | _ -> None)
  | _ -> None

let rec unblock = function
  | A.EBlock (es, sp) -> (match List.rev es with last :: _ -> unblock last | [] -> A.EBlock (es, sp))
  | e -> e

(* Extract `match param do Ctor(vars) -> body … end` arms (None if not that shape). *)
let measure_arms (param : string) (body : A.expr) : (string * string list * A.expr) list option =
  match unblock body with
  | A.EMatch (A.EVar { A.txt; _ }, branches, _) when txt = param -> (
      try
        Some
          (List.map
             (fun (br : A.branch) ->
               match br.A.branch_pat with
               | A.PatCon (ctor, pats) ->
                 let vars =
                   List.map (function A.PatVar n -> n.A.txt | _ -> raise Exit) pats
                 in
                 (ctor.A.txt, vars, br.A.branch_body)
               | _ -> raise Exit)
             branches)
      with Exit -> None)
  | _ -> None

(* Translate a measure arm body to SMT (function-app encoding): patvars -> Const,
   recursive measure calls m(v) -> (m v) where v MUST be a bound patvar
   (structural recursion — the soundness gate).  None => untranslatable. *)
let rec smt_of_axiom_body (bound : string list) (e : A.expr) : Smt.term option =
  let r = smt_of_axiom_body bound in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.EVar { A.txt; _ } when List.mem txt bound -> Some (Smt.Const txt)
  | A.EApp (A.EVar { A.txt = m; _ }, [ A.EVar { A.txt = v; _ } ], _)
    when is_measure m && List.mem v bound ->
    Some (Smt.App (m, [ Smt.Const v ]))
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) ->
    (match r a, r b with Some x, Some y -> Some (Smt.Add (x, y)) | _ -> None)
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) ->
    (match r a, r b with Some x, Some y -> Some (Smt.Sub (x, y)) | _ -> None)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ A.ELit (A.LitInt k, _); b ], _) ->
    Option.map (fun y -> Smt.MulLit (k, y)) (r b)
  | _ -> None

let datatype_decl (adt : string) : string =
  let ctors = try Hashtbl.find adt_ctors adt with Not_found -> [] in
  let ctor_decl c =
    let sorts = try Hashtbl.find ctor_field_sorts c with Not_found -> [] in
    if sorts = [] then Printf.sprintf "(%s)" c
    else
      Printf.sprintf "(%s %s)" c
        (String.concat " "
           (List.mapi
              (fun i s -> Printf.sprintf "(%s_%d %s)" c i (Smt.string_of_sort s))
              sorts))
  in
  Printf.sprintf "(declare-datatypes ((%s 0)) ((%s)))" adt
    (String.concat " " (List.map ctor_decl ctors))

(* Build the global measure-axiom preamble; populates [axiom_measures]. *)
let build_measure_preamble (mdefs : (string * A.fn_def) list) : unit =
  Hashtbl.reset axiom_measures;
  let buf = Buffer.create 256 in
  let used_adts = Hashtbl.create 8 in
  List.iter
    (fun (name, fd) ->
      match measure_param_adt fd, fd.A.fn_clauses with
      | None, _ | _, [] -> ()
      | Some (param, adt), c :: _ -> (
          match measure_arms param c.A.fc_body with
          | None -> ()
          | Some arms ->
            (* Totality gate: the match must cover every constructor of the ADT. *)
            let covered = List.sort compare (List.map (fun (c, _, _) -> c) arms) in
            let all = List.sort compare (try Hashtbl.find adt_ctors adt with Not_found -> []) in
            (* Translate every arm; structural recursion is enforced in smt_of_axiom_body. *)
            let axioms =
              List.map
                (fun (ctor, vars, body) ->
                  match smt_of_axiom_body vars body with
                  | None -> None
                  | Some bsmt ->
                    let sorts = try Hashtbl.find ctor_field_sorts ctor with Not_found -> [] in
                    if List.length vars <> List.length sorts then None
                    else
                      let lhs =
                        if vars = [] then Printf.sprintf "(%s %s)" name ctor
                        else Printf.sprintf "(%s (%s %s))" name ctor (String.concat " " vars)
                      in
                      if vars = [] then Some (Printf.sprintf "(assert (= %s %s))" lhs (Smt.render bsmt))
                      else
                        let bound =
                          List.map2 (fun v s -> Printf.sprintf "(%s %s)" v (Smt.string_of_sort s)) vars sorts
                        in
                        Some
                          (Printf.sprintf
                             "(assert (forall (%s) (! (= %s %s) :pattern (%s))))"
                             (String.concat " " bound) lhs (Smt.render bsmt) lhs))
                arms
            in
            if covered = all && all <> [] && not (List.exists (( = ) None) axioms) then begin
              Hashtbl.replace axiom_measures name adt;
              Hashtbl.replace used_adts adt ();
              Buffer.add_string buf (Printf.sprintf "(declare-fun %s (%s) Int)\n" name adt);
              if is_nonneg_measure name then
                Buffer.add_string buf
                  (Printf.sprintf
                     "(assert (forall ((x %s)) (! (>= (%s x) 0) :pattern ((%s x)))))\n"
                     adt name name);
              List.iter (function Some s -> Buffer.add_string buf (s ^ "\n") | None -> ()) axioms
            end))
    mdefs;
  if Hashtbl.length axiom_measures > 0 then begin
    let dts =
      Hashtbl.fold (fun adt () acc -> datatype_decl adt :: acc) used_adts []
      |> String.concat "\n"
    in
    measure_preamble := "(declare-sort Elem 0)\n" ^ dts ^ "\n" ^ Buffer.contents buf
  end
  else measure_preamble := ""

(* ── Translate the decidable predicate fragment to an SMT term ────────────── *)
(* [resolve_var] maps a scalar variable to its SMT term; [resolve_measure]
   maps a (measure-name, argument-name) to its measure term.  None => outside
   the supported Int/Bool linear fragment. *)
let rec smt_of ~resolve_var ~resolve_measure (e : A.expr) : Smt.term option =
  let r = smt_of ~resolve_var ~resolve_measure in
  let b2 f a b = match r a, r b with Some x, Some y -> Some (f x y) | _ -> None in
  match e with
  | A.ELit (A.LitInt n, _) -> Some (Smt.IntLit n)
  | A.ELit (A.LitBool b, _) -> Some (Smt.BoolLit b)
  (* A measure application m(e): m(var) reflects to a consistent measure symbol;
     len(list-literal) is computed concretely. *)
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _) when is_measure m ->
    (match a with
     | A.EVar { A.txt = x; _ } -> resolve_measure m x
     | _ -> if m = "len" then (match list_len a with Some n -> Some (Smt.IntLit n) | None -> None) else None)
  | A.EVar { A.txt; _ } -> resolve_var txt
  | A.EApp (A.EVar { A.txt = "&&"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.And (x, y)) a b
  | A.EApp (A.EVar { A.txt = "||"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Or (x, y)) a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> Option.map (fun x -> Smt.Not x) (r a)
  | A.EApp (A.EVar { A.txt = ">="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ge (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Le (x, y)) a b
  | A.EApp (A.EVar { A.txt = ">"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Gt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "<"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Lt (x, y)) a b
  | A.EApp (A.EVar { A.txt = "=="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Eq (x, y)) a b
  | A.EApp (A.EVar { A.txt = "!="; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Ne (x, y)) a b
  | A.EApp (A.EVar { A.txt = "+"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Add (x, y)) a b
  | A.EApp (A.EVar { A.txt = "-"; _ }, [ a; b ], _) -> b2 (fun x y -> Smt.Sub (x, y)) a b
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> Option.map (fun x -> Smt.Neg x) (r a)
  | A.EApp (A.EVar { A.txt = "*"; _ }, [ a; b ], _) ->
    (match a, b with
     | A.ELit (A.LitInt k, _), _ -> Option.map (fun y -> Smt.MulLit (k, y)) (r b)
     | _, A.ELit (A.LitInt k, _) -> Option.map (fun x -> Smt.MulLit (k, x)) (r a)
     | _ -> None)
  | _ -> None

(* User-facing infix rendering of a predicate (best-effort). *)
let rec pred_str (e : A.expr) : string =
  let binop op a b = pred_str a ^ " " ^ op ^ " " ^ pred_str b in
  match e with
  | A.ELit (A.LitInt n, _) -> string_of_int n
  | A.ELit (A.LitBool b, _) -> if b then "true" else "false"
  | A.EApp (A.EVar { A.txt = m; _ }, [ a ], _) when is_measure m -> m ^ "(" ^ pred_str a ^ ")"
  | A.EVar { A.txt; _ } -> txt
  | A.EApp (A.EVar { A.txt = ("&&" | "||" | ">=" | "<=" | ">" | "<" | "==" | "!=" | "+" | "-" | "*") as op; _ }, [ a; b ], _) ->
    binop op a b
  | A.EApp (A.EVar { A.txt = "not"; _ }, [ a ], _) -> "!" ^ pred_str a
  | A.EApp (A.EVar { A.txt = "negate"; _ }, [ a ], _) -> "-" ^ pred_str a
  | _ -> "<predicate>"

(* Render an SMT counterexample model for humans: a measure symbol `m$x` is
   shown as `m(x)`.  Empty model => "". *)
let format_cx (model : (string * string) list) : string =
  if model = [] then ""
  else
    let entry (k, v) =
      match String.index_opt k '$' with
      | Some i ->
        Printf.sprintf "%s(%s) = %s"
          (String.sub k 0 i) (String.sub k (i + 1) (String.length k - i - 1)) v
      | None -> Printf.sprintf "%s = %s" k v
    in
    " (counterexample: " ^ String.concat ", " (List.map entry model) ^ ")"

let model_of = function Refine.Refuted m -> m | _ -> []

(* ── Scope of refined locals/params: name -> (binder, predicate) ─────────── *)
type scope = (string * (string * A.expr)) list

let refined_int_ty : A.ty option -> (string * A.expr) option = function
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred)
  | _ -> None

let scope_add_param (sc : scope) (p : A.param) : scope =
  match refined_int_ty p.A.param_ty with
  | Some r -> (p.A.param_name.A.txt, r) :: sc
  | None -> sc

let scope_add_fnparam (sc : scope) : A.fn_param -> scope = function
  | A.FPNamed p | A.FPDefault (p, _) -> scope_add_param sc p
  | A.FPPat _ -> sc

let scope_add_binding (sc : scope) (b : A.binding) : scope =
  match b.A.bind_pat, refined_int_ty b.A.bind_ty with
  | A.PatVar n, Some r -> (n.A.txt, r) :: sc
  | _ -> sc

(* ── Collect signatures, keyed by bare + qualified name ──────────────────── *)
let param_name_of : A.fn_param -> string = function
  | A.FPNamed p | A.FPDefault (p, _) -> p.A.param_name.A.txt
  | A.FPPat _ -> "_"

let sig_of_clause (c : A.fn_clause) : fn_sig =
  let param_names = List.map param_name_of c.A.fc_params in
  let refined =
    List.mapi (fun idx fp -> (idx, fp)) c.A.fc_params
    |> List.filter_map (fun (idx, fp) ->
           match fp with
           | A.FPNamed p | A.FPDefault (p, _) ->
             (match refined_int_ty p.A.param_ty with
              | Some (binder, pred) -> Some { idx; binder; pred }
              | None -> None)
           | A.FPPat _ -> None)
  in
  { param_names; refined }

(* Gather every refined function as (bare_name, qualified_name option, sig). *)
let collect_sig_list (decls : A.decl list) : (string * string option * fn_sig) list =
  let acc = ref [] in
  let rec go prefix decls =
    List.iter
      (function
        | A.DFn (fd, _) ->
          let sg =
            match fd.A.fn_clauses with
            | c :: _ -> sig_of_clause c
            | [] -> { param_names = []; refined = [] }
          in
          if sg.refined <> [] then
            let q = if prefix = "" then None else Some (prefix ^ "." ^ fd.A.fn_name.A.txt) in
            acc := (fd.A.fn_name.A.txt, q, sg) :: !acc
        | A.DMod (name, _, ds, _) ->
          go (if prefix = "" then name.A.txt else prefix ^ "." ^ name.A.txt) ds
        | _ -> ())
      decls
  in
  go "" decls;
  !acc

(* Build the lookup table.  Qualified names are always registered (unique).  A
   bare name is registered ONLY when a single definition uses it — colliding
   bare names across modules are dropped, so an ambiguous bare call is
   conservatively skipped rather than checked against the wrong predicate. *)
let build_table (lst : (string * string option * fn_sig) list) : sigs =
  let tbl : sigs = Hashtbl.create 64 in
  List.iter (fun (_, q, sg) -> match q with Some qn -> Hashtbl.replace tbl qn sg | None -> ()) lst;
  let counts = Hashtbl.create 64 in
  List.iter
    (fun (b, _, _) ->
      Hashtbl.replace counts b (1 + (try Hashtbl.find counts b with Not_found -> 0)))
    lst;
  List.iter (fun (b, _, sg) -> if Hashtbl.find counts b = 1 then Hashtbl.replace tbl b sg) lst;
  tbl

(* ── Reflect a scalar actual argument into (term, decls, assumptions) ─────── *)
let reflect_scalar (sc : scope) (actual : A.expr)
  : (Smt.term * (string * Smt.sort) list * Smt.term list) option =
  match actual with
  | A.EVar { A.txt = x; _ } ->
    let xc = Smt.Const x in
    (match List.assoc_opt x sc with
     | Some (b, q) ->
       (* A refined local: carry its own refinement as an assumption. *)
       let rv n = if n = b || n = "_" then Some xc else None in
       let assumptions =
         match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
         | Some qa -> [ qa ]
         | None -> []
       in
       Some (xc, [ (x, Smt.SInt) ], assumptions)
     | None ->
       (* An ordinary variable: reflect it as a constant so a path-context
          guard about it can constrain it.  Without a guard it stays
          unconstrained and the definite-failure check keeps us silent. *)
       Some (xc, [ (x, Smt.SInt) ], []))
  | _ ->
    (match smt_of ~resolve_var:(fun _ -> None) ~resolve_measure:(fun _ _ -> None) actual with
     | Some t -> Some (t, [], [])
     | None -> None)

(* ── Check one refined parameter at a call site ──────────────────────────── *)
(* [path] is the path context: conditions known true here, each tagged with
   whether it is negated (the else-branch of an `if`). *)
let check_call ~root errctx ~span (sg : fn_sig) (args : A.expr list)
    (path : (A.expr * bool) list) (rp : rparam) (sc : scope) : unit =
  let name_pos = List.mapi (fun i n -> (n, i)) sg.param_names in
  let actual_of_name name =
    match List.assoc_opt name name_pos with
    | Some i -> List.nth_opt args i
    | None -> None
  in
  match List.nth_opt args rp.idx with
  | None -> ()
  | Some self_actual ->
    let decls = ref [] and assume = ref [] in
    let absorb = function
      | Some (t, d, a) -> decls := d @ !decls; assume := a @ !assume; Some t
      | None -> None
    in
    (* Resolve a scalar variable.  A predicate references callee parameters;
       a path condition references caller variables — both go through the
       actual caller values so the names line up in SMT. *)
    let resolve_var name =
      if name = rp.binder || name = "_" then absorb (reflect_scalar sc self_actual)
      else
        match actual_of_name name with
        | Some a -> absorb (reflect_scalar sc a)
        | None ->
          (* a caller-scope variable from the path context *)
          decls := (name, Smt.SInt) :: !decls;
          Some (Smt.Const name)
    in
    let measure_of_var m x =
      let c = Smt.Const (m ^ "$" ^ x) in
      decls := (m ^ "$" ^ x, Smt.SInt) :: !decls;
      (* `len` is known non-negative; user measures get no axiom in v1 (sound;
         guarded uses still discharge via the path context). *)
      if is_nonneg_measure m then assume := Smt.Ge (c, Smt.IntLit 0) :: !assume;
      Some c
    in
    (* Reflect a value into the SMT datatype term an axiomatised measure ranges
       over: a constructor application becomes (ctor …) (so the recursion axioms
       fire); a variable becomes a fresh datatype constant. *)
    let dt_counter = ref 0 in
    let rec reflect_dt adt e =
      match e with
      | A.ECon (ctor, args, _)
        when (match Hashtbl.find_opt adt_ctors adt with Some cs -> List.mem ctor.A.txt cs | None -> false) ->
        let sorts = try Hashtbl.find ctor_field_sorts ctor.A.txt with Not_found -> [] in
        if List.length args <> List.length sorts then None
        else
          List.fold_right2
            (fun a s acc ->
              match reflect_field a s, acc with Some t, Some ts -> Some (t :: ts) | _ -> None)
            args sorts (Some [])
          |> Option.map (fun ts -> Smt.App (ctor.A.txt, ts))
      | A.EVar { A.txt = x; _ } -> decls := (x, Smt.SData adt) :: !decls; Some (Smt.Const x)
      | _ -> None
    and reflect_field a = function
      | Smt.SData sub when sub <> "Elem" -> reflect_dt sub a
      | sort ->
        (* element / Int field: irrelevant to a structural measure -> fresh const *)
        incr dt_counter;
        let nm = Printf.sprintf "_e%d" !dt_counter in
        decls := (nm, sort) :: !decls;
        Some (Smt.Const nm)
    in
    let resolve_measure m name =
      if is_axiom_measure m then (
        let adt = Hashtbl.find axiom_measures m in
        match actual_of_name name with
        | None ->
          decls := (name, Smt.SData adt) :: !decls;
          Some (Smt.App (m, [ Smt.Const name ]))
        | Some a -> Option.map (fun t -> Smt.App (m, [ t ])) (reflect_dt adt a))
      else
        match actual_of_name name with
        | Some a -> (
            match (if m = "len" then list_len a else None) with
            | Some n -> Some (Smt.IntLit n)
            | None -> (match a with A.EVar { A.txt = x; _ } -> measure_of_var m x | _ -> None))
        | None -> measure_of_var m name (* a caller-scope variable *)
    in
    (* Translate the path conditions into assumptions (dropping any that fall
       outside the supported fragment — sound, just weaker). *)
    List.iter
      (fun (cond, negated) ->
        match smt_of ~resolve_var ~resolve_measure cond with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of ~resolve_var ~resolve_measure rp.pred with
     | None -> ()
     | Some goal ->
       (* de-duplicate decls (a symbol may be requested twice) *)
       let decls =
         List.fold_left
           (fun acc d -> if List.mem d acc then acc else d :: acc)
           [] !decls
       in
       let vc = { Smt.decls; assumptions = !assume; goal } in
       (* Report a violation ONLY when the precondition can *never* hold under
          the assumptions (a definite failure).  If it merely *might* fail
          (e.g. a symbolic, unknown length), that is unprovable either way and
          we stay silent — no false positives.

          - discharge(goal=G) Verified  => G always holds        => pass
          - else discharge(goal=¬G) Verified => G never holds     => violation
          - otherwise (G depends on unknowns / solver unsure)     => skip *)
       (match Refine.discharge ~root ~preamble:!measure_preamble vc with
        | Refine.Verified -> ()
        | first ->
          (match Refine.discharge ~root ~preamble:!measure_preamble { vc with Smt.goal = Smt.Not goal } with
           | Refine.Verified ->
             Err.error errctx ~span
               (Printf.sprintf
                  "refinement violation: argument does not satisfy precondition `%s`%s\n\
                   note: guard the call (e.g. `if %s do …`) or pass a value known to satisfy it"
                  (pred_str rp.pred) (format_cx (model_of first)) (pred_str rp.pred))
           | _ -> ())))

(* ── Postconditions: a function's return value must satisfy its return
   refinement.  We check each *tail* expression (a return position) under the
   path/scope reaching it, with the same definite-failure soundness stance. ── *)

let return_refine (fd : A.fn_def) : (string * A.expr) option =
  match fd.A.fn_ret_ty with
  | Some (A.TyRefine (base, binder, pred)) when is_int_base base ->
    Some (binder_name binder, pred)
  | _ -> None

(* Return-position expressions of a body, each with the path reaching it. *)
let rec tails (path : (A.expr * bool) list) (e : A.expr) : ((A.expr * bool) list * A.expr) list =
  match e with
  | A.EBlock (es, _) -> (match List.rev es with last :: _ -> tails path last | [] -> [ (path, e) ])
  | A.EIf (c, t, el, _) -> tails ((c, false) :: path) t @ tails ((c, true) :: path) el
  | A.ECond (arms, _) -> List.concat_map (fun (c, b) -> tails ((c, false) :: path) b) arms
  | A.EMatch (_, branches, _) ->
    List.concat_map
      (fun (br : A.branch) ->
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        tails p br.A.branch_body)
      branches
  | _ -> [ (path, e) ]

(* Facts true throughout the body: each refined param contributes its predicate. *)
let scope_facts (sc : scope) : (string * Smt.sort) list * Smt.term list =
  List.fold_left
    (fun (ds, asm) (name, (b, q)) ->
      let c = Smt.Const name in
      let rv n = if n = b || n = "_" then Some c else Some (Smt.Const n) in
      let ds = (name, Smt.SInt) :: ds in
      match smt_of ~resolve_var:rv ~resolve_measure:(fun _ _ -> None) q with
      | Some qa -> (ds, qa :: asm)
      | None -> (ds, asm))
    ([], []) sc

let check_post ~root errctx ~span (sc : scope) (binder : string) (ret_pred : A.expr)
    ((path, tail_e) : (A.expr * bool) list * A.expr) : unit =
  let base_decls, base_assume = scope_facts sc in
  let decls = ref base_decls and assume = ref base_assume in
  let var_const name = decls := (name, Smt.SInt) :: !decls; Some (Smt.Const name) in
  let resolve_measure m name =
    let c = Smt.Const (m ^ "$" ^ name) in
    decls := (m ^ "$" ^ name, Smt.SInt) :: !decls;
    if is_nonneg_measure m then assume := Smt.Ge (c, Smt.IntLit 0) :: !assume;
    Some c
  in
  (* The returned value, reflected (variables become their constants). *)
  match smt_of ~resolve_var:var_const ~resolve_measure tail_e with
  | None -> ()
  | Some tail_term ->
    let resolve_var name = if name = binder || name = "_" then Some tail_term else var_const name in
    List.iter
      (fun (cond, negated) ->
        match smt_of ~resolve_var ~resolve_measure cond with
        | Some t -> assume := (if negated then Smt.Not t else t) :: !assume
        | None -> ())
      path;
    (match smt_of ~resolve_var ~resolve_measure ret_pred with
     | None -> ()
     | Some goal ->
       let decls =
         List.fold_left (fun acc d -> if List.mem d acc then acc else d :: acc) [] !decls
       in
       let vc = { Smt.decls; assumptions = !assume; goal } in
       (match Refine.discharge ~root ~preamble:!measure_preamble vc with
        | Refine.Verified -> ()
        | first -> (
            match Refine.discharge ~root ~preamble:!measure_preamble { vc with Smt.goal = Smt.Not goal } with
            | Refine.Verified ->
              ignore tail_e;
              Err.error errctx ~span
                (Printf.sprintf
                   "refinement violation: return value cannot satisfy postcondition `%s`%s\n\
                    note: every return path of this function must satisfy `%s`"
                   (pred_str ret_pred) (format_cx (model_of first)) (pred_str ret_pred))
            | _ -> ())))

let check_fn_post ~root errctx (fd : A.fn_def) : unit =
  match return_refine fd with
  | None -> ()
  | Some (binder, ret_pred) ->
    List.iter
      (fun (c : A.fn_clause) ->
        let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
        let base = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
        List.iter
          (check_post ~root errctx ~span:c.A.fc_span sc binder ret_pred)
          (tails base c.A.fc_body))
      fd.A.fn_clauses

(* ── Walk expressions, threading the refined-local scope and path context ── *)
let rec visit ~root errctx (tbl : sigs) (path : (A.expr * bool) list) (sc : scope)
    (e : A.expr) : unit =
  let go = visit ~root errctx tbl path sc in
  let go_path p = visit ~root errctx tbl p sc in
  match e with
  | A.EApp (A.EVar { A.txt = fname; _ }, args, sp) ->
    (match Hashtbl.find_opt tbl fname with
     | Some sg ->
       List.iter (fun rp -> check_call ~root errctx ~span:sp sg args path rp sc) sg.refined
     | None -> ());
    List.iter go args
  | A.EApp (f, args, _) -> go f; List.iter go args
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> List.iter go args
  | A.EBlock (es, _) ->
    (* Thread BOTH the path context and the refined-local scope left-to-right:
       a `let` extends the scope; an `assert(p)` (used as an `assume`) extends
       the path so a later call can rely on p. *)
    ignore
      (List.fold_left
         (fun (path, sc) e ->
           visit ~root errctx tbl path sc e;
           let path' =
             match e with A.EAssert (p, _) -> (p, false) :: path | _ -> path
           in
           let sc' = match e with A.ELet (b, _) -> scope_add_binding sc b | _ -> sc in
           (path', sc'))
         (path, sc) es)
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.ELam (ps, body, _) ->
    visit ~root errctx tbl path (List.fold_left scope_add_param sc ps) body
  | A.ELetFn (_, ps, _, body, _) ->
    visit ~root errctx tbl path (List.fold_left scope_add_param sc ps) body
  | A.EMatch (subj, branches, _) ->
    go subj;
    List.iter
      (fun (br : A.branch) ->
        let p = match br.A.branch_guard with Some g -> (g, false) :: path | None -> path in
        go_path p br.A.branch_body)
      branches
  | A.EIf (c, t, e, _) ->
    go c;
    go_path ((c, false) :: path) t;
    go_path ((c, true) :: path) e
  | A.ECond (arms, _) ->
    List.iter (fun (c, b) -> go c; go_path ((c, false) :: path) b) arms
  | A.ERecord (fields, _) -> List.iter (fun (_, v) -> go v) fields
  | A.ERecordUpdate (r, fields, _) -> go r; List.iter (fun (_, v) -> go v) fields
  | A.EField (r, _, _) -> go r
  | A.EPipe (a, b, _) -> go a; go b
  | A.EAnnot (e, _, _) | A.ESpawn (e, _) | A.EAssert (e, _) | A.ESigil (_, e, _) -> go e
  | A.ESend (a, b, _) -> go a; go b
  | A.ELetQ (_, e1, e2, _) -> go e1; go e2
  | A.EDbg (Some e, _) -> go e
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()

let visit_fn ~root errctx (tbl : sigs) (fd : A.fn_def) : unit =
  check_fn_post ~root errctx fd;
  List.iter
    (fun (c : A.fn_clause) ->
      let sc = List.fold_left scope_add_fnparam [] c.A.fc_params in
      let path = match c.A.fc_guard with Some g -> [ (g, false) ] | None -> [] in
      visit ~root errctx tbl path sc c.A.fc_body)
    fd.A.fn_clauses

let rec visit_decls ~root errctx (tbl : sigs) (decls : A.decl list) : unit =
  List.iter
    (function
      | A.DFn (fd, _) -> visit_fn ~root errctx tbl fd
      | A.DMod (_, _, ds, _) -> visit_decls ~root errctx tbl ds
      | _ -> ())
    decls

(** Entry point: check refinement preconditions across [m], emitting
    diagnostics into [errctx].  [root] is the project root for the VC cache. *)
(* Functions annotated `@[measure]` as (bare name, fn_def). *)
let rec collect_measure_fns (decls : A.decl list) : (string * A.fn_def) list =
  List.concat_map
    (function
      | A.DFn (fd, _) when List.mem "measure" fd.A.fn_attrs -> [ (fd.A.fn_name.A.txt, fd) ]
      | A.DMod (_, _, ds, _) -> collect_measure_fns ds
      | _ -> [])
    decls

let check_module ?(root = Sys.getcwd ()) (errctx : Err.ctx) (m : A.module_) : unit =
  let mfns = collect_measure_fns m.A.mod_decls in
  registered_measures := List.map fst mfns;
  (* Determine which measures are non-negative (single pass; a measure depending
     only on already-classified ones, itself, and `len` is classified). *)
  measure_nonneg :=
    List.fold_left
      (fun known (name, fd) ->
        match fd.A.fn_clauses with
        | c :: _ when measure_body_nonneg name known c.A.fc_body -> name :: known
        | _ -> known)
      [] mfns;
  Hashtbl.reset adt_ctors;
  Hashtbl.reset ctor_field_sorts;
  register_adts m.A.mod_decls;
  build_measure_preamble mfns;
  let tbl = build_table (collect_sig_list m.A.mod_decls) in
  (* Always walk: a function may have a refined *return* (postcondition) even
     with no refined parameters, so it won't appear in [tbl]. *)
  visit_decls ~root errctx tbl m.A.mod_decls
