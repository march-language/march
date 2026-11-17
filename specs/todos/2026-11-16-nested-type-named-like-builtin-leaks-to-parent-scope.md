`[P2]` Typecheck: a nested module's `type Result` hides the builtin in the enclosing module

```march
mod Main do
  needs IO.Console
  mod Inner do
    type Result = Won(Int) | Lost
    derive Show for Result
    fn won(n : Int) : Result do Won(n) end
  end
  fn main(c : Cap(IO.Console)) do
    print_line(to_string(Inner.won(3)))
    let r : Result(Int, String) = Ok(1)
    print_line(to_string(r))
  end
end
```

`march --check`: ``Result` expects 0 type argument(s) but got 2. [type_arity]`` at the `let r`
annotation, in both the interpreter and `--compile`.

By the lexical rule in `lib/typecheck/typecheck_nominal.ml` ("a bare `Note` means the innermost
enclosing module that declares a type `Note`"), `Main` declares no `Result`, so the annotation
means the builtin `Result(a, b)`. The nested declaration's arity reaches the outer scope instead,
probably through a short-name-keyed arity check. Found while fixing
`specs/progress/2026-11-11-compiled-derive-on-user-type-named-like-prelude-type.md`; reproduces on
`bd2ff7958` (before that fix).
