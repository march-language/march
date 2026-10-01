# hcr stdlib actors driver tests: expect the qualified `NodeQueue__Writer`

**Fixed 2026-10-01.** `hcr stdlib actors` cases 3 and 4 (`test/test_hcr_stdlib_actors.ml`)
failed on main on every CI leg (ubuntu `compiler`, macOS `all`) after #726 and #727 merged.
Each PR was green alone; together they made a semantic merge conflict. #727 added the tests and
looked for the stdlib Writer actor as `@Writer_dispatch(` and `Writer_Credit`. #726 changed desugar
to qualify stdlib actors, so the program now emits `NodeQueue__Writer_dispatch` and
`NodeQueue__Writer_Credit`. #734 fixed the tests to look for the qualified names. There was no compiler change.
