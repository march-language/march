# An unqualified constructor key resolves among same-named stdlib types by hash-table order (2026-11-25)

Found while checking the pre-mono prune (`specs/progress/2026-11-24-pre-mono-dce.md`) with
`scripts/ir-canon-diff.sh`.

`Llvm_data.ctor_entry` (`lib/tir/llvm_data.ml`) looks a constructor up by the key the TIR
carries. When that key is not in `ctor_info` it falls back to every entry whose key ends in
`.<key>`, takes the first whose arity matches, and otherwise the first found. "First" is
`Hashtbl.fold` order over `ctor_info`.

The TIR for `stdlib/hash_map.march` still carries unqualified keys (`HEntry.HLeaf`,
`HEntry.HBranch`, …), while `ctor_info` holds `Hamt.HEntry.HLeaf`, `HashMap.HEntry.HLeaf` and
`Map.HEntry.HLeaf`, all with the same arity. So which type's collision tag and header type id
a `HashMap` cell gets depends on the table's bucket layout, which depends on how many types
the module carries. On `bench/hash_map_bench.march` before the prune, `HashMap` code stamped
`HLeaf` and `HBranch` cells as `Hamt.HEntry` and `HCollision` cells as `HashMap.HEntry`; after
it, `HLeaf` is `HashMap.HEntry` and `HBranch` is still `Hamt.HEntry`.

It is consistent inside one build (every lookup of one key gets one answer, so construction
and matching agree), and the three `HEntry` declarations have the same layout, so nothing
misbehaves today: 20 programs changed their pick under the prune and all print the same
output. Two other fixtures moved the same way: `native_h_sigil_safe_collision` (`Safe` now
resolves to `Html.Safe`) and `native_session_party_released`.

What is wrong with it:

- Any change to the number of emitted types can move the pick, so unrelated changes show up
  as IR diffs in programs that use `HashMap`, `Map` or `Html.Safe`.
- Two candidates of the same arity need not have the same field layout. Picking the wrong
  one would read fields at the wrong types.
- The header type id names the wrong type for part of a `HashMap`'s cells, which is what the
  runtime uses to name an erased value's type.

What to do: make lowering emit the module-qualified key for a constructor of a colliding type
(`Collision_set` already knows which types collide), so the fallback is never reached for
them; then make the fallback fail, or at least pick deterministically (sorted key), when more
than one same-arity candidate remains. Check with `scripts/ir-oracle.sh` and
`scripts/ir-canon-diff.sh`.
