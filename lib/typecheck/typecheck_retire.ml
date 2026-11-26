(* Retired capability values (ocap phase 7b; design §11, §14, §17).

   Since phase 4 a program's authority is the current authority: `main`'s
   `needs` clause asks for it, every operation checks it, `restrict` and
   grants narrow it.  The `Cap(IO.X)` values that once carried it are erased
   at run time and grant nothing, so this pass retires them:

   - [deprecated_main_cap] (a warning, for one release): `fn main(c :
     Cap(IO.X))`.  The fix rewrites it to `fn main() : () needs IO.X`, which
     asks for exactly the same authority.
   - [cap_param_retired] (an error): a `Cap(IO.X)` type anywhere else, a
     parameter, a return type, a field, an annotation.  For a parameter of a
     named function the fix deletes the parameter and the argument at every
     call of the function in this file: the value was only ever passed along.
   - [cap_narrow_retired] (an error): a call of `cap_narrow`.  It narrowed a
     `Cap(IO.X)` value, and there is none left; an argument it produced for a
     retired parameter goes with that parameter's fix.

   `Cap(Actor.Introspect)`, `Cap(Actor.Debug)`, `Cap(Session.Live)`,
   `Cap(ClusterNode.Live)` and a program's own proof capabilities stay: they
   are proof capabilities, minted by a checked operation or by [mint_cap()].
   Only `main`'s parameters treat `Cap(Actor.X)` as a request, as phase 7a
   did, so they are part of the deprecated form there.

   The fixes edit source text, so they read the file a span names; a span of
   generated code (no file) gets the diagnostic without a fix. *)

module Ast = March_ast.Ast
module Err = March_errors.Errors
module Code = March_errors.Code
module L = March_caps.Cap_lattice

(* ── Source text ─────────────────────────────────────────────────────────── *)

let src_cache : (string, string array) Hashtbl.t = Hashtbl.create 8

let lines_of (file : string) : string array option =
  match Hashtbl.find_opt src_cache file with
  | Some a -> Some a
  | None ->
    if file = "" || not (Sys.file_exists file) then None
    else
      try
        let ic = open_in_bin file in
        let s = really_input_string ic (in_channel_length ic) in
        close_in ic;
        let a = Array.of_list (String.split_on_char '\n' s) in
        Hashtbl.replace src_cache file a;
        Some a
      with _ -> None

(* A position: 1-based line, 0-based column (the span convention). *)
type pos = int * int

let start_of (sp : Ast.span) : pos = (sp.Ast.start_line, sp.Ast.start_col)
let end_of (sp : Ast.span) : pos = (sp.Ast.end_line, sp.Ast.end_col)

let span_of ~file ((l1, c1) : pos) ((l2, c2) : pos) : Ast.span =
  { Ast.file; start_line = l1; start_col = c1; end_line = l2; end_col = c2 }

(* The position of the `,` before [p], skipping whitespace (newlines too), or
   [None] when the character before [p] is anything else. *)
let comma_before (lines : string array) ((l, c) : pos) : pos option =
  let rec go l c =
    if l < 1 then None
    else if c <= 0 then (if l = 1 then None else go (l - 1) (String.length lines.(l - 2)))
    else
      let ch = lines.(l - 1).[c - 1] in
      if ch = ' ' || ch = '\t' || ch = '\r' then go l (c - 1)
      else if ch = ',' then Some (l, c - 1)
      else None
  in
  if l < 1 || l > Array.length lines then None else go l (min c (String.length lines.(l - 1)))

(* The text between two positions. *)
let slice (lines : string array) ((l1, c1) : pos) ((l2, c2) : pos) : string =
  if l1 = l2 then
    let s = lines.(l1 - 1) in
    let c2 = min c2 (String.length s) in
    if c2 <= c1 then "" else String.sub s c1 (c2 - c1)
  else begin
    let b = Buffer.create 64 in
    let first = lines.(l1 - 1) in
    Buffer.add_string b (String.sub first c1 (String.length first - c1));
    for l = l1 + 1 to l2 - 1 do
      Buffer.add_char b '\n';
      Buffer.add_string b lines.(l - 1)
    done;
    Buffer.add_char b '\n';
    let last = lines.(l2 - 1) in
    Buffer.add_string b (String.sub last 0 (min c2 (String.length last)));
    Buffer.contents b
  end

(* Deletions removing the items flagged [true] from a comma-separated list
   whose items are given as (start, end) in order: each run of consecutive
   flagged items is deleted with the separator after it, or, for a run that
   ends the list, with the separator before it.  [None] when a separator
   cannot be found (the text is not shaped as expected). *)
let delete_runs (lines : string array) ~file (items : (pos * pos) list) (flags : bool list)
  : Ast.span list option =
  let items = Array.of_list items and flags = Array.of_list flags in
  let n = Array.length items in
  let rec runs i acc =
    if i >= n then List.rev acc
    else if not flags.(i) then runs (i + 1) acc
    else
      let j = ref i in
      while !j + 1 < n && flags.(!j + 1) do incr j done;
      runs (!j + 1) ((i, !j) :: acc)
  in
  let one (a, b) =
    if b < n - 1 then Some (span_of ~file (fst items.(a)) (fst items.(b + 1)))
    else if a > 0 then
      Option.map (fun c -> span_of ~file c (snd items.(b))) (comma_before lines (fst items.(a)))
    else Some (span_of ~file (fst items.(a)) (snd items.(b)))
  in
  let spans = List.map one (runs 0 []) in
  if List.for_all Option.is_some spans then Some (List.filter_map Fun.id spans) else None

let deletion (sp : Ast.span) : Err.fix_kind = Err.FReplace { span = sp; text = "" }

(* ── Which types are retired ─────────────────────────────────────────────── *)

let is_io_kind (k : string) = k = "IO" || L.cap_subsumes "IO" k || String.starts_with ~prefix:"IO." k

(* A `Cap(K)` written with K under IO: the occurrence's span (from `Cap` to
   the closing parenthesis when it is on one line) and K. *)
let cap_io_of (t : Ast.ty) : (Ast.span * string) option =
  match t with
  | Ast.TyCon ({ Ast.txt = "Cap"; span = cap_sp }, [ Ast.TyCon (inner, []) ]) when is_io_kind inner.Ast.txt ->
    let isp = inner.Ast.span in
    let sp =
      if cap_sp.Ast.file = isp.Ast.file && isp.Ast.end_line >= cap_sp.Ast.start_line then
        { cap_sp with Ast.end_line = isp.Ast.end_line; end_col = isp.Ast.end_col + 1 }
      else cap_sp
    in
    Some (sp, inner.Ast.txt)
  | _ -> None

(* `main`'s request form: `Cap(K)` with K any capability kind. *)
let main_cap_kind (t : Ast.ty option) : (Ast.span * string) option =
  match t with
  | Some (Ast.TyCon ({ Ast.txt = "Cap"; span = cap_sp }, [ Ast.TyCon (inner, []) ]))
    when is_io_kind inner.Ast.txt || L.is_authority inner.Ast.txt ->
    let isp = inner.Ast.span in
    Some ({ cap_sp with Ast.end_line = isp.Ast.end_line; end_col = isp.Ast.end_col + 1 }, inner.Ast.txt)
  | _ -> None

let rec retired_in_ty (acc : (Ast.span * string) list) (t : Ast.ty) =
  match cap_io_of t with
  | Some x -> x :: acc
  | None -> (
    match t with
    | Ast.TyCon (_, ts) | Ast.TyTuple ts -> List.fold_left retired_in_ty acc ts
    | Ast.TyArrow (a, b) | Ast.TyNatOp (_, a, b) -> retired_in_ty (retired_in_ty acc a) b
    | Ast.TyRecord fs -> List.fold_left (fun acc (_, t) -> retired_in_ty acc t) acc fs
    | Ast.TyLinear (_, t) | Ast.TyRefine (t, _, _) -> retired_in_ty acc t
    | Ast.TyVar _ | Ast.TyNat _ | Ast.TyChan _ -> acc)

(* ── Walking the declarations ────────────────────────────────────────────── *)

type fn_info = {
  fi_simple : string;               (* `helper` *)
  fi_qual : string;                 (* `Outer.helper` *)
  fi_arity : int;
  fi_clause : Ast.fn_clause;
  fi_retired : bool list;           (* per parameter: a retired `Cap(IO.X)` *)
}

let param_ty = function
  | Ast.FPNamed p | Ast.FPDefault (p, _) -> p.Ast.param_ty
  | Ast.FPPat _ -> None

let param_start = function
  | Ast.FPNamed p | Ast.FPDefault (p, _) -> Some (start_of p.Ast.param_name.Ast.span)
  | Ast.FPPat _ -> None

let check_module ~(iter_expr : (Ast.expr -> unit) -> Ast.expr -> unit) (errors : Err.ctx)
    (decls : Ast.decl list) : unit =
  let fns : fn_info list ref = ref [] in
  (* Every expression of a declaration, with its nested ones visited. *)
  let rec exprs_of_decl (f : Ast.expr -> unit) (d : Ast.decl) =
    let ex = iter_expr f in
    match d with
    | Ast.DFn (def, _) ->
      List.iter
        (fun (c : Ast.fn_clause) ->
           List.iter (function Ast.FPDefault (_, e) -> ex e | _ -> ()) c.Ast.fc_params;
           Option.iter ex c.Ast.fc_guard;
           ex c.Ast.fc_body)
        def.Ast.fn_clauses
    | Ast.DLet (_, b, _) -> ex b.Ast.bind_expr
    | Ast.DActor (_, _, a, _) ->
      ex a.Ast.actor_init;
      List.iter (fun (h : Ast.actor_handler) -> ex h.Ast.ah_body) a.Ast.actor_handlers;
      Option.iter (fun (h : Ast.actor_handler) -> ex h.Ast.ah_body) a.Ast.actor_on_stop;
      Option.iter (fun (_, e) -> ex e) a.Ast.actor_migrate
    | Ast.DMod (_, _, ds, _) | Ast.DDescribe (_, ds, _) -> List.iter (exprs_of_decl f) ds
    | Ast.DImpl (idef, _) -> List.iter (fun (_, (def : Ast.fn_def)) -> exprs_of_decl f (Ast.DFn (def, Ast.dummy_span))) idef.Ast.impl_methods
    | Ast.DTest (t, _) -> ex t.Ast.test_body
    | Ast.DSetup (e, _) | Ast.DSetupAll (e, _) -> ex e
    | Ast.DApp (a, _) -> ex a.Ast.app_body; Option.iter ex a.Ast.app_on_start; Option.iter ex a.Ast.app_on_stop
    | _ -> ()
  in
  (* The types a declaration writes outside expressions, each with the
     parameter position when it is a named function's parameter. *)
  let occurrences : (Ast.span * string) list ref = ref [] in
  let note t = occurrences := retired_in_ty !occurrences t in
  let note_params ps = List.iter (fun p -> Option.iter note (param_ty p)) ps in
  let note_plain_params (ps : Ast.param list) = List.iter (fun (p : Ast.param) -> Option.iter note p.Ast.param_ty) ps in
  let rec types_of_decl ~prefix ~top (d : Ast.decl) =
    match d with
    | Ast.DFn (def, _) when top && def.Ast.fn_name.Ast.txt = "main" ->
      (* `main`'s parameters are the deprecated request form (below); its
         return type is an ordinary type. *)
      Option.iter note def.Ast.fn_ret_ty
    | Ast.DFn (def, _) ->
      Option.iter note def.Ast.fn_ret_ty;
      (match def.Ast.fn_clauses with
       | c :: _ ->
         let retired = List.map (fun p -> Option.bind (param_ty p) cap_io_of <> None) c.Ast.fc_params in
         if List.exists Fun.id retired then
           fns := { fi_simple = def.Ast.fn_name.Ast.txt; fi_qual = prefix ^ def.Ast.fn_name.Ast.txt;
                    fi_arity = List.length c.Ast.fc_params; fi_clause = c; fi_retired = retired } :: !fns;
         (* the parameters' own occurrences are reported by the fn's
            diagnostic; anything nested deeper (`List(Cap(IO))`) here *)
         List.iter
           (fun p ->
              match param_ty p with
              | Some t when cap_io_of t = None -> note t
              | _ -> ())
           c.Ast.fc_params
       | [] -> ())
    | Ast.DLet (_, b, _) -> Option.iter note b.Ast.bind_ty
    | Ast.DType (_, _, _, td, _) | Ast.DAlwaysLinearType (_, _, _, td, _) -> (
      match td with
      | Ast.TDAlias (t, ps) -> note t; List.iter (fun (_, t) -> note t) ps
      | Ast.TDVariant vs -> List.iter (fun (v : Ast.variant) -> List.iter note v.Ast.var_args) vs
      | Ast.TDRecord fs -> List.iter (fun (f : Ast.field) -> note f.Ast.fld_ty) fs)
    | Ast.DActor (_, _, a, _) ->
      List.iter (fun (f : Ast.field) -> note f.Ast.fld_ty) a.Ast.actor_state;
      note_plain_params a.Ast.actor_init_params;
      List.iter (fun (h : Ast.actor_handler) -> note_plain_params h.Ast.ah_params) a.Ast.actor_handlers
    | Ast.DMod (nm, _, ds, _) -> List.iter (types_of_decl ~prefix:(prefix ^ nm.Ast.txt ^ ".") ~top:false) ds
    | Ast.DDescribe (_, ds, _) -> List.iter (types_of_decl ~prefix ~top:false) ds
    | Ast.DImpl (idef, _) ->
      List.iter
        (fun (_, (def : Ast.fn_def)) ->
           Option.iter note def.Ast.fn_ret_ty;
           List.iter (fun (c : Ast.fn_clause) -> note_params c.Ast.fc_params) def.Ast.fn_clauses)
        idef.Ast.impl_methods
    | Ast.DInterface (idef, _) -> List.iter (fun (md : Ast.method_decl) -> note md.Ast.md_ty) idef.Ast.iface_methods
    | _ -> ()
  in
  List.iter (types_of_decl ~prefix:"" ~top:true) decls;
  (* Types written inside expressions, and the calls the fixes edit. *)
  let calls : (string * Ast.expr list) list ref = ref [] in
  let narrows : Ast.span list ref = ref [] in
  let visit (e : Ast.expr) =
    match e with
    | Ast.ELet (b, _) -> Option.iter note b.Ast.bind_ty
    | Ast.ELam (ps, _, _) -> note_plain_params ps
    | Ast.ELetFn (_, ps, ret, _, _) -> note_plain_params ps; Option.iter note ret
    | Ast.EAnnot (_, t, _) -> note t
    | Ast.EApp (Ast.EVar { Ast.txt = "cap_narrow"; _ }, _, sp) -> narrows := sp :: !narrows
    | Ast.EApp (Ast.EVar f, args, _) -> calls := (f.Ast.txt, args) :: !calls
    | _ -> ()
  in
  List.iter (exprs_of_decl visit) decls;
  let span_of_expr = Typecheck_types.span_of_expr in
  (* ── main ── *)
  List.iter
    (function
      | Ast.DFn (def, _) when def.Ast.fn_name.Ast.txt = "main" -> (
        match def.Ast.fn_clauses with
        | c :: _ ->
          let kinds = List.map (fun p -> main_cap_kind (param_ty p)) c.Ast.fc_params in
          if List.exists Option.is_some kinds then begin
            let written = List.filter_map (Option.map snd) kinds in
            let uniq =
              L.normalize (List.fold_left (fun acc k -> if List.mem k acc then acc else acc @ [ k ]) [] written)
            in
            let first_sp = List.find_map (Option.map fst) kinds |> Option.get in
            let file = c.Ast.fc_params_span.Ast.file in
            let fix =
              match lines_of file with
              | None -> None
              | Some lines ->
                let all_caps = List.for_all Option.is_some kinds in
                let params_edit =
                  if all_caps then
                    Some [ Err.FReplace { span = c.Ast.fc_params_span; text = "()" } ]
                  else
                    let items =
                      List.map2
                        (fun p k ->
                           match param_start p, k with
                           | Some s, Some (sp, _) -> Some (s, end_of sp)
                           | Some s, None -> Some (s, s)
                           | None, _ -> None)
                        c.Ast.fc_params kinds
                    in
                    if List.for_all Option.is_some items then
                      Option.map (List.map deletion)
                        (delete_runs lines ~file (List.filter_map Fun.id items) (List.map Option.is_some kinds))
                    else None
                in
                (* The request: merged into an existing `needs` clause, or
                   written before the `do` that opens the body. *)
                let needs_edit =
                  match def.Ast.fn_needs with
                  | Some (_, nsp) ->
                    Some (Err.FReplace { span = { nsp with Ast.start_line = nsp.Ast.end_line; start_col = nsp.Ast.end_col };
                                         text = ", " ^ String.concat ", " uniq })
                  | None ->
                    let after = end_of c.Ast.fc_params_span in
                    let body = start_of (span_of_expr c.Ast.fc_body) in
                    let between = slice lines after body in
                    (* the last `do` before the body *)
                    let rec find_do i =
                      if i < 0 then None
                      else if i + 2 <= String.length between && String.sub between i 2 = "do"
                              && (i = 0 || not (Char.equal between.[i - 1] '_' || (between.[i - 1] >= 'a' && between.[i - 1] <= 'z')))
                              && (i + 2 = String.length between
                                  || not (between.[i + 2] = '_' || (between.[i + 2] >= 'a' && between.[i + 2] <= 'z')))
                      then Some i
                      else find_do (i - 1)
                    in
                    (match find_do (String.length between - 2) with
                     | None -> None
                     | Some i ->
                       let pre = String.sub between 0 i in
                       (* map the offset back to a position *)
                       let l = ref (fst after) and col = ref (snd after) in
                       String.iter (fun ch -> if ch = '\n' then (incr l; col := 0) else incr col) pre;
                       let at = { Ast.file; start_line = !l; start_col = !col; end_line = !l; end_col = !col } in
                       (* no return type is added: a `main` without one
                          returns whatever its last expression does *)
                       let text = "needs " ^ String.concat ", " uniq ^ " " in
                       Some (Err.FReplace { span = at; text }))
                in
                (match params_edit, needs_edit with
                 | Some ps, Some n -> Some (Err.FMulti (ps @ [ n ]))
                 | _ -> None)
            in
            let msg =
              Printf.sprintf
                "`main` asks for its authority with `Cap` parameters, which are deprecated and will be \
                 removed in the next release: a capability value grants nothing since the current \
                 authority replaced it.\n\
                 help: request it with a `needs` clause: `fn main() needs %s do`."
                (String.concat ", " uniq)
            in
            match fix with
            | Some fix -> Err.warning_with_fix ~code:Code.deprecated_main_cap errors ~span:first_sp ~fix msg
            | None -> Err.warning ~code:Code.deprecated_main_cap errors ~span:first_sp msg
          end
        | [] -> ())
      | _ -> ())
    decls;
  (* ── parameters of named functions ── *)
  let reported : (Ast.span, unit) Hashtbl.t = Hashtbl.create 16 in
  (* Arguments a fix deletes (a retired parameter's), so a `cap_narrow`
     inside one is not reported a second time. *)
  let dropped : Ast.span list ref = ref [] in
  List.iter
    (fun (fi : fn_info) ->
       let c = fi.fi_clause in
       let cap_sps =
         List.filter_map (fun p -> Option.bind (param_ty p) cap_io_of) c.Ast.fc_params
       in
       let first_sp, first_kind = List.hd cap_sps in
       List.iter (fun (sp, _) -> Hashtbl.replace reported sp ()) cap_sps;
       let file = first_sp.Ast.file in
       let fix =
         match lines_of file with
         | None -> None
         | Some lines ->
           let items =
             List.map
               (fun p ->
                  match param_start p, Option.bind (param_ty p) cap_io_of with
                  | Some s, Some (sp, _) -> Some (s, end_of sp)
                  | Some s, None -> Some (s, s)
                  | None, _ -> None)
               c.Ast.fc_params
           in
           let def_edits =
             if List.for_all Option.is_some items then
               delete_runs lines ~file (List.filter_map Fun.id items) fi.fi_retired
             else None
           in
           let matches name =
             name = fi.fi_simple || name = fi.fi_qual
             || String.ends_with ~suffix:("." ^ fi.fi_simple) name
                && String.ends_with ~suffix:name ("." ^ fi.fi_qual)
           in
           let call_edits =
             List.filter_map
               (fun (name, args) ->
                  if matches name && List.length args = fi.fi_arity then
                    let items = List.map (fun a -> let sp = span_of_expr a in (start_of sp, end_of sp)) args in
                    let afile = (span_of_expr (List.hd args)).Ast.file in
                    List.iter2 (fun a r -> if r then dropped := span_of_expr a :: !dropped) args fi.fi_retired;
                    if afile <> file then None
                    else delete_runs lines ~file items fi.fi_retired
                  else None)
               !calls
           in
           Option.map (fun d -> Err.FMulti (List.map deletion (d @ List.concat call_edits))) def_edits
       in
       let msg =
         Printf.sprintf
           "`%s` takes a `Cap(%s)` parameter, but capability values were retired: a function no \
            longer receives its authority, it uses the current authority, which `main`'s `needs` \
            clause asks for and each operation checks.\n\
            help: remove the parameter and the argument at each call; to state what `%s` may use, \
            give it a `needs` clause."
           fi.fi_simple first_kind fi.fi_simple
       in
       match fix with
       | Some fix -> Err.error_with_fix ~code:Code.cap_param_retired errors ~span:first_sp ~fix msg
       | None -> Err.error ~code:Code.cap_param_retired errors ~span:first_sp msg)
    (List.rev !fns);
  (* ── every other `Cap(IO.X)` ── *)
  List.iter
    (fun (sp, k) ->
       if not (Hashtbl.mem reported sp) then begin
         Hashtbl.replace reported sp ();
         Err.error ~code:Code.cap_param_retired errors ~span:sp
           (Printf.sprintf
              "`Cap(%s)` was retired: capability values grant nothing since the current authority \
               replaced them.\n\
               help: remove it; code uses the current authority, which `main`'s `needs` clause asks \
               for and each operation checks."
              k)
       end)
    (List.rev !occurrences);
  (* ── cap_narrow ── *)
  let within (inner : Ast.span) (outer : Ast.span) =
    inner.Ast.file = outer.Ast.file
    && compare (start_of outer) (start_of inner) <= 0
    && compare (end_of inner) (end_of outer) <= 0
  in
  List.iter
    (fun sp ->
       if not (List.exists (within sp) !dropped) then
       Err.error ~code:Code.cap_narrow_retired errors ~span:sp
         "`cap_narrow` was retired with the capability values it narrowed.\n\
          help: remove the call; to run code under less authority, use `restrict SCOPE do ... end`.")
    (List.rev !narrows)
