# The stdlib self-check test was vacuous for any call into another stdlib module

Landed 2026-09-22.

## The hole

`test/test_compiler.ml`'s `assert_stdlib_file_typechecks_cleanly` guarded five
stdlib files against internal type errors that `bin/main.ml` hides (its
`is_user_file` filter drops any diagnostic spanned in stdlib). It typechecked
the file **completely alone** — one `DMod` through `check_module_core`, no
siblings — and the test comment argued that was sufficient, because the bug it
was written for (a tuple-arrow callback annotation) is internal to one file.

It is not sufficient for anything that calls another module. `stdlib/ordered_map.march`
had five real errors and the test was GREEN:

```march
fn keys(m) : List(k) do List.map(tree_to_list(m.tree, Nil), fn (k, _) -> k) end
fn from_list(pairs, cmp) do List.fold_left(new(cmp), pairs, fn m -> fn (k, v) -> put(m, k, v)) end
```

`fn (k, _) -> k` is a TWO-PARAMETER lambda, not a pair callback, and
`fold_left`'s first two arguments are swapped. With no `List` module in the
check, `List.map` resolves through `Module_registry.ensure_loaded`, and
`load_module_into_env` (`lib/typecheck/typecheck_env.ml:1235`) binds every
registry export as `Mono (fresh_var 0)` — an unconstrained type variable that
accepts any argument list. Adding `list.march` as a sibling made all five
appear.

The user-visible consequence was total: `OrderedMap.keys/values/from_list`
returned a list of FUNCTIONS, so `List.each(OrderedMap.values(m), println)` was
"expected `s2 -> s2` but got `String`" at the user's own call site, with the
real fault three modules away.

## The fix

`assert_stdlib_file_typechecks_cleanly` now checks the file inside the whole
stdlib, exactly as `bin/main.ml`'s `get_stdlib_tc_env` does: every file in
`Stdlib_manifest.stdlib_file_list` loaded the way `Toolchain.load_stdlib_file`
loads it (prelude desugared as the entry and unwrapped, every other file
`~is_entry:false` and wrapped in its own `DMod`), all of them registered in
`stdlib_source_files`, one `check_module_core`, diagnostics bucketed by span
file. The check is cached, so the five by-name tests and the new ratchet share
one run (~5s).

`stdlib/ordered_map.march`'s three functions are fixed (pair callbacks written
as `fn pair -> match pair do … end`, matching `sorted_set.march`), and
`test/stdlib/test_ordered_map.march` exercises them at runtime — it fails with
"Non-exhaustive pattern match" against the old file.

## Proof it is not vacuous

- Old `ordered_map.march` restored: FAIL, naming all five errors at :241/:256.
- Current tree: green.
- A deliberate error appended to `csv.march`: the ratchet FAILS.
- `test/stdlib/test_ordered_map.march` against the old file: 3 failures.

## What the sweep found

98 errors in 15 stdlib files, all previously invisible.
`test_stdlib_internal_errors_ratchet` pins the per-file counts (two-sided: a
fix must lower the count in the same commit). The backlog is filed as
`specs/todos/2026-09-22-stdlib-internal-type-errors.md` plus one todo per
class. Not fixed here — this PR closes the hole and quarantines what fell out
of it.

Worth stating plainly, since it is the reason the backlog matters: a stdlib
function whose body failed to check is still callable, and its call sites bind
it as an unconstrained metavariable. `string_length(System.os())` typechecks
and dies at runtime. A generic one reaches monomorphization unresolved, which
is the silent boxed-vs-niche wrong-value class `lib/modules/stdlib_manifest.ml`
documents.
