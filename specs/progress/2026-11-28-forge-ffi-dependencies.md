# Forge FFI dependencies

A project can explicitly link native bindings from its resolved dependency
graph with `dependencies` in an FFI table. Resolving by package name gives
native bindings the same nearest-dependency precedence as March imports
and keeps native source paths relative to the package that owns them.

Forge applies OS selectors to the importing table and the provider's C
tables. Commands that build Rust FFI build the selected packages with their
Cargo lockfiles and store the results in the consumer's build directory.
The consumer chooses every native provider explicitly. Runtime capability
grants use the existing dependency grant mechanism.
