# A closure environment is freed shallowly: every capture leaks (GAPS G80)

Reported by the `cube_forge` project (its GAPS **G80**, and the investigation
"The relight box, and where the frame's memory goes", 2026-09-05, which traced
~1.8 MB of per-frame growth to it).

**Status: partially implemented on the branch `fix/closure-env-deep-drop`,
NOT safe to merge.** The blocker is at the bottom and is the important part of
this file — two of the three designs anyone would reach for are ruled out by
measurement, and the third needs a fact this pass does not have.

## The leak

`dec_rc` on a defunctionalized closure releases the environment cell and never
touches what the lambda captured. `march_decrc_local` is `free(p)` with no
child decrements, and `Drop.run` only routed a bare `EDecRC` through a
synthesized deep drop for *variant* types (`Repr.find_variant`), so a
`$Clo_...` struct matched nothing.

Repro `probes/drop_xmod` in `cube_forge`, maximum resident set size from
`/usr/bin/time -l`:

| repro | main (`7eb8d76a`) | branch |
|---|---|---|
| `WHICH=5` — 1,000 closures each capturing a 1 MB array, called once, dropped | 1,073 MB | **7.4 MB** |
| `WHICH=4` — 4,000 replacements of a 64 KB element in a 64-element `Array.PVec` | 339 MB | 339 MB |

## What is implemented

`lib/tir/drop.ml`, `rewrite_apply_clo_drop`. A capturing apply function has
already loaded every capture it uses into a local, so it needs no layout
knowledge — only an answer to "did MY release of the environment free it?".
The `dec_rc $clo` Perceus splices in (`Perceus.insert_apply_fn_clo_drop`) is
rewritten to `let $freed = march_decrc_freed($clo)` — same reference, same
instant, only now remembered — and every tail is prefixed with
`case $freed of True -> drop c1 ; drop c2 | _ -> ()` over those locals.

Neither of the two designs the gap report sketched (a drop pointer stored in
the environment, or a runtime release reading capture kinds from the header) is
needed for this site: an apply function corresponds to exactly one `$Clo_...`
definition. Nothing about the closure layout, the header, or the runtime
changes.

## The blocker

On `test/native/node_discovery.march`, 60 runs interleaved against a
same-box build of `7eb8d76a`:

| exit | main | branch |
|---|---|---|
| 0 | 50 | 37 |
| SIGTRAP (malloc freelist corruption) | 10 | 6 |
| **SIGBUS** | **0** | **17** |

The SIGBUS is a guard-page hit in the PROLOGUE of
`Msgpack.list_append$List_Int$List_Int` — unbounded recursion, not a deep one:
a 16x larger `MARCH_STACK_MAX` does not prevent it. `list_append` recurses once
per cons cell, so an unbounded recursion there means a CYCLIC list, i.e. a
dangling pointer written into reused memory. Something is releasing a capture
that is still owned elsewhere.

`lib/tir/borrow.ml`'s `closure_escapes` names the fact that would decide it:
"A non-escaping closure does not transfer ownership of its captured free
variables to any longer-lived value — so those captures are borrowing dups, not
ownership transfers of the caller's reference." A closure that is only ever the
callee of an `ECallPtr` — a join point, an immediately-applied lambda, which is
exactly what Msgpack's parser is a long chain of — does not own its captures,
and releasing them when its environment dies is a double release. The apply
function cannot see which kind of allocation site its `$clo` came from.

So the release has to be gated on the closure's ownership classification, which
is a property of the ALLOCATION site (`Borrow`'s escape verdict), not of the
apply function or the closure type. Propagating it is the remaining work; a
per-closure-type "every allocation site of this lambda transfers ownership"
summary is the obvious shape, and it must fail CLOSED (leak, never release).

Two designs already ruled out by measurement, so nobody re-derives them:

1. **Deepening the release in place.** The captures are BORROWED from the
   environment (`Perceus.collect_closure_fvs` puts each `let a = $clo.$fvN`
   binding in the borrowed set, so nothing in the body releases one) and the
   body reads them well after the splice point. The shallow free is survivable
   precisely because it orphans the captures rather than freeing them;
   releasing them there frees a value the body is about to read
   (`$lam$apply` reads `native_u8_arr_length(a)` two instructions later).
2. **Moving the release to the tails**, the way
   `Perceus.insert_owned_aggregate_param_drops` moves an owned aggregate
   parameter's drop, so a deep drop there is safe. The release count per path
   is unchanged and the RC arithmetic works on paper. It is still wrong: with
   the child releases removed ENTIRELY, so the moved drop does nothing but
   `march_decrc_freed`, node_discovery still died with the same SIGBUS in 8 of
   20 runs against 0 of 20 without the move. `insert_apply_fn_clo_drop`'s
   splice point is load-bearing for something not yet understood.

Also worth knowing, found on the way: `Msgpack.encode_val` corrupts the malloc
freelist on **main** (10 of 60 runs above, SIGTRAP in `mfm_free` under
`march_decrc`). Unrelated to this, and it makes node_discovery a noisy oracle —
compare SIGBUS counts, not pass counts.

## The other half of `Array.set`

`WHICH=4` does not move because its remaining leak is not this. Two separate
things:

- Perceus dups `$clo` at every capture read (`find_inc_vars` at an `EField`
  treats the source as consuming) and nothing undoes it, so an apply function
  that reads two captures pins its environment's refcount two above zero
  forever — `Array.set`'s `descend` reads three against one release. Excluding
  `TPtr` sources there, exactly as `TTuple`/`TRecord` are already excluded
  three lines above for the same reason, takes `WHICH=4` from 339 MB to 177 MB
  and makes the tail (`lst_set`) half flat — a constant 73 live objects at any
  iteration count. It is NOT on the branch: on its own it causes the same
  node_discovery SIGBUS (10 of 20 runs), which is consistent with the same
  ownership question — those dups are currently what keeps a borrowed-capture
  environment alive.
- `Array.lst_replace_nth` binds the node it replaces by name in the arm that
  discards it (GAPS G81, the shape `lst_set` had fixed for it in `7eb8d76a`).
  The identical wildcard fix was applied, measured **neutral** (live objects
  identical to the digit, 2268 at N=100 and 6712 at N=300, before and after),
  and reverted: the deep drop it enables is emitted as `__drop$TrieNode_String`
  against a `TrieNode(NativeU8Arr)` value, a monomorphization mismatch in the
  mono-TVar-collapse family. Fix that first.

Measured shape of what is left on the trie path, per `Array.set`: ~0.7 leaked
64 KB arrays, ~19 32-byte cons cells, one 16-byte and one 24-byte cell. The
`ascend` traversal in `trie_update` also never releases its `stk` spine or the
frame tuples it walks.
