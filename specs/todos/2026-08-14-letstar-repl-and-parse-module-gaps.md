`[P3]` - [ ] Two `let*` follow-ups, deliberately scoped out of the initial implementation (`specs/progress/2026-08-14-letstar-generalized-bind.md`, `specs/lang/let-star-generalized-bind.md`):

1. **`stdlib/parse.march`'s `Parser` type doesn't fit `let*`'s dispatch
   convention.** `let*` resolves `M`'s `flat_map` in a module named `M`;
   `Parser`'s `flat_map` lives in a module named `Parse`. `let* p =
   some_parser(); ...` currently fails with a clear "`Parser.flat_map`
   doesn't exist" error rather than working — this was in fact the
   original motivating use case for `let*` (`specs/plans/
   2026-08-09-parsing-and-string-search.md` §4.3's worked example). Fix
   options: rename the `Parse` module to `Parser` (aligns with every other
   stdlib container-type convention — `Option`/`Result`/`List` are all
   named after their primary type, not a verb), or extend `let*`'s
   resolution with a second, explicit path (e.g. an opt-in annotation or a
   registry) for types whose operations live in a differently-named
   module. The rename is probably simpler and more consistent, but touches
   every `Parse.foo(...)` call site across `stdlib/parse.march` and any
   consumers — check blast radius before choosing.

   **Blast radius measured 2026-08-16** (`specs/progress/2026-08-16-parse-usability-pass.md`
   §5), which removes the main unknown here:
   - The **only** consumers of `Parse.` anywhere in the repo are its own two
     test files (`test/stdlib/test_parse.march`, `test_parse_errors.march`) —
     243 call sites, no stdlib module and no example depends on it. The rename
     is therefore cheap and self-contained.
   - `mod X do type X(a) = X(a) ... end` is **legal** (verified), so either
     direction is mechanically possible.
   - A module rename **alone suffices** — no file rename and no
     `lib/modules/stdlib_manifest.ml` change — because the eager stdlib load
     registers each module under its declared `mod` name, and (since the
     2026-08-16 fix) `let*` resolves `flat_map` from the current scope rather
     than by guessing a filename.
   - **Both directions stutter**, which is the real reason this is still open:
     `mod Parse` → `mod Parser` makes external type annotations read
     `Parser.Parser(a)`; renaming the *type* `Parser` → `Parse` gives
     `Parse.Parse(a)` instead but keeps all 243 `Parse.foo(...)` call sites
     working, so it is strictly less churn.

   Worth deciding at the same time: the stutter is forced by `let*`'s
   "module name == type name" convention itself, which cannot be satisfied
   *without* stutter by any module that defines both a type and its
   operations. If more such types are expected, fixing the convention (a
   second, explicit resolution path) may beat renaming each library to fit
   it. Documented for users meanwhile in `docs/parsing.md`.

2. **`let*` has no REPL support.** `let?` has a dedicated `ReplLetQ`
   top-level AST form with its own `Result`-hardwired typecheck/eval path
   (`lib/repl/repl.ml`) for binding into the REPL session's persistent
   environment across statements. `let*` has no equivalent — `let* x = e`
   typed at the REPL prompt is currently a parse error (the `LET; STAR`
   productions were deliberately NOT added to `repl_input`/`repl_sequence`
   in `lib/parser/parser.mly`), not a crash, but also not supported. Adding
   it needs a `ReplLetStar` variant and a generalized (not
   `Result`-hardwired) REPL eval path doing the same `type_name_of_value`
   dispatch the ordinary interpreter path already does
   (`lib/eval/eval.ml`'s `ELetStar` case is the template).
