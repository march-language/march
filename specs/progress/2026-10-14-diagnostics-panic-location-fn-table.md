Diagnostics crash reports: compiled panic location and a function table (2026-10-14)

Follow-up to `progress/2026-10-14-runtime-diagnostics-crash-observers.md`;
items 1 and 3, and part of 2, of
`todos/2026-10-14-diagnostics-backtrace-followups.md`. Compiled crash reports
used to carry no `location` and frames with no file or line, named by
`dladdr` (macOS only; Linux reported an empty backtrace) with mangled names
(`$lam0__lam0__top$apply$1_Fragile_Poison`).

## Panic location

`lib/tir/lower_expr.ml` lowers a direct `panic` / `todo` / `unreachable`
call (outside the prelude, not a local binding of that name) as
`__panic_site(file, line); <the call>`. `march_panic_site`
(`runtime/march_runtime.c`) stores the literal and line on the proc (TLS off
the scheduler: `todo` goes through the prelude wrapper, which can hit a
reduction check and resume on another OS thread). Every `march_panic` takes
and clears it, reported or not, and passes it to the observers as
`DiagCrash`'s two new fields; `Diagnostics.report_of` turns it into
`location`. It costs nothing unless the panic happens. The interpreter
reports the same site: the innermost call outside the prelude, when it is a
call to `panic` / `todo` / `unreachable`.

No location (both backends): a panic raised inside a prelude helper
(`unwrap`), `assert`, non-exhaustive matches, runtime errors. A user's own
top-level `panic` cannot be told apart in lowering (the prelude's functions
are in `_current_module_fns` too); one that does not panic leaves a site the
next siteless panic reports, and every panic clears it.

`__panic_site` is a lowering-only builtin: `llvm_builtins` (row + preamble
declare), `defun` builtin_names, `borrow` (both args borrowed), `purity`
(impure: never CSE'd or dropped), `alloc_contract` (allocates nothing),
`js_emit` (no-op), and a `runtime/march_runtime_wasm.c` stub.

## Function table

`Llvm_toplevel.fn_table_block` appends, for a native program with a `main`,
`@march_fn_table` (`{fn, name, file, line}` for every function the module
defines, in definition order; `alwaysinline` helpers left out), its length,
and `@march_text_end`, an empty function defined last that bounds the last
entry. `main` calls `march_fn_table_register` before spawning the March
`main`. Names come from the provenance side table: the source function
without the specialisation suffixes (`List.append$dps$...` -> `List.append`),
a lambda as `<host>.{fn}`; file and line are the function's definition span.
Glue with no span (drop glue, closure wrappers, actor dispatch) is an
unnamed entry: bounded, never reported.

The runtime sorts the table on first use (not at startup), maps each return
address to the entry at or below it (inside `[first, march_text_end)`, else
runtime code), and keeps only named entries, so the panic machinery and the
scheduler drop out with no symbol names at all. A table whose end marker is
not above every function is not used, and `dladdr` (the old path) remains
for a program without a table.

Cost: about 32 bytes per function plus names (43 entries for the fixture),
and the out-of-line copies of functions LLVM inlined everywhere, which the
table now keeps alive past `-dead_strip` / `--gc-sections` (3 small functions
in `bench/binary_trees`; +240 bytes in `bench/tree_transform`, +200 in
`bench/list_ops`; the +16 KB `binary_trees` showed is one arm64 page of
segment alignment). Their callees are their inlined copies' callees, so the
capability-by-absence set does not change. Benchmarks within noise.

## Also fixed

An observer that panicked inside its own `try_finally` (`with_context`,
`Logger.with_scope`) re-raised onto the observer landing before
`march_panic` cleared `march_panic_reraise`, so the flag stayed set and the
next real crash was not reported. The flag is now taken first.

## Tests

`test/native/diagnostics_crash_observers.march` (both backends, one
`.expected`): the location is exactly the `panic` line and, through a new
`Fragile.Later` handler, the `todo` line; every frame has a name, file and
line, and one is in the fixture; the main panic is still reported after an
observer panicked inside its own `with_context`. Perturbation: dropping the
lowering arm reddens it. `scripts/triage.sh --deep`: interpreted and compiled
match under every optional-pass switch; ASAN+UBSan clean.
