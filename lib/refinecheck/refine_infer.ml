(* The module-wide inference fixpoint (`--refine-infer`)
   (specs/2026-10-20-refinement-suggest-lite-design.md §3).

   The caller has run [Refine_check.check_module] (registration globals).
   Rounds repeat until one accepts nothing (cap [rounds]):
     F-phase — facts: return slots (K2, K4, K5-return) and abstract (K6), in
               callees-first order; a return that is USEFUL but not TRUE tries
               a demand chain through its tail callee (depth ≤ 3);
     D-phase — demands: parameter slots (K1, K3, K5-param), callees first;
     A-phase — accumulators (K7).
   Facts go first: a return discharges caller debt and burdens no one, a
   precondition only moves debt up.  Every accepted proposal is installed (in
   the decl tree and in the checker's definition tables) so later probes see
   it; the tables are restored when the run ends.  The real checker is the
   only oracle ([Infer_oracle]). *)

module A = March_ast.Ast
module PI = Precond_infer
module IS = Infer_slot
module IV = Infer_vocab
module IO = Infer_oracle
module LD = Ledger_diff
module RC = Refine_check
module Ob = Obligation

type proposal = {
  id : string;
  round : int;
  slot : IS.slot;
  pred : string;
  annotation : string;
  source : IV.source;
  depends_on : string list;
  closes : LD.key list;
  new_skipped : LD.key list;
  external_callers : bool;
}

(** A metric inferred for one function of an uncertified recursive SCC
    (termination phase 5, §3.5): `@[decreases(d_metric)]`, checked through
    every phase-2 obligation of the SCC, then confirmed by a real re-check
    with every applied one written. *)
type dproposal = {
  d_fn : string;  (** the unit's display name ([Inner.f], [f/go]) *)
  d_span : A.span;  (** its declaring name *)
  d_metric : string list;  (** the components, as March source *)
  d_exprs : A.expr list;  (** the same, as written into the tree for the re-check *)
  d_class : string;  (** §0.5 class of the unit, without the [?] *)
  d_checked : int;  (** candidates checked, this one included *)
  d_total : int;  (** candidates generated (at most 8 are checked) *)
  d_scc : string list;  (** the other members, each with its own proposal *)
  d_apply : string option;
      (** [None]: written by [--refine-infer-apply]; else why not: [local] (a
          local `fn` takes no attribute), [written] (it would replace a
          `@[decreases]` the user wrote), [apply-by-hand] (no textual edit).
          A proposal the re-check with it written did not certify is dropped
          (its SCC is listed in [decreases_none]). *)
}

(** An uncertified SCC member for which no candidate proved. *)
type dnone = { n_fn : string; n_span : A.span; n_class : string; n_checked : int; n_total : int }

(** A lemma call inferred for one skipped obligation: the statement [lp_call]
    inserted before the statement at [lp_stmt], checked to prove the
    obligation, then confirmed with every other applied one. *)
type lproposal = {
  lp_fn : string;  (** the enclosing function, qualified *)
  lp_target : Ob.t;  (** the obligation it closes *)
  lp_lemma : string;  (** the lemma, as called *)
  lp_call : string;  (** the statement, as March source *)
  lp_stmt : A.span;  (** the statement it goes before *)
  lp_expr : A.expr;  (** the same call, as written into the tree *)
  lp_checked : int;  (** candidates checked, this one included *)
  lp_total : int;  (** candidates found *)
  lp_apply : string option;
      (** [None]: written by [--refine-infer-apply]; else why not
          ([apply-by-hand]: the statement does not start its own line). *)
}

(** A skipped obligation for which no candidate proved, with the lemma whose
    statement would close it when one was found: checked by assuming that
    statement (an [assert] before the statement) and re-checking.  It is
    never written by [--refine-infer-apply]: the lemma is not proved. *)
type lnone = {
  ln_fn : string;
  ln_target : Ob.t;
  ln_checked : int;
  ln_total : int;
  ln_skeleton : (string * string) option;  (** the lemma's text, and its call *)
}

type result = {
  decreases : dproposal list;
  decreases_none : dnone list;
  proposals : proposal list;
  rejected : (IS.slot * string * string * string) list;   (* slot, pred, reason, detail *)
  refused : (IS.slot * string * PI.refusal) list;          (* slot, pred, refusal *)
  notes : (string * string) list;                          (* fn, note *)
  before : LD.snapshot;
  after : LD.snapshot;
  after_counts : int * int;
    (* Raw user-code (skipped, violated) obligation counts of the final
       hypothesis tree — what `--check --refine-report` will print once the
       proposals are applied (the snapshot dedupes sites; the report does not). *)
  lemma_calls : lproposal list;
  lemma_none : lnone list;
  probes : int;
  rounds : int;
}

let all_kinds = IS.[ K1; K2; K3; K4; K5; K6; K7 ]
let default_budget = 3000
let default_rounds = 10
let chain_depth = 3

(* ── The decl tree ───────────────────────────────────────────────────────── *)

let rec replace_fn (prefix : string list) (q : string) (fd' : A.fn_def) (decls : A.decl list) : A.decl list =
  List.map
    (function
      | A.DFn (f, sp) when String.concat "." (prefix @ [ f.A.fn_name.A.txt ]) = q -> A.DFn (fd', sp)
      | A.DMod (n, vis, inner, sp) -> A.DMod (n, vis, replace_fn (prefix @ [ n.A.txt ]) q fd' inner, sp)
      | d -> d)
    decls

let find_fd (decls : A.decl list) (q : string) : A.fn_def option =
  List.find_map
    (fun ((_, fd) as pf) -> if PI.qualified_of pf = q then Some fd else None)
    (PI.enum_fns [] decls)

(* Strongly connected components of the user call graph, callees first
   (Tarjan emits them in reverse topological order). *)
let sccs ?(defined : (string, unit) Hashtbl.t option) (fns : (string * A.fn_def) list) : string list list =
  let defined =
    match defined with
    | Some d -> d
    | None -> let t = Hashtbl.create 16 in List.iter (fun (q, _) -> Hashtbl.replace t q ()) fns; t
  in
  let path_of q = match List.rev (String.split_on_char '.' q) with _ :: tl -> List.rev tl | [] -> [] in
  let caller_of = Hashtbl.create 16 in
  List.iter (fun (q, fd) -> Hashtbl.replace caller_of fd.A.fn_name.A.span (path_of q)) fns;
  let calls (f : A.fn_def) g =
    let caller = Option.value (Hashtbl.find_opt caller_of f.A.fn_name.A.span) ~default:[] in
    PI.fn_calls_target ~defined ~caller ~target:g f
  in
  let index = Hashtbl.create 16 and low = Hashtbl.create 16 and on = Hashtbl.create 16 in
  let stack = ref [] and counter = ref 0 and out = ref [] in
  let rec strong (v, fd) =
    Hashtbl.replace index v !counter;
    Hashtbl.replace low v !counter;
    incr counter;
    stack := v :: !stack;
    Hashtbl.replace on v ();
    List.iter
      (fun (w, wfd) ->
        if w <> v && calls fd w then
          if not (Hashtbl.mem index w) then begin
            strong (w, wfd);
            Hashtbl.replace low v (min (Hashtbl.find low v) (Hashtbl.find low w))
          end
          else if Hashtbl.mem on w then Hashtbl.replace low v (min (Hashtbl.find low v) (Hashtbl.find index w)))
      fns;
    if Hashtbl.find low v = Hashtbl.find index v then begin
      let rec pop acc =
        match !stack with
        | w :: tl ->
          stack := tl;
          Hashtbl.remove on w;
          if w = v then w :: acc else pop (w :: acc)
        | [] -> acc
      in
      out := List.sort compare (pop []) :: !out
    end
  in
  List.iter (fun ((v, _) as n) -> if not (Hashtbl.mem index v) then strong n) fns;
  List.rev !out

(* The direct tail call of [fd]'s body, if it is a call to a user function. *)
let tail_callee (fd : A.fn_def) : string option =
  let rec tail (e : A.expr) =
    match e with
    | A.EBlock (es, _) -> (match List.rev es with x :: _ -> tail x | [] -> None)
    | A.EApp (A.EVar { A.txt; _ }, _, _) -> Some txt
    | _ -> None
  in
  match fd.A.fn_clauses with [ c ] -> tail c.A.fc_body | _ -> None

(* ── The run ─────────────────────────────────────────────────────────────── *)

let attr_text (d : dproposal) = Printf.sprintf "@[decreases(%s)]" (String.concat ", " d.d_metric)

(* Termination phase 5: with [Refine_term.infer] on and every SCC holding a
   [is_target] unit demanded, one real [Refine_check.check_module] of the
   hypothesis tree [decls] searches each uncertified SCC (§3.5); its
   results ([Refine_term.last_inferred]) become proposals.  Each applicable
   one is then written into the tree and the module checked again, with
   inference off: a proposal stands only if that re-check certifies its SCC
   [metric], and the re-check's user ledger is the prediction
   [--refine-infer-apply] compares against.  Returns the proposals, the
   SCCs with none, and that ledger (when anything was written). *)
let infer_decreases ~root ~(is_target : A.span -> bool) ~(is_user : A.span -> bool)
    ~(applicable : dproposal -> string option) (m : A.module_) (decls : A.decl list) :
    dproposal list * dnone list * (LD.snapshot * (int * int)) option =
  let module RT = Refine_term in
  let type_map = !Refine_encode.call_type_map in
  let stdlib_files = !RC.stdlib_source_files in
  let saved_infer = !RT.infer and saved_demand = !RT.infer_demand in
  let check ~infer decls =
    RT.infer := infer;
    RT.infer_demand := (if infer then Some is_target else None);
    Fun.protect
      ~finally:(fun () ->
        RT.infer := saved_infer;
        RT.infer_demand := saved_demand)
      (fun () ->
        RC.check_module ~root ~stdlib_files ?type_map (March_errors.Errors.create ())
          { m with A.mod_decls = decls })
  in
  let t = RT.analyze ?type_map ~file_mod:m.A.mod_name.A.txt decls in
  let g = t.RT.graph in
  (* Nothing to search (no target cycle a metric could certify): no check. *)
  let searchable (u : RT.unit_) =
    is_target u.RT.u_span && RT.is_recursive g u.RT.u_id
    && (match t.RT.certs.(g.RT.scc_of.(u.RT.u_id)) with
        | RT.Structural | RT.Diverges | RT.Unproved ("reference" | "non-positive" | "unresolved") -> false
        | RT.Unproved _ -> true)
  in
  if not (Array.exists searchable g.RT.units) then ([], [], None)
  else
  Fun.protect ~finally:(fun () -> Witness.set_module m) @@ fun () ->
  check ~infer:true decls;
  let class_of (u : RT.unit_) =
    match List.find_opt (fun (r : RT.row) -> r.RT.r_span = u.RT.u_span) (RT.rows t) with
    | Some r ->
      let c = r.RT.r_class in
      if String.length c > 1 && c.[String.length c - 1] = '?' then String.sub c 0 (String.length c - 1) else c
    | None -> "?"
  in
  let seen = Hashtbl.create 16 in
  let props = ref [] and nones = ref [] in
  Array.iter
    (fun (u : RT.unit_) ->
      let key = (u.RT.u_span.A.file, u.RT.u_span.A.start_line, u.RT.u_span.A.start_col) in
      if is_target u.RT.u_span && not (Hashtbl.mem seen key) then begin
        Hashtbl.replace seen key ();
        match Hashtbl.find_opt RT.last_inferred u.RT.u_span with
        | None -> ()
        | Some i -> (
          let si = g.RT.scc_of.(u.RT.u_id) in
          let members = g.RT.sccs.(si) in
          match i.RT.inf_metric with
          | None ->
            nones :=
              { n_fn = u.RT.u_name; n_span = u.RT.u_span; n_class = class_of u; n_checked = i.RT.inf_checked;
                n_total = i.RT.inf_total }
              :: !nones
          | Some es ->
            let why =
              if List.exists (fun v -> g.RT.units.(v).RT.u_kind <> RT.Top) members then Some "local"
              else if List.exists (fun v -> g.RT.units.(v).RT.u_decreases <> None) members then Some "written"
              else None
            in
            props :=
              { d_fn = u.RT.u_name; d_span = u.RT.u_span; d_metric = es;
                d_exprs = Option.value ~default:[] (Hashtbl.find_opt RT.last_inferred_exprs u.RT.u_span);
                d_class = class_of u;
                d_checked = i.RT.inf_checked; d_total = i.RT.inf_total;
                d_scc = List.filter_map (fun v -> if v = u.RT.u_id then None else Some g.RT.units.(v).RT.u_name) members;
                d_apply = why }
              :: !props)
      end)
    g.RT.units;
  let props = List.rev !props and nones = List.rev !nones in
  (* A cycle is written whole or not at all: every member's edit must be
     possible. *)
  let props = List.map (fun d -> match d.d_apply with None -> { d with d_apply = applicable d } | Some _ -> d) props in
  let scc_of_prop (d : dproposal) = List.sort compare (d.d_fn :: d.d_scc) in
  let blocked = List.filter_map (fun d -> if d.d_apply <> None then Some (scc_of_prop d) else None) props in
  let props =
    List.map
      (fun d -> if d.d_apply = None && List.mem (scc_of_prop d) blocked then { d with d_apply = Some "apply-by-hand" } else d)
      props
  in
  (* Write the applicable ones into the tree; confirm by a real re-check. *)
  let install (ps : dproposal list) =
    List.fold_left
      (fun decls (d : dproposal) ->
        match
          List.find_opt (fun ((_, fd) : string list * A.fn_def) -> fd.A.fn_name.A.span = d.d_span) (PI.enum_fns [] decls)
        with
        | None -> decls
        | Some ((_, fd) as pf) ->
          let es = d.d_exprs in
          if es = [] then decls
          else
            let fd' =
              { fd with
                A.fn_attrs = (if List.mem "decreases" fd.A.fn_attrs then fd.A.fn_attrs else fd.A.fn_attrs @ [ "decreases" ]);
                fn_attr_args = ("decreases", es) :: List.remove_assoc "decreases" fd.A.fn_attr_args }
            in
            replace_fn [] (PI.qualified_of pf) fd' decls)
      decls ps
  in
  let rec confirm ps tries =
    if ps = [] then ([], None)
    else begin
      check ~infer:false (install ps);
      let bad =
        List.filter (fun (d : dproposal) -> Hashtbl.find_opt RT.last_certs d.d_span <> Some "metric") ps
      in
      if bad = [] || tries = 0 then begin
        let obs = Ob.all () in
        let counts =
          List.fold_left
            (fun (sk, vi) (o : Ob.t) ->
              if not (is_user o.Ob.span) then (sk, vi)
              else match o.Ob.verdict with Ob.Skipped _ -> (sk + 1, vi) | Ob.Violated -> (sk, vi + 1) | _ -> (sk, vi))
            (0, 0) obs
        in
        if bad = [] then (ps, Some (LD.snapshot ~is_user (), counts)) else ([], None)
      end
      else
        let bad_sccs = List.map scc_of_prop bad in
        confirm (List.filter (fun d -> not (List.mem (scc_of_prop d) bad_sccs)) ps) (tries - 1)
    end
  in
  let applied = List.filter (fun d -> d.d_apply = None) props in
  let kept, ledger = confirm applied 3 in
  (* A proposal the real re-check did not certify is not offered at all: the
     SCC is listed as having none. *)
  let unconfirmed = List.filter (fun d -> d.d_apply = None && not (List.memq d kept)) props in
  let props = List.filter (fun d -> not (List.memq d unconfirmed)) props in
  let nones =
    nones
    @ List.map
        (fun d -> { n_fn = d.d_fn; n_span = d.d_span; n_class = d.d_class; n_checked = d.d_checked; n_total = d.d_total })
        unconfirmed
  in
  (props, nones, ledger)

(* ── Lemma calls (reflection phase 7) ────────────────────────────────────── *)

module IL = Infer_lemma

(* The source text of [sp], or [None] when its file cannot be read. *)
let source_cache : (string, string option) Hashtbl.t = Hashtbl.create 4

let source_of (file : string) =
  match Hashtbl.find_opt source_cache file with
  | Some s -> s
  | None ->
    let s = try Some (In_channel.with_open_bin file In_channel.input_all) with Sys_error _ -> None in
    Hashtbl.replace source_cache file s;
    s

let offset_of (src : string) (line : int) (col : int) : int option =
  let rec go i l =
    if l <= 1 then Some (i + col)
    else match String.index_from_opt src i '\n' with Some j -> go (j + 1) (l - 1) | None -> None
  in
  match go 0 line with Some o when o >= 0 && o <= String.length src -> Some o | _ -> None

let text_of (sp : A.span) : string option =
  match source_of sp.A.file with
  | None -> None
  | Some src -> (
    match offset_of src sp.A.start_line sp.A.start_col, offset_of src sp.A.end_line sp.A.end_col with
    | Some a, Some b when b >= a -> Some (String.sub src a (b - a))
    | _ -> None)

let max_lemma_candidates = 8

let same_key (a : Ob.t) (b : Ob.t) =
  a.Ob.span = b.Ob.span && a.Ob.kind = b.Ob.kind && a.Ob.callee = b.Ob.callee && a.Ob.predicate = b.Ob.predicate

(* How the call names the lemma from the site: the short name inside the
   lemma's own file, the qualified name elsewhere. *)
let lemma_spelling (l : IL.lemma) (site_file : string) =
  if l.IL.l_fd.A.fn_name.A.span.A.file = site_file then IL.last_seg l.IL.l_name else l.IL.l_name

(* Write the statement [e] into [decls] before the statement holding [sp]. *)
let install_stmt (decls : A.decl list) (sp : A.span) (e : A.expr) : A.decl list =
  match IL.find_site decls sp with
  | None -> decls
  | Some s ->
    let q = PI.qualified_of s.IL.fn in
    let fd = snd s.IL.fn in
    let fd' =
      { fd with
        A.fn_clauses =
          List.mapi
            (fun i (fc : A.fn_clause) -> if i = s.IL.clause then { fc with A.fc_body = s.IL.rebuild e } else fc)
            fd.A.fn_clauses }
    in
    replace_fn [] q fd' decls

let install_lemma_call (decls : A.decl list) (p : lproposal) : A.decl list =
  install_stmt decls p.lp_target.Ob.span p.lp_expr

let infer_lemmas ~root ~(is_user : A.span -> bool) ~(applicable : lproposal -> string option) (m : A.module_)
    (decls : A.decl list) : lproposal list * lnone list * A.decl list * (LD.snapshot * (int * int)) option =
  let type_map = !Refine_encode.call_type_map in
  let stdlib_files = !RC.stdlib_source_files in
  let saved_infer = !Refine_term.infer and saved_demand = !Refine_term.infer_demand in
  (* One real check of [decls]: the number of errors it reported. *)
  let check decls =
    Refine_term.infer := false;
    Refine_term.infer_demand := None;
    let errctx = March_errors.Errors.create () in
    Fun.protect
      ~finally:(fun () ->
        Refine_term.infer := saved_infer;
        Refine_term.infer_demand := saved_demand)
      (fun () -> RC.check_module ~root ~stdlib_files ?type_map errctx { m with A.mod_decls = decls });
    List.length
      (List.filter (fun (d : March_errors.Errors.diagnostic) -> d.March_errors.Errors.severity = March_errors.Errors.Error)
         errctx.March_errors.Errors.diagnostics)
  in
  let proved_keys () =
    List.filter (fun (o : Ob.t) -> is_user o.Ob.span && o.Ob.verdict = Ob.Proved) (Ob.all ())
  in
  let verdict_of (t : Ob.t) =
    List.find_map
      (fun (o : Ob.t) -> if same_key o t then Some o.Ob.verdict else None)
      (Ob.obligations_at t.Ob.span)
  in
  let counts () =
    List.fold_left
      (fun (sk, vi) (o : Ob.t) ->
        if not (is_user o.Ob.span) then (sk, vi)
        else match o.Ob.verdict with Ob.Skipped _ -> (sk + 1, vi) | Ob.Violated -> (sk, vi + 1) | _ -> (sk, vi))
      (0, 0) (Ob.all ())
  in
  Hashtbl.reset source_cache;
  Fun.protect ~finally:(fun () -> Witness.set_module m) @@ fun () ->
  let base_errors = check decls in
  let targets =
    List.sort_uniq
      (fun (a : Ob.t) (b : Ob.t) -> compare (a.Ob.span, a.Ob.predicate) (b.Ob.span, b.Ob.predicate))
      (List.filter (IL.is_target ~is_user) (Ob.all ()))
  in
  if targets = [] then ([], [], decls, None)
  else begin
    let base_proved = proved_keys () in
    let lemmas = List.filter_map IL.lemma_of !RC.lemma_defs in
    (* Does [decls'] prove [t] with the call at [call_sp] giving its fact, and
       lose no proof and add no error? *)
    let helps decls' (t : Ob.t) (call_sp : A.span) =
      let errs = check decls' in
      errs <= base_errors
      && verdict_of t = Some Ob.Proved
      && Hashtbl.mem RC.lemma_fact_spans call_sp
      && (let now = proved_keys () in
          List.for_all (fun b -> List.exists (same_key b) now) base_proved)
    in
    let fresh = ref 0 in
    let fresh_span (stmt_sp : A.span) =
      incr fresh;
      let c = - !fresh in
      { stmt_sp with A.start_col = c; end_col = c; end_line = stmt_sp.A.start_line }
    in
    (* The skeleton for [t], when assuming its statement proves [t]; each
       gets a name no other skeleton of this run has. *)
    let named = ref [] in
    let skeleton s (t : Ob.t) stmt_sp =
      match IL.skeleton_of ~text_of ~avoid:!named decls s t with
      | None -> None
      | Some sk ->
        named := sk.IL.sk_name :: !named;
        let a = A.EAssert (sk.IL.sk_goal, fresh_span stmt_sp) in
        let errs = check (install_stmt decls t.Ob.span a) in
        if errs <= base_errors && verdict_of t = Some Ob.Proved
           && (let now = proved_keys () in List.for_all (fun b -> List.exists (same_key b) now) base_proved)
        then Some (IL.skeleton_text sk, IL.skeleton_call sk)
        else None
    in
    let props = ref [] and nones = ref [] in
    List.iter
      (fun (t : Ob.t) ->
        match IL.find_site decls t.Ob.span with
        | None -> ()
        | Some s ->
          let pool = IL.pool s t in
          let stmt_sp = IL.span_of s.IL.stmt in
          (* In the lemma's own file the short name is tried first, then the
             qualified one (a lemma in a nested module of the same file). *)
          let spellings (l : IL.lemma) =
            let short = lemma_spelling l stmt_sp.A.file in
            if short = l.IL.l_name then [ short ] else [ short; l.IL.l_name ]
          in
          let cands =
            List.concat_map
              (fun (l : IL.lemma) ->
                List.concat_map (fun args -> List.map (fun n -> (l, n, args)) (spellings l)) (IL.matches l ~scope:s.IL.scope pool))
              lemmas
          in
          let total = List.length cands in
          let fn = PI.qualified_of s.IL.fn in
          let none k =
            nones :=
              { ln_fn = fn; ln_target = t; ln_checked = k; ln_total = total; ln_skeleton = skeleton s t stmt_sp }
              :: !nones
          in
          let rec try_ k = function
            | [] -> none k
            | _ when k >= max_lemma_candidates -> none k
            | ((_ : IL.lemma), name, args) :: rest -> (
              let texts = List.map (fun a -> text_of (IL.span_of a)) args in
              (* A term spanning lines is not written into one statement. *)
              if List.exists (function None -> true | Some t -> String.contains t '\n') texts then try_ k rest
              else begin
                let call_sp = fresh_span stmt_sp in
                let e = A.EApp (A.EVar { A.txt = name; span = call_sp }, args, call_sp) in
                let p =
                  { lp_fn = fn; lp_target = t; lp_lemma = name;
                    lp_call = Printf.sprintf "%s(%s)" name (String.concat ", " (List.filter_map Fun.id texts));
                    lp_stmt = stmt_sp; lp_expr = e; lp_checked = k + 1; lp_total = total; lp_apply = None }
                in
                if helps (install_lemma_call decls p) t call_sp then props := p :: !props else try_ (k + 1) rest
              end)
          in
          try_ 0 cands)
      targets;
    (* One call per statement: a second target the same call closes reuses it. *)
    let props =
      List.fold_left
        (fun acc (p : lproposal) ->
          if List.exists (fun (q : lproposal) -> q.lp_stmt = p.lp_stmt && q.lp_call = p.lp_call) acc then acc
          else acc @ [ p ])
        [] (List.rev !props)
    in
    let props = List.map (fun p -> { p with lp_apply = applicable p }) props in
    let install ps = List.fold_left install_lemma_call decls ps in
    let rec confirm ps tries =
      if ps = [] then ([], decls, None)
      else
        let decls' = install ps in
        let errs = check decls' in
        let bad =
          List.filter
            (fun (p : lproposal) ->
              verdict_of p.lp_target <> Some Ob.Proved
              || not (Hashtbl.mem RC.lemma_fact_spans (match p.lp_expr with A.EApp (_, _, sp) -> sp | _ -> A.dummy_span)))
            ps
        in
        if errs <= base_errors && bad = [] then (ps, decls', Some (LD.snapshot ~is_user (), counts ()))
        else if tries = 0 then ([], decls, None)
        else confirm (List.filter (fun p -> not (List.memq p bad)) ps) (tries - 1)
    in
    let applied = List.filter (fun p -> p.lp_apply = None) props in
    let kept, decls', ledger = confirm applied 3 in
    let unconfirmed = List.filter (fun p -> p.lp_apply = None && not (List.memq p kept)) props in
    let props = List.filter (fun p -> not (List.memq p unconfirmed)) props in
    let nones =
      List.rev !nones
      @ List.map
          (fun p ->
            { ln_fn = p.lp_fn; ln_target = p.lp_target; ln_checked = p.lp_checked; ln_total = p.lp_total;
              ln_skeleton = None })
          unconfirmed
    in
    (props, nones, decls', ledger)
  end

let run ?(root = Sys.getcwd ()) ?(kinds = all_kinds) ?(budget = default_budget)
    ?(rounds = default_rounds) ?(allow_caller_violations = false) ?(stdlib = false)
    ?(decreases = true)
    ?(applicable : proposal -> accepted:proposal list -> string option = fun _ ~accepted:_ -> None)
    ?(applicable_decreases : dproposal -> string option = fun _ -> None)
    ?(lemmas = true) ?(applicable_lemmas : lproposal -> string option = fun _ -> None)
    ~(is_user : A.span -> bool) (m : A.module_) : result =
  let is_target sp = stdlib || is_user sp in
  (* Lemma calls are searched only when the caller's check skipped something
     at reflection's frontier (phase 7, ruling 1): no other program pays. *)
  let lemmas = lemmas && List.exists (Infer_lemma.is_target ~is_user) (Ob.all ()) in
  Ob.with_scratch @@ fun () ->
  let saved_defs = Hashtbl.copy Refine_param.fn_defs_tbl in
  let saved_proved = Hashtbl.copy Refine_param.elem_ret_proved in
  let saved_abs = Hashtbl.copy RC.abstracts_tbl in
  let restore () =
    let back dst src =
      Hashtbl.reset dst;
      Hashtbl.iter (fun k v -> Hashtbl.replace dst k v) src
    in
    back Refine_param.fn_defs_tbl saved_defs;
    back Refine_param.elem_ret_proved saved_proved;
    back RC.abstracts_tbl saved_abs
  in
  Fun.protect ~finally:restore @@ fun () ->
  let decls = ref m.A.mod_decls in
  let user_snapshot () =
    let defs = RC.collect_all_defs !decls in
    let snap = PI.walk_ledger ~root ~defs !decls in
    (List.filter (fun ((k : LD.key), _) -> is_user k.LD.span) snap, Ob.all ())
  in
  let before, _ = user_snapshot () in
  let budget = ref budget in
  let start_budget = !budget in
  let proposals = ref [] and rejected = ref [] and refused = ref [] and notes = ref [] in
  let next_id = ref 0 in
  let note fn n = if not (List.mem (fn, n) !notes) then notes := (fn, n) :: !notes in
  (* Install an accepted hypothesis: in the tree, and in the checker's tables. *)
  let install (s : IS.slot) (hyp : A.fn_def) =
    decls := replace_fn [] s.IS.fn hyp !decls;
    (match Hashtbl.find_opt Refine_param.fn_defs_tbl s.IS.fn with
     | Some (prefix, _) -> Hashtbl.replace Refine_param.fn_defs_tbl s.IS.fn (prefix, hyp)
     | None -> ());
    Hashtbl.remove RC.abstracts_tbl s.IS.fn;
    (* An accepted element return, or a K6 slot (a callback PARAMETER whose
       proposal includes the element return the oracle proved), is a proved
       element return from here on.  The K6 arm was unreachable behind the
       [IS.Param _] case until 2026-10-25: a definer's own (any arity)
       recursive calls and its callers then read "`f`'s own body is not
       proved", and the prediction disagreed with the re-check. *)
    if List.mem IS.K6 s.IS.kinds then Hashtbl.replace Refine_param.elem_ret_proved s.IS.fn ()
    else
    match s.IS.path with
    | IS.Return | IS.Param _ | IS.Lambda_param _ -> ()
    | p -> if IS.root p = IS.Return then Hashtbl.replace Refine_param.elem_ret_proved s.IS.fn ()
  in
  let current_slot (s : IS.slot) =
    match find_fd !decls s.IS.fn with Some fd -> Some { s with IS.fd = fd } | None -> None
  in
  let annotation_of (s : IS.slot) (pred : string) =
    match s.IS.path with
    | IS.Lambda_param _ -> Printf.sprintf "{%s | %s}" (Option.value (IS.render IS.Return s.IS.base) ~default:"Int") pred
    | _ -> Option.value (IS.respell s ~pred) ~default:pred
  in
  (* [applicable] (the driver's, under --refine-infer-apply/-diff) withholds a
     proposal that will not be written — external callers without
     --apply-public, an edit that must be made by hand — BEFORE it is
     installed, so no later probe and no prediction counts on it.  A withheld
     proposal is reported as refused with that reason. *)
  let proposal_of ~round ~(s : IS.slot) ~pred ~annotation ~source ~depends ~(v : IO.verdict) =
    let id = Printf.sprintf "P%d" (!next_id + 1) in
    let closes, new_skipped = match v with IO.Accept { closes; new_skipped } -> (closes, new_skipped) | _ -> ([], []) in
    let path, name = IO.split_qualified s.IS.fn in
    let external_callers =
      (match IS.root s.IS.path with IS.Param _ -> true | _ -> false)
      && s.IS.fd.A.fn_vis = A.Public
      && not (PI.has_in_unit_callers path name !decls)
    in
    { id; round; slot = s; pred; annotation; source; depends_on = depends; closes; new_skipped; external_callers }
  in
  let withheld (p : proposal) =
    match applicable p ~accepted:(List.rev !proposals) with
    | None -> false
    | Some why ->
      refused := (p.slot, p.pred, { PI.rf_reason = why; rf_sites = [] }) :: !refused;
      true
  in
  let commit (p : proposal) =
    incr next_id;
    proposals := p :: !proposals;
    p.id
  in
  let note_verdicts (s : IS.slot) (pairs : (string * IO.verdict) list) =
    List.iter
      (fun (pred, v) ->
        match v with
        | IO.Reject (("not-true" | "opens-site" | "unsatisfiable" | "vacuous-branch") as r, d) -> rejected := (s, pred, r, d) :: !rejected
        | IO.Reject ("budget", _) -> note s.IS.fn "budget-exhausted"
        | IO.Refuse rf -> refused := (s, pred, rf) :: !refused
        | _ -> ())
      pairs
  in
  (* One ordinary slot (K1-K5, K7): best candidate, or a chain for a return. *)
  let try_slot ~round ~ledger ~depth (s : IS.slot) : bool =
    (* A slot of a container of several arguments (`Arg`, 2026-10-25) is
       tried only where a demand could make it USEFUL: a skip at a caller
       for a return, a skip in the body for a parameter. *)
    let rec has_arg = function IS.Arg _ -> true | IS.Elem p | IS.Tuple (_, p) -> has_arg p | _ -> false in
    let demanded (s : IS.slot) =
      (not (has_arg s.IS.path))
      || (if IO.is_return s then IV.caller_has_skip s ~ledger ~unit_decls:!decls else IV.body_has_skip s ~ledger)
    in
    match current_slot s with
    | Some s when not (demanded s) -> false
    | None -> false
    | Some s ->
      let cands, truncated = IV.mine_full s ~ledger ~unit_decls:!decls in
      if truncated then note s.IS.fn "vocabulary-truncated";
      (* Not ordered here: [IO.best_for_slot ~order:true] orders only the
         candidates that tie for the best score (see there). *)
      let per_fn = ref (min !budget (if IO.is_return s then 60 else 200)) in
      let used0 = !per_fn in
      (* [~allow_caller_violations] (D2's override): a candidate refused only
         for the callers it would break is taken as if admissible — still
         only if some value satisfies it. *)
      let best, verdicts = IO.best_for_slot ~order:true ~allow_caller_violations ~root ~decls:!decls s cands ~budget:per_fn in
      budget := !budget - (used0 - !per_fn);
      let pairs = List.mapi (fun i v -> ((match List.nth_opt cands i with Some c -> c.IV.c.PI.c_text | None -> ""), v)) verdicts in
      match best with
      | Some (c, v) ->
        let p =
          proposal_of ~round ~s ~pred:c.IV.c.PI.c_text ~annotation:(annotation_of s c.IV.c.PI.c_text)
            ~source:c.IV.source ~depends:[] ~v
        in
        if withheld p then false
        else begin
          let hyp = IS.install s ~mk:c.IV.c.PI.c_pred in
          install s hyp;
          ignore (commit p);
          true
        end
      | None ->
        (* Demand chain (§3.3): a return candidate that is not TRUE because
           its tail calls a user function whose own return could carry it. *)
        let chained =
          IO.is_return s && depth < chain_depth
          && (match tail_callee s.IS.fd with
              | None -> false
              | Some callee ->
                let caller, _ = IO.split_qualified s.IS.fn in
                let callee = PI.resolve_call ~defined:(PI.defined_fns !decls) ~caller callee in
                let callee_slot =
                  List.find_opt
                    (fun (t : IS.slot) -> Some t.IS.fn = callee && t.IS.path = s.IS.path)
                    (IS.enumerate ~is_user:is_target !decls)
                in
                match callee_slot with
                | None -> false
                | Some cs ->
                  List.exists
                    (fun ((pred, v) : string * IO.verdict) ->
                      match v with
                      | IO.Reject ("not-true", _) when !budget > 0 -> (
                        match List.find_opt (fun c -> c.IV.c.PI.c_text = pred) cands with
                        | None -> false
                        | Some c ->
                          decr budget;
                          if not (IO.holds ~root ~decls:!decls cs c) then false
                          else begin
                            (* Tentatively install the callee link, then re-probe. *)
                            let saved_decls = !decls in
                            let saved_tbl = Hashtbl.find_opt Refine_param.fn_defs_tbl cs.IS.fn in
                            let saved_proved = Hashtbl.mem Refine_param.elem_ret_proved cs.IS.fn in
                            let csf = Option.value (current_slot cs) ~default:cs in
                            let chyp = IS.install csf ~mk:c.IV.c.PI.c_pred in
                            install csf chyp;
                            let b2 = ref 1 in
                            match IO.best_for_slot ~root ~decls:!decls s [ c ] ~budget:b2 with
                            | Some (_, v2), _
                              when (let dp =
                                      proposal_of ~round ~s:csf ~pred
                                        ~annotation:(Option.value (IS.respell csf ~pred) ~default:pred)
                                        ~source:c.IV.source ~depends:[] ~v:(IO.Accept { closes = []; new_skipped = [] })
                                    in
                                    not (withheld dp)
                                    && (let dep = commit dp in
                                        let mp =
                                          proposal_of ~round ~s ~pred
                                            ~annotation:(Option.value (IS.respell s ~pred) ~default:pred)
                                            ~source:c.IV.source ~depends:[ dep ] ~v:v2
                                        in
                                        if withheld mp then begin
                                          (* The link alone closes nothing: take it back. *)
                                          proposals := List.tl !proposals;
                                          decr next_id;
                                          false
                                        end
                                        else begin
                                          let hyp = IS.install s ~mk:c.IV.c.PI.c_pred in
                                          install s hyp;
                                          ignore (commit mp);
                                          true
                                        end)) ->
                              true
                            | _, _ ->
                              decls := saved_decls;
                              (match saved_tbl with
                               | Some v -> Hashtbl.replace Refine_param.fn_defs_tbl cs.IS.fn v
                               | None -> ());
                              if not saved_proved then Hashtbl.remove Refine_param.elem_ret_proved cs.IS.fn;
                              false
                          end)
                      | _ -> false)
                    pairs)
        in
        if not chained then note_verdicts s pairs;
        chained
  in
  let try_k6 ~round (s : IS.slot) : bool =
    match current_slot s with
    | None -> false
    | Some s -> (
      let per_fn = ref (min !budget 60) in
      let used0 = !per_fn in
      let best, verdicts = IO.best_k6 ~root ~decls:!decls s ~budget:per_fn in
      budget := !budget - (used0 - !per_fn);
      match best with
      | Some (shape, v) -> (
        match IS.graft s shape with
        | Some hyp ->
          let p =
            proposal_of ~round ~s ~pred:"p" ~annotation:(shape.IS.k6_callback ^ " / " ^ shape.IS.k6_return)
              ~source:IV.House ~depends:[] ~v
          in
          if withheld p then false
          else begin
            install s hyp;
            ignore (commit p);
            true
          end
        | None -> false)
      | None ->
        note_verdicts s (List.map (fun v -> ("p", v)) verdicts);
        false)
  in
  (* K5 relational element refinements: a whole two-slot container type a
     caller demands (Demand source only). *)
  let try_rel ~round (s : IS.slot) : bool =
    match current_slot s with
    | None -> false
    | Some s -> (
      match IS.rel_demands ~unit_decls:!decls s with
      | [] -> false
      | tys -> (
        let per_fn = ref (min !budget 12) in
        let used0 = !per_fn in
        let best, verdicts = IO.best_whole ~allow_caller_violations ~root ~decls:!decls s tys ~budget:per_fn in
        budget := !budget - (used0 - !per_fn);
        let text t = Option.value (IS.render IS.Return t) ~default:"" in
        match best with
        | Some (t, v) ->
          let ann = text t in
          let p = proposal_of ~round ~s ~pred:ann ~annotation:ann ~source:IV.Demand ~depends:[] ~v in
          if withheld p then false
          else begin
            install s (IS.install_ty s t);
            if IO.is_return s then Hashtbl.replace Refine_param.elem_ret_proved s.IS.fn ();
            ignore (commit p);
            true
          end
        | None ->
          note_verdicts s (List.map (fun (t, v) -> (text t, v)) verdicts);
          false))
  in
  let rec loop round =
    if round > rounds || !budget <= 0 then round - 1
    else begin
      let _, ledger = user_snapshot () in
      let slots =
        IS.enumerate ~is_user:is_target !decls
        |> List.filter (fun (s : IS.slot) -> List.exists (fun k -> List.mem k kinds) s.IS.kinds)
      in
      let user_fns =
        List.filter_map
          (fun ((_, fd) as pf) -> if is_target fd.A.fn_name.A.span then Some (PI.qualified_of pf, fd) else None)
          (PI.enum_fns [] !decls)
      in
      let order = sccs ~defined:(PI.defined_fns !decls) user_fns in
      let rank = Hashtbl.create 16 in
      List.iteri (fun i comp -> List.iter (fun f -> Hashtbl.replace rank f i) comp) order;
      let by_order ss =
        List.stable_sort
          (fun (a : IS.slot) (b : IS.slot) ->
            compare (Hashtbl.find_opt rank a.IS.fn) (Hashtbl.find_opt rank b.IS.fn))
          ss
      in
      let is_k6 (s : IS.slot) = List.mem IS.K6 s.IS.kinds in
      let is_k7 (s : IS.slot) = List.mem IS.K7 s.IS.kinds in
      let facts = by_order (List.filter (fun s -> (not (is_k6 s)) && (not (is_k7 s)) && IO.is_return s) slots) in
      let k6s = by_order (List.filter is_k6 slots) in
      let demands = by_order (List.filter (fun s -> (not (is_k6 s)) && (not (is_k7 s)) && not (IO.is_return s)) slots) in
      let accs = List.filter is_k7 slots in
      let rels =
        if not (List.mem IS.K5 kinds) then []
        else
          by_order
            (List.concat_map
               (fun ((_, (fd : A.fn_def)) as pf) ->
                 if is_target fd.A.fn_name.A.span then IS.rel_slots ~fn:(PI.qualified_of pf) fd else [])
               (PI.enum_fns [] !decls))
      in
      let accepted = ref false in
      let go f ss = List.iter (fun s -> if f s then accepted := true) ss in
      go (try_slot ~round ~ledger ~depth:0) facts;
      go (try_k6 ~round) k6s;
      go (try_rel ~round) (List.filter IO.is_return rels);
      go (try_slot ~round ~ledger ~depth:0) demands;
      go (try_rel ~round) (List.filter (fun s -> not (IO.is_return s)) rels);
      go (try_slot ~round ~ledger ~depth:0) accs;
      (* An SCC of size > 1 whose members got nothing. *)
      List.iter
        (fun comp ->
          if List.length comp > 1
             && not (List.exists (fun (p : proposal) -> List.mem p.slot.IS.fn comp) !proposals)
          then List.iter (fun f -> note f "scc-unsupported") comp)
        order;
      if !accepted then loop (round + 1) else round
    end
  in
  let rounds_run = loop 1 in
  let after, after_obs = user_snapshot () in
  let after_counts =
    List.fold_left
      (fun (sk, vi) (o : Ob.t) ->
        if not (is_user o.Ob.span) then (sk, vi)
        else match o.Ob.verdict with Ob.Skipped _ -> (sk + 1, vi) | Ob.Violated -> (sk, vi + 1) | _ -> (sk, vi))
      (0, 0) after_obs
  in
  (* Lemma calls (reflection phase 7), on the contracts proved above; the
     metric search then re-checks a tree that has them. *)
  let lprops, lnones, ldecls, lledger =
    if lemmas then infer_lemmas ~root ~is_user ~applicable:applicable_lemmas m !decls else ([], [], !decls, None)
  in
  decls := ldecls;
  (* Termination phase 5, last: a metric costs no caller anything, and the
     search reads the contracts proved above. *)
  let dprops, dnones, dledger =
    if decreases then infer_decreases ~root ~is_target ~is_user ~applicable:applicable_decreases m !decls
    else ([], [], None)
  in
  let after, after_counts =
    match dledger, lledger with
    | Some (snap, counts), _ | None, Some (snap, counts) -> (snap, counts)
    | None, None -> (after, after_counts)
  in
  (* A refusal found again in a later round is the same refusal. *)
  let dedupe_refused rs =
    let seen = Hashtbl.create 16 in
    List.filter
      (fun ((s : IS.slot), pred, (rf : PI.refusal)) ->
        let k = (s.IS.fn, s.IS.path, pred, rf.PI.rf_reason) in
        if Hashtbl.mem seen k then false else (Hashtbl.replace seen k (); true))
      rs
  in
  { decreases = dprops;
    decreases_none = dnones;
    lemma_calls = lprops;
    lemma_none = lnones;
    proposals = List.rev !proposals;
    rejected = List.rev !rejected;
    refused = dedupe_refused (List.rev !refused);
    notes = List.rev !notes;
    before;
    after;
    after_counts;
    probes = start_budget - !budget;
    rounds = rounds_run }
