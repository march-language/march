`[P3]` - [ ] **`from_json` resolved by the result type: interpreter and compiled code disagree on what is accepted.**

Filed 2026-10-12 by the interpreter-vs-compiled differential sweep (group V).
Related to, but not the same as,
`2026-10-03-derive-json-same-short-name-two-modules.md`.

**1. A primitive target.** `specs/lang/types/accept/t142_json_ordinary_type_in_cap_module.march`:

```march
let n : Int = from_json("1")
```

typechecks. Interpreted it fails at run time (`from_json: cannot determine
target type from JSON value`); compiled it is rejected after typechecking
(``error: `from_json` (called from `main`) is not a function in scope and not
a runtime builtin``). Neither runs it. Either the typechecker should reject
a `from_json` whose target has no `JsonFrom` impl (and whose argument is a
`String`, not a `Json` value), or both backends should decode it.

**2. Several derives in one module, target fixed only by later use.**
`test/stdlib/test_derive_json_multi.march` (three `derive Json` types in one
module; `match from_json(pj) do Ok(p2) -> … p2.x …`) prints all three
round-trips interpreted (the interpreter picks the decoder from the JSON
shape) but does not compile:

```
error: ambiguous interface-method call to `from_json`: 3 implementations are
in scope (JsonFrom$Shape.from_json, JsonFrom$Color.from_json,
JsonFrom$Point.from_json) and the call site's types do not determine which one
applies.
```

The compiled rule is the documented one (dispatch on the result type); the
interpreter's shape-guessing accepts programs compiled code rejects. Decide
which is the language rule (specs/2026-07-31-json-from-json-dispatch-design.md)
and make the other backend match; the test file should then state its target
types.
