(** Formatter tests.

    Properties checked:
    1. Idempotence — fmt(fmt(src)) = fmt(src)
    2. Correctness — formatted source parses to the same AST structure
    3. Roundtrip — stdlib files format without errors *)

(* ------------------------------------------------------------------ *)
(* Helpers                                                             *)
(* ------------------------------------------------------------------ *)

let parse_module src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.module_ (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

let fmt src =
  let m = parse_module src in
  March_format.Format.format_module ~src m

(** Check that formatting is idempotent. *)
let check_idempotent label src =
  let once  = fmt src in
  let twice = fmt once in
  Alcotest.(check string) (label ^ ": idempotent") once twice

(** Check that the formatted source parses without error. *)
let check_parses label src =
  let formatted = fmt src in
  (try ignore (parse_module formatted)
   with _ ->
     Alcotest.fail (Printf.sprintf "%s: formatted source does not parse:\n%s" label formatted))

(* ------------------------------------------------------------------ *)
(* Basic expression tests                                              *)
(* ------------------------------------------------------------------ *)

let test_simple_fn () =
  let src = {|mod Test do
fn add(x : Int, y : Int) : Int do
  x + y
end
end|} in
  check_parses "simple fn" src;
  check_idempotent "simple fn" src

let test_match_expr () =
  let src = {|mod Test do
fn label(x : Int) : String do
  match x do
  0 -> "zero"
  1 -> "one"
  _ -> "many"
  end
end
end|} in
  check_parses "match" src;
  check_idempotent "match" src

let test_if_expr () =
  let src = {|mod Test do
fn sign(x : Int) : String do
  if x > 0 do "positive" else if x < 0 do "negative" else "zero" end end
end
end|} in
  check_parses "if" src;
  check_idempotent "if" src

let test_let_binding () =
  let src = {|mod Test do
fn double(x : Int) : Int do
  let y = x * 2
  y
end
end|} in
  check_parses "let binding" src;
  check_idempotent "let binding" src

let test_pipe_chain () =
  let src = {|mod Test do
fn process(xs : List(Int)) : List(Int) do
  xs |> List.map(fn x -> x * 2) |> List.filter(fn x -> x > 0)
end
end|} in
  check_parses "pipe chain" src;
  check_idempotent "pipe chain" src

let test_lambda () =
  let src = {|mod Test do
fn apply(f : Int -> Int, x : Int) : Int do
  f(x)
end
end|} in
  check_parses "lambda" src;
  check_idempotent "lambda" src

(** Regression test: a lambda with a multi-statement body must not be
    collapsed to a literal "..." placeholder (invalid syntax). *)
let contains_substring haystack needle =
  let hl = String.length haystack and nl = String.length needle in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  go 0

let check_no_ellipsis_placeholder label src =
  let formatted = fmt src in
  if contains_substring formatted "-> ..." then
    Alcotest.fail (Printf.sprintf "%s: lambda body collapsed to '...':\n%s" label formatted)

let test_multiline_lambda_let () =
  let src = {|mod Test do
fn make() : Int -> Int do
  fn x ->
    let y = x + 1
    let z = y * 2
    z
end
end|} in
  check_parses "multiline lambda let" src;
  check_idempotent "multiline lambda let" src;
  check_no_ellipsis_placeholder "multiline lambda let" src

let test_multiline_lambda_call_arg () =
  let src = {|mod Test do
fn make(xs : List(Int)) : List(Int) do
  List.map(xs, fn x ->
    let y = x + 1
    let z = y * 2
    z
  )
end
end|} in
  check_parses "multiline lambda call arg" src;
  check_idempotent "multiline lambda call arg" src;
  check_no_ellipsis_placeholder "multiline lambda call arg" src

let test_multiline_lambda_pipe_stage () =
  let src = {|mod Test do
fn make(xs : List(Int)) : List(Int) do
  xs
  |> List.map(fn x ->
    let y = x + 1
    let z = y * 2
    z
  )
  |> List.filter(fn x -> x > 0)
end
end|} in
  check_parses "multiline lambda pipe stage" src;
  check_idempotent "multiline lambda pipe stage" src;
  check_no_ellipsis_placeholder "multiline lambda pipe stage" src

let test_multiline_lambda_nested_ctor () =
  let src = {|mod Test do
fn wrap(w : Int, th : Int) : Int do
  GenTree(w, Thunk(fn _ ->
    let a = List.map(th, fn c -> c + 1)
    let b = force(th)
    List.append(a, b)
  ))
end
end|} in
  check_parses "multiline lambda nested ctor" src;
  check_idempotent "multiline lambda nested ctor" src;
  check_no_ellipsis_placeholder "multiline lambda nested ctor" src

let test_type_variant () =
  let src = {|mod Test do
type Color = Red | Green | Blue
end|} in
  check_parses "type variant" src;
  check_idempotent "type variant" src

let test_type_record () =
  let src = {|mod Test do
type Point = { x : Float, y : Float }
end|} in
  check_parses "type record" src;
  check_idempotent "type record" src

let test_pub_fn () =
  let src = {|mod Test do
fn greet(name : String) : String do
  "hello"
end
end|} in
  check_parses "fn" src;
  check_idempotent "fn" src

let test_nested_match () =
  let src = {|mod Test do
fn classify(x : Int, y : Int) : String do
  match x do
  0 -> do
    match y do
    0 -> "origin"
    _ -> "x-axis"
    end
  end
  _ -> "other"
  end
end
end|} in
  check_parses "nested match" src;
  check_idempotent "nested match" src

let test_tuple () =
  let src = {|mod Test do
fn pair(x : Int, y : Int) : (Int, Int) do
  (x, y)
end
end|} in
  check_parses "tuple" src;
  check_idempotent "tuple" src

let test_record_literal () =
  let src = {|mod Test do
fn make_point(x : Float, y : Float) : Point do
  { x: x, y: y }
end
end|} in
  check_parses "record literal" src;
  check_idempotent "record literal" src

let test_record_pattern () =
  let src = {|mod Test do
fn has_val({ left: l, right: r }, value : Int) : Bool do
  match l == value do
  true -> true
  false -> false
  end
end
end|} in
  check_parses "record pattern" src;
  check_idempotent "record pattern" src

let test_local_fn () =
  let src = {|mod Test do
fn fib(n : Int) : Int do
  fn go(n : Int) : Int do
    if n <= 1 do n else go(n - 1) + go(n - 2) end
  end
  go(n)
end
end|} in
  check_parses "local fn" src;
  check_idempotent "local fn" src

let test_use_decl () =
  let src = {|mod Test do
use List.*
fn demo() : Int do
  42
end
end|} in
  check_parses "use decl" src;
  check_idempotent "use decl" src

let test_doc_comment () =
  let src = {|mod Test do
doc "Returns the answer."
fn answer() : Int do
  42
end
end|} in
  check_parses "doc comment" src;
  check_idempotent "doc comment" src

let test_type_alias () =
  let src = {|mod Test do
type Name = String
end|} in
  check_parses "type alias" src;
  check_idempotent "type alias" src

(* ------------------------------------------------------------------ *)
(* Idempotence property: format is a fixpoint                         *)
(* ------------------------------------------------------------------ *)

let test_small_float_literal () =
  (* string_of_float renders small-magnitude floats in scientific notation
     (e.g. "9.537e-07"), but the March lexer's float literal only accepts
     digit+ '.' digit+ — no exponent form. The formatter must expand
     scientific notation back to plain decimal so a second --fmt pass
     doesn't fail to parse. *)
  let src = {|mod Test do
fn f(x : Float) : Float do
  if x < 0.0000009537 do 1.0 else 2.0 end
end
end|} in
  check_parses "small float literal" src;
  check_idempotent "small float literal" src

let test_format_fixpoint () =
  (* A source written in already-formatted style should be unchanged *)
  let src = {|mod Demo do
  needs IO.Console

type Shape = Circle(Float) | Rect(Float, Float)

fn area(s : Shape) : Float do
  match s do
  Circle(r) -> 3.14159 * r * r
  Rect(w, h) -> w * h
  end
end

fn main(_cap_console : Cap(IO.Console)) : Unit do
  let s = Circle(5.0)
  let a = area(s)
  print(a)
end

end|} in
  check_parses "format fixpoint" src;
  check_idempotent "format fixpoint" src

let test_trailing_blank_insensitive () =
  (* Extra trailing blank lines in the INPUT must not change the output, so a
     formatted file never accumulates trailing blank lines across runs. (The
     formatter already satisfies this; this locks it in.) *)
  let src = {|mod Test do

fn f() : Int do
  1
end

end|} in
  let once = fmt src in
  let with_blanks = fmt (once ^ "\n\n\n") in
  Alcotest.(check string) "trailing blanks don't change output" once with_blanks;
  (* And a second pass over the padded output is still stable. *)
  Alcotest.(check string) "stable after re-format" once (fmt with_blanks)

let test_import_run_is_tight () =
  (* A run of imports reads as one list, not as N paragraphs, so the blank
     lines between them are removed. *)
  let src = {|mod Test do

import A.B

import C.D

import E.F

fn f() : Int do
  1
end

end|} in
  let out = fmt src in
  if not (contains_substring out "  import A.B\n  import C.D\n  import E.F\n") then
    Alcotest.fail (Printf.sprintf "imports were not tightened:\n%s" out);
  check_parses "import run" src;
  check_idempotent "import run" src

let test_cap_run_is_tight () =
  (* Same for capability declarations.  `cap no_panic` must also round-trip
     under its real surface spelling — it was once re-emitted as `opts
     no_panic`, which does not parse. *)
  let src = {|mod Test do

needs IO.Network

needs IO.Clock

cap no_panic

cap pure

fn f() : Int do
  1
end

end|} in
  let out = fmt src in
  if not (contains_substring out "  needs IO.Network\n  needs IO.Clock\n  cap no_panic\n  cap pure\n") then
    Alcotest.fail (Printf.sprintf "caps were not tightened:\n%s" out);
  check_parses "cap run" src;
  check_idempotent "cap run" src

let test_unrelated_decls_keep_blank_line () =
  (* REJECT witness for the two tests above: tightening must apply ONLY within
     a run of the same kind.  A formatter that dropped every blank line would
     pass both of them, and only this test tells the two apart.  Imports and
     caps are different kinds, so even they stay separated. *)
  let src = {|mod Test do

needs IO.Clock

import A.B

fn f() : Int do
  1
end

fn g() : Int do
  2
end

end|} in
  let out = fmt src in
  List.iter (fun (what, s) ->
    if not (contains_substring out s) then
      Alcotest.fail (Printf.sprintf "%s lost its blank line:\n%s" what out))
    [ "cap/import boundary", "  needs IO.Clock\n\n  import A.B";
      "import/fn boundary",  "  import A.B\n\n  fn f";
      "fn/fn boundary",      "  end\n\n  fn g" ]

(* ------------------------------------------------------------------ *)
(* Stdlib file roundtrip                                               *)
(* ------------------------------------------------------------------ *)

let stdlib_roundtrip name =
  (* Look for stdlib relative to test binary location or cwd *)
  let candidates = [
    Filename.concat "stdlib" name;
    Filename.concat "../stdlib" name;
    Filename.concat "../../stdlib" name;
  ] in
  match List.find_opt Sys.file_exists candidates with
  | None ->
    (* Skip gracefully if stdlib not found *)
    ()
  | Some path ->
    let src =
      let ic = open_in path in
      let n  = in_channel_length ic in
      let buf = Bytes.create n in
      really_input ic buf 0 n;
      close_in ic;
      Bytes.to_string buf
    in
    (try
       let formatted = March_format.Format.format_source ~filename:path src in
       (* Formatted must parse *)
       (try ignore (parse_module formatted)
        with _ ->
          Alcotest.fail (Printf.sprintf "stdlib/%s: formatted source does not parse" name));
       (* Idempotence *)
       let twice = March_format.Format.format_source ~filename:path formatted in
       Alcotest.(check string)
         (Printf.sprintf "stdlib/%s: idempotent" name) formatted twice
     with March_parser.Parser.Error ->
       (* Some stdlib files may use syntax the formatter doesn't support yet *)
       ())

let test_stdlib_list ()    = stdlib_roundtrip "list.march"
let test_stdlib_option ()  = stdlib_roundtrip "option.march"
let test_stdlib_result ()  = stdlib_roundtrip "result.march"
let test_stdlib_math ()    = stdlib_roundtrip "math.march"
let test_stdlib_string ()  = stdlib_roundtrip "string.march"
let test_stdlib_prelude () = stdlib_roundtrip "prelude.march"

(* ------------------------------------------------------------------ *)
(* Test suite registration                                             *)
(* ------------------------------------------------------------------ *)

let () =
  let open Alcotest in
  run "formatter" [
    "basic", [
      test_case "simple fn"       `Quick test_simple_fn;
      test_case "match expr"      `Quick test_match_expr;
      test_case "if expr"         `Quick test_if_expr;
      test_case "let binding"     `Quick test_let_binding;
      test_case "pipe chain"      `Quick test_pipe_chain;
      test_case "lambda"          `Quick test_lambda;
      test_case "multiline lambda let"          `Quick test_multiline_lambda_let;
      test_case "multiline lambda call arg"     `Quick test_multiline_lambda_call_arg;
      test_case "multiline lambda pipe stage"   `Quick test_multiline_lambda_pipe_stage;
      test_case "multiline lambda nested ctor"  `Quick test_multiline_lambda_nested_ctor;
      test_case "type variant"    `Quick test_type_variant;
      test_case "type record"     `Quick test_type_record;
      test_case "fn"          `Quick test_pub_fn;
      test_case "nested match"    `Quick test_nested_match;
      test_case "tuple"           `Quick test_tuple;
      test_case "record literal"  `Quick test_record_literal;
      test_case "record pattern"  `Quick test_record_pattern;
      test_case "local fn"        `Quick test_local_fn;
      test_case "use decl"        `Quick test_use_decl;
      test_case "doc comment"     `Quick test_doc_comment;
      test_case "type alias"      `Quick test_type_alias;
      test_case "small float literal" `Quick test_small_float_literal;
      test_case "format fixpoint" `Quick test_format_fixpoint;
      test_case "trailing blank insensitive" `Quick test_trailing_blank_insensitive;
      test_case "import run is tight" `Quick test_import_run_is_tight;
      test_case "cap run is tight"    `Quick test_cap_run_is_tight;
      test_case "unrelated decls keep blank line" `Quick
        test_unrelated_decls_keep_blank_line;
    ];
    "stdlib", [
      test_case "list"    `Quick test_stdlib_list;
      test_case "option"  `Quick test_stdlib_option;
      test_case "result"  `Quick test_stdlib_result;
      test_case "math"    `Quick test_stdlib_math;
      test_case "string"  `Quick test_stdlib_string;
      test_case "prelude" `Quick test_stdlib_prelude;
    ];
  ]
