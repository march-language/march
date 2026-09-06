# Widen the closure-capture release, and fix Array.set's leak

Follow-up to `specs/progress/2026-09-06-closure-environment-deep-drop.md`,
which releases a closure's captures only for closure types whose environment
provably owns them. That gate declines most closures — 2,001 of 5,305 closure
types qualified in `cube_forge`'s `probes/drop_xmod` — so the leak it closes is
real but narrow: `WHICH=5` went 1,073 MB -> 9.5 MB, while `WHICH=4` and
`cube_forge`'s own gauge (86 live objects a frame) did not move at all.

## 1. Perceus dups `$clo` at every capture read and nothing undoes it

`find_inc_vars` at an `EField` treats the source atom as sitting at a consuming
position and dups it when it is live afterwards. `TTuple` and `TRecord` sources
are already excluded three lines above for exactly this reason ("a record
passed to a field-reading helper therefore never reached refcount zero — 2001
live objects over a 1000-iteration loop"). A closure environment — a `TPtr`
source, an apply function's `$clo` — is not excluded, so an apply function that
reads two captures pins its environment's refcount two above zero permanently.
`Array.set`'s `descend` reads three captures against one release.

Adding `Tir.TPtr _` to that exclusion in `lib/tir/perceus_core.ml` takes
`WHICH=4` from 339 MB to **177 MB** and makes the tail (`lst_set`) half of
`Array.set` flat — a constant 73 live objects at any iteration count.

Not landed, because it was measured against the confounded baseline described
in the progress entry (a binary built against a different runtime) and needs
re-measuring properly: rebuild both sides against the same runtime, interleave,
and compare per-signal counts. Its last reading was SIGTRAP 23 of 60 against a
baseline 15 of 60 — the same double-free signal the ownership gate exists to
suppress, which is consistent with those dups currently being what keeps a
borrowed-capture environment alive. Land it WITH the gate and re-measure.

## 2. Widen the gate

`owning_apply_fns` fails closed on any allocation shape it does not recognise,
which is the right default and also why it declines so many. Two directions:

- Recognise more allocation shapes (an `EAlloc` in a tail, in an argument, in a
  field) instead of noting them `false`.
- Reach the verdict per ALLOCATION SITE rather than per closure TYPE, so one
  non-escaping site does not disqualify every other use of the same lambda.
  That needs the verdict carried into the apply function, which is the
  code-pointer table or header-tag design the original gap report sketched.

## 3. The outer release site

A bare `EDecRC` on a closure value that was never applied, or was extracted
from a data structure, is still shallow. Its type there is a function type,
which names no layout, and the environment is not in hand to read captures out
of. Needs a table keyed by the code pointer in field 0, or a small drop id in
the closure header's `pad` word (which already carries
`MARCH_CLO_ARG0_BORROWED` and is otherwise free). Either touches the REPL/JIT,
where per-fragment modules must append to rather than replace the table, and
hot reload.

## 4. `Array.lst_replace_nth` (GAPS G81) is blocked on a mono mismatch

It binds the node it replaces by name in the arm that discards it, so Perceus
never releases it — the shape `lst_set` had fixed for it in `7eb8d76a`. The
identical wildcard fix was applied, measured **neutral** (live objects
identical to the digit: 2268 at N=100 and 6712 at N=300, before and after), and
reverted: the deep drop it enables is emitted as `__drop$TrieNode_String`
against a `TrieNode(NativeU8Arr)` value, a monomorphization mismatch in the
mono-TVar-collapse family. Understand that first.

Measured shape of what still leaks on `Array.set`'s trie path, per update:
~0.7 leaked 64 KB arrays, ~19 32-byte cons cells, one 16-byte and one 24-byte
cell. `trie_update`'s `ascend` also never releases its `stk` spine or the frame
tuples it walks.

## 5. `node_discovery` has two pre-existing memory bugs on main

Not caused by any of the above, and they make that test a poor oracle:
`Msgpack.encode_val` corrupts the malloc freelist (SIGTRAP in `mfm_free` under
`march_decrc`, ~8% of runs) and `Msgpack.list_append` overflows the stack
(~19%, unaffected by a 16x larger `MARCH_STACK_MAX`, so a cyclic list — very
likely the same corruption). One run hung for over an hour. Worth fixing on its
own account; until then, compare per-signal counts across interleaved runs.
