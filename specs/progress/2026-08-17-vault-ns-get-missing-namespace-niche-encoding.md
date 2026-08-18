# Vault.ns_get on a never-written namespace returned Some(garbage), not None

`march_vault_ns_get` (`runtime/march_extras.c`) took a shortcut on the
namespace-missing path: it hand-built an "Option" by `march_alloc(16)` with a
tag word of 0 at offset 8, mimicking a boxed `None`. But Option is
niche-encoded across the whole runtime (see `make_some`/`make_none` in the
same file, ~line 299): `None` is the NULL pointer itself, `Some(v)` is `v`
itself — there is no boxed tag/payload struct. The hand-built value was a
non-NULL pointer, so every read of it decoded as `Some(<uninitialized
pointer>)` instead of `None`. Destructuring that `Some` payload dereferences
garbage — hangs or OOMs in compiled binaries. The tree-walking interpreter
takes a separate `march_vault_get`/registry path and was unaffected.

Fix: return the real `make_none()` (NULL) on that path, mirroring what
`march_vault_get` already does for a missing key.

Added a compiled regression test (`test_compiled_vault_ns_get_missing_namespace`
in `test/test_stdlib_suite.ml`, `adversarial-regressions` suite, `Slow`):
compiles a program that calls `Vault.ns_get` on a namespace that was never
written and asserts the match arm taken is `None`, exiting nonzero if `Some`
is (wrongly) taken. Passes with the fix; the bug only manifests when
compiled, so no interpreter-level (`eval_with_vault`) test would have caught
it.

Separately noted but not fixed here: `forge test` (`forge/lib/cmd_test.ml`
~163-192) uses the first test file as the sole compile entry and silently
skips test modules that fail to compile — the suite still reports 0 failures
with a lower test count. Filed as a todo:
`specs/todos/2026-08-17-forge-test-silent-skip-on-compile-failure.md`.
