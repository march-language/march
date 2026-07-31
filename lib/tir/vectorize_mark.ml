(** Runs immediately after [Lower.lower_module], before
    [Mono.monomorphize] — the one point in the pipeline where a TIR
    fn_def's name is still EXACTLY its source name (mono hasn't
    mangled/duplicated anything yet, defun hasn't lifted any lambdas yet),
    so AST attrs can be matched to TIR functions by plain name equality —
    no fragile post-optimization string surgery required (see
    [Vectorize_check]'s "Revision" doc comment for what that surgery got
    wrong).

    Rather than track the match by name from this point on, this injects
    a sentinel call at the head of the matched fn's body. Mono's
    record-update duplication and Defun/Opt/inlining all preserve BODY
    CONTENTS wherever they end up — a function inlined into its caller
    carries its body, sentinel included, into that caller — so the
    sentinel reaches [Vectorize_check.check] even when the function's own
    top-level identity does not survive that far. The sentinel also
    carries the fn's declaration span, so the late check can still anchor
    its diagnostic at the right source location despite TIR having no
    general per-expression span tracking. *)

let marker_name (sev : Vectorize_check.severity) : string =
  match sev with
  | Vectorize_check.Hard -> "__vectorize_marker_hard"
  | Vectorize_check.Soft -> "__vectorize_marker_soft"

let marker_var (sev : Vectorize_check.severity) : Tir.var =
  { Tir.v_name = marker_name sev; v_ty = Tir.TPtr Tir.TUnit; v_lin = Tir.Unr }

(** Every top-level [DFn] anywhere in [decls] (recursing into nested
    [DMod] with the module-qualified name Lower itself uses — e.g.
    [Inner.helper] for a fn named [helper] inside [mod Inner do ... end]) —
    since that's the exact name [Tir.fn_def.fn_name] will carry at this
    pre-Mono point) whose [fn_attrs] names a @[vectorize] variant. *)
let rec collect_attrs (prefix : string) (decls : March_ast.Ast.decl list)
  : (string * Vectorize_check.severity * March_ast.Ast.span) list =
  List.concat_map (function
      | March_ast.Ast.DFn (def, span) ->
        (match Vectorize_check.attr_severity def.March_ast.Ast.fn_attrs with
         | Some sev -> [ (prefix ^ def.March_ast.Ast.fn_name.March_ast.Ast.txt, sev, span) ]
         | None -> [])
      | March_ast.Ast.DMod (nm, _, inner, _) ->
        collect_attrs (prefix ^ nm.March_ast.Ast.txt ^ ".") inner
      | _ -> [])
    decls

let sentinel_call (sev : Vectorize_check.severity) (name : string) (span : March_ast.Ast.span) : Tir.expr =
  Tir.EApp (marker_var sev,
            [ Tir.ALit (March_ast.Ast.LitString span.March_ast.Ast.file);
              Tir.ALit (March_ast.Ast.LitInt span.March_ast.Ast.start_line);
              Tir.ALit (March_ast.Ast.LitInt span.March_ast.Ast.start_col);
              Tir.ALit (March_ast.Ast.LitInt span.March_ast.Ast.end_line);
              Tir.ALit (March_ast.Ast.LitInt span.March_ast.Ast.end_col);
              Tir.ALit (March_ast.Ast.LitString name) ])

(** Entry point. A no-op (returns [m] untouched) when nothing in [ast]
    carries a @[vectorize] variant. *)
let mark (ast : March_ast.Ast.module_) (m : Tir.tir_module) : Tir.tir_module =
  let attrs = collect_attrs "" ast.March_ast.Ast.mod_decls in
  if attrs = [] then m
  else
    let new_fns = List.map (fun (fd : Tir.fn_def) ->
        match List.find_opt (fun (n, _, _) -> n = fd.Tir.fn_name) attrs with
        | None -> fd
        | Some (name, sev, span) ->
          { fd with Tir.fn_body = Tir.ESeq (sentinel_call sev name span, fd.Tir.fn_body) })
      m.Tir.tm_fns
    in
    { m with Tir.tm_fns = new_fns }
