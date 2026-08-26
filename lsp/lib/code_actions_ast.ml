(** AST-driven code actions: refactorings offered from the shape of the
    source alone — pipe, extract/inline variable, capture collapse/expand,
    typed-hole fill, auto-import, impl/actor/session scaffolding, destructure,
    extract/inline function, organize imports, doc comments, auto-alias.

    [ast_code_actions] moved here verbatim from [analysis.ml]. The
    diagnostic-driven engine lives in [Code_actions_diag], which opens this
    module and splices these actions into its own result at exactly the
    position the single original call site used. *)

open Analysis_util

let ast_code_actions (a : t) ~line ~character : Lsp.Types.CodeAction.t list =
  let open Lsp.Types in
  let uri = DocumentUri.of_path a.filename in
  let src = a.src in
  let mk_we edits = WorkspaceEdit.create ~changes:[(uri, edits)] () in
  let range_of_span (sp : Ast.span) =
    Range.create
      ~start:(Position.create ~line:(sp.Ast.start_line - 1) ~character:sp.Ast.start_col)
      ~end_:(Position.create ~line:(sp.Ast.end_line - 1) ~character:sp.Ast.end_col)
  in
  let at sp = Pos.span_contains sp ~line ~character in

  (* ---- P1.2: Introduce pipe ---- *)
  (* f(arg0, rest...)  →  arg0 |> f(rest...)  *)
  let introduce_pipe_actions =
    let pred = function
      | Ast.EApp (callee, _ :: _, _) ->
        (match callee with
         | Ast.EVar n -> is_ident_name n.Ast.txt
         | Ast.EField _ -> true
         | _ -> false)
      | _ -> false
    in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EApp (callee, arg0 :: rest, sp)) ->
      let callee_text = slice_span src (span_of_expr callee) in
      let arg0_text   = slice_span src (span_of_expr arg0) in
      if callee_text = "" || arg0_text = "" then []
      else begin
        let rest_text = List.map (fun e -> slice_span src (span_of_expr e)) rest in
        let new_text =
          Printf.sprintf "%s |> %s(%s)" arg0_text callee_text
            (String.concat ", " rest_text)
        in
        let edit = TextEdit.create ~range:(range_of_span sp) ~newText:new_text in
        [CodeAction.create ~title:"Introduce pipe"
           ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
      end
    | _ -> []
  in

  (* ---- P1.2: Remove pipe ---- *)
  (* a |> f(b) |> g()  →  g(f(a, b))  *)
  let remove_pipe_actions =
    (* Pick the LARGEST pipe chain containing the cursor so the whole chain
       collapses in one action. *)
    let pipes =
      List.filter (function
          | Ast.EPipe (_, _, sp) -> at sp
          | _ -> false)
        (all_exprs a.decls)
    in
    match pipes with
    | [] -> []
    | x :: xs ->
      let outer =
        List.fold_left (fun best e ->
            if Pos.span_smaller (span_of_expr best) (span_of_expr e) then e else best)
          x xs
      in
      let rec to_call (e : Ast.expr) : string =
        match e with
        | Ast.EPipe (l, r, _) ->
          let lt = to_call l in
          (match r with
           | Ast.EApp (callee, args, _) ->
             let callee_text = slice_span src (span_of_expr callee) in
             let arg_texts = List.map (fun e -> slice_span src (span_of_expr e)) args in
             Printf.sprintf "%s(%s)" callee_text (String.concat ", " (lt :: arg_texts))
           | Ast.EVar n -> Printf.sprintf "%s(%s)" n.Ast.txt lt
           | _ -> Printf.sprintf "%s(%s)" (slice_span src (span_of_expr r)) lt)
        | _ -> slice_span src (span_of_expr e)
      in
      let sp = span_of_expr outer in
      let edit = TextEdit.create ~range:(range_of_span sp) ~newText:(to_call outer) in
      [CodeAction.create ~title:"Remove pipe"
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- P1.3: Extract variable ---- *)
  let extract_var_actions =
    let pred = function
      | Ast.EApp _ | Ast.ECon _ | Ast.EField _ | Ast.ERecord _
      | Ast.ERecordUpdate _ | Ast.ETuple _ | Ast.EAtom _ | Ast.EPipe _ -> true
      | _ -> false
    in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      let sp = span_of_expr e in
      let expr_text = slice_span src sp in
      if expr_text = "" then []
      else begin
        (* Suggest a name from the inferred type, else a generic one. *)
        let name =
          match Hashtbl.find_opt a.type_map sp with
          | Some ty ->
            (match ty_head_name ty with
             | Some h when is_ident_name h -> String.lowercase_ascii h
             | _ -> "value")
          | None -> "value"
        in
        let indent = indent_of_line src (sp.Ast.start_line - 1) in
        let insert_pos =
          Position.create ~line:(sp.Ast.start_line - 1) ~character:0 in
        let insert_edit =
          TextEdit.create
            ~range:(Range.create ~start:insert_pos ~end_:insert_pos)
            ~newText:(Printf.sprintf "%slet %s = %s\n" indent name expr_text)
        in
        let replace_edit =
          TextEdit.create ~range:(range_of_span sp) ~newText:name in
        [CodeAction.create ~title:"Extract variable"
           ~kind:CodeActionKind.RefactorExtract
           ~edit:(mk_we [insert_edit; replace_edit]) ()]
      end
  in

  (* ---- P1.4: Inline variable ---- *)
  let inline_var_actions =
    (* Locate a `let <name> = rhs` whose name is under the cursor. *)
    let found = ref None in
    let rec scan_block (es : Ast.expr list) =
      List.iter (fun e -> match e with
          | Ast.ELet (b, let_sp) ->
            (match b.Ast.bind_pat with
             | Ast.PatVar nm when at nm.Ast.span ->
               found := Some (nm, b.Ast.bind_expr, let_sp)
             | _ -> ());
            scan_one b.Ast.bind_expr
          | _ -> scan_one e) es
    and scan_one e =
      match e with
      | Ast.EBlock (es, _) -> scan_block es
      | Ast.ELam (_, body, _) | Ast.ELetFn (_, _, _, body, _) -> scan_one body
      | Ast.EMatch (subj, brs, _) ->
        scan_one subj;
        List.iter (fun (br : Ast.branch) -> scan_one br.branch_body) brs
      | Ast.EIf (c, t, el, _) -> scan_one c; scan_one t; scan_one el
      | Ast.EApp (f, args, _) -> scan_one f; List.iter scan_one args
      | Ast.EPipe (l, r, _) | Ast.ESend (l, r, _) -> scan_one l; scan_one r
      | Ast.ELet (b, _) -> scan_one b.Ast.bind_expr
      | _ -> ()
    in
    List.iter (fun d -> iter_decl_exprs (fun e ->
        match e with Ast.EBlock (es, _) -> scan_block es | _ -> ()) d) a.decls;
    match !found with
    | None -> []
    | Some (nm, rhs, let_sp) ->
      (* Use spans gathered by the (proven) consumption pass. *)
      let uses =
        List.fold_left (fun acc (c : consumption) ->
            if c.con_name = nm.Ast.txt && c.con_def = let_sp then c.con_uses @ acc
            else acc) [] a.consumption
      in
      if uses = [] then []
      else begin
        let rhs_text = slice_span src (span_of_expr rhs) in
        (* Parenthesize compound RHS so precedence is preserved at use sites. *)
        let needs_parens = match rhs with
          | Ast.EPipe _ | Ast.EIf _ | Ast.EMatch _ | Ast.ELam _ | Ast.EAnnot _ -> true
          | Ast.EApp (Ast.EVar n, _ :: _, _) -> not (is_ident_name n.Ast.txt)
          | _ -> false
        in
        let value = if needs_parens then "(" ^ rhs_text ^ ")" else rhs_text in
        let use_edits =
          List.map (fun (sp : Ast.span) ->
              TextEdit.create ~range:(range_of_span sp) ~newText:value) uses
        in
        (* Delete the whole let line(s). *)
        let del_edit =
          TextEdit.create
            ~range:(Range.create
                      ~start:(Position.create ~line:(let_sp.Ast.start_line - 1) ~character:0)
                      ~end_:(Position.create ~line:let_sp.Ast.end_line ~character:0))
            ~newText:""
        in
        [CodeAction.create
           ~title:(Printf.sprintf "Inline variable `%s`" nm.Ast.txt)
           ~kind:CodeActionKind.RefactorInline
           ~edit:(mk_we (del_edit :: use_edits)) ()]
      end
  in

  (* ---- P1.9: Collapse function capture (eta-contraction) ---- *)
  (* fn (x) -> f(x)  →  f  *)
  let collapse_capture_actions =
    let pred = function Ast.ELam _ -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.ELam (params, Ast.EApp (callee, args, _), sp))
      when List.length params = List.length args && params <> [] ->
      let param_names = List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) params in
      let args_are_params =
        List.for_all2 (fun pn a -> match a with
            | Ast.EVar n -> n.Ast.txt = pn
            | _ -> false) param_names args
      in
      (* The callee must not itself mention the bound params. *)
      let callee_text = slice_span src (span_of_expr callee) in
      let callee_ok =
        match callee with
        | Ast.EVar n -> not (List.mem n.Ast.txt param_names)
        | Ast.EField _ -> true
        | _ -> false
      in
      if args_are_params && callee_ok && callee_text <> "" then
        [CodeAction.create
           ~title:(Printf.sprintf "Collapse to `%s`" callee_text)
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:callee_text])
           ()]
      else []
    | _ -> []
  in

  (* ---- P1.9: Expand function capture (eta-expansion) ---- *)
  (* a function-valued identifier `f`  →  fn (_x0, _x1) -> f(_x0, _x1) *)
  let expand_capture_actions =
    (* Spans of identifiers appearing in callee position — expanding those
       would be wrong (it would wrap the function being applied). *)
    let callee_spans = Hashtbl.create 16 in
    List.iter (function
        | Ast.EApp (callee, _, _) ->
          Hashtbl.replace callee_spans (span_of_expr callee) ()
        | _ -> ())
      (all_exprs a.decls);
    let pred = function
      | Ast.EVar _ as e -> not (Hashtbl.mem callee_spans (span_of_expr e))
      | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EVar n as e) when is_ident_name n.Ast.txt ->
      let sp = span_of_expr e in
      let arity =
        match Hashtbl.find_opt a.type_map sp with
        | Some ty -> ty_arrow_arity ty
        | None ->
          (match List.assoc_opt n.Ast.txt a.vars with
           | Some sch -> ty_arrow_arity (scheme_ty sch)
           | None -> 0)
      in
      if arity <= 0 || arity > 8 then []
      else begin
        let ps = List.init arity (fun i -> Printf.sprintf "_x%d" i) in
        let new_text =
          Printf.sprintf "fn (%s) -> %s(%s)"
            (String.concat ", " ps) n.Ast.txt (String.concat ", " ps)
        in
        [CodeAction.create ~title:"Expand to lambda"
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:new_text]) ()]
      end
    | _ -> []
  in

  (* ---- P2.1: Typed hole fills ---- *)
  let hole_fill_actions =
    let pred = function Ast.EHole _ -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EHole (_, sp)) ->
      let expected = Option.map Tc.repr (Hashtbl.find_opt a.type_map sp) in
      let suggestions =
        match expected with
        | None -> []
        | Some ty ->
          let head = ty_head_name ty in
          (* Literals for base types. *)
          let lits = match head with
            | Some "Int"    -> ["0"]
            | Some "Float"  -> ["0.0"]
            | Some "String" -> ["\"\""]
            | Some "Bool"   -> ["true"; "false"]
            | Some "Char"   -> ["' '"]
            | Some "Unit"   -> ["()"]
            | _ -> []
          in
          (* Constructors producing the expected type. Prefer the unqualified
             form; skip module-qualified duplicates ("Mod.Ctor"). *)
          let ctors = match head with
            | None -> []
            | Some h ->
              List.filter_map (fun (cname, parent) ->
                  if String.contains cname '.' then None
                  else if parent = h || parent = h ^ "()" then
                    let ar = try List.assoc cname a.ctor_arities with Not_found -> 0 in
                    if ar = 0 then Some cname
                    else Some (Printf.sprintf "%s(%s)" cname
                                 (String.concat ", " (List.init ar (fun _ -> "?"))))
                  else None) a.ctors
          in
          (* In-scope (non-function) variables whose head type matches. *)
          let vars = match head with
            | None -> []
            | Some h ->
              List.filter_map (fun (vn, sch) ->
                  if String.length vn > 0 && vn.[0] = '_' then None
                  else if String.contains vn '.' then None
                  else
                    let ty = scheme_ty sch in
                    match ty_head_name ty with
                    | Some vh when vh = h && is_ident_name vn
                                && ty_arrow_arity ty = 0
                                && not (List.mem_assoc vn a.ctors) -> Some vn
                    | _ -> None) a.vars
          in
          let all = lits @ ctors @ vars in
          (* De-dup preserving order, cap the count. *)
          let seen = Hashtbl.create 16 in
          List.filter (fun s ->
              if Hashtbl.mem seen s then false
              else (Hashtbl.add seen s (); true)) all
      in
      let suggestions = List.filteri (fun i _ -> i < 12) suggestions in
      List.map (fun s ->
          CodeAction.create
            ~title:(Printf.sprintf "Fill hole with `%s`" s)
            ~kind:CodeActionKind.QuickFix
            ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:s]) ())
        suggestions
    | _ -> []
  in

  (* ---- P1.5: Auto-import (use ModuleName) ---- *)
  let auto_import_actions =
    (* Build an index of unqualified-name → modules that define it, from the
       qualified entries in def_map (keys like "List.map"). *)
    let head_name e = match e with
      | Ast.EVar n -> Some (n.Ast.txt, n.Ast.span)
      | Ast.ECon (n, _, _) -> Some (n.Ast.txt, n.Ast.span)
      | Ast.EField (Ast.ECon (m, [], _), fld, fsp) ->
        Some (m.Ast.txt ^ "." ^ fld.Ast.txt, fsp)
      (* `name(args)` and `Mod.fn(args)` — peer through the call to the callee. *)
      | Ast.EApp (Ast.EVar n, _, _) -> Some (n.Ast.txt, n.Ast.span)
      | Ast.EApp (Ast.EField (Ast.ECon (m, [], _), fld, fsp), _, _) ->
        Some (m.Ast.txt ^ "." ^ fld.Ast.txt, fsp)
      | _ -> None
    in
    let pred e = head_name e <> None in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      (match head_name e with
       | None -> []
       | Some (qname, _) ->
         (* Resolve the base name that may need importing. *)
         let base, modpath =
           match String.index_opt qname '.' with
           | Some i -> (String.sub qname 0 i, Some (String.sub qname 0 i))
           | None -> (qname, None)
         in
         (* Already resolvable? Then no import needed. *)
         let in_scope =
           List.mem_assoc base a.vars
           || List.mem_assoc base a.ctors
           || List.mem_assoc base a.types
           || (match modpath with Some m -> List.mem_assoc m a.types | None -> false)
         in
         if in_scope then []
         else begin
           (* Find modules that define `base` as `Mod.base`. *)
           let modules =
             Hashtbl.fold (fun k _ acc ->
                 match String.rindex_opt k '.' with
                 | Some i when String.sub k (i + 1) (String.length k - i - 1) = base ->
                   let m = String.sub k 0 i in
                   if List.mem m acc then acc else m :: acc
                 | _ -> acc) a.def_map []
           in
           let modules = List.sort String.compare modules in
           (* Insert `use Mod.{base}` at the top of the first user decl's line. *)
           let insert_line =
             List.fold_left (fun best d ->
                 let sp = match d with
                   | Ast.DFn (fn, _) -> fn.fn_name.span
                   | Ast.DLet (_, _, sp) | Ast.DType (_, _, _, _, sp)
                   | Ast.DActor (_, _, _, sp) | Ast.DImpl (_, sp)
                   | Ast.DUse (_, sp) -> sp
                   | Ast.DMod (n, _, _, _) -> n.Ast.span
                   | _ -> Ast.dummy_span
                 in
                 if sp.Ast.start_line > 0 && sp.Ast.start_line - 1 < best
                 then sp.Ast.start_line - 1 else best)
               max_int a.decls
           in
           let insert_line = if insert_line = max_int then 0 else insert_line in
           let indent = indent_of_line src insert_line in
           List.map (fun m ->
               let pos = Position.create ~line:insert_line ~character:0 in
               let edit = TextEdit.create
                   ~range:(Range.create ~start:pos ~end_:pos)
                   ~newText:(Printf.sprintf "%suse %s.{%s}\n" indent m base) in
               CodeAction.create
                 ~title:(Printf.sprintf "Import `%s` from `%s`" base m)
                 ~kind:CodeActionKind.QuickFix ~edit:(mk_we [edit]) ())
             modules
         end)
  in

  (* ---- P1.6: Generate interface impl scaffold ---- *)
  let impl_scaffold_actions =
    let impl_at =
      List.find_map (function
          | Ast.DImpl (idef, sp) when at sp -> Some (idef, sp)
          | _ -> None) a.decls
    in
    match impl_at with
    | None -> []
    | Some (idef, sp) ->
      (match List.assoc_opt idef.Ast.impl_iface.Ast.txt a.interfaces with
       | None -> []
       | Some iface ->
         let implemented =
           List.map (fun (n, _) -> n.Ast.txt) idef.Ast.impl_methods in
         let missing =
           List.filter (fun (md : Ast.method_decl) ->
               not (List.mem md.Ast.md_name.txt implemented))
             iface.Ast.iface_methods
         in
         if missing = [] then []
         else begin
           let indent = indent_of_line src (sp.Ast.start_line - 1) ^ "  " in
           let stub (md : Ast.method_decl) =
             let params, _ret = split_arrow md.Ast.md_ty in
             let param_list =
               List.mapi (fun i pt -> Printf.sprintf "p%d: %s" i (surface_ty pt)) params in
             Printf.sprintf "%sfn %s(%s) do ? end\n"
               indent md.Ast.md_name.txt (String.concat ", " param_list)
           in
           let body = String.concat "" (List.map stub missing) in
           (* Insert just before the impl block's closing `end`. *)
           (match find_end_before_span src sp with
            | None -> []
            | Some end_ofs ->
              let l = ref 0 and c = ref 0 and cl = ref 0 and cc = ref 0 in
              String.iteri (fun i _ ->
                  if i = end_ofs then begin l := !cl; c := !cc end;
                  if src.[i] = '\n' then begin incr cl; cc := 0 end else incr cc) src;
              let pos = Position.create ~line:!l ~character:!c in
              let edit = TextEdit.create
                  ~range:(Range.create ~start:pos ~end_:pos) ~newText:body in
              [CodeAction.create
                 ~title:(Printf.sprintf "Implement %d missing method(s)"
                           (List.length missing))
                 ~kind:CodeActionKind.QuickFix ~edit:(mk_we [edit]) ()])
         end)
  in

  (* ---- P3.1: Actor boilerplate (client wrappers) ---- *)
  let actor_boilerplate_actions =
    let actor_at =
      List.find_map (function
          | Ast.DActor (_, n, adef, sp) when at n.Ast.span || at sp ->
            Some (n.Ast.txt, adef, sp)
          | _ -> None) a.decls
    in
    match actor_at with
    | None -> []
    | Some (name, adef, sp) ->
      let wrappers =
        List.map (fun (h : Ast.actor_handler) ->
            let msg = h.Ast.ah_msg.txt in
            let params =
              List.map (fun (p : Ast.param) -> p.Ast.param_name.txt) h.Ast.ah_params in
            let plist = String.concat ", " ("pid" :: params) in
            let payload =
              if params = [] then msg
              else Printf.sprintf "%s(%s)" msg (String.concat ", " params) in
            Printf.sprintf "  fn %s(%s) do send(pid, %s) end\n"
              (String.lowercase_ascii msg) plist payload)
          adef.Ast.actor_handlers
      in
      let body =
        Printf.sprintf "\nmod %sClient do\n%send\n" name (String.concat "" wrappers) in
      (* Insert after the actor declaration's last line. *)
      let pos = Position.create ~line:sp.Ast.end_line ~character:0 in
      let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:body in
      [CodeAction.create
         ~title:(Printf.sprintf "Generate %sClient module" name)
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- P3.2: Session-type scaffolding ---- *)
  let session_scaffold_actions =
    let proto_at =
      List.find_map (function
          | Ast.DProtocol (n, pd, sp) when at n.Ast.span || at sp ->
            Some (n.Ast.txt, pd, sp)
          | _ -> None) a.decls
    in
    match proto_at with
    | None -> []
    | Some (name, pd, sp) ->
      let rec steps_text indent ss =
        String.concat ""
          (List.map (fun (st : Ast.protocol_step) -> match st with
               | Ast.ProtoMsg (from, _to, ty) ->
                 Printf.sprintf "%s-- %s sends %s\n%ssend(ch, ?)\n%slet _ = receive(ch)\n"
                   indent from.Ast.txt (surface_ty ty) indent indent
               | Ast.ProtoLoop inner ->
                 Printf.sprintf "%sloop do\n%s%send\n" indent
                   (steps_text (indent ^ "  ") inner) indent
               | Ast.ProtoChoice (role, branches) ->
                 Printf.sprintf "%s-- choice by %s\n%smatch receive(ch) do\n%s%send\n"
                   indent role.Ast.txt indent
                   (String.concat ""
                      (List.map (fun (lbl, inner) ->
                           Printf.sprintf "%s  %s ->\n%s" indent lbl.Ast.txt
                             (steps_text (indent ^ "    ") inner)) branches))
                   indent
               | Ast.ProtoStop _ ->
                 Printf.sprintf "%s-- stop (loop exit)\n" indent)
             ss)
      in
      let body =
        Printf.sprintf "\nfn handle_%s(ch) do\n%s  close(ch)\nend\n"
          (String.lowercase_ascii name) (steps_text "  " pd.Ast.proto_steps) in
      let pos = Position.create ~line:sp.Ast.end_line ~character:0 in
      let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:body in
      [CodeAction.create
         ~title:(Printf.sprintf "Generate %s session handler" name)
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- P2.7 / case-to-match: convert `if` to `match` ---- *)
  let if_to_match_actions =
    let pred = function Ast.EIf _ -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EIf (cond, t, el, sp))
      when slice_span src (span_of_expr t) <> ""
        && slice_span src (span_of_expr el) <> ""
        && slice_span src (span_of_expr cond) <> "" ->
      let t_text = slice_span src (span_of_expr t) in
      (* Equality-chain form: if subj == K do .. else if subj == K2 .. *)
      let eq_parts e = match e with
        | Ast.EApp (Ast.EVar op, [Ast.EVar subj; rhs], _) when op.Ast.txt = "==" ->
          Some (subj.Ast.txt, slice_span src (span_of_expr rhs))
        | _ -> None
      in
      let new_text =
        match eq_parts cond with
        | Some (subj, k0) ->
          let buf = Buffer.create 128 in
          Buffer.add_string buf (Printf.sprintf "match %s do\n" subj);
          let rec emit kpat body rest =
            Buffer.add_string buf (Printf.sprintf "  %s -> %s\n" kpat
                                     (slice_span src (span_of_expr body)));
            match rest with
            | Ast.EIf (c2, t2, e2, _) ->
              (match eq_parts c2 with
               | Some (s2, k2) when s2 = subj -> emit k2 t2 e2
               | _ -> Buffer.add_string buf (Printf.sprintf "  _ -> %s\n"
                                               (slice_span src (span_of_expr rest))))
            | _ -> Buffer.add_string buf (Printf.sprintf "  _ -> %s\n"
                                            (slice_span src (span_of_expr rest)))
          in
          emit k0 t el;
          Buffer.add_string buf "end";
          Buffer.contents buf
        | None ->
          let e_text = slice_span src (span_of_expr el) in
          Printf.sprintf "match %s do\n  true -> %s\n  false -> %s\nend"
            (slice_span src (span_of_expr cond)) t_text e_text
      in
      [CodeAction.create ~title:"Convert if to match"
         ~kind:CodeActionKind.RefactorRewrite
         ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:new_text]) ()]
    | _ -> []
  in

  (* ---- P3.3: Linear consumption audit ---- *)
  (* Flag a linear binding (a `linear` function parameter, or a `let linear`
     binding) that is never consumed, or report how many times it is. *)
  let linear_audit_actions =
    (* Collect (name, name_span, body_expr) for every linear parameter. *)
    let lin_params = ref [] in
    let scan_clause (cl : Ast.fn_clause) =
      List.iter (function
          | Ast.FPNamed p | Ast.FPDefault (p, _)
            when p.Ast.param_lin = Ast.Linear || p.Ast.param_lin = Ast.Affine ->
            lin_params := (p.Ast.param_name, cl.fc_body) :: !lin_params
          | _ -> ()) cl.fc_params
    in
    let rec scan_decl (d : Ast.decl) =
      match d with
      | Ast.DFn (fn, _) -> List.iter scan_clause fn.fn_clauses
      | Ast.DMod (_, _, ds, _) -> List.iter scan_decl ds
      | _ -> ()
    in
    List.iter scan_decl a.decls;
    List.filter_map (fun ((nm : Ast.name), body) ->
        if not (Pos.span_contains nm.Ast.span ~line ~character) then None
        else begin
          let uses = find_uses nm.Ast.txt body [] in
          if uses = [] then
            Some (CodeAction.create
                    ~title:(Printf.sprintf
                              "Linear `%s` is never consumed (must be used exactly once)"
                              nm.Ast.txt)
                    ~kind:CodeActionKind.QuickFix
                    ~edit:(mk_we []) ())
          else
            Some (CodeAction.create
                    ~title:(Printf.sprintf "Linear `%s` is consumed at %d site(s)"
                              nm.Ast.txt (List.length uses))
                    ~kind:CodeActionKind.QuickFix
                    ~edit:(mk_we []) ())
        end)
      !lin_params
  in

  (* ---- Destruct / case-split: variant-typed expr -> exhaustive match ---- *)
  let destruct_actions =
    let pred = function
      | Ast.EVar _ | Ast.EField _ | Ast.EApp _ -> true
      | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      let sp = span_of_expr e in
      (match Option.map Tc.repr (Hashtbl.find_opt a.type_map sp) with
       | Some (Tc.TCon (tyname, _)) ->
         (* Constructors of [tyname], bare names only (drop qualified dups). *)
         let seen = Hashtbl.create 8 in
         let ctors =
           List.filter_map (fun (cname, parent) ->
               if parent = tyname && not (String.contains cname '.')
                  && not (Hashtbl.mem seen cname)
               then (Hashtbl.add seen cname (); Some cname) else None)
             a.ctors in
         let subj = slice_span src sp in
         if ctors = [] || subj = "" then []
         else begin
           let indent = indent_of_line src (sp.Ast.start_line - 1) in
           let arms =
             List.map (fun c ->
                 let ar = try List.assoc c a.ctor_arities with Not_found -> 0 in
                 let binders =
                   if ar = 0 then ""
                   else "(" ^ String.concat ", "
                          (List.init ar (fun i -> Printf.sprintf "x%d" i)) ^ ")" in
                 Printf.sprintf "%s  %s%s -> ?" indent c binders) ctors in
           let new_text =
             Printf.sprintf "match %s do\n%s\n%send" subj
               (String.concat "\n" arms) indent in
           [CodeAction.create
              ~title:(Printf.sprintf "Destruct `%s` into a match" subj)
              ~kind:CodeActionKind.RefactorRewrite
              ~edit:(mk_we [TextEdit.create ~range:(range_of_span sp) ~newText:new_text]) ()]
         end
       | _ -> [])
  in

  (* ---- Extract function: selected expr -> top-level fn capturing free locals ---- *)
  let extract_fn_actions =
    let pred = function
      | Ast.EApp _ | Ast.ECon _ | Ast.EField _ | Ast.ERecord _
      | Ast.ERecordUpdate _ | Ast.ETuple _ | Ast.EPipe _ | Ast.EIf _
      | Ast.EMatch _ | Ast.EAtom _ -> true
      | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | None -> []
    | Some e ->
      let sp = span_of_expr e in
      let expr_text = slice_span src sp in
      if expr_text = "" then []
      else begin
        (* Scoped free-variable analysis: collect EVar uses not bound within e. *)
        let pat_names p =
          let acc = ref [] in
          let rec go = function
            | Ast.PatVar n -> acc := n.Ast.txt :: !acc
            | Ast.PatAs (p, n, _) -> go p; acc := n.Ast.txt :: !acc
            | Ast.PatCon (_, ps) | Ast.PatAtom (_, ps, _) | Ast.PatTuple (ps, _) ->
              List.iter go ps
            | Ast.PatRecord (fs, _) -> List.iter (fun (_, p) -> go p) fs
            | _ -> () in
          go p; !acc
        in
        let frees = ref [] in
        let rec fv bound (e : Ast.expr) =
          match e with
          | Ast.EVar n -> if not (List.mem n.Ast.txt bound) then frees := (n.Ast.txt, n.Ast.span) :: !frees
          | Ast.ELit _ | Ast.EHole _ | Ast.EResultRef _ | Ast.EDbg (None, _) -> ()
          | Ast.EApp (g, args, _) -> fv bound g; List.iter (fv bound) args
          | Ast.ECon (_, args, _) | Ast.EAtom (_, args, _) | Ast.ETuple (args, _) ->
            List.iter (fv bound) args
          | Ast.ELam (ps, body, _) ->
            let b = List.fold_left (fun b (p : Ast.param) -> p.Ast.param_name.txt :: b) bound ps in
            fv b body
          | Ast.ELetFn (n, ps, _, body, _) ->
            let b = n.Ast.txt :: List.fold_left (fun b (p : Ast.param) -> p.Ast.param_name.txt :: b) bound ps in
            fv b body
          | Ast.EBlock (es, _) ->
            ignore (List.fold_left (fun b e -> match e with
                | Ast.ELet (bd, _) -> fv b bd.Ast.bind_expr; pat_names bd.Ast.bind_pat @ b
                | _ -> fv b e; b) bound es)
          | Ast.ELet (bd, _) -> fv bound bd.Ast.bind_expr
          | Ast.EMatch (s, brs, _) ->
            fv bound s;
            List.iter (fun (br : Ast.branch) ->
                let b = pat_names br.branch_pat @ bound in
                (match br.branch_guard with Some g -> fv b g | None -> ());
                fv b br.branch_body) brs
          | Ast.EIf (c, t, el, _) -> fv bound c; fv bound t; fv bound el
          | Ast.ECond (arms, _) -> List.iter (fun (c, b) -> fv bound c; fv bound b) arms
          | Ast.EPipe (a, b, _) | Ast.ESend (a, b, _) -> fv bound a; fv bound b
          | Ast.ERecord (fs, _) -> List.iter (fun (_, e) -> fv bound e) fs
          | Ast.ERecordUpdate (e, fs, _) -> fv bound e; List.iter (fun (_, e) -> fv bound e) fs
          | Ast.ELetQ (p, r, c, _) | Ast.ELetStar (p, r, c, _) ->
            fv bound r;
            let b = pat_names p @ bound in
            fv b c
          | Ast.EField (e, _, _) | Ast.EAnnot (e, _, _) | Ast.ESpawn (e, _)
          | Ast.EAssert (e, _) | Ast.ESigil (_, e, _) | Ast.EDbg (Some e, _) -> fv bound e
        in
        fv [] e;
        (* Keep only locals (names not in the module/global env), de-duped, in use order. *)
        let seen = Hashtbl.create 16 in
        let params =
          List.rev !frees
          |> List.filter_map (fun (name, span) ->
              if Hashtbl.mem seen name then None
              else if List.mem_assoc name a.vars then (Hashtbl.add seen name (); None)
              else begin
                Hashtbl.add seen name ();
                let ty_s = match Hashtbl.find_opt a.type_map span with
                  | Some ty -> Some (Tc.pp_ty (Tc.repr ty)) | None -> None in
                Some (name, ty_s)
              end)
        in
        let param_text =
          String.concat ", "
            (List.map (fun (n, t) -> match t with Some t -> n ^ ": " ^ t | None -> n) params) in
        let arg_text = String.concat ", " (List.map fst params) in
        (* Insert the new function before the enclosing top-level fn. *)
        let enclosing_line = ref None in
        let rec scan_decl (d : Ast.decl) =
          match d with
          | Ast.DFn (fn, _) ->
            List.iter (fun (cl : Ast.fn_clause) ->
                let bsp = span_of_expr cl.Ast.fc_body in
                if Pos.span_contains bsp ~line ~character then
                  enclosing_line := Some fn.Ast.fn_name.Ast.span.Ast.start_line) fn.Ast.fn_clauses
          | Ast.DMod (_, _, ds, _) -> List.iter scan_decl ds
          | _ -> () in
        List.iter scan_decl a.decls;
        match !enclosing_line with
        | None -> []
        | Some fn_line ->
          let indent = indent_of_line src (fn_line - 1) in
          let new_fn =
            Printf.sprintf "%sfn extracted(%s) do\n%s  %s\n%send\n\n"
              indent param_text indent expr_text indent in
          let insert_pos = Position.create ~line:(fn_line - 1) ~character:0 in
          let insert_edit =
            TextEdit.create ~range:(Range.create ~start:insert_pos ~end_:insert_pos) ~newText:new_fn in
          let call_text = Printf.sprintf "extracted(%s)" arg_text in
          let replace_edit = TextEdit.create ~range:(range_of_span sp) ~newText:call_text in
          [CodeAction.create ~title:"Extract function"
             ~kind:CodeActionKind.RefactorExtract
             ~edit:(mk_we [insert_edit; replace_edit]) ()]
      end
  in

  (* ---- Organize imports: sort + de-duplicate `use` declarations ---- *)
  let organize_imports_actions =
    (* Collect every `use` declaration (including inside nested modules). *)
    let uses = ref [] in
    let rec scan (d : Ast.decl) =
      match d with
      | Ast.DUse (_, sp) -> uses := sp :: !uses
      | Ast.DMod (_, _, ds, _) -> List.iter scan ds
      | _ -> () in
    List.iter scan a.decls;
    let use_spans =
      List.rev !uses
      |> List.filter (fun (sp : Ast.span) ->
          sp.Ast.file = a.filename || sp.Ast.file = "" || sp.Ast.file = "<unknown>")
      |> List.sort (fun (a : Ast.span) b ->
          compare (a.Ast.start_line, a.Ast.start_col) (b.Ast.start_line, b.Ast.start_col))
    in
    if List.length use_spans < 2 then []
    else begin
      let texts = List.map (fun sp -> String.trim (slice_span src sp)) use_spans in
      (* Sorted + de-duplicated, first-occurrence wins. *)
      let seen = Hashtbl.create 16 in
      let organized =
        List.sort_uniq String.compare
          (List.filter (fun t ->
               if t = "" || Hashtbl.mem seen t then false
               else (Hashtbl.add seen t (); true)) texts)
      in
      (* Only offer if it actually changes the order or removes duplicates. *)
      if organized = texts then []
      else begin
        let first = List.hd use_spans in
        let indent = indent_of_line src (first.Ast.start_line - 1) in
        let block = String.concat ("\n" ^ indent) organized in
        (* Replace the first use with the organized block; delete the rest's lines. *)
        let first_edit =
          TextEdit.create ~range:(range_of_span first) ~newText:block in
        let delete_edits =
          List.filter_map (fun (sp : Ast.span) ->
              if sp == first then None
              else
                let r = Range.create
                    ~start:(Position.create ~line:(sp.Ast.start_line - 1) ~character:0)
                    ~end_:(Position.create ~line:sp.Ast.end_line ~character:0) in
                Some (TextEdit.create ~range:r ~newText:""))
            use_spans
        in
        [CodeAction.create ~title:"Organize imports"
           ~kind:CodeActionKind.SourceOrganizeImports
           ~edit:(mk_we (first_edit :: delete_edits)) ()]
      end
    end
  in

  (* ---- Generate doc comment (Feature 20) ---- *)
  (* Cursor on an undocumented function name → insert a scaffolded doc string. *)
  let doc_comment_actions =
    let found = ref None in
    let rec scan (d : Ast.decl) =
      match d with
      | Ast.DFn (fn, dsp) when fn.Ast.fn_doc = None && at fn.Ast.fn_name.Ast.span ->
        found := Some (fn, dsp)
      | Ast.DMod (_, _, ds, _) -> List.iter scan ds
      | _ -> ()
    in
    List.iter scan a.decls;
    match !found with
    | None -> []
    | Some (fn, dsp) ->
      let pnames = match fn.Ast.fn_clauses with cl :: _ -> clause_param_names cl | [] -> [] in
      let args =
        if pnames = [] then ""
        else "\n\nArguments:\n" ^ String.concat "\n" (List.map (fun n -> "- " ^ n) pnames)
      in
      let ret = match fn.Ast.fn_ret_ty with Some _ -> "\n\nReturns: TODO" | None -> "" in
      let indent = String.make dsp.Ast.start_col ' ' in
      let scaffold =
        Printf.sprintf "doc \"TODO: describe %s.%s%s\"\n%s" fn.Ast.fn_name.Ast.txt args ret indent
      in
      let pos = Position.create ~line:(dsp.Ast.start_line - 1) ~character:dsp.Ast.start_col in
      let edit = TextEdit.create ~range:(Range.create ~start:pos ~end_:pos) ~newText:scaffold in
      [CodeAction.create ~title:"Generate doc comment"
         ~kind:CodeActionKind.RefactorRewrite ~edit:(mk_we [edit]) ()]
  in

  (* ---- Inline function (Feature 10b) ---- *)
  (* Cursor on a call f(args) where f is a single-clause, non-recursive function
     with simple-name params → substitute the body, params → arg expressions. *)
  let inline_fn_actions =
    let pred = function Ast.EApp (Ast.EVar _, _, _) -> true | _ -> false in
    match smallest_expr_at a ~line ~character ~pred with
    | Some (Ast.EApp (Ast.EVar fname, args, callsp)) ->
      let target = ref None in
      let rec scan (d : Ast.decl) =
        match d with
        | Ast.DFn (fn, _) when fn.Ast.fn_name.Ast.txt = fname.Ast.txt -> target := Some fn
        | Ast.DMod (_, _, ds, _) -> List.iter scan ds
        | _ -> ()
      in
      List.iter scan a.decls;
      (match !target with
       | Some fn when List.length fn.Ast.fn_clauses = 1 ->
         let cl = List.hd fn.Ast.fn_clauses in
         let pnames = clause_param_names cl in
         if List.length pnames = List.length args
            && List.length pnames = List.length cl.Ast.fc_params  (* all params are simple names *)
            && not (contains_call fn.Ast.fn_name.Ast.txt cl.Ast.fc_body)  (* non-recursive *)
         then begin
           let arg_texts =
             List.map (fun e ->
                 let t = slice_span src (span_of_expr e) in
                 match e with Ast.EVar _ | Ast.ELit _ -> t | _ -> "(" ^ t ^ ")") args
           in
           let body_text = slice_span src (span_of_expr cl.Ast.fc_body) in
           let substituted = substitute_idents body_text (List.combine pnames arg_texts) in
           let edit =
             TextEdit.create ~range:(range_of_span callsp) ~newText:("(" ^ substituted ^ ")")
           in
           [CodeAction.create ~title:(Printf.sprintf "Inline function `%s`" fname.Ast.txt)
              ~kind:CodeActionKind.RefactorInline ~edit:(mk_we [edit]) ()]
         end else []
       | _ -> [])
    | _ -> []
  in

  (* ---- Auto-alias for a repeated module prefix (Feature 13a) ---- *)
  (* Cursor on a qualified `A.B.foo` whose multi-segment module prefix `A.B`
     appears >= 3 times → insert `alias A.B` and rewrite uses to `B.foo`. *)
  let auto_alias_actions =
    let rec module_prefix = function
      | Ast.EVar n          -> Some n.Ast.txt
      | Ast.ECon (n, [], _) -> Some n.Ast.txt
      | Ast.EField (inner, f, _) ->
        (match module_prefix inner with Some p -> Some (p ^ "." ^ f.Ast.txt) | None -> None)
      | _ -> None
    in
    let rec root_span = function
      | Ast.EVar n          -> Some n.Ast.span
      | Ast.ECon (n, _, _)  -> Some n.Ast.span
      | Ast.EField (inner, _, _) -> root_span inner
      | _ -> None
    in
    (* (prefix, field, full-chain span) for every qualified field access. The
       node's own span covers only the field, so span the whole `A.B.foo`. *)
    let quals =
      List.filter_map (fun e -> match e with
          | Ast.EField (base, field, _) ->
            (match module_prefix base, root_span base with
             | Some p, Some rs when String.contains p '.' ->
               let full = { Ast.file = rs.Ast.file;
                            start_line = rs.Ast.start_line; start_col = rs.Ast.start_col;
                            end_line = field.Ast.span.Ast.end_line;
                            end_col = field.Ast.span.Ast.end_col } in
               Some (p, field, full)
             | _ -> None)
          | _ -> None)
        (all_exprs a.decls)
    in
    let count p = List.length (List.filter (fun (p', _, _) -> p' = p) quals) in
    match List.find_opt (fun (_, _, sp) -> at sp) quals with
    | Some (prefix, _, _) when count prefix >= 3 ->
      let short =
        match List.rev (String.split_on_char '.' prefix) with s :: _ -> s | [] -> prefix in
      (* Rewrite each `prefix.field` → `short.field`. *)
      let rewrites =
        List.filter_map (fun (p, field, sp) ->
            if p = prefix
            then Some (TextEdit.create ~range:(range_of_span sp)
                         ~newText:(short ^ "." ^ field.Ast.txt))
            else None) quals
      in
      (* Insert `alias <prefix>` before the first declaration of the module
         body (the file's top module body is stored directly in [a.decls]). *)
      let decl_line (d : Ast.decl) = match d with
        | Ast.DFn (fn, _)         -> fn.Ast.fn_name.Ast.span.Ast.start_line
        | Ast.DType (_, _, _, _, sp) | Ast.DLet (_, _, sp)
        | Ast.DApp (_, sp) | Ast.DImpl (_, sp) | Ast.DAlias (_, sp) -> sp.Ast.start_line
        | Ast.DMod (n, _, _, _) | Ast.DActor (_, n, _, _) -> n.Ast.span.Ast.start_line
        | _ -> max_int
      in
      let first = List.fold_left (fun acc d -> min acc (decl_line d)) max_int a.decls in
      if first = max_int then []
      else begin
        let indent = String.make 2 ' ' in
        let pos = Position.create ~line:(first - 1) ~character:0 in
        let alias_edit =
          TextEdit.create ~range:(Range.create ~start:pos ~end_:pos)
            ~newText:(Printf.sprintf "%salias %s\n" indent prefix)
        in
        [CodeAction.create
           ~title:(Printf.sprintf "Add `alias %s` and shorten %d use(s)"
                     prefix (List.length rewrites))
           ~kind:CodeActionKind.RefactorRewrite
           ~edit:(mk_we (alias_edit :: rewrites)) ()]
      end
    | _ -> []
  in

  (* ---- Extract closure captures into a record (data clump in a closure) ---- *)
  (* Cursor on a lambda capturing >=2 genuine local values → insert a record
     `let captured = { a = a, b = b }` before the enclosing statement and rewrite
     the body's captures to `captured.a`. Globals/top-level fns are not captures. *)
  (* Multi-site extract: when the cursor lambda shares its genuine capture set
     with ≥1 other closure in the same function, offer to group those values
     into ONE shared record and rewrite EVERY sharing closure's body. This
     mirrors the closure-capture hint, which only fires for a repeated clump. *)
  let extract_captures_actions =
    let is_global n = List.mem_assoc n a.vars in
    (* Inclusive span ⊇ span (boundary-safe: `let f = <lambda>` ends exactly
       where the lambda ends). *)
    let contains (outer : Ast.span) (inner : Ast.span) =
      (outer.Ast.start_line < inner.Ast.start_line
       || (outer.Ast.start_line = inner.Ast.start_line && outer.Ast.start_col <= inner.Ast.start_col))
      && (outer.Ast.end_line > inner.Ast.end_line
          || (outer.Ast.end_line = inner.Ast.end_line && outer.Ast.end_col >= inner.Ast.end_col))
    in
    let span_size (s : Ast.span) =
      (s.Ast.end_line - s.Ast.start_line, s.Ast.end_col - s.Ast.start_col)
    in
    match smallest_expr_at a ~line ~character ~pred:(function Ast.ELam _ -> true | _ -> false) with
    | Some (Ast.ELam (params, body, lam_sp)) ->
      let caps =
        lambda_free_vars params body
        |> List.filter (fun n -> not (is_global n))
        |> List.sort_uniq String.compare
      in
      if List.length caps < 2 then []
      else begin
        (* Find the innermost function-clause body containing the cursor lambda —
           the scope shared by all sibling closures. *)
        let fn_bodies =
          let acc = ref [] in
          let rec go (d : Ast.decl) = match d with
            | Ast.DFn (fn, _) ->
              List.iter (fun (cl : Ast.fn_clause) -> acc := cl.Ast.fc_body :: !acc) fn.Ast.fn_clauses
            | Ast.DMod (_, _, decls, _) | Ast.DDescribe (_, decls, _) -> List.iter go decls
            | _ -> ()
          in
          List.iter go a.decls; !acc
        in
        let scope =
          List.fold_left (fun best b ->
              let bsp = span_of_expr b in
              if contains bsp lam_sp then
                match best with
                | Some (bestsp, _) when span_size bestsp <= span_size bsp -> best
                | _ -> Some (bsp, b)
              else best)
            None fn_bodies
        in
        match scope with
        | None -> []
        | Some (_, scope_body) ->
          (* Every closure in this function with the IDENTICAL capture set. *)
          let group =
            collect_lambda_captures is_global scope_body
            |> List.filter (fun (_, _, cs) -> cs = caps)
          in
          if List.length group < 2 then []   (* lone closure: no warning, no extract *)
          else begin
            (* Each closure's innermost enclosing block statement. *)
            let stmt_of (lsp : Ast.span) =
              let target = ref None in
              iter_expr (fun e ->
                  match e with
                  | Ast.EBlock (es, _) ->
                    List.iter (fun el ->
                        let esp = span_of_expr el in
                        if contains esp lsp then target := Some esp) es
                  | _ -> ()) scope_body;
              !target
            in
            let stmts = List.filter_map (fun (lsp, _, _) -> stmt_of lsp) group in
            if List.length stmts <> List.length group then []
            else begin
              (* Insert the shared record before the EARLIEST sharing closure —
                 after the captured locals are bound, in scope for all of them. *)
              let earliest =
                List.fold_left (fun best s ->
                    match best with
                    | Some b when (b.Ast.start_line, b.Ast.start_col) <= (s.Ast.start_line, s.Ast.start_col) -> best
                    | _ -> Some s) None stmts
              in
              match earliest with
              | None -> []
              | Some stmt_sp ->
                let indent = String.make stmt_sp.Ast.start_col ' ' in
                let record = "{ " ^ String.concat ", " (List.map (fun c -> c ^ " = " ^ c) caps) ^ " }" in
                let ins_pos = Position.create ~line:(stmt_sp.Ast.start_line - 1) ~character:0 in
                let insert_edit =
                  TextEdit.create ~range:(Range.create ~start:ins_pos ~end_:ins_pos)
                    ~newText:(Printf.sprintf "%slet captured = %s\n" indent record) in
                let body_edits =
                  List.map (fun (_, bsp, _) ->
                      let body_text = slice_span src bsp in
                      let rewritten =
                        substitute_idents body_text (List.map (fun c -> (c, "captured." ^ c)) caps) in
                      TextEdit.create ~range:(range_of_span bsp) ~newText:rewritten) group
                in
                [CodeAction.create
                   ~title:(Printf.sprintf
                             "Extract %d captured values into a shared record (%d closures)"
                             (List.length caps) (List.length group))
                   ~kind:CodeActionKind.RefactorRewrite
                   ~edit:(mk_we (insert_edit :: body_edits)) ()]
            end
          end
      end
    | _ -> []
  in

  introduce_pipe_actions @ remove_pipe_actions
  @ extract_var_actions @ inline_var_actions
  @ collapse_capture_actions @ expand_capture_actions
  @ hole_fill_actions @ auto_import_actions
  @ impl_scaffold_actions @ actor_boilerplate_actions
  @ session_scaffold_actions @ if_to_match_actions
  @ linear_audit_actions @ destruct_actions @ extract_fn_actions
  @ organize_imports_actions
  @ doc_comment_actions @ inline_fn_actions @ auto_alias_actions
  @ extract_captures_actions

