`[P3]` Some stdlib calls are never translated as a call's subject, so a lemma about them cannot help.

Found 2026-11-04 building stdlib lemma sweep S1 (`specs/2026-11-04-stdlib-lemma-sweep-design.md`
§2.1). Each lemma below proves, but a caller's precondition over the call stays
`unreflectable-subject` ("the argument … could not be translated to SMT, so no goal was built")
whether or not the lemma is called first:

```march
fn need_eq(a : Int, b : {Int | _ == a}) : Int do 0 end
fn need_b(a : Bool, b : {Bool | _ == a}) : Int do 0 end
fn need_oeq(a : Option(Int), b : {Option(Int) | _ == a}) : Int do 0 end

need_eq(x, Option.unwrap_or(Some(x), d))         -- let-bound, the same call proves
let a = Option.is_some(o)                        -- also Result.is_ok / is_err
let b = Option.is_none(o)
need_b(a, !b)
let h = List.head_opt(Cons(x, xs))
need_oeq(Some(x), h)
```

By contrast `Result.to_option(Option.to_result(o, e))` (an `Option` subject) and a `let`-bound
`Result.unwrap_or(Ok(x), d)` prove by unfolding. So it is not "every `Option`" or "every
polymorphic call": find which shapes the subject translator refuses (a direct polymorphic
argument; a `Bool` from a `match`; `head_opt`'s `Cons(h, _)` pattern?).

Done when each call above is translated as a subject, and the `Option` / `Result` lemmas of
the sweep design's §2.1 (`unwrap_or`, `is_some` / `is_none`, `is_ok` / `is_err`, `head_opt`)
ship with `reflect-stdlib-sweep` cases.
