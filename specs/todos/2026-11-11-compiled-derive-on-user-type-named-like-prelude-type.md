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
