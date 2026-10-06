# A record named by its short name was dropped shallowly (and a qualified field name gave the wrong representation)

**FIXED 2026-10-06.**

## Cause

A nominal record is registered under its qualified name (`GlobalRegistry.Entry`,
`ClusterNode.CnState`), but types elsewhere name it bare: `GlobalRegistry.Names` is
`Names(Map(String, Entry))`. `Drop.aggregate_fields` looked the name up exactly, missed,
and the map leaves' entries were freed shallowly: every replaced registry entry leaked
its `VectorClock`, three objects per registry update once the old registry was released
whole (as the cluster node's old state is).

## Fix

`lib/tir/drop.ml`, `record_fields_by_suffix`: an unresolved short name resolves to the
one record whose qualified name ends with it, unless two records share it or any variant
does (the use site could then be the variant). The resolved record's field types are
rewritten to BARE names. The first version kept them qualified, and that was a
use-after-free: a field typed `GlobalRegistry.Names` classifies as a newtype while every
`Names` value is built boxed under the bare name, so `__drop$CnState` freed the box and
then dropped the box's pointer as its own payload (ASAN: `__drop$CnState` then
`__drop$HEntry_String_Entry` on one cell; an RC underflow abort in 3 of 4 runs of the
session probe). Found by bisecting the 25 records the fallback resolves (only `CnState`
triggered it) and an ASAN run in the Linux container. The structural record a use site
carries spells those names bare already.

## Test

`test/native/record_ownership_drops.march`, leg 3: a `ClusterNode.CnState` whose `reg`
is replaced in a loop. Red on main, green after.

## Left

`Kind`'s representation of a qualified type name and of its bare spelling can disagree
(`GlobalRegistry.Names` newtype vs `Names` Boxed). Only the bare one is ever constructed,
so nothing else is known to be affected, but any other path that reads a qualified field
type should be suspected first.
