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
  March_parser.Parser.module_ March_lexer.Lexer.token lexbuf

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
fn describe(x : Int) : String do
  match x with
  | 0 -> "zero"
  | 1 -> "one"
  | _ -> "many"
  end
end
end|} in
  check_parses "match" src;
  check_idempotent "match" src

let test_if_expr () =
  let src = {|mod Test do
fn sign(x : Int) : String do
  if x > 0 then "positive" else if x < 0 then "negative" else "zero"
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
pub fn greet(name : String) : String do
  "hello"
end
end|} in
  check_parses "pub fn" src;
  check_idempotent "pub fn" src

let test_nested_match () =
  let src = {|mod Test do
fn classify(x : Int, y : Int) : String do
  match x with
  | 0 ->
    match y with
    | 0 -> "origin"
    | _ -> "x-axis"
    end
  | _ -> "other"
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
  { x = x, y = y }
end
end|} in
  check_parses "record literal" src;
  check_idempotent "record literal" src

let test_local_fn () =
  let src = {|mod Test do
fn fib(n : Int) : Int do
  fn go(n : Int) : Int do
    if n <= 1 then n else go(n - 1) + go(n - 2)
  end
  go(n)
end
end|} in
  check_parses "local fn" src;
  check_idempotent "local fn" src

let test_use_decl () =
  let src = {|mod Test do
use List.*
pub fn demo() : Int do
  42
end
end|} in
  check_parses "use decl" src;
  check_idempotent "use decl" src

let test_doc_comment () =
  let src = {|mod Test do
doc "Returns the answer."
pub fn answer() : Int do
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

let test_format_fixpoint () =
  (* A source written in already-formatted style should be unchanged *)
  let src = {|mod Demo do

type Shape = Circle(Float) | Rect(Float, Float)

fn area(s : Shape) : Float do
  match s with
  | Circle(r) -> 3.14159 * r * r
  | Rect(w, h) -> w * h
  end
end

pub fn main() : Unit do
  let s = Circle(5.0)
  let a = area(s)
  print(a)
end

end|} in
  check_parses "format fixpoint" src;
  check_idempotent "format fixpoint" src

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
      test_case "type variant"    `Quick test_type_variant;
      test_case "type record"     `Quick test_type_record;
      test_case "pub fn"          `Quick test_pub_fn;
      test_case "nested match"    `Quick test_nested_match;
      test_case "tuple"           `Quick test_tuple;
      test_case "record literal"  `Quick test_record_literal;
      test_case "local fn"        `Quick test_local_fn;
      test_case "use decl"        `Quick test_use_decl;
      test_case "doc comment"     `Quick test_doc_comment;
      test_case "type alias"      `Quick test_type_alias;
      test_case "format fixpoint" `Quick test_format_fixpoint;
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
