# file_*/dir_* builtins declare a bare `FileError` that no ptype declares

Split out of `specs/progress/2026-09-08-file-dir-builtins-fileerror-representation-fix.md`
(originally the "Related, separate gap" section of the 2026-08-08 todo it
closed). The representation bug is fixed; this naming gap is not.

`lib/typecheck/typecheck_builtins.ml` registers every `file_*`/`dir_*`
builtin's error type as the bare, unqualified `FileError`
(`TCon("FileError", [])`), while the only real `ptype FileError` is declared
inside `mod File` (`stdlib/file.march:12`) and compiles as
`File.FileError`. Two consequences, both still live:

- Compiled `to_string` / `Show` on one of these `Err` payloads prints
  `#<tag:0>` instead of the interpreter's `NotFound("...")`, because
  monomorphization needs the concrete type name to find a printer and no
  type is named bare `FileError`.
- March source cannot pattern-match these payloads by constructor name at
  all: `Err(NotFound(p))` and `Err(File.NotFound(p))` both fail to typecheck
  against the bare-typed result. Only `Err(e)`, treated opaquely, works.

The second is the one that bites ordinary application code — error handling
on file IO cannot branch on the error kind, only stringify it.

Likely fixes: (a) qualify these builtins' declared error type as
`File.FileError` in the typechecker table, or (b) register a bare top-level
alias for `FileError` resolving to the same compiled type-def. Needs
investigation into how other module-qualified ptypes used by bare builtins
are handled elsewhere before picking one.

Note that `test_compiled_file_dir_err_are_real_fileerrors` in
`test/test_stdlib_suite.ml` currently accepts `#<tag:N>` as a valid compiled
output precisely because of this gap. Closing this todo should tighten that
test to require the constructor form.
