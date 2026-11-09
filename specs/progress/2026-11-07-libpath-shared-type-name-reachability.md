# A shared type name no longer loads unreferenced MARCH_LIB_PATH modules (2026-11-07)

GitHub issue #1183.

## The bug

`March_resolver.Resolver.resolve_imports` prunes auto-discovered lib-path modules by
textual reachability: a module is kept when a kept source contains its module name or one
of its *anchors*, its type and constructor names (`provided_anchor_names`). The anchors
exist because a bare type or constructor name resolves program-wide: an entry can write
`let t : Tally = ...` or `Red` for a module it never names.

But the anchors were matched against every token of the referencing source, including
names that source declares itself. With `MARCH_LIB_PATH=lib`, `mod Alpha` using its own
`type Tally` therefore reached every other discovered module declaring `type Tally`, such
as an unreferenced `mod Zeta`, and Zeta's errors failed `--check`, `--compile` and the
interpreter. Renaming Zeta's type made it go away. Constructors had the same
over-inclusion; function names are not anchors, so they never did.

## The fix

A reachability seed is now `Resolver.ref_seed`: the source's tokens plus the type and
constructor names its own decls provide. `Resolver.seed_reaches` keeps a module when the
seed contains its module name, or one of its type/constructor names that the seed's source
does not define itself. That is sound because a bare name a module defines resolves to its
own definition (for a constructor shared with another type, the current module's wins;
checked with both modules loaded). A bare name used without a local definition still
reaches every module defining it.

The entry's seed uses the entry's decls, explicitly imported modules carry their parsed
decls (`loaded_srcs`), and discovered modules carry theirs. The B7.2 depend-mode load-set
check in `bin/main.ml` (`valid_loadset`) uses the same rule, so the cache's "would the
resolver prune it again" answer matches the resolver.

## Test

`test/test_compiler.ml`, `test_shared_type_name_does_not_load_unreferenced_module` (suite
`resolver`): the issue's layout (an entry naming only `Alpha`, which uses its own `Tally`
and `Red`; a broken `Zeta` with `type Tally`, a broken `HueLib` with constructor `Red`, and
the renamed-type control `Omega`). None of the three is loaded, and the program typechecks.
A second entry that uses `Tally` and `Green` without defining them still keeps `Zeta` and
`HueLib`. Red before the fix (Zeta loaded), green after.
