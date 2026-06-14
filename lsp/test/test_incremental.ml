(* Tests for the Phase 5 incremental typecheck engine:
   env-returning incremental check, cached stdlib/deps envs, run_tir_pass memo. *)

module Tc = March_typecheck.Typecheck
module An = March_lsp_lib.Analysis

(* Wrap bare declarations in a module so they parse (March requires an
   explicit `mod Name do ... end`). *)
let parse decls =
  let src = "mod M do\n" ^ decls ^ "\nend\n" in
  let lb = Lexing.from_string src in
  March_desugar.Desugar.desugar_module
    (March_parser.Parser.module_
       (March_parser.Token_filter.make March_lexer.Lexer.token) lb)

(* ── Increment 0: check_module_with_env_full ─────────────────────────────── *)

let test_with_env_full_returns_env () =
  let base = parse "  fn helper() : Int do 41 end" in
  let (_e, _tm, base_env) = Tc.check_module_full base in
  let user = parse "  fn g() : Int do helper() end" in
  let (_errs, _tm2, final_env) = Tc.check_module_with_env_full base_env user in
  Alcotest.(check bool) "g bound"      true (Tc.StrMap.mem "g" final_env.Tc.vars);
  Alcotest.(check bool) "helper bound" true (Tc.StrMap.mem "helper" final_env.Tc.vars)

let () =
  Alcotest.run "incremental"
    [ "with_env_full",
      [ Alcotest.test_case "returns final env" `Quick test_with_env_full_returns_env ] ]
