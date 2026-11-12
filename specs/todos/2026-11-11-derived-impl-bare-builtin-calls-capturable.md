`[P3]` A derived `Hash` / `Json` body calls a user fn named `int_wrapping_add`, `int_wrapping_mul` or `float_to_int`

Found 2026-11-11 while fixing
`specs/progress/2026-11-10-derived-impl-calls-user-fn-named-like-method.md`. Same shape as that
bug, for plain builtins instead of interface methods. Both backends agree, both are wrong:

```march
mod Main do
  needs IO.Console
  type J = { n : Int }
  derive Json for J
  fn float_to_int(_f : Float) : Int do 99 end
  fn main(_c : Cap(IO.Console)) do
    let k : Result(J, DecodeError) = from_json(to_json({ n: 5 }))
    match k do
      Ok(v) -> println(to_string(v.n))     -- prints 99, want 5
      Err(_) -> println("err")
    end
  end
end
```

`derive Hash` on a record with two or more fields mixes the field hashes with bare
`int_wrapping_add` / `int_wrapping_mul` (a user fn of either name returning 0 makes every hash
equal), and `derive Json` decodes an `Int` field with bare `float_to_int`.

The interface methods had a qualified spelling to switch to (`Show.show`); a plain builtin has
none. Tried and rejected: prelude helpers (`pfn __derive_hash_mix`) that the derive calls. They
work, but once the prelude itself calls `float_to_int`, the `prelude_collision` check turns every
user `fn float_to_int` into a hard error, derive or not. Options: an unshadowable spelling for a
builtin that generated code can use (needs a typechecker binding), or helpers in a stdlib module
the derive already depends on (`Json.` for the decode; `Hash` has no module).

Also seen, not investigated: a first-class `let f = show` (or `Show.show`) fails to link compiled
(`use of undefined value '@show'`), with no user fn involved.
