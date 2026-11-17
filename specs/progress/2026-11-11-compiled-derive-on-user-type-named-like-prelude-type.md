`[P3]` Compiled: `derive Show` on a user type named like a prelude type does not compile

```march
mod Main do
  needs IO.Console
  type Result = Won(Int) | Lost
  derive Show for Result
  fn main(c : Cap(IO.Console)) do
    print_line(to_string(Won(3)))
  end
end
```

- Interpreted: `Won(3)`.
- `--compile`: `error: ambiguous interface-method call to show: … implementations are in scope …
  and the call site's types do not determine which one applies` (the list has no `Show$Result`).

The typechecker gives the user's `Result` its own identity
(`specs/progress/2026-11-02-typecheck-conflates-same-short-named-types.md`), but the backends
key a type by its short name (`Lower_types.convert_ty` maps the identity back), and `Result` is
a name mono and the impl tables special-case. Not checked on the commit before that fix; the
typechecker change does not reach the names TIR sees, so it is expected to predate it. The same
program with a name no prelude type has (`Outcome`) compiles. Probably needs the user type's TIR
name kept distinct (as `Lower_types` does for the handle names with `$Handle`), or the
declaration rejected.

## Fixed 2026-11-16

Two compiled-backend bugs, both from the TIR keying a user type by the builtin's bare name.

1. **The type's name.** `Lower_types.convert_ty` mapped every typecheck identity back to its
   short name, so the user's `Main.Result` became `Result`, the builtin `Result(a, b)`. Its
   derived `Show$Result.show` was then deduplicated against the prelude's, and the call
   resolved to nothing. A user type whose short name is a builtin ADT (`Option`, `Result`,
   `List`: `Lower_types.builtin_adt_names`) now keeps its identity as its TIR name, at every
   site that names it: `convert_ty`, `lower_ty` (via `Typecheck_nominal.ref_identity`), the
   declaration in `Lower` and in the early collision walk, the ctor table in `Lower_state`,
   and the impl head in `collect_iface_impls`, which does not re-qualify it. Nested types
   already had this name (`Inner.Result`); only the call-site types were wrong, so a nested
   `type Result` with a derive failed the same way.
2. **The builtin's layout.** A nested `type Option(a)` made the short name `Option` colliding,
   and `Collision_set.is_colliding` then forced the builtin `Option` Boxed and globally tagged.
   `string_to_int` still returns the runtime's niche `Option(Int)`, so a `match` on it read the
   raw pointer as a tagged cell: SIGSEGV at 0x5d. This happened on `main` with a bare
   declaration and no derive. The builtin ADTs' exact bare names are never colliding now; a
   user type shadowing one still is, so it is Boxed and globally tagged everywhere. The two
   raw table lookups in `drop.ml` go through `is_colliding` too.

Regression: `test/test_codegen.ml` "user type named like a builtin ADT keeps its identity"
(a top-level `type Result` with `derive Show, Eq`, a nested `type Option(a)` with `derive Show`,
the builtin `Option` from `List.head_opt` and from `string_to_int`), checked against the
interpreter and compiled at `--opt 0` and `2`. RED on `bd2ff7958`: the compile error above.

Not fixed here, filed separately (all reproduce before this change):
`todos/2026-11-16-nested-type-named-like-builtin-leaks-to-parent-scope.md`,
`todos/2026-11-16-toplevel-type-list-breaks-generated-code.md` and
`todos/2026-11-16-interp-user-option-show-captures-builtin.md`.

### Follow-up: the layout split the TIR verifier caught (2026-11-16)

CI's `cross-linux-oracle` compiles with `MARCH_VERIFY_TIR=1`. It failed on
`specs/lang/golden/g49_user_type_named_like_base_type.march`, a top-level `type Option(a) = Some(a) | None`,
with exit 3. `Kind.canonical_name` folded `Main.Option` to its short name `Option`. Once the builtin
`Option` stopped being colliding, that name pointed at the builtin, so allocation (`is_niche_shaped`)
chose the niche layout. `Kind.repr_of` sees the qualified, colliding name and chose Boxed. The program
still printed the right answer, but encode and decode decided the layout separately, which the
verifier's repr checks forbid.

`canonical_name` now leaves a name that shadows a builtin ADT unchanged (`Collision_set.shadows_builtin_adt`).
The verifier's collision-tag check skips the exempt builtins, which keep their runtime-fixed tags. The
regression test compiles with the verifier on; it fails without the `canonical_name` change.
