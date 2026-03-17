# March compiler

March is a statically-typed functional language (ML/Elixir hybrid) compiled with OCaml 5.3.0.

## Build & test

The opam switch is `march`. `opam` and `dune` are available directly in PATH — no wrapper needed.

```
dune build          # build everything
dune runtest        # run all 40 tests
dune exec march -- file.march   # run the compiler
```

## Project layout

```
bin/main.ml                 compiler entry point (parse→desugar→typecheck→eval)
lib/ast/ast.ml              AST types (span, expr, pattern, decl, …)
lib/lexer/lexer.mll         ocamllex lexer
lib/parser/parser.mly       menhir parser
lib/desugar/desugar.ml      pipe desugar, multi-head fn → single EMatch clause
lib/typecheck/typecheck.ml  bidirectional HM type inference
lib/eval/eval.ml            tree-walking interpreter
lib/errors/errors.ml        diagnostic type (Error/Warning/Hint + span)
lib/effects/effects.ml      (placeholder)
lib/codegen/codegen.ml      (placeholder)
test/test_march.ml          alcotest suite
```

## Pipeline

1. Parse (`March_parser.Parser.module_`)
2. Desugar (`March_desugar.Desugar.desugar_module`)
3. Typecheck (`March_typecheck.Typecheck.check_module`) — prints diagnostics, exits 1 on errors
4. Eval (`March_eval.Eval.run_module`) — calls `main()` if present
