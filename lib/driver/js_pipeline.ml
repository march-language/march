(** Shared TIR compile pipeline: typecheck -> lower -> mono -> ... -> js_emit.

    Mirrors the --target js branch of bin/main.ml's compile_mode handling
    (parse/desugar/stdlib-merge are the caller's responsibility; this
    covers typecheck through js_emit). Used by both the browser live-compile
    entry point (js/march_browser_compile.ml) and its own test suite
    (test/test_codegen.ml). bin/main.ml is NOT changed to call this — see
    the plan's Task 1 note for why. If bin/main.ml's JS pipeline changes,
    update this file to match. *)

let format_diagnostic (d : March_errors.Errors.diagnostic) =
  let open March_errors.Errors in
  let open March_ast.Ast in
  Printf.sprintf "%s:%d:%d: %s" d.span.file d.span.start_line d.span.start_col
    d.message

let compile_module_to_js ~source_file ~fn_lines (m : March_ast.Ast.module_) :
    (string * string option, string list) result =
  let errctx, type_map, _typecheck_env =
    March_typecheck.Typecheck.check_module_full m
  in
  if March_errors.Errors.has_errors errctx then
    let diags = March_errors.Errors.sorted errctx in
    Error
      (List.filter_map
         (fun (d : March_errors.Errors.diagnostic) ->
           match d.March_errors.Errors.severity with
           | March_errors.Errors.Error -> Some (format_diagnostic d)
           | _ -> None)
         diags)
  else
    let tir = March_tir.Lower.lower_module ~type_map m in
    let iface_methods = March_tir.Lower.get_iface_methods () in
    let tir = March_tir.Mono.monomorphize ~iface_methods tir in
    let tir = March_tir.Fusion.run ~changed:(ref false) tir in
    let policy_violations = March_tir.Policy_dce.audit tir in
    if policy_violations <> [] then
      Error (List.map (fun (_fn, msg) -> msg) policy_violations)
    else
      let tir = March_tir.Defun.defunctionalize tir in
      let tir = March_tir.Join_points.run_pre ~changed:(ref false) tir in
      let tir =
        March_tir.Simplify.run ~pre_perceus:true ~changed:(ref false) tir
      in
      let tir = March_tir.Perceus.perceus tir in
      let tir = March_tir.Escape.escape_analysis tir in
      let tir = March_tir.Opt.run tir in
      let tir_for_js = March_tir.Opt.run tir in
      (try Ok (March_tir.Js_emit.emit_module ~source_file ~fn_lines tir_for_js)
       with March_tir.Js_emit.Js_emit_error msgs -> Error msgs)
