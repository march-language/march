> **Landed 2026-09-11.** Root cause was not the bare `FileError` in the
> builtin tables (that spelling is correct: March has one global type
> namespace, a module-declared type's canonical identity is its bare name, and
> a qualified annotation `File.FileError` canonicalizes to it in `surface_ty`).
> It was `load_module_into_env`'s cross-module constructor arm minting a
> QUALIFIED parent type (`ci_type = "File.FileError"`), so a value produced by
> `Err(File.NotFound(p))` could never unify with the bare `FileError` every
> annotation and builtin denotes — "expected `FileError` but got
> `File.FileError`". That arm now uses the bare parent type, matching every
> in-file constructor site. A first attempt that qualified both builtin tables
> instead is recorded in the design spec as the wrong turn.
>
> **Deliberately NOT closed here:** compiled `to_string` of such an error still
> prints `#<tag:N>`, because the ctor-descriptor table is keyed by the lowered
> qualified name while call sites look it up by the bare static one. Aliasing
> the bare suffix was tried and **deterministically SIGSEGVs** (40/40 runs of
> `native_actor_monitor_down_reason`, against 0/30 on main); two narrowings of
> that alias did not help. The full measurement trail, the two ruled-out
> mechanisms and three alternative designs are in
> `specs/todos/2026-09-11-compiled-to-string-of-module-declared-type.md`.
> `test_stdlib_suite.ml`'s table therefore keeps accepting `#<tag:N>`, and
> `test/native/file_error_ctor_match.march` prints a classification string
> rather than the error value.
>
> While that alias was briefly in place it did expose a SEPARATE backend
> divergence, which is fixed and kept: the interpreter's `file_rename`
> reported a bare strerror message where the compiled runtime and every other
> file builtin carry `"<path>: <strerror>"` (OCaml's `Sys.rename` does not
> include the path, unlike `open_in_bin`).
> Design: `specs/2026-09-11-correctness-fixes-design.md` §2. Original filing
> follows.

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

> **Design spec (2026-09-11):** `specs/2026-09-11-correctness-fixes-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
