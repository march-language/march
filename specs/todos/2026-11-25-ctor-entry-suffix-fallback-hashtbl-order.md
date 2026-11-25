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

It is consistent inside one build: every lookup of one key gets one answer, so construction
and matching agree. For the three `HEntry` declarations the layouts are the same, so the wrong
pick only mislabels the cell. 20 programs changed their pick under the prune and all print the
same output.

**It is already a wrong-layout pick in one fixture.** `test/native/h_sigil_safe_collision.march`
declares `Other.Safe = Safe(Int)` beside the stdlib's `Html.Safe = Safe(String)`. When the
fallback picks `Other.Safe` for `Html.raw`'s cell, the String payload is emitted as an Int
field (`ptrtoint`, a conditional untag, `store i64`). The fixture's output happens to match
either way. Measured in the final review by adding K extra closures to its `main`:

| K | with the pre-mono prune | without it |
|---|---|---|
| 0, 3, 10, 30, 80 | `Html.Safe` (right) | `Other.Safe` (wrong layout) |
| 200 | `Other.Safe` (wrong layout) | `Other.Safe` (wrong layout) |

So before the prune the pick was wrong but stable for this program at every size tried; with
the prune it is right for small programs and flips with the number of types the user's own
program adds. Whether the mis-typed field can corrupt or leak at run time has not been shown.
`native_session_party_released` moved its pick the same way.

**Priority: high.** The prune did not create this, but it makes the pick depend on program
size.

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
