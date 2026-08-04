# Per-module capability attribution

Shipped 2026-08-04. `forge cap inspect` now reports which module's code
performs each capability's IO, not only that the binary performs it.

    Capabilities — ./myapp
      IO.Console              [march_print]
      IO.FileRead             [march_file_read]

    Attributed to
      IO.Console            MyApp
      IO.FileRead           StdDep

## Why this had to be a pre-inline TIR pass

The obvious implementation is a codegen side effect: `Llvm_builtins.mangle_extern`
already records every cap-bearing C symbol it resolves, and `emit_fn` already
sets `ctx.cur_emit_fn`, so pairing them looks like a two-line change.

It is wrong, and wrong in the dangerous direction. Measured before writing any
code: a two-line `BigLib.load` calling `file_read`, called from `main`, leaves
**no trace of `BigLib` in the emitted IR at all** — the inliner folds it into
the caller and the `march_file_read` call site lands in `@march_main`. Codegen
attribution would report that the *application* reads files and the dependency
does not: a false clean bill for exactly the party you are inspecting.

So `Cap_attrib.attribute` runs on the pre-`Opt.run` TIR, where module prefixes
still exist (verified: `@BigLib.load` survives to emitted IR when the function
is too large to inline), over a `Dce.prune_unreachable` copy, so a dependency
feature nothing calls contributes no owner row.

Both passes are pure, so this observes the pipeline without perturbing it.

## The stdlib-wrapper problem, and the transparent-module walk

First working version reported `IO.FileRead ← File` for a dependency that read
a file through the stdlib's `File.read`. Since most dependencies reach IO
through a stdlib wrapper, every capability in a real program landed on a
handful of stdlib modules — a report that names the same owner regardless of
which dependency is responsible answers nobody's question, and would have made
the per-dependency budgets this feature exists to enable impossible.

`attribute ~transparent` therefore walks the reverse call graph through stdlib
modules to the nearest non-stdlib callers. The transparent set is derived from
the stdlib declarations actually loaded (`stdlib_module_names` in `bin/main.ml`,
mirroring `stdlib_span_files`), **not** from a hand-maintained name list —
`Resolver.stdlib_module_names` is the cautionary example, having carried
`Depot*` names that ship in a third-party package and a mis-cased `URI` that
was never a module.

The entry module is never transparent; seeing through it would leave a
capability with nowhere to land.

## Marker encoding

`@__march_capfrom_<CAP>__<OWNER>`, pinned in `@llvm.used` like the flat
markers so `-dead_strip` cannot drop them.

Two encoding decisions that are load-bearing:

- The prefix is **not** a longer `__march_cap_` name. `Cap_binary` matches that
  prefix and takes the whole remainder as the capability path, so
  `@__march_cap_IO_FileRead__BigLib` would decode as a bogus capability named
  `IO_FileRead__BigLib`. `__march_capfrom_` diverges at the 12th character.
  Pinned by a test.
- The owner is emitted **verbatim**, dots and all (LLVM global names permit
  them). Mangling `.`→`_` would be irreversible: a module named `My_Mod` and a
  nested module `My.Mod` would share one encoding.

Capability paths never contain `__`, so splitting the remainder on the first
`__` recovers `(cap, owner)` unambiguously.

## Known limits

- **Indirect calls are unattributed.** `ECallPtr` has no statically known
  callee. The flat marker still reports the capability; the report names it as
  unattributed rather than omitting it, because an empty owner set must not
  read as "nothing uses it".
- **`prelude.march` is invisible.** `load_stdlib_file` unwraps it into global
  scope, so its members are bare-named and indistinguishable from the entry
  module's. A capability used only by a prelude function is attributed to the
  entry module.
- **Attribution is per-module, not per-package.** Mapping modules to packages
  is forge's job (it already does this in `cap_package.ml`) and is the next
  step toward per-dependency capability budgets in `forge.toml`.
- **Over-approximation is filtered, not prevented.** Attribution is computed
  pre-opt, so a call site that `cprop`/`fold` later proves dead would be
  reported. Emission intersects the owner rows against the flat marker set, so
  the owners are always a subset of the capabilities the binary actually has.

## Where the code is

- `lib/tir/cap_attrib.ml` / `.mli` — the analysis
- `lib/tir/llvm_toplevel.ml` — marker emission (alongside the flat markers)
- `lib/tir/llvm_builtins.ml` — `c_symbol_of_march_name`, the side-effect-free
  twin of `mangle_extern` (recording there would mark capabilities the binary
  never references)
- `bin/main.ml` — `stdlib_module_names`, and the pre-`Opt.run` call site
- `forge/lib/cap_binary.ml` — the `attribution` channel
- `forge/lib/cmd_cap.ml` — the "Attributed to" section and JSON field
- `test/test_cap_markers.ml` — four cases, each measured in its failing state
  before the fix
