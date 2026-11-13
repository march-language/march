# Scope syntax: several names and string-valued options (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 11. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- Extend `scoped_cap_path` in `lib/parser/parser.mly` (and `tree-sitter-march/grammar.js`) to accept several strings and string-valued options such as `prefix("x")`; scope strings encode as `"a;name=b"`, `";prefix=w."`.

**Done** (Task 11, commit `518c4a00a`; one spelling per encoding settled in Task 12, ruling R16):
the parser, formatter and tree-sitter grammar accept several names and string-valued options,
and the parser refuses the forms that would encode alike.
