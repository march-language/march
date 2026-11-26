`[P3]` An entry-module `let` that names an earlier `let` fails to compile in a function that uses only the later one

Found while checking function-local fresh names
(`specs/progress/2026-11-26-function-local-fresh-counters.md`). It is not caused by that change:
the compiler before it fails the same way.

`Lower.lower_module` folds each top-level `let` of the entry module into every function whose
body mentions the let's name (`fn_body_uses`, "Inject top-level let bindings into function
bodies that reference them"). It looks at the function's body only, not at the initialisers it
is about to fold in, so a let reached only through another let is left out:

```march
mod M do
  needs IO.Console
  fn mk(n : Int) : List(String) do
    if n == 0 do Nil else Cons(int_to_string(n), mk(n - 1)) end
  end
  let names = List.map(mk(4), fn s -> s ++ "!")
  let label = String.join(names, ",")
  fn show_label(n : Int) : Int do n + String.byte_size(label) end
  fn main(_c : Cap(IO.Console)) do
    println(int_to_string(show_label(1)))
  end
end
```

`show_label` gets `let label = String.join(names, ",")` with no binding for `names`.
`march --compile` ends in `clang failed (exit 1)`; `--verify-tir` names it: ``in `show_label`:
[tir-mono] variable `names` is not bound``. `main` is unaffected (it gets every let).

Fix direction: close `needed` over the lets each needed initialiser mentions, keeping
declaration order.
