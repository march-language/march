(** @[no_alloc] allocation contracts.

    Design: specs/2026-09-03-allocation-contracts-design.md.

    Attribute bookkeeping (form + spans, keyed by the module-qualified
    pre-Mono TIR name) is collected from the AST here and matched to
    TIR functions by [Tir_names.strip_specialization_suffix] — never by
    mutating an annotated function's TIR, because the verdict must be the
    verdict of the code as it compiles WITHOUT the attribute. *)

type form = Hard | Warn | Assume

let form_of_attrs (attrs : string list) : form option =
  if List.mem "no_alloc" attrs then Some Hard
  else if List.mem "no_alloc:warn" attrs then Some Warn
  else if List.mem "no_alloc:assume" attrs then Some Assume
  else None

type decl_info = {
  d_name      : string;                 (** module-qualified pre-Mono TIR name *)
  d_form      : form option;
  d_name_span : March_ast.Ast.span;     (** the identifier *)
  d_decl_span : March_ast.Ast.span;     (** the whole [DFn] *)
}

(* Same walk as [Vectorize_mark.collect_attrs]: the module-qualified name is
   exactly what [Lower] gives the TIR fn_def before Mono mangles it. *)
let rec collect_prefixed (prefix : string) (decls : March_ast.Ast.decl list)
  : decl_info list =
  List.concat_map (function
      | March_ast.Ast.DFn (def, span) ->
        [ { d_name = prefix ^ def.March_ast.Ast.fn_name.March_ast.Ast.txt;
            d_form = form_of_attrs def.March_ast.Ast.fn_attrs;
            d_name_span = def.March_ast.Ast.fn_name.March_ast.Ast.span;
            d_decl_span = span } ]
      | March_ast.Ast.DMod (nm, _, inner, _) ->
        collect_prefixed (prefix ^ nm.March_ast.Ast.txt ^ ".") inner
      | _ -> [])
    decls

let collect (m : March_ast.Ast.module_) : decl_info list =
  collect_prefixed "" m.March_ast.Ast.mod_decls
