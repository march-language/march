(** Helpers shared by [Analysis] and the code-action engines.

    Every definition here moved verbatim out of [analysis.ml]. They are the
    transitive closure of what [Code_actions_ast] and [Code_actions_diag]
    reach, computed mechanically; nothing was rewritten. [Analysis]
    re-exports the whole module with [include Analysis_util], so
    [Analysis.rename_at], [Analysis.references_at] and the rest keep their
    existing names for every consumer. *)

include Analysis_types

let rec find_uses name (e : Ast.expr) acc =
  match e with
  | Ast.EVar n when n.txt = name -> n.span :: acc
  | Ast.EApp (f, args, _) ->
    find_uses name f
      (List.fold_left (fun a e -> find_uses name e a) acc args)
  | Ast.ELam (_, body, _) -> find_uses name body acc
  | Ast.EBlock (es, _) ->
    List.fold_left (fun a e -> find_uses name e a) acc es
  | Ast.ELet (b, _) -> find_uses name b.bind_expr acc
  | Ast.ELetFn (_, _, _, body, _) -> find_uses name body acc
  | Ast.EMatch (subj, brs, _) ->
    find_uses name subj
      (List.fold_left
         (fun a (br : Ast.branch) -> find_uses name br.branch_body a)
         acc brs)
  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
    List.fold_left (fun a e -> find_uses name e a) acc es
  | Ast.EIf (c, t, f, _) ->
    find_uses name c (find_uses name t (find_uses name f acc))
  | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) ->
    find_uses name a (find_uses name b acc)
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
  | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) ->
    find_uses name e acc
  | Ast.ERecord (fs, _) ->
    List.fold_left (fun a (_, e) -> find_uses name e a) acc fs
  | Ast.ERecordUpdate (e, fs, _) ->
    find_uses name e
      (List.fold_left (fun a (_, e2) -> find_uses name e2 a) acc fs)
  | _ -> acc

(** Extract the source span from any expression node. *)
let span_of_expr = function
  | Ast.ELit (_, sp) | Ast.EApp (_, _, sp) | Ast.ECon (_, _, sp)
  | Ast.ELam (_, _, sp) | Ast.EBlock (_, sp) | Ast.ELet (_, sp)
  | Ast.EMatch (_, _, sp) | Ast.ETuple (_, sp) | Ast.ERecord (_, sp)
  | Ast.ERecordUpdate (_, _, sp) | Ast.EField (_, _, sp)
  | Ast.EIf (_, _, _, sp) | Ast.ECond (_, sp) | Ast.EPipe (_, _, sp) | Ast.EAnnot (_, _, sp)
  | Ast.EHole (_, sp) | Ast.EAtom (_, _, sp) | Ast.ESend (_, _, sp)
  | Ast.ESpawn (_, sp) | Ast.EDbg (_, sp) | Ast.ELetFn (_, _, _, _, sp)
  | Ast.ELetQ (_, _, _, sp) | Ast.ELetStar (_, _, _, sp)
  | Ast.EAssert (_, sp) -> sp
  | Ast.ESigil (_, _, sp) -> sp
  | Ast.EVar name -> name.Ast.span
  | Ast.EResultRef _ -> Ast.dummy_span

(** Operators whose results count as "pending work" after a call returns,
    preventing tail-call optimisation. *)
let march_operators =
  ["+"; "-"; "*"; "/"; "%"; "&&"; "||"; "=="; "!="; "<>"; "<"; ">"; "<="; ">=";
   "++"; "^"; "not"]

let is_march_operator name = List.mem name march_operators

(** Names bound by a pattern (used to extend the scope in closures). *)
let rec pat_bound_names (pat : Ast.pattern) =
  match pat with
  | Ast.PatVar n -> [n.txt]
  | Ast.PatAs (p, n, _) -> n.txt :: pat_bound_names p
  | Ast.PatTuple (ps, _) | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) ->
    List.concat_map pat_bound_names ps
  | Ast.PatRecord (fs, _) ->
    List.concat_map (fun (_, p) -> pat_bound_names p) fs
  | _ -> []

(** Visit every sub-expression of [e] (including [e] itself), pre-order. *)
let rec iter_expr (f : Ast.expr -> unit) (e : Ast.expr) =
  f e;
  match e with
  | Ast.EApp (g, args, _) -> iter_expr f g; List.iter (iter_expr f) args
  | Ast.ECon (_, args, _) | Ast.EAtom (_, args, _) | Ast.ETuple (args, _) ->
    List.iter (iter_expr f) args
  | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> iter_expr f body
  | Ast.EBlock (es, _) -> List.iter (iter_expr f) es
  | Ast.ELet (b, _) -> iter_expr f b.Ast.bind_expr
  | Ast.EMatch (subj, brs, _) ->
    iter_expr f subj;
    List.iter (fun (br : Ast.branch) ->
        (match br.branch_guard with Some g -> iter_expr f g | None -> ());
        iter_expr f br.branch_body) brs
  | Ast.ECond (arms, _) ->
    List.iter (fun (c, b) -> iter_expr f c; iter_expr f b) arms
  | Ast.EIf (c, t, el, _) -> iter_expr f c; iter_expr f t; iter_expr f el
  | Ast.EPipe (l, r, _) | Ast.ESend (l, r, _) -> iter_expr f l; iter_expr f r
  | Ast.ERecord (fs, _) -> List.iter (fun (_, e2) -> iter_expr f e2) fs
  | Ast.ERecordUpdate (e2, fs, _) ->
    iter_expr f e2; List.iter (fun (_, e3) -> iter_expr f e3) fs
  | Ast.EField (e2, _, _) | Ast.EAnnot (e2, _, _)
  | Ast.ESpawn (e2, _) | Ast.EAssert (e2, _) | Ast.ESigil (_, e2, _)
  | Ast.EDbg (Some e2, _) -> iter_expr f e2
  | Ast.ELetQ (_, r, c, _) | Ast.ELetStar (_, r, c, _) -> iter_expr f r; iter_expr f c
  | Ast.ELit _ | Ast.EVar _ | Ast.EHole _ | Ast.EResultRef _
  | Ast.EDbg (None, _) -> ()

(** Collect free variable names in [body] that are not the lambda's own
    [params].  These are the values the closure must capture. *)
let lambda_free_vars (params : Ast.param list) (body : Ast.expr) : string list =
  let param_names = List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) params in
  let fvs : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  let rec go (bound : string list) (e : Ast.expr) =
    match e with
    | Ast.EVar n ->
      if not (List.mem n.txt bound) && not (is_march_operator n.txt)
      then Hashtbl.replace fvs n.txt ()
    | Ast.ELam (ps, lbody, _) ->
      let inner = List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) ps @ bound in
      go inner lbody
    | Ast.ELetFn (name, ps, _, fbody, _) ->
      let inner = name.txt :: List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) ps @ bound in
      go inner fbody
    | Ast.EBlock (es, _) ->
      let rec go_block bound = function
        | [] -> ()
        | (Ast.ELet (b, _)) :: rest ->
          go bound b.Ast.bind_expr;
          go_block (pat_bound_names b.Ast.bind_pat @ bound) rest
        | (Ast.ELetFn (name, ps, _, fbody, _)) :: rest ->
          let inner = name.txt :: List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) ps @ bound in
          go inner fbody;
          go_block (name.txt :: bound) rest
        | e :: rest -> go bound e; go_block bound rest
      in
      go_block bound es
    | Ast.ELet (b, _) -> go bound b.Ast.bind_expr
    | Ast.EMatch (subj, branches, _) ->
      go bound subj;
      List.iter (fun (br : Ast.branch) ->
          let names = pat_bound_names br.Ast.branch_pat in
          go (names @ bound) br.Ast.branch_body
        ) branches
    | Ast.EApp (f, args, _) -> go bound f; List.iter (go bound) args
    | Ast.EIf (c, t, f, _) -> go bound c; go bound t; go bound f
    | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> go bound a; go bound b
    | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
      List.iter (go bound) es
    | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> go bound e) fs
    | Ast.ERecordUpdate (e, fs, _) ->
      go bound e; List.iter (fun (_, e2) -> go bound e2) fs
    | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _)
    | Ast.EDbg (Some e, _) | Ast.ESpawn (e, _) | Ast.EAssert (e, _) ->
      go bound e
    | _ -> ()
  in
  go param_names body;
  Hashtbl.fold (fun k () acc -> k :: acc) fvs []

(** Walk [e] collecting perf insights for lambdas with ≥3 captures. *)
(* Collect every lambda in [body] with its genuine local capture set (≥2
   values), as (span, sorted-caps). [is_global] excludes top-level/stdlib names. *)
(* Each entry: (lambda span, lambda-body span, sorted genuine captures). *)
let collect_lambda_captures is_global (body : Ast.expr)
  : (Ast.span * Ast.span * string list) list =
  let found = ref [] in
  (* [iter_expr] is the canonical generic visitor: it descends INTO ELam bodies
     (so nested lambdas are still collected, matching the old [walk lbody]) and
     covers every form including ECond and ESigil (the ~H interpolation) that
     the old hand walk fell through on. *)
  iter_expr (fun e ->
      match e with
      | Ast.ELam (params, lbody, sp) ->
        let caps =
          lambda_free_vars params lbody
          |> List.filter (fun nm -> not (is_global nm))
          |> List.sort_uniq String.compare
        in
        if List.length caps >= 2 then
          found := (sp, span_of_expr lbody, caps) :: !found
      | _ -> ())
    body;
  !found

(** Convert a [perf_insight] to an LSP [Diagnostic.t]. *)
let perf_insight_to_diag (pi : perf_insight) : Lsp.Types.Diagnostic.t =
  let range = Pos.span_to_lsp_range pi.pi_span in
  let severity, code = match pi.pi_kind with
    | NonTailCall _    -> Lsp.Types.DiagnosticSeverity.Warning, "perf/non-tail-call"
    | ActorSendCopy _  -> Lsp.Types.DiagnosticSeverity.Warning, "perf/actor-send-copy"
    | ClosureCapture _ -> Lsp.Types.DiagnosticSeverity.Hint,    "perf/closure-capture"
    | StackPromoted _  -> Lsp.Types.DiagnosticSeverity.Hint,    "perf/stack-promoted"
    | FbipReuse _      -> Lsp.Types.DiagnosticSeverity.Hint,    "perf/fbip-reuse"
    | TirIndirectCall _ -> Lsp.Types.DiagnosticSeverity.Hint,   "perf/indirect-call"
    | IndirectCall _    -> Lsp.Types.DiagnosticSeverity.Hint,   "perf/indirect-call"
    | RecursiveAlloc _  -> Lsp.Types.DiagnosticSeverity.Hint,   "perf/recursive-alloc"
    | Parallelizable _  -> Lsp.Types.DiagnosticSeverity.Hint,   "perf/parallelizable"
  in
  Lsp.Types.Diagnostic.create
    ~range
    ~severity
    ~message:(`String pi.pi_message)
    ~source:"march"
    ~code:(`String code)
    ()

(** Parameter names bound by a function clause (named or bare-pattern). *)
let clause_param_names (cl : Ast.fn_clause) : string list =
  List.filter_map (function
      | Ast.FPNamed p -> Some p.Ast.param_name.Ast.txt
      | Ast.FPPat (Ast.PatVar n) -> Some n.Ast.txt
      | _ -> None
    ) cl.Ast.fc_params

(** True when [e] contains a call to [fn_name] (self-recursion). *)
let rec contains_call fn_name (e : Ast.expr) =
  match e with
  | Ast.EApp (Ast.EVar n, args, _) ->
    n.Ast.txt = fn_name || List.exists (contains_call fn_name) args
  | Ast.EApp (f, args, _) ->
    contains_call fn_name f || List.exists (contains_call fn_name) args
  | Ast.ELet (b, _) -> contains_call fn_name b.Ast.bind_expr
  | Ast.EBlock (es, _) -> List.exists (contains_call fn_name) es
  | Ast.EMatch (subj, brs, _) ->
    contains_call fn_name subj ||
    List.exists (fun (br : Ast.branch) -> contains_call fn_name br.Ast.branch_body) brs
  | Ast.EIf (c, t, f, _) ->
    contains_call fn_name c || contains_call fn_name t || contains_call fn_name f
  | Ast.EPipe (x, y, _) | Ast.ESend (x, y, _) ->
    contains_call fn_name x || contains_call fn_name y
  | Ast.ETuple (es, _) | Ast.EAtom (_, es, _) | Ast.ECon (_, es, _) ->
    List.exists (contains_call fn_name) es
  | Ast.ERecord (fs, _) -> List.exists (fun (_, e) -> contains_call fn_name e) fs
  | Ast.ERecordUpdate (e, fs, _) ->
    contains_call fn_name e || List.exists (fun (_, e) -> contains_call fn_name e) fs
  | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
  | Ast.EDbg (Some e, _) | Ast.EAssert (e, _) -> contains_call fn_name e
  | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> contains_call fn_name body
  | _ -> false

(** Walk [TArrow] chain to collect stringified parameter types. *)
let rec unwrap_arrows (ty : Tc.ty) : string list * string =
  match ty with
  | Tc.TArrow (param, rest) ->
    let (more, ret) = unwrap_arrows rest in
    (Tc.pp_ty param :: more, ret)
  | _                       -> ([], Tc.pp_ty ty)

(* Raw inferred type of the smallest user-file span containing the cursor.
   Only considers current-file spans (the type_map is shared with stdlib whose
   spans collide on line/col). *)
let local_symbol_at (a : t) ~line ~character : int option =
  let best = ref None in
  let consider sp id =
    if Pos.span_contains sp ~line ~character then
      match !best with
      | Some (bsp, _) when not (Pos.span_smaller sp bsp) -> ()
      | _ -> best := Some (sp, id)
  in
  Hashtbl.iter (fun sp id -> consider sp id) a.sym_uses;
  Hashtbl.iter (fun id sp -> consider sp id) a.sym_defs;
  Option.map snd !best

(* A span belongs to the file being analysed (not stdlib). Position scans that
   find "the name under the cursor" MUST filter by this: stdlib decls share the
   same (line,col) coordinate space, so an unfiltered scan can match a stdlib
   span that merely collides with the cursor's line/col. *)
let span_in_user_file (a : t) (sp : Ast.span) : bool =
  sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>"

let locations_of_spans (a : t) (spans : Ast.span list) : Lsp.Types.Location.t list =
  List.filter_map (fun (sp : Ast.span) ->
      if sp = Ast.dummy_span then None
      else
        let path =
          if sp.Ast.file = "" || sp.Ast.file = "<unknown>" then a.filename
          else sp.Ast.file
        in
        let uri   = Lsp.Types.DocumentUri.of_path path in
        let range = Pos.span_to_lsp_range sp in
        Some (Lsp.Types.Location.create ~uri ~range)
    ) spans

(* Resolve the symbol under the cursor to (definition span option, use spans).
   Shared by find-references and documentHighlight so the two never diverge.
   Locals resolve by scope (shadow-correct); everything else by name. *)
let symbol_spans_at (a : t) ~line ~character
    : (Ast.span option * Ast.span list) option =
  match local_symbol_at a ~line ~character with
  | Some id ->
    let use_spans = try Hashtbl.find a.sym_id_uses id with Not_found -> [] in
    Some (Hashtbl.find_opt a.sym_defs id, use_spans)
  | None ->
    let name_opt =
      let from_use =
        Hashtbl.fold (fun sp name found ->
            match found with
            | Some _ -> found
            | None   ->
              if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
              else None
          ) a.use_map None
      in
      match from_use with
      | Some _ -> from_use
      | None ->
        Hashtbl.fold (fun name sp found ->
            match found with
            | Some _ -> found
            | None   ->
              if span_in_user_file a sp && Pos.span_contains sp ~line ~character then Some name
              else None
          ) a.def_map None
    in
    match name_opt with
    | None -> None
    | Some name ->
      let use_spans =
        match Hashtbl.find_opt a.refs_map name with
        | Some spans -> spans
        | None       -> []
      in
      Some (Hashtbl.find_opt a.def_map name, use_spans)

let references_at (a : t) ~include_declaration ~line ~character
    : Lsp.Types.Location.t list =
  match symbol_spans_at a ~line ~character with
  | None -> []
  | Some (def_opt, use_spans) ->
    let all_spans =
      if include_declaration then
        match def_opt with Some d -> d :: use_spans | None -> use_spans
      else use_spans
    in
    locations_of_spans a all_spans

(** Return a flat list of [TextEdit.t] replacing every occurrence of the
    symbol at the cursor with [new_name], including its definition site. *)
let rename_at (a : t) ~line ~character ~new_name
    : Lsp.Types.TextEdit.t list =
  let locs =
    references_at a ~include_declaration:true ~line ~character
  in
  List.map (fun (loc : Lsp.Types.Location.t) ->
      Lsp.Types.TextEdit.create ~range:loc.range ~newText:new_name
    ) locs

(** Convert 0-indexed (line, character) to a byte offset in [src]. *)
let offset_of_pos src line character =
  let n = String.length src in
  let cur_line = ref 0 in
  let i = ref 0 in
  while !i < n && !cur_line < line do
    if src.[!i] = '\n' then incr cur_line;
    incr i
  done;
  !i + character

(* ==================================================================== *)
(* AST-driven code action helpers (Phase 2+).                           *)
(*                                                                       *)
(* These walk the retained raw user AST ([a.decls]) to power the         *)
(* refactoring actions that need structural information: pipe            *)
(* introduce/remove, extract/inline variable, expand/collapse function   *)
(* capture, typed-hole fills, and actor/protocol scaffolding.            *)
(* ==================================================================== *)

(** Byte [start, end) of a span within [src]. *)
let span_byte_bounds src (sp : Ast.span) =
  let s = offset_of_pos src (sp.Ast.start_line - 1) sp.Ast.start_col in
  let e = offset_of_pos src (sp.Ast.end_line   - 1) sp.Ast.end_col in
  (s, e)

(** Source text covered by [sp], or "" if out of bounds. *)
let slice_span src (sp : Ast.span) =
  let (s, e) = span_byte_bounds src sp in
  if e > s && s >= 0 && e <= String.length src then String.sub src s (e - s)
  else ""

(** Leading whitespace (indentation) of the source line [line0] (0-indexed). *)
let indent_of_line src line0 =
  let start = offset_of_pos src line0 0 in
  let n = String.length src in
  let buf = Buffer.create 8 in
  let i = ref start in
  while !i < n && (src.[!i] = ' ' || src.[!i] = '\t') do
    Buffer.add_char buf src.[!i]; incr i
  done;
  Buffer.contents buf

(** Visit every expression occurring in declaration [d] (recursing into
    nested modules). *)
let rec iter_decl_exprs (f : Ast.expr -> unit) (d : Ast.decl) =
  match d with
  | Ast.DFn (fn, _) ->
    List.iter (fun (cl : Ast.fn_clause) ->
        (match cl.fc_guard with Some g -> iter_expr f g | None -> ());
        iter_expr f cl.fc_body) fn.fn_clauses
  | Ast.DLet (_, b, _) -> iter_expr f b.Ast.bind_expr
  | Ast.DActor (_, _, adef, _) ->
    iter_expr f adef.Ast.actor_init;
    List.iter (fun (h : Ast.actor_handler) -> iter_expr f h.ah_body)
      adef.Ast.actor_handlers
  | Ast.DTest (t, _) -> iter_expr f t.Ast.test_body
  | Ast.DDescribe (_, decls, _) -> List.iter (iter_decl_exprs f) decls
  | Ast.DMod (_, _, decls, _) -> List.iter (iter_decl_exprs f) decls
  | _ -> ()

(** All sub-expressions across [decls]. *)
let all_exprs (decls : Ast.decl list) : Ast.expr list =
  let acc = ref [] in
  List.iter (iter_decl_exprs (fun e -> acc := e :: !acc)) decls;
  !acc

(** The smallest expression satisfying [pred] that contains the cursor. *)
let smallest_expr_at (a : t) ~line ~character ~(pred : Ast.expr -> bool)
    : Ast.expr option =
  let cands =
    List.filter (fun e ->
        let sp = span_of_expr e in
        (sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>")
        && Pos.span_contains sp ~line ~character
        && pred e)
      (all_exprs a.decls)
  in
  match cands with
  | [] -> None
  | x :: xs ->
    Some (List.fold_left (fun best e ->
        if Pos.span_smaller (span_of_expr e) (span_of_expr best) then e else best)
        x xs)

(** Find the byte offset of name [name] in [src] starting from [hint_ofs]. *)
let find_name_ofs src name hint_ofs =
  let sn  = String.length name in
  let len = String.length src in
  let rec go i =
    if i + sn > len then None
    else if String.sub src i sn = name then Some i
    else go (i + 1)
  in
  go hint_ofs

(** Find the byte offset of the [end] keyword immediately before the end of
    [span] in [src].  Scans backwards to locate it. *)
let find_end_before_span src (span : Ast.span) =
  let end_ofs = offset_of_pos src (span.Ast.end_line - 1) span.Ast.end_col in
  let sn = 3 in
  let rec go i =
    if i < sn then None
    else
      let candidate = String.sub src (i - sn) sn in
      if candidate = "end" then begin
        let before_ok =
          i - sn = 0 ||
          (let c = src.[i - sn - 1] in c = ' ' || c = '\n' || c = '\t')
        in
        let after_ok =
          i >= String.length src ||
          (let c = src.[i] in c = ' ' || c = '\n' || c = '\t' || c = '\r')
        in
        if before_ok && after_ok then Some (i - sn)
        else go (i - 1)
      end else
        go (i - 1)
  in
  go (min end_ofs (String.length src))

(* ------------------------------------------------------------------ *)
(* Diagnostics-driven quickfix framework                              *)
(* ------------------------------------------------------------------ *)

(** A fix generator takes the analysis result and a diagnostic and returns
    zero or more code actions that would fix that diagnostic. *)
type fix_gen = t -> Lsp.Types.Diagnostic.t -> Lsp.Types.CodeAction.t list

(** Registry mapping diagnostic code strings to their fix generators.
    Register new fixes with [register_fix]. *)
let fix_registry : (string, fix_gen) Hashtbl.t = Hashtbl.create 8

(** Run all registered fix generators for every diagnostic in [diags] and
    return the collected code actions. *)
let apply_fix_registry (a : t) (diags : Lsp.Types.Diagnostic.t list)
    : Lsp.Types.CodeAction.t list =
  List.concat_map (fun (diag : Lsp.Types.Diagnostic.t) ->
      let code = match diag.code with
        | Some (`String s) -> Some s
        | _ -> None
      in
      match code with
      | None -> []
      | Some c ->
        (match Hashtbl.find_opt fix_registry c with
         | None -> []
         | Some gen -> gen a diag)
    ) diags

(** Render a surface [Ast.ty] back to March source syntax (best-effort,
    used for generated scaffolds). *)
let rec surface_ty (t : Ast.ty) : string =
  match t with
  | Ast.TyCon (n, [])   -> n.Ast.txt
  | Ast.TyCon (n, args) ->
    n.Ast.txt ^ "(" ^ String.concat ", " (List.map surface_ty args) ^ ")"
  | Ast.TyVar n         -> n.Ast.txt
  | Ast.TyArrow (a, b)  -> surface_ty a ^ " -> " ^ surface_ty b
  | Ast.TyTuple ts      -> "(" ^ String.concat ", " (List.map surface_ty ts) ^ ")"
  | Ast.TyRecord fs     ->
    "{ " ^ String.concat ", "
             (List.map (fun (n, t) -> n.Ast.txt ^ ": " ^ surface_ty t) fs) ^ " }"
  | Ast.TyLinear (_, t) -> "linear " ^ surface_ty t
  | Ast.TyNat n         -> string_of_int n
  | Ast.TyNatOp (op, a, b) ->
    surface_ty a ^ (match op with Ast.NatAdd -> " + " | Ast.NatMul -> " * ")
    ^ surface_ty b
  | Ast.TyChan (r, p)   -> "Chan(" ^ r.Ast.txt ^ ", " ^ p.Ast.txt ^ ")"
  (* Best-effort (A1a): predicate elided in generated scaffolds. *)
  | Ast.TyRefine (base, None, _)   -> "{ " ^ surface_ty base ^ " | ... }"
  | Ast.TyRefine (base, Some n, _) -> "{ " ^ n.Ast.txt ^ " : " ^ surface_ty base ^ " | ... }"

(** Split a surface arrow type into (param types, return type). *)
let rec split_arrow (t : Ast.ty) : Ast.ty list * Ast.ty =
  match t with
  | Ast.TyArrow (a, b) -> let ps, r = split_arrow b in (a :: ps, r)
  | _ -> ([], t)

let scheme_ty = function Tc.Mono t -> t | Tc.Poly (_, _, t) -> t

(** Head type-constructor name of a resolved [Tc.ty], if any. *)
let ty_head_name (t : Tc.ty) : string option =
  match Tc.repr t with
  | Tc.TCon (n, _) -> Some n
  | _ -> None

(** Number of leading arrows (arity) of a resolved [Tc.ty]. *)
let rec ty_arrow_arity (t : Tc.ty) : int =
  match Tc.repr t with
  | Tc.TArrow (_, rest) -> 1 + ty_arrow_arity rest
  | _ -> 0

(** Is [name] a plain identifier (vs. an operator like `+`, `==`, `|>`)? *)
let is_ident_name name =
  String.length name > 0 &&
  (let c = name.[0] in
   (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_')

(* ==================================================================== *)
(* AST-driven code actions (Phase 2+).                                  *)
(* ==================================================================== *)

(** Replace whole-identifier occurrences in [text] per the (name → replacement)
    [subs] table. Identifier-aware (won't match substrings); does not track
    shadowing — adequate for inlining a small single-clause function body. *)
let substitute_idents (text : string) (subs : (string * string) list) : string =
  let buf = Buffer.create (String.length text) in
  let n = String.length text in
  let is_id c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_' || c = '\''
  in
  let i = ref 0 in
  while !i < n do
    let c = text.[!i] in
    if is_id c && (!i = 0 || not (is_id text.[!i - 1])) then begin
      let j = ref !i in
      while !j < n && is_id text.[!j] do incr j done;
      let word = String.sub text !i (!j - !i) in
      (match List.assoc_opt word subs with
       | Some repl -> Buffer.add_string buf repl
       | None -> Buffer.add_string buf word);
      i := !j
    end else begin Buffer.add_char buf c; incr i end
  done;
  Buffer.contents buf

