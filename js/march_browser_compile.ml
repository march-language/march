(** March browser live-compile entry point — compiled to JavaScript via
    js_of_ocaml. Exposes:

      marchCompileToJs(source: string) -> { js: string|null, errors: string[] }

    Parses + desugars the given source, merges it with a curated stdlib
    bundle (loaded from window.marchStdlib, same convention as
    js/march_browser.ml), and runs it through March_driver.Js_pipeline.

    The stdlib file list is intentionally a separate, standalone copy of
    js/march_browser.ml's browser_stdlib_files (rather than a shared
    library) to avoid coupling two independent js_of_ocaml executables.
    It additionally includes dom.march, which the interpreter-backed REPL
    (march_browser.ml) does not need. *)

open Js_of_ocaml

(** Ordered list of stdlib file names to load in the browser, mirroring
    js/march_browser.ml's browser_stdlib_files, extended with dom.march
    (this entry point compiles real Dom-driven programs, unlike the
    interpreter-backed REPL). *)
let browser_stdlib_files = [
  "prelude.march";
  "option.march";
  "list.march";
  "math.march";
  "string.march";
  "array.march";
  "random.march";
  "dom.march";
]

(** Names that exist in BOTH prelude.march (unwrapped to bare top-level, see
    below) and one of the other bundled modules' own bodies (e.g. fold_left
    is defined in both prelude.march and list.march/array.march, with
    different signatures). check_module_full's pass-1 registers bare names
    in a single flat table when every stdlib file is merged as a top-level
    sibling this way (unlike the CLI's real per-file lazy stdlib loading),
    so the later-registered module's fold_left can end up shadowing
    prelude's own during prelude's OWN body typecheck, producing a bogus
    "expected (a, b) but got a" error inside prelude.march itself. None of
    this bundle's own code calls these prelude names bare (always via
    List.fold_left / Array.fold_left etc.), so dropping prelude's bare copy
    here is safe — this is a playground-bundle-only workaround, not a
    stdlib change. *)
let prelude_bare_name_collisions = ["fold_left"]

let is_colliding_prelude_decl = function
  | March_ast.Ast.DFn (def, _) ->
    List.mem def.March_ast.Ast.fn_name.March_ast.Ast.txt
      prelude_bare_name_collisions
  | _ -> false

(** Parse and desugar a stdlib source string, returning its decl list.
    Same logic as js/march_browser.ml's parse_stdlib_src. *)
let parse_stdlib_src filename src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  try
    let m = March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    let m = March_desugar.Desugar.desugar_module m in
    if filename = "prelude.march" then
      match m.March_ast.Ast.mod_decls with
      | [March_ast.Ast.DMod (_, _, inner, _)] ->
        List.filter (fun d -> not (is_colliding_prelude_decl d)) inner
      | ds -> List.filter (fun d -> not (is_colliding_prelude_decl d)) ds
    else
      [March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                           March_ast.Ast.Public,
                           m.March_ast.Ast.mod_decls,
                           March_ast.Ast.dummy_span)]
  with _ -> []

(** Load stdlib decls from window.marchStdlib (JS object: filename -> source).
    Returns [] entries silently skipped if window.marchStdlib or a given
    filename is absent. *)
let load_browser_stdlib () : March_ast.Ast.decl list =
  try
    let stdlib_obj = Js.Unsafe.eval_string
      {|(function(){
          if (typeof window !== 'undefined' && window.marchStdlib) return window.marchStdlib;
          if (typeof globalThis !== 'undefined' && globalThis.marchStdlib) return globalThis.marchStdlib;
          return null;
        })()|} in
    if Js.to_bool (Js.Unsafe.fun_call
          (Js.Unsafe.eval_string "(function(x){return x===null})")
          [| stdlib_obj |])
    then []
    else
      List.concat_map (fun filename ->
        try
          let src_js = Js.Unsafe.get stdlib_obj (Js.string filename) in
          if Js.to_bool (Js.Unsafe.fun_call
                (Js.Unsafe.eval_string "(function(x){return x===undefined})")
                [| src_js |])
          then []
          else parse_stdlib_src filename (Js.to_string (Js.Unsafe.coerce src_js))
        with _ -> []
      ) browser_stdlib_files
  with _ -> []

(** Compile user source to JS. Returns (js_opt, errors). *)
let compile_to_js source =
  let lexbuf = Lexing.from_string source in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = "playground.march" };
  match
    (try
       let m = March_parser.Parser.module_
           (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
       Ok (March_desugar.Desugar.desugar_module m)
     with
     | March_errors.Errors.ParseError (msg, _hint, pos) ->
       Error [Printf.sprintf "line %d: parse error: %s" pos.Lexing.pos_lnum msg]
     | March_parser.Parser.Error ->
       let pos = Lexing.lexeme_start_p lexbuf in
       Error [Printf.sprintf "line %d: parse error" pos.Lexing.pos_lnum])
  with
  | Error errs -> (None, errs)
  | Ok user_mod ->
    let stdlib_decls = load_browser_stdlib () in
    let merged =
      { user_mod with
        March_ast.Ast.mod_decls =
          stdlib_decls @ user_mod.March_ast.Ast.mod_decls }
    in
    (match
       March_driver.Js_pipeline.compile_module_to_js
         ~source_file:"playground.march" ~fn_lines:[] merged
     with
     | Ok (js, _map) -> (Some js, [])
     | Error errs -> (None, errs))

let () =
  Js.export "marchCompileToJs"
    (Js.wrap_callback (fun source_js ->
       let source = Js.to_string source_js in
       let (js_opt, errors) = compile_to_js source in
       let obj = Js.Unsafe.obj [||] in
       Js.Unsafe.set obj (Js.string "js")
         (match js_opt with
          | None -> Js.Unsafe.inject Js.null
          | Some js -> Js.Unsafe.inject (Js.string js));
       Js.Unsafe.set obj (Js.string "errors")
         (Js.array (Array.of_list (List.map Js.string errors)));
       obj))
