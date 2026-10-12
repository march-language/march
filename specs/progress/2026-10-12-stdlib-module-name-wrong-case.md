# A wrong-case stdlib module name typechecked and ran compiled

**Date:** 2026-10-12. Found by the interpreter-vs-compiled differential sweep
(group V).

## What was wrong

```march
println(BigInt.to_string(Bigint.from_int(3)))
```

There is no module `Bigint` (it is `BigInt`). The program typechecked; the
compiled binary printed `3`; the interpreter died
`unbound variable: Bigint.from_int`.

`Module_registry.find_stdlib_file` guessed the file from the CamelCase name
(`Bigint` -> `bigint.march`) and accepted the guess whenever the file existed,
without checking what module the file declares. `ensure_loaded "Bigint"` then
registered BigInt's exports under the misspelling, so every qualified lookup
of `Bigint.x` resolved. The same held for the other stdlib files whose
declared name is not the CamelCase of the filename (`Uuid`/`UUID`,
`Iolist`/`IOList`, `Datetime`, `Dataframe`, `Websocket`, `Pubsub`, `Crdt`,
`Io`, and `Audio`/`Canvas`/`Dom` for the `Js.*` modules). Nothing in the repo
used those spellings.

## The fix

- `lib/modules/module_registry.ml`: the filename guess counts only when the
  file's first top-level `mod` is the requested name
  (`declared_module_of_file`, new, exported); otherwise the declared-name
  index decides, as it already did for `RRB`.
- `lib/typecheck/typecheck_env.ml`: `suggest_module_name` compares against the
  name each stdlib file declares and accepts a case-only difference, so the
  error reads ``Unknown module `Bigint`. Did you mean `BigInt`?``.

## Tests

`test/test_compiler.ml`: `stdlib module name wrong case` (rejected, with the
suggestion; the correct spelling still typechecks).
