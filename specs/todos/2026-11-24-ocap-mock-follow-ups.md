`[P3]` `mock` follow-ups from phase 7a (2026-11-24)

- **Handler records are never freed.** The mock registry keeps each `mock` entry's
  handler for the life of the process (closures made inside the block may reach it after
  the block ends, and the registry cannot run the record's drop glue). Bounded by the
  number of `mock` entries a test binary executes; a mock entered in a long loop grows.
- **A covered operation without a handler panics on refusal.** `mock_fallthrough` panics
  when the authority outside the mock refuses the real operation, because the builtin's
  own result type cannot carry a `CapError`.
- **`ClusterNode.start` reports a refusal as a `String`** (its existing error type), not a
  `CapError`.
- **Named handler types.** The plan named the handler records `Mock.Console`, ... with
  all-`None` constructors; 7a types a named handler structurally (the kind's record) and
  has no `Mock` module: a partial record literal in the `with` position covers the common
  case.
- **The interpreter does not run nested supervisors' children** in
  `test/cap_mock/cap_mock_supervised_nested.march` (with or without the mock; pre-existing),
  so that fixture is compiled-only.
