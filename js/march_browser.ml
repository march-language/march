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

(** Redirect both Format.std_formatter and eval's capture_write to [buf]
    while [f ()] runs.  This catches both Format.printf output and the
    print/println builtins (which go through Eval.test_capture_buf). *)
let with_output_captured buf f =
  let old_out = Format.get_formatter_output_functions () in
  let write s p l = Buffer.add_substring buf s p l in
  let flush () = () in
  Format.set_formatter_output_functions write flush;
  March_eval.Eval.test_capture_buf := Some buf;
  (try f ()
   with exn ->
     March_eval.Eval.test_capture_buf := None;
     Format.set_formatter_output_functions (fst old_out) (snd old_out);
     raise exn);
  March_eval.Eval.test_capture_buf := None;
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

(** Scan backwards from [i] skipping whitespace; return the resulting index. *)
let skip_ws_back line i =
  let p = ref i in
  while !p >= 0 && (line.[!p] = ' ' || line.[!p] = '\t') do decr p done;
  !p

(** Extract the identifier that ends at position [pos] in [line], if any.
    Returns the identifier string, or None if the character at [pos] is not
    part of an identifier. *)
let ident_ending_at line pos =
  let is_id c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') || c = '_' || c = '.'
  in
  if pos < 0 || not (is_id line.[pos]) then None
  else begin
    let i = ref pos in
    while !i > 0 && is_id line.[!i - 1] do decr i done;
    Some (String.sub line !i (pos - !i + 1))
  end

(** Return a short description of the value kind for a session variable. *)
let kind_of_value v =
  match v with
  | March_eval.Eval.VInt _     -> "an Int"
  | March_eval.Eval.VFloat _   -> "a Float"
  | March_eval.Eval.VBool _    -> "a Bool"
  | March_eval.Eval.VString _  -> "a String"
  | March_eval.Eval.VUnit      -> "unit"
  | March_eval.Eval.VClosure _ | March_eval.Eval.VBuiltin _ -> "a function"
  | March_eval.Eval.VPid _     -> "an actor Pid"
  | March_eval.Eval.VCon (tag, []) -> "the value " ^ tag
  | March_eval.Eval.VCon (tag, _)  -> "a " ^ tag
  | _                          -> "a value"

(** Produce a context-sensitive hint from the character at [col] and the
    surrounding source, optionally using the session env to name things. *)
let parse_hint line col env =
  let len = String.length line in
  if col >= len then None
  else
    let ch   = line.[col] in
    let prev_pos = skip_ws_back line (col - 1) in
    let prev = if prev_pos >= 0 then line.[prev_pos] else ' ' in
    match ch, prev with
    | ',', '(' ->
      (* e.g. send(pid(,  — the thing before '(' is often a named variable *)
      let before_paren = skip_ws_back line (prev_pos - 1) in
      let name_hint = match ident_ending_at line before_paren with
        | Some name ->
          let scope_note = match List.assoc_opt name env with
            | Some v -> Printf.sprintf " (%s is %s, not a function)" name (kind_of_value v)
            | None   -> ""
          in
          Printf.sprintf "looks like `%s` is being called as a function — \
                          did you mean `%s,` instead of `%s(`?%s"
            name name name scope_note
        | None ->
          "expected an expression here — there is an extra opening parenthesis before this comma"
      in
      Some name_hint
    | ')', '(' ->
      Some "empty parentheses — an expression is required between them"
    | ',', _ ->
      Some "unexpected comma — is there a missing expression or an extra opening parenthesis nearby?"
    | ')', _ ->
      Some "unexpected closing parenthesis — check for a mismatched or extra opening parenthesis earlier"
    | '(', _ ->
      Some "unexpected opening parenthesis here"
    | '=', _ when prev <> '!' && prev <> '<' && prev <> '>' && prev <> '=' ->
      Some "unexpected equals sign — did you mean: let name = expr"
    | _ -> None

(** Given [code], the session [env], and a [Lexing.position], return a string
    showing the error.  When a context-specific hint is available it leads the
    output (so it's the first thing the user reads); the source line and caret
    follow as supporting context.  Falls back to a bare "parse error" header
    when no hint can be derived. *)
let format_parse_error code env (pos : Lexing.position) msg =
  let lines = String.split_on_char '\n' code in
  let line_no = pos.Lexing.pos_lnum in   (* 1-based *)
  let col     = pos.Lexing.pos_cnum - pos.Lexing.pos_bol in  (* 0-based *)
  match List.nth_opt lines (line_no - 1) with
  | Some src_line ->
    let caret = String.make (max 0 col) ' ' ^ "^" in
    (match parse_hint src_line col env with
     | Some hint ->
       (* Hint first — most useful info visible immediately *)
       Printf.sprintf "%s\n%s\n%s" hint src_line caret
     | None ->
       Printf.sprintf "%s\n%s\n%s" msg src_line caret)
  | None ->
    Printf.sprintf "%s (line %d col %d)" msg line_no col

(** Parse all REPL items from [code] using the [repl_sequence] grammar rule.
    Returns [Ok items] or [Error msg] with source context and a caret pointer. *)
let parse_all_repl_items code env =
  let lexbuf = Lexing.from_string (code ^ "\n") in
  lexbuf.Lexing.lex_curr_p <-
    { lexbuf.Lexing.lex_curr_p with Lexing.pos_fname = "<repl>" };
  try
    let items = March_parser.Parser.repl_sequence
        (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf in
    Ok items
  with
  | March_errors.Errors.ParseError (msg, _hint, pos) ->
    Error (format_parse_error code env pos ("parse error: " ^ msg))
  | March_parser.Parser.Error ->
    let pos = Lexing.lexeme_start_p lexbuf in
    Error (format_parse_error code env pos "parse error")

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
    | March_eval.Eval.VCon ("Nil", []) -> Buffer.add_string buf "[]"
    | March_eval.Eval.VCon ("Cons", _) ->
      (* Pretty-print linked lists as [a, b, c] *)
      let rec collect acc = function
        | March_eval.Eval.VCon ("Cons", [hd; tl]) -> collect (hd :: acc) tl
        | March_eval.Eval.VCon ("Nil", []) -> List.rev acc
        | v -> List.rev (v :: acc)
      in
      let elems = collect [] v in
      Buffer.add_char buf '[';
      List.iteri (fun i e -> if i > 0 then Buffer.add_string buf ", "; pp e) elems;
      Buffer.add_char buf ']'
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

(** Evaluate a single parsed repl_input item in the session.
    Returns [(output, value_opt, error_opt)].
    [value_opt] is set for ReplExpr items so the caller can display the result. *)
let eval_item item =
  let out_buf = Buffer.create 128 in
  let error_ref : string option ref = ref None in
  let value_ref : March_eval.Eval.value option ref = ref None in
  with_output_captured out_buf (fun () ->
    try
      (match item with
       | March_ast.Ast.ReplEOF -> ()
       | March_ast.Ast.ReplExpr expr ->
         let v = March_eval.Eval.eval_expr !session_env_ref expr in
         value_ref := Some v
       | March_ast.Ast.ReplDecl decl ->
         let new_env = March_eval.Eval.eval_decl !session_env_ref decl in
         session_env_ref := new_env;
         (* If `main` was just defined, call it immediately *)
         (match List.assoc_opt "main" new_env with
          | Some v ->
            let result = March_eval.Eval.apply v [] in
            let s = string_of_value result in
            if s <> "()" then Format.printf "%s\n%!" s
          | None -> ()))
    with
    | March_eval.Eval.Eval_error msg ->
      error_ref := Some ("runtime error: " ^ msg)
    | March_eval.Eval.Match_failure msg ->
      error_ref := Some ("match failure: " ^ msg)
    | exn ->
      error_ref := Some ("error: " ^ Printexc.to_string exn)
  );
  (Buffer.contents out_buf, !value_ref, !error_ref)

(** Evaluate [code] in the persistent session.
    Parses all items from [code] sequentially from a shared lexbuf, so that
    multi-declaration inputs like type defs + let bindings + expressions all
    work without requiring artificial line splitting.
    Returns [(output_text, error_opt)]. *)
let eval_line code =
  ensure_session_init ();
  match parse_all_repl_items code !session_env_ref with
  | Error msg -> ("", Some msg)
  | Ok items ->
    let overall_out = Buffer.create 128 in
    let last_value = ref None in
    let first_error = ref None in
    List.iter (fun item ->
      if !first_error = None then begin
        let (out, v, err) = eval_item item in
        Buffer.add_string overall_out out;
        last_value := v;
        first_error := err
      end
    ) items;
    let output =
      match !last_value with
      | None -> Buffer.contents overall_out
      | Some v ->
        let s = string_of_value v in
        let base = Buffer.contents overall_out in
        if base = "" then s ^ "\n" else base ^ s ^ "\n"
    in
    (output, !first_error)

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
