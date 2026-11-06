(** [--why-copies]: find where a value is passed to a function that would
    reuse its cells in place, while the value is still live after the call
    (specs/2026-11-05-why-copies-design.md).

    Runs on the TIR right after Perceus and reads only what Perceus decided:

    - Perceus puts an [inc_rc x] immediately before a call that passes [x]
      at an owned position when [x] is used again afterwards.  That inc is
      the fact "x is still shared when the callee runs".
    - A callee that reuses a parameter in place does so with [reuse p] or
      [reuse_hole p] (FBIP, TRMC), checked for uniqueness at run time.  With
      the inc above, the check fails and the callee allocates fresh cells.

    A site is the two together.  Purely a read: nothing is rewritten.  The
    driver maps each site back to source (the host function's AST, the call,
    the variable's next use) and renders it; TIR carries no per-expression
    spans, so this module only names things. *)

type site = {
  host : string;     (** TIR name of the function containing the call *)
  var : string;      (** the shared variable, as the source spells it *)
  callee : string;   (** the callee's source name ([List.map]), suffixes stripped *)
  arg_index : int;   (** which argument of the call the variable is *)
}

(** [List.map$List_Int$Fn_Int_Int$hspec$1_...] -> [List.map]: the name the
    program wrote.  Monomorphisation, specialisation and clones all append
    after a [$]. *)
let source_name (tir_name : string) : string =
  match String.index_opt tir_name '$' with
  | Some i -> String.sub tir_name 0 i
  | None -> tir_name

(** A variable the program named (not a compiler temporary like [$t12]). *)
let is_source_var (v : Tir.var) =
  v.Tir.v_name <> "" && v.Tir.v_name.[0] <> '$'

(** Does function [fname] reuse its [i]th parameter's cell in place, either
    directly or by passing it on at a position its callee reuses?  Memoised;
    a function still being examined answers [false], so recursion ends. *)
let make_reuses (fns : (string, Tir.fn_def) Hashtbl.t) : string -> int -> bool =
  let memo : (string * int, bool) Hashtbl.t = Hashtbl.create 64 in
  let rec reuses fname i =
    match Hashtbl.find_opt memo (fname, i) with
    | Some b -> b
    | None ->
      Hashtbl.replace memo (fname, i) false;
      let b =
        match Hashtbl.find_opt fns fname with
        | None -> false
        | Some fd ->
          (match List.nth_opt fd.Tir.fn_params i with
           | None -> false
           | Some p -> body_reuses p.Tir.v_name fd.Tir.fn_body)
      in
      Hashtbl.replace memo (fname, i) b;
      b
  and is_p p = function Tir.AVar v -> String.equal v.Tir.v_name p | _ -> false
  and body_reuses p (e : Tir.expr) : bool =
    match e with
    | Tir.EReuse (a, _, _) -> is_p p a
    | Tir.EAllocHole (Some a, _, _, _) -> is_p p a
    | Tir.EApp (f, args) ->
      List.exists Fun.id
        (List.mapi (fun j a -> is_p p a && reuses f.Tir.v_name j) args)
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> body_reuses p e1 || body_reuses p e2
    | Tir.ECase (_, brs, def) ->
      List.exists (fun (br : Tir.branch) -> body_reuses p br.Tir.br_body) brs
      || (match def with Some d -> body_reuses p d | None -> false)
    | Tir.ELetRec (_, body) -> body_reuses p body
    | _ -> false
  in
  reuses

(** The first expression [e] evaluates, past RC operations and into the
    right-hand side of a [let]. *)
let rec head (e : Tir.expr) : Tir.expr =
  match e with
  | Tir.ESeq ((Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _), rest) ->
    head rest
  | Tir.ESeq (e1, _) -> head e1
  | Tir.ELet (_, e1, _) -> head e1
  | e -> e

let sites_of_fn (reuses : string -> int -> bool) (fd : Tir.fn_def) : site list =
  let acc = ref [] in
  let add s = if not (List.mem s !acc) then acc := s :: !acc in
  let rec walk (e : Tir.expr) =
    (match e with
     | Tir.ESeq ((Tir.EIncRC (Tir.AVar x) | Tir.EAtomicIncRC (Tir.AVar x)), rest)
       when is_source_var x ->
       (match head rest with
        | Tir.EApp (f, args) ->
          List.iteri (fun i a ->
              match a with
              | Tir.AVar v when String.equal v.Tir.v_name x.Tir.v_name
                                && reuses f.Tir.v_name i ->
                add { host = fd.Tir.fn_name; var = x.Tir.v_name;
                      callee = source_name f.Tir.v_name; arg_index = i }
              | _ -> ())
            args
        | _ -> ())
     | _ -> ());
    match e with
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> walk e1; walk e2
    | Tir.ECase (_, brs, def) ->
      List.iter (fun (br : Tir.branch) -> walk br.Tir.br_body) brs;
      Option.iter walk def
    | Tir.ELetRec (fns, body) ->
      List.iter (fun (f : Tir.fn_def) -> walk f.Tir.fn_body) fns; walk body
    | _ -> ()
  in
  walk fd.Tir.fn_body;
  List.rev !acc

(** Every site in [m], in function order.  The caller keeps the ones whose
    host is the user's own code. *)
let analyze (m : Tir.tir_module) : site list =
  let fns = Hashtbl.create 256 in
  List.iter (fun (fd : Tir.fn_def) -> Hashtbl.replace fns fd.Tir.fn_name fd) m.Tir.tm_fns;
  let reuses = make_reuses fns in
  List.concat_map (sites_of_fn reuses) m.Tir.tm_fns

(** Whether a call the program writes as [name] ([List.length], [size],
    [println]) can be moved earlier without changing what the program does:
    it performs no IO, touches no actor or mutable runtime state, and calls
    nothing through a closure.  Judged on the module BEFORE Perceus (no RC
    operations yet).  [Purity.impure_fns_of_module] is too strict to reuse:
    it counts the [panic("non-exhaustive pattern match")] default arm the
    compiler adds to every match, which would make every function that
    matches impure.  That arm is unreachable for an exhaustive match, so it
    is allowed here; any other panic is not (moving it could change which
    failure the program reports).  TRMC's hole fill ([ESetField]) writes a
    cell the function itself just allocated, so it is allowed too.
    Conservative everywhere else. *)
let pure_call_oracle (pre : Tir.tir_module) : string -> bool =
  let module S = Purity.StringSet in
  let generated_panic (f : Tir.var) args =
    (f.Tir.v_name = "panic" || f.Tir.v_name = "panic_")
    && (match args with
        | [ Tir.ALit (March_ast.Ast.LitString "non-exhaustive pattern match") ] -> true
        | _ -> false) in
  let rec movable impure (e : Tir.expr) : bool =
    match e with
    | Tir.EApp (f, args) ->
      generated_panic f args
      || (let base = Tir_names.strip_specialization_suffix f.Tir.v_name in
          not (Purity.is_impure_builtin base)
          && not (S.mem f.Tir.v_name impure) && not (S.mem base impure))
    | Tir.ECallPtr _ -> false
    | Tir.ELet (_, e1, e2) | Tir.ESeq (e1, e2) -> movable impure e1 && movable impure e2
    | Tir.ELetRec (fns, body) ->
      List.for_all (fun (fd : Tir.fn_def) -> movable impure fd.Tir.fn_body) fns
      && movable impure body
    | Tir.ECase (_, brs, def) ->
      List.for_all (fun (br : Tir.branch) -> movable impure br.Tir.br_body) brs
      && Option.fold ~none:true ~some:(movable impure) def
    | Tir.EIncRC _ | Tir.EDecRC _ | Tir.EAtomicIncRC _ | Tir.EAtomicDecRC _
    | Tir.EFree _ | Tir.EReuse _ -> false
    | Tir.EAtom _ | Tir.ETuple _ | Tir.ERecord _ | Tir.EField _ | Tir.EUpdate _
    | Tir.EAlloc _ | Tir.EStackAlloc _ | Tir.EAllocHole _ | Tir.ESetField _ -> true
  in
  let rec fixpoint impure =
    let impure' = List.fold_left (fun acc (fd : Tir.fn_def) ->
        if S.mem fd.Tir.fn_name acc || movable acc fd.Tir.fn_body then acc
        else S.add fd.Tir.fn_name acc) impure pre.Tir.tm_fns in
    if S.cardinal impure' = S.cardinal impure then impure' else fixpoint impure' in
  let impure = fixpoint S.empty in
  let by_source = Hashtbl.create 256 in
  List.iter (fun (fd : Tir.fn_def) ->
      Hashtbl.add by_source (source_name fd.Tir.fn_name) fd.Tir.fn_name)
    pre.Tir.tm_fns;
  fun name ->
    let last s = match String.rindex_opt s '.' with
      | Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s in
    let matches =
      Hashtbl.find_all by_source name
      @ (Hashtbl.fold (fun src tir acc ->
          if String.ends_with ~suffix:("." ^ name) src then tir :: acc else acc)
          by_source []) in
    (* No definition in the module: a builtin, judged by [Purity]'s list. *)
    not (Purity.is_impure_builtin (last name))
    && not (List.exists (fun n -> S.mem n impure) matches)

(* ── Back to source ───────────────────────────────────────────────────── *)

module A = March_ast.Ast

let span_of = March_typecheck.Typecheck_types.span_of_expr

(* Every sub-expression, block statements included.  Exhaustive on purpose,
   like [Typecheck.iter_expr]: a new form must be placed here. *)
let rec iter_expr (f : A.expr -> unit) (e : A.expr) : unit =
  f e;
  let go = iter_expr f in
  match e with
  | A.ELit _ | A.EVar _ | A.EHole _ | A.EResultRef _ | A.EDbg (None, _) -> ()
  | A.EDbg (Some inner, _) -> go inner
  | A.EApp (h, args, _) -> go h; List.iter go args
  | A.EPipe (l, r, _) -> go l; go r
  | A.ECon (_, args, _) | A.EAtom (_, args, _) | A.ETuple (args, _) -> List.iter go args
  | A.ELam (_, body, _) -> go body
  | A.EBlock (es, _) -> List.iter go es
  | A.ELet (b, _) -> go b.A.bind_expr
  | A.EMatch (scrut, branches, _) ->
    go scrut;
    List.iter (fun (br : A.branch) -> Option.iter go br.A.branch_guard; go br.A.branch_body) branches
  | A.ERecord (fields, _) -> List.iter (fun (_, ex) -> go ex) fields
  | A.ERecordUpdate (base, fields, _) -> go base; List.iter (fun (_, ex) -> go ex) fields
  | A.EField (ex, _, _) -> go ex
  | A.EIf (c, t, e, _) -> go c; go t; go e
  | A.ECond (arms, _) -> List.iter (fun (c, b) -> go c; go b) arms
  | A.EAnnot (ex, _, _) | A.ESpawn (ex, _) | A.EAssert (ex, _) | A.ESigil (_, ex, _)
  | A.ERefineMsg (ex, _, _) -> go ex
  | A.ESend (a, b, _) -> go a; go b
  | A.ELetFn (_, _, _, body, _) -> go body
  | A.ELetQ (_, r, k, _) | A.ELetStar (_, r, k, _) -> go r; go k

let pos (sp : A.span) = (sp.A.start_line, sp.A.start_col)
let end_pos (sp : A.span) = (sp.A.end_line, sp.A.end_col)
let within ~(outer : A.span) (inner : A.span) =
  pos inner >= pos outer && end_pos inner <= end_pos outer

(* The function definition whose span holds [sp], with its body clauses. *)
let rec find_fn (decls : A.decl list) (sp : A.span) : A.fn_def option =
  List.find_map (fun (d : A.decl) ->
      match d with
      | A.DFn (fd, dsp) when within ~outer:dsp sp || pos dsp = pos sp -> Some fd
      | A.DMod (_, _, ds, _) -> find_fn ds sp
      | _ -> None)
    decls

(* [List.map] matches a call written [List.map(...)], or [map(...)] after
   [use List.*]: compare the last dotted component, and the whole name when
   the call spells a qualifier. *)
let callee_matches ~(callee : string) (h : A.expr) =
  let last s = match String.rindex_opt s '.' with
    | Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s in
  match h with
  | A.EVar n -> n.A.txt = callee || (not (String.contains n.A.txt '.') && n.A.txt = last callee)
  | A.EField (A.EVar m, f, _) -> m.A.txt ^ "." ^ f.A.txt = callee
  | _ -> false

let is_var x = function A.EVar n -> n.A.txt = x | _ -> false

let vars_of (e : A.expr) : (string * A.span) list =
  let acc = ref [] in
  iter_expr (function A.EVar n -> acc := (n.A.txt, n.A.span) :: !acc | _ -> ()) e;
  List.rev !acc

let rec pat_names (p : A.pattern) : string list =
  match p with
  | A.PatVar n -> [ n.A.txt ]
  | A.PatAs (q, n, _) -> n.A.txt :: pat_names q
  | A.PatCon (_, ps) | A.PatAtom (_, ps, _) | A.PatTuple (ps, _) | A.PatOr (ps, _) ->
    List.concat_map pat_names ps
  | A.PatRecord (fs, _) -> List.concat_map (fun (_, q) -> pat_names q) fs
  | A.PatWild _ | A.PatLit _ -> []

(* Names a block statement binds for the statements after it. *)
let stmt_binds (s : A.expr) : string list =
  match s with
  | A.ELet (b, _) -> pat_names b.A.bind_pat
  | A.ELetFn (n, _, _, _, _) -> [ n.A.txt ]
  | _ -> []

(** Why the value is still shared when the callee runs: the one thing the
    warning can point at.  A site whose reason can't be found in the source
    (a value pulled out of a tuple that still holds it, say) is not
    reported: a warning that names the wrong cause is worse than none. *)
type reason =
  | Later of A.span
      (** used again after the call, in the same function *)
  | Enclosing of A.span * string
      (** also an argument of the enclosing call (named), which runs after *)
  | Captured of A.span
      (** the call is inside this closure, which captured the value *)

type located = {
  call_arg : A.span;            (** the variable in the call *)
  call : A.span;                (** the whole call *)
  reason : reason;
  fix : March_errors.Errors.fix_kind option;
  moved : string option;        (** the moved statement's text, for the note *)
}

(* The source text of whole lines [a..b] (1-based). *)
let lines_text (lines : string array) a b =
  String.concat "\n" (Array.to_list (Array.sub lines (a - 1) (b - a + 1)))

let only_ws s = String.for_all (fun c -> c = ' ' || c = '\t') s

(* A statement that owns its lines: nothing but indentation before it and
   nothing after it on its last line. *)
let owns_lines (lines : string array) (sp : A.span) =
  sp.A.start_line >= 1 && sp.A.end_line <= Array.length lines
  && only_ws (String.sub lines.(sp.A.start_line - 1) 0
                (min sp.A.start_col (String.length lines.(sp.A.start_line - 1))))
  && (let l = lines.(sp.A.end_line - 1) in
      sp.A.end_col >= String.length l
      || only_ws (String.sub l sp.A.end_col (String.length l - sp.A.end_col)))

(* The reorder fix: move the statement holding [use] above the one holding
   [call], when that is safe (see the design note): both in one block, the
   later one a [let] that is the variable's only later use, mentioning
   nothing bound in between and no capability. *)
let reorder_fix ~(lines : string array) ~(caps : string list) ~(is_pure_call : string -> bool)
    ~(locals : string list) ~(var : string)
    ~(fn_body : A.expr) ~(call : A.span) ~(use : A.span) ~(later_uses : int)
  : (March_errors.Errors.fix_kind * string) option =
  if later_uses <> 1 then None else
  let found = ref None in
  iter_expr (function
      | A.EBlock (stmts, _) when !found = None ->
        let arr = Array.of_list stmts in
        let idx p = let r = ref None in
          Array.iteri (fun i s -> if !r = None && within ~outer:(span_of s) p then r := Some i) arr;
          !r in
        (match idx call, idx use with
         | Some i, Some j when j > i ->
           (match arr.(j) with
            | A.ELet (b, ssp) ->
              let between = List.concat_map stmt_binds (Array.to_list (Array.sub arr i (j - i))) in
              let used = List.map fst (vars_of b.A.bind_expr) in
              (* Every call in the moved statement must be free of effects,
                 or moving it would reorder them: a named pure function, not
                 a local closure. *)
              let calls_pure =
                let ok = ref true in
                iter_expr (function
                    | A.EApp (A.EVar n, _, _) ->
                      if List.mem n.A.txt locals || not (is_pure_call n.A.txt) then ok := false
                    | A.EApp (_, _, _) | A.ESend _ | A.ESpawn _ -> ok := false
                    | _ -> ()) b.A.bind_expr;
                !ok in
              let s_i = span_of arr.(i) in
              if not calls_pure
              || List.exists (fun n -> List.mem n between) used
              || List.exists (fun n -> List.mem n caps) used
              || not (List.mem var used)
              || not (owns_lines lines ssp) || not (owns_lines lines s_i)
              then ()
              else begin
                let text = lines_text lines ssp.A.start_line ssp.A.end_line in
                let fix = March_errors.Errors.FMulti [
                    March_errors.Errors.FDelete
                      { start_line = ssp.A.start_line; end_line = ssp.A.end_line };
                    March_errors.Errors.FInsert
                      { after_line = s_i.A.start_line - 1; text } ] in
                found := Some (fix, String.trim text)
              end
            | _ -> ())
         | _ -> ())
      | _ -> ()) fn_body;
  !found

let ty_mentions_cap (t : A.ty) =
  let s = A.show_ty t in
  let rec has i = i + 4 <= String.length s && (String.sub s i 4 = "Cap(" || has (i + 1)) in
  has 0

(* Parameters of the host function whose annotated type is a capability. *)
let cap_params (fd : A.fn_def) : string list =
  List.concat_map (fun (c : A.fn_clause) ->
      List.filter_map (function
          | A.FPNamed p | A.FPDefault (p, _) ->
            (match p.A.param_ty with
             | Some t when ty_mentions_cap t -> Some p.A.param_name.A.txt
             | _ -> None)
          | A.FPPat _ -> None) c.A.fc_params)
    fd.A.fn_clauses

(** Find [s] in the source: the call in its host function, the variable's
    next use after it, and the reorder fix when safe.  [None] when the call
    can't be found (the host is generated code, or the call was rewritten
    past recognition): such a site is not reported. *)
let locate ~(decls : A.decl list) ~(source : string) ~(is_pure_call : string -> bool)
    ~(host_span : A.span) (s : site)
  : located option =
  match find_fn decls host_span with
  | None -> None
  | Some fd ->
    let lines = Array.of_list (String.split_on_char '\n' source) in
    let caps = cap_params fd in
    List.find_map (fun (c : A.fn_clause) ->
        let body = c.A.fc_body in
        let calls = ref [] in
        iter_expr (function
            | A.EApp (h, args, csp) when callee_matches ~callee:s.callee h ->
              let arg =
                match List.nth_opt args s.arg_index with
                | Some a when is_var s.var a -> Some a
                | _ -> List.find_opt (is_var s.var) args in
              (match arg with
               | Some a -> calls := (span_of a, csp) :: !calls
               | None -> ())
            | _ -> ()) body;
        let uses = List.filter (fun (n, _) -> n = s.var) (vars_of body) |> List.map snd in
        (* Names bound inside the function: a call through one is a closure,
           whose effects this can't see. *)
        let locals =
          let acc = ref [] in
          iter_expr (fun e -> acc := stmt_binds e @ !acc) body;
          List.concat_map (function
              | A.FPNamed p | A.FPDefault (p, _) -> [ p.A.param_name.A.txt ]
              | A.FPPat q -> pat_names q) c.A.fc_params
          @ !acc in
        let candidates = List.rev !calls in
        (* The innermost lambda around [sp] that does not bind the variable
           itself: the variable is then captured from outside it. *)
        let capturing_lambda sp =
          let best = ref None in
          iter_expr (function
              | A.ELam (ps, _, lsp) when within ~outer:lsp sp ->
                let binds = List.concat_map (fun (p : A.param) -> [ p.A.param_name.A.txt ]) ps in
                if not (List.mem s.var binds) then
                  (match !best with
                   | Some b when within ~outer:b lsp -> best := Some lsp
                   | None -> best := Some lsp
                   | _ -> ())
                else best := None
              | _ -> ()) body;
          !best in
        (* The innermost call around [csp] that also passes the variable. *)
        let enclosing csp =
          let best = ref None in
          iter_expr (function
              | A.EApp (h, args, osp) when within ~outer:osp csp && osp <> csp ->
                let other = List.find_map (fun a ->
                    if within ~outer:(span_of a) csp then None
                    else List.find_map (fun (n, u) -> if n = s.var then Some u else None)
                        (vars_of a)) args in
                (match other, h with
                 | Some u, A.EVar n ->
                   (match !best with
                    | Some (b, _, _) when not (within ~outer:b osp) -> ()
                    | _ -> best := Some (osp, u, n.A.txt))
                 | _ -> ())
              | _ -> ()) body;
          Option.map (fun (_, u, n) -> (u, n)) !best in
        let reason_of (_arg_sp, csp) =
          match capturing_lambda csp with
          | Some lsp -> Some (Captured lsp, [])
          | None ->
            let later = List.filter (fun u -> pos u > end_pos csp) uses
                        |> List.sort (fun a b -> compare (pos a) (pos b)) in
            (match later with
             | u :: _ -> Some (Later u, later)
             | [] ->
               (match enclosing csp with
                | Some (u, n) -> Some (Enclosing (u, n), [])
                | None -> None)) in
        List.find_map (fun ((arg_sp, csp) as c) ->
            match reason_of c with
            | None -> None
            | Some (reason, later) ->
              let fix, moved =
                match reason with
                | Later u ->
                  (match reorder_fix ~lines ~caps ~is_pure_call ~locals ~var:s.var ~fn_body:body
                           ~call:csp ~use:u ~later_uses:(List.length later) with
                   | Some (f, t) -> (Some f, Some t)
                   | None -> (None, None))
                | Enclosing _ | Captured _ -> (None, None) in
              Some { call_arg = arg_sp; call = csp; reason; fix; moved })
          candidates)
      fd.A.fn_clauses

let diagnostic (s : site) (l : located) : March_errors.Errors.diagnostic =
  let v = s.var and f = s.callee in
  let because, why, label = match l.reason with
    | Later u ->
      (Printf.sprintf "`%s` is used again afterwards" v,
       Printf.sprintf
         "A function can update a value in place only when it holds the only reference to it; \
          make this call the last use of `%s` and `%s` reuses its memory instead of allocating." v f,
       { March_errors.Errors.lbl_span = u;
         lbl_message = Printf.sprintf "`%s` is used again here, so it is still shared when `%s` runs" v f })
    | Enclosing (u, outer) ->
      (Printf.sprintf "`%s` is used again afterwards" v,
       Printf.sprintf
         "A function can update a value in place only when it holds the only reference to it; \
          `%s` also holds `%s` until it runs, after `%s`." outer v f,
       { March_errors.Errors.lbl_span = u;
         lbl_message = Printf.sprintf "`%s` is also passed to `%s` here, which runs after `%s`" v outer f })
    | Captured lsp ->
      (Printf.sprintf "a closure captured `%s`" v,
       Printf.sprintf
         "A closure keeps its own reference to every value it captures, since it may run more \
          than once, so a call inside it never holds the only reference to `%s`." v,
       { March_errors.Errors.lbl_span = lsp;
         lbl_message = Printf.sprintf "this closure captures `%s`" v }) in
  let headline = Printf.sprintf
      "`%s` builds a new copy instead of reusing `%s` in place, because %s." f v because in
  let help = match l.moved with
    | Some t -> [ Printf.sprintf "help: move `%s` above the call." t ]
    | None -> [] in
  { March_errors.Errors.severity = March_errors.Errors.Warning;
    span = l.call_arg; message = String.concat "\n" (headline :: why :: help);
    labels = [ label ]; notes = []; code = March_errors.Code.copy_shared; fix = l.fix }
