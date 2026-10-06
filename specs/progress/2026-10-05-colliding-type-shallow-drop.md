# A dying value of a colliding short-named type was freed shallowly (the lab's per-session leak)

**FIXED 2026-10-05.** Found while chasing the multi-host lab's soak result: nodes grew
~400,000-680,000 live objects per session and were OOM-killed at 2 GB within about two
minutes of traffic, before and after #785 alike.

## Finding it

Bisected with single-process probes (`live_allocs()` before and after N iterations,
compiled `--opt 2`):

| Probe | Objects left |
|---|---|
| In-process session (`Session.in_process`), any payload size | 31 per session, constant |
| Cluster session on ONE node (loopback link), 0 / 1,000 / 10,000-byte payload | 4,810 / 8,760 / 28,289 per session |
| `NetFrame.encode/decode`, `Bytes.from_list/to_list` | 0 |
| `NodeSend.decode_msg` of a 1,000-byte message | 1,001 per call |
| `Msgpack.decode`: `bin` of 1,000 bytes / `str` / array of 100 ints | 1,000 / 0 / 200 per call |
| `Msgpack.Bin(list)` built in user code and dropped, no decoding | 1,001 per call |
| The same type copied into user code, dropped | 0 |

The emitted LLVM for the last probe released the dying `Msgpack.Value` cell with a bare
`__march_rc_decrc_local`: no `__drop$` helper was synthesized, so the cell's byte list
was orphaned.

## Cause

`Msgpack.Value`, `Config.Value` and `DataFrame.Value` share the short name `Value` (also
`Level`, `State`, `Event`, `Error`, `Mode`, `TransportError` in the stdlib). By design the
static type stays the bare short name at every use site (`Collision_set`'s module doc:
"never qualify TCon references, only ctor identity/impl module/runtime tags carry module
identity"); colliding types are forced Boxed and get globally unique constructor tags,
registered under the qualified `ctor_info` key (`Msgpack.Value.Bin`), so "a later
runtime tag switch" could tell them apart. `drop.ml` never had that switch: the exact
lookup misses the short name, and `find_variant_by_suffix` deliberately refuses a name
with two or more candidates. So every dying cell of a colliding type was freed
shallowly, including the decoded Msgpack frame of every cluster message.

## Fix

`lib/tir/drop.ml`: `colliding_union`. For a short name in the collision set, the drop
destructures the UNION of every candidate's constructors, each named by its qualified
key (which `Llvm_case` accepts as a branch tag as is); the dying cell's tag selects
exactly one branch, with that candidate's field types. Each candidate is substituted
with the use site's type arguments on its own; a candidate that is a concrete niche or
whose parameters do not line up leaves the name unresolved (shallow, as before).

The union is refused (shallow, as before) when two candidates share a constructor name
with different fields. The tag only identifies the candidate when the construction's
key was module-qualified, and `Lower_expr` qualifies only the narrow impl-bearing
collisions; any other construction keys bare (`Row.Row`) and `Llvm_data.ctor_entry`'s
suffix scan hands it the tag of whichever same-named type registered first. A first
version without this guard segfaulted `test/native/niche_ctor_ambiguity` (pinned by
`test_oracle.ml`): its nested `Inner.Row.Row` cells carried `DataFrame.Row.Row`'s tag,
so the drop freed a `List(Int)` as a `List((String, Value))`. The three stdlib `Value`s
have disjoint constructor names, so they are unaffected. `variant_ctors` (the niche
path) deliberately does not use the union.

## Effect

- Every `Msgpack.decode` probe above: 0 objects left.
- Cluster session on one node: 4,420 / 6,369 / 7,894 per session at 0 / 1,000 / 10,000
  bytes (was 4,810 / 8,760 / 28,289).

## Test

`test/native/colliding_type_drop.march` (dune rule `native_colliding_type_drop`): a
dropped `Msgpack.Bin`, a dropped `Msgpack.Array`, and a decoded frame dropped, each
"no growth"; all three false without the fix.

## Left

- The cluster session still leaves ~4,400 objects per session regardless of payload,
  plus ~0.35 per payload byte: the session machinery (very likely
  [the dropped-closure gap](../todos/2026-10-04-dropped-closure-leaks-its-captures.md))
  and something on the message path still to find.
- `NodeSend.encode_msg_schema` leaves 3 objects per call.
- Colliding types that share a constructor name with different fields (`Inner.Row` vs
  `DataFrame.Row`) still drop shallowly; deep-dropping them needs every construction
  keyed by its module, not only the narrow collisions'.
- A module declaring its own `Value` crashes, compiled, when it uses `Msgpack.Value`
  (found writing the test, independent of this fix):
  [../todos/2026-10-05-local-type-named-like-stdlib-value-crashes-compiled.md](../todos/2026-10-05-local-type-named-like-stdlib-value-crashes-compiled.md).
