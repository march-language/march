(** March browser REPL — compiled to JavaScript via js_of_ocaml.

    Exposes two functions to JavaScript:
      marchEvalLine(code: string) -> {output: string, error: string|null}
      marchResetSession()         -> undefined

    The session maintains a persistent environment across calls so that
    definitions made in one eval are visible in subsequent ones.

    Pipeline: parse -> desugar -> (typecheck) -> eval_decl into env ref.

    Stdlib is loaded from window.marchStdlib (a JS object mapping filename
    to source string) if present, otherwise skipped gracefully.

    Limitations in the browser:
    - No file I/O (stubs return errors)
    - No Unix processes or sockets
    - No HTTP server / network sockets
    - Actors and tasks run synchronously in-process
*)

open Js_of_ocaml

(* ------------------------------------------------------------------ *)
(* Output capture via Buffer + Format redirector                       *)
(* ------------------------------------------------------------------ *)

(** Redirect Format.std_formatter to [buf] while [f ()] runs.
    In the browser there are no real file descriptors to redirect, so
    we just intercept the Format formatter output functions. *)
let with_output_captured buf f =
  let old_out = Format.get_formatter_output_functions () in
  let write s p l = Buffer.add_substring buf s p l in
  let flush () = () in
  Format.set_formatter_output_functions write flush;
  (try f ()
   with exn ->
     Format.set_formatter_output_functions (fst old_out) (snd old_out);
     raise exn);
  Format.set_formatter_output_functions (fst old_out) (snd old_out)

(* ------------------------------------------------------------------ *)
(* Session state                                                       *)
(* ------------------------------------------------------------------ *)

(** Persistent environment ref — accumulates bindings across eval calls. *)
let session_env_ref : March_eval.Eval.env ref = ref []

(** Whether stdlib has been loaded into the session yet. *)
let stdlib_loaded : bool ref = ref false

(** Reset the session to empty state. *)
let reset_session () =
  session_env_ref := [];
  stdlib_loaded := false

(* ------------------------------------------------------------------ *)
(* Stdlib loading from window.marchStdlib                              *)
(* ------------------------------------------------------------------ *)

(** Ordered list of stdlib file names to load in the browser.
    Networking / file / HTTP modules are excluded as they depend on
    platform-specific C calls. *)
let browser_stdlib_files = [
  "prelude.march";
  "option.march";
  "result.march";
  "list.march";
  "hamt.march";
  "map.march";
  "math.march";
  "string.march";
  "sort.march";
  "seq.march";
  "set.march";
  "array.march";
  "tuple.march";
  "char.march";
  "range.march";
  "enum.march";
  "random.march";
  "json.march";
]

(** Parse and desugar a stdlib source string, returning its decl list. *)
let parse_stdlib_src filename src =
  let lexbuf = Lexing.from_string src in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = filename };
  try
    let m = March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    let m = March_desugar.Desugar.desugar_module m in
    if filename = "prelude.march" then
      (* Unwrap outer mod so prelude names are in global scope *)
      (match m.March_ast.Ast.mod_decls with
       | [March_ast.Ast.DMod (_, _, inner, _)] -> inner
       | ds -> ds)
    else
      [March_ast.Ast.DMod (m.March_ast.Ast.mod_name,
                           March_ast.Ast.Public,
                           m.March_ast.Ast.mod_decls,
                           March_ast.Ast.dummy_span)]
  with _ -> []

(** Load stdlib from window.marchStdlib (JS object: filename -> source).
    Returns all collected decls. If window.marchStdlib is absent, returns []. *)
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

(* ------------------------------------------------------------------ *)
(* Session initialisation                                              *)
(* ------------------------------------------------------------------ *)

(** Ensure the session env is initialised.
    On first call: loads stdlib into session_env_ref. *)
let ensure_session_init () =
  if not !stdlib_loaded then begin
    let stdlib_decls = load_browser_stdlib () in
    (* Build an empty module carrying just the stdlib decls *)
    let dummy_span = March_ast.Ast.dummy_span in
    let dummy_name = { March_ast.Ast.txt = "ReplInit"; March_ast.Ast.span = dummy_span } in
    let init_mod = {
      March_ast.Ast.mod_name  = dummy_name;
      March_ast.Ast.mod_decls = stdlib_decls;
    } in
    (* eval_module_env resets global state and returns the env with stdlib *)
    let env = March_eval.Eval.eval_module_env init_mod in
    session_env_ref := env;
    stdlib_loaded := true
  end

(* ------------------------------------------------------------------ *)
(* Parse helpers                                                       *)
(* ------------------------------------------------------------------ *)

let parse_user_code code =
  let lexbuf = Lexing.from_string code in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = "<repl>" };
  try
    let m = March_parser.Parser.module_
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    Ok (March_desugar.Desugar.desugar_module m)
  with
  | March_errors.Errors.ParseError (msg, _hint, pos) ->
    let open Lexing in
    Error (Printf.sprintf "parse error at line %d: %s" pos.pos_lnum msg)
  | March_parser.Parser.Error ->
    let pos = Lexing.lexeme_start_p lexbuf in
    let open Lexing in
    Error (Printf.sprintf "parse error at line %d col %d"
             pos.pos_lnum (pos.pos_cnum - pos.pos_bol))

(* ------------------------------------------------------------------ *)
(* Eval an expression / declaration sequence                           *)
(* ------------------------------------------------------------------ *)

(** Pretty-print a value to a string using the eval module's pp. *)
let string_of_value v =
  (* March values don't have a public pretty-printer exposed from eval.
     We use Printf to build a simple representation. *)
  let buf = Buffer.create 32 in
  let rec pp v =
    match v with
    | March_eval.Eval.VInt n    -> Buffer.add_string buf (string_of_int n)
    | March_eval.Eval.VFloat f  ->
      let s = Printf.sprintf "%g" f in
      Buffer.add_string buf s
    | March_eval.Eval.VString s ->
      Buffer.add_char buf '"';
      Buffer.add_string buf (String.escaped s);
      Buffer.add_char buf '"'
    | March_eval.Eval.VBool true  -> Buffer.add_string buf "true"
    | March_eval.Eval.VBool false -> Buffer.add_string buf "false"
    | March_eval.Eval.VAtom a     -> Buffer.add_string buf (":" ^ a)
    | March_eval.Eval.VUnit       -> Buffer.add_string buf "()"
    | March_eval.Eval.VTuple vs   ->
      Buffer.add_char buf '(';
      List.iteri (fun i v -> if i > 0 then Buffer.add_string buf ", "; pp v) vs;
      Buffer.add_char buf ')'
    | March_eval.Eval.VCon (tag, [])  -> Buffer.add_string buf tag
    | March_eval.Eval.VCon (tag, vs)  ->
      Buffer.add_string buf tag;
      Buffer.add_char buf '(';
      List.iteri (fun i v -> if i > 0 then Buffer.add_string buf ", "; pp v) vs;
      Buffer.add_char buf ')'
    | March_eval.Eval.VRecord fields ->
      Buffer.add_char buf '{';
      List.iteri (fun i (k, v) ->
        if i > 0 then Buffer.add_string buf ", ";
        Buffer.add_string buf k;
        Buffer.add_string buf " = ";
        pp v) fields;
      Buffer.add_char buf '}'
    | March_eval.Eval.VClosure _       -> Buffer.add_string buf "<fn>"
    | March_eval.Eval.VBuiltin (n, _)  -> Buffer.add_string buf ("<builtin:" ^ n ^ ">")
    | March_eval.Eval.VMultiarity _    -> Buffer.add_string buf "<fn>"
    | March_eval.Eval.VNativeIntArr a  ->
      Buffer.add_string buf "[|";
      Array.iteri (fun i n -> if i > 0 then Buffer.add_string buf ", ";
                    Buffer.add_string buf (string_of_int n)) a;
      Buffer.add_string buf "|]"
    | March_eval.Eval.VNativeFloatArr a ->
      Buffer.add_string buf "[|";
      Array.iteri (fun i f -> if i > 0 then Buffer.add_string buf ", ";
                    Buffer.add_string buf (Printf.sprintf "%g" f)) a;
      Buffer.add_string buf "|]"
    | March_eval.Eval.VTypedArray a ->
      Buffer.add_string buf "[|";
      Array.iteri (fun i v -> if i > 0 then Buffer.add_string buf ", "; pp v) a;
      Buffer.add_string buf "|]"
    | _ -> Buffer.add_string buf "<value>"
  in
  pp v;
  Buffer.contents buf

(** Evaluate [code] in the persistent session.
    Returns [(output_text, error_opt)]. *)
let eval_line code =
  ensure_session_init ();
  match parse_user_code code with
  | Error msg -> ("", Some msg)
  | Ok user_module ->
    let out_buf = Buffer.create 128 in
    let error_ref : string option ref = ref None in
    with_output_captured out_buf (fun () ->
      try
        (* Typecheck the user's decls in isolation (no session type env;
           typecheck is just for catching obvious errors).
           We build a module that includes the new decls only. *)
        let dummy_span = March_ast.Ast.dummy_span in
        let dummy_name = { March_ast.Ast.txt = "ReplSnippet"; March_ast.Ast.span = dummy_span } in
        let check_mod = {
          March_ast.Ast.mod_name  = dummy_name;
          March_ast.Ast.mod_decls = user_module.March_ast.Ast.mod_decls;
        } in
        let (tc_ctx, _) = March_typecheck.Typecheck.check_module check_mod in
        let errors = March_errors.Errors.sorted tc_ctx
                     |> List.filter (fun (d : March_errors.Errors.diagnostic) ->
                          d.severity = March_errors.Errors.Error) in
        (match errors with
         | d :: _ ->
           error_ref := Some d.March_errors.Errors.message
         | [] ->
           (* Eval each new declaration into the session env *)
           let new_env = List.fold_left March_eval.Eval.eval_decl
                           !session_env_ref
                           user_module.March_ast.Ast.mod_decls in
           session_env_ref := new_env;
           (* If a top-level `main` was just defined, call it once *)
           (match List.assoc_opt "main" new_env with
            | Some v ->
              let result = March_eval.Eval.apply v [] in
              let s = string_of_value result in
              if s <> "()" then begin
                Format.printf "%s\n%!" s
              end
            | None ->
              (* If the snippet is a single expression (DLet _ or DExpr _),
                 print its value. We detect this by looking for bindings with
                 auto-generated names from desugar, or by counting decls. *)
              ()))
      with
      | March_eval.Eval.Eval_error msg ->
        error_ref := Some ("runtime error: " ^ msg)
      | March_eval.Eval.Match_failure msg ->
        error_ref := Some ("match failure: " ^ msg)
      | exn ->
        error_ref := Some ("error: " ^ Printexc.to_string exn)
    );
    (Buffer.contents out_buf, !error_ref)

(* ------------------------------------------------------------------ *)
(* JavaScript exports                                                  *)
(* ------------------------------------------------------------------ *)

let () =
  (* marchEvalLine(code) -> {output, error} *)
  Js.export "marchEvalLine"
    (Js.wrap_callback (fun code_js ->
       let code = Js.to_string code_js in
       let (output, error_opt) = eval_line code in
       let obj = Js.Unsafe.obj [||] in
       Js.Unsafe.set obj (Js.string "output") (Js.string output);
       Js.Unsafe.set obj (Js.string "error")
         (match error_opt with
          | None     -> Js.Unsafe.inject Js.null
          | Some msg -> Js.Unsafe.inject (Js.string msg));
       obj));

  (* marchResetSession() *)
  Js.export "marchResetSession"
    (Js.wrap_callback (fun () ->
       reset_session ();
       Js.undefined))
