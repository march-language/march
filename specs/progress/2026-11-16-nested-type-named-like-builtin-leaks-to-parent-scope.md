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

## Fixed 2026-11-19

**Root cause.** The same short-name-keyed type table as
`2026-11-16-toplevel-type-list-breaks-generated-code.md`, by two routes. Inside `Inner`,
`check_decl` registered the bare `Result` at arity 0 over the builtin's 2
(`lib/typecheck/typecheck.ml:8204`). Then the nested module's export step copied every public
bare key of `inner_env.types` into the enclosing env (`new_types`, `:8726`), last writer wins
(`StrMap.union` at `:8911`), so the bare `Result` in `Main` had arity 0 although the lexical
rule resolves `Result` written in `Main` (which declares none) to the builtin.

**Fix.** `Typecheck_env.add_decl_type` (see the sibling entry) never lets a base-type-shadowing
declaration claim the bare key, and the export step skips the bare key of a type this module
declares under such an identity (`shadows_base_bare`). The type is still reachable as
`Inner.Result` and by its identity.

Regression: `test/test_codegen.ml` "nested `type Result` does not hide the builtin outside"
(interpreted, and compiled at `--opt 0` and `2`). RED before the fix with the reported error.
