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

## Fixed 2026-11-25

A probe on the fallback over the 528-program IR corpus found five ambiguous keys:

| key | candidates | fields |
|---|---|---|
| `HEntry.HLeaf`, `.HBranch`, `.HCollision`, `.HEmpty` | `Hamt`, `HashMap`, `Map` | same |
| `Seq.Seq` | `File.Seq`, `Seq.Seq` | same |
| `Safe.Safe` (`test/native/h_sigil_safe_collision.march`) | `Html.Safe`, `Other.Safe` | different |
| `Row.Row`, bare `Row` (`test/native/niche_ctor_ambiguity.march`) | `DataFrame.Row`, `Inner.Row`, `Csv.CsvRow` | different |

Qualifying every key by module, as the "What to do" above proposed, is not safe:
`File.Seq`/`Seq.Seq` are handed across modules by shape on purpose (see
`Lower_state.shared_ctor_collision_tbl`), and qualifying them splits construction from
matching. So the fix has two parts.

- **Same fields: a sorted pick.** `Llvm_data.ctor_entry` sorts the candidates by key before
  choosing, so the answer no longer depends on `Hashtbl` order or on how many types the
  program declares. A `HashMap` cell is still stamped as `Hamt.HEntry`, now always; the
  layouts are the same.
- **Different fields: keyed by the declaring module.** `Lower_state.ctor_shape_conflict_tbl`
  records, per module and constructor, a type whose same-named twin gives that constructor
  other fields. `own_module_ctor_key` keys such a module's own constructions and matches as
  `Mod.Type.Ctor`, and a pattern with no recorded type inside that module resolves the same
  way. Two declarations with different fields cannot be a by-shape hand-off, so this cannot
  split one.
- **What still reaches the fallback with different fields gets the sorted pick.** That is a
  use carrying no type at all: a test harness that lowers without a type map (`tco_codegen`'s
  `type L = Nil | Cons(Int, L)` beside the builtin `List`), or a bare constructor outside
  every declaring module. Failing the compile there was tried and broke that harness, so it
  is deterministic but still a guess. No program in the IR corpus reaches it.
- **The match side sorts too.** `llvm_case.ml`'s `qualified_br_key` resolves a pattern's tag
  on its own, and it took the first key a `Hashtbl.fold` produced. With construction sorted
  and matching not, `cross_module_ctor_resolution` case 5 (`DcA`/`DcB`, both `Thing.Shared`)
  built one type's cell and matched the other's tag. It now takes the first key in sorted
  order, the same pick as `ctor_entry`.

A program that showed it: `test/native/ctor_shape_collision.march` (two nested modules, `Safe(Int)`
and `Safe(Float)`). Before, both were laid out as one of them and clang rejected the module
(`floating point constant invalid for type`); it now prints `a=42`, `z=2.5`, as interpreted.

Not changed: the header type id of a `HashMap`/`Map` cell still names `Hamt.HEntry`.
