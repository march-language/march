(** March compiler entry point. *)

let () =
  let _lexer = March_lexer.Lexer.token in
  let _typecheck = March_typecheck.Typecheck.check_module in
  let _codegen = March_codegen.Codegen.compile in
  let _capabilities = March_effects.Effects.check_capabilities in
  Printf.printf "march 0.1.0 — not yet implemented\n"
