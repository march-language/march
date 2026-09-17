# Widen the closure-capture release, and fix Array.set's leak

Follow-up to `specs/progress/2026-09-06-closure-environment-deep-drop.md`,
which releases a closure's captures only for closure types whose environment
provably owns them. That gate declines most closures — 2,001 of 5,305 closure
types qualified in `cube_forge`'s `probes/drop_xmod` — so the leak it closes is
real but narrow: `WHICH=5` went 1,073 MB -> 9.5 MB, while `WHICH=4` and
`cube_forge`'s own gauge (86 live objects a frame) did not move at all.

> **Update 2026-09-13: item 1 landed, and item 2 in part**
> (`specs/progress/2026-09-13-closure-environment-released.md`). Perceus no
> longer dups `$clo` at capture reads. The gate now admits a closure allocated
> in tail position, which is every closure factory, and an ELet right-hand
> side's tail. Landing it exposed and fixed a use-after-free in
> `rewrite_apply_clo_drop`: it released captures in front of a tail that used
> them. Items 3 (the outer release site), 4 (`Array.lst_replace_nth`'s mono
> mismatch) and 5 (`node_discovery`) are untouched. So is item 2's per-SITE
> verdict: the gate is still per closure type. Measured leftovers are in the
> progress entry.

> **Update 2026-09-15: item 2's HOF-loop half landed; item 3 was built and
> BACKED OUT** (`specs/progress/2026-09-15-closure-captures-released-by-the-hof-loop.md`).
> The gate was never the problem for `map`/`filter`: their `go` closure already
> qualified, but the release that reaches zero is the SELF-ALIAS's
> (`dec_rc go`), not the `dec_rc $clo` the deep drop was keyed on. That is
> fixed.
>
> Item 3 (the outer release of a closure value) was implemented as the runtime
> table this file asks for — keyed by the apply-fn pointer rather than a pad-word
> drop id, so no header bit is needed — and it is a USE-AFTER-FREE as gated.
> ASAN, on `two-node[skew]`: a node id decoded off the wire and still owned by
> the members `Map` was freed by the deep drop of a closure that had captured
> it. **The verdict this file's gate computes is per closure TYPE and asks
> whether the environment escapes. The outer release needs a different question:
> did THIS allocation site take its own reference to each capture?** Perceus
> emits no RC op when a closure captures a borrowed alias (a field of a live
> record, an entry a map still owns), so such an environment owns nothing and
> must release nothing.
>
> A sound version registers a closure type only when every allocation site of it
> demonstrably took its own reference to every capture that needs one — an
> `inc_rc` immediately before the alloc, or a capture whose last use IS the
> alloc. Both are visible in the TIR at [Drop], which runs after RC insertion.
>
> **Update 2026-09-14:** measured shape of item 2 after closure calls started
> consuming their arguments
> (`specs/progress/2026-09-14-closure-calls-consume-their-arguments.md`):
> `List.map(xs, fn s -> string_length(s) + k)` leaks exactly one object per
> `map` call, the capturing lambda's environment. `map` allocates a `go`
> closure capturing `f` and `go$apply` drops it with a plain `dec_rc go`, so
> `f` is never released. For item 3: a closure header's pad word is now
> entirely free (`MARCH_CLO_ARG0_BORROWED` was retired).

> **Update 2026-09-16: RE-MEASURED after the `if`/`else` dead-side fix
> (`specs/progress/2026-09-16-if-else-drops-the-dead-side.md`). Every measured
> figure below this line predates that fix and several of them are now zero.**
> The current picture, with the design for what is left, is
> `specs/2026-09-16-remaining-rc-leaks-design.md`. In short, at `0a4275849`:
>
> - **Item 1 is DONE** (it landed 2026-09-13; the section body below was never
>   updated). An apply fn reading two or three heap captures, applied, is flat:
>   0.00015 per iteration over 20,000.
> - **Item 2's measured shapes are now flat.** `List.map(xs, fn s ->
>   string_length(s) + k)` — the 2026-09-14 note below records it leaking
>   exactly one object per `map` call — measures 0.00015 per iteration, as do
>   `List.fold_left` and `List.filter` with a capturing lambda. The per-SITE
>   verdict is still not built, but it is now wanted only as the gate for item
>   3, not for a leak of its own.
> - **Item 3 is LIVE and is the keystone**, narrowed: the leak fires only when
>   a closure is dropped WITHOUT ever being applied (1.0001 per iteration);
>   applied once it is flat (0.0001). The environment cell is freed either way
>   — what leaks is the capture inside it. Three closures over one `String`
>   leak one object, not three.
> - **Item 4 is LIVE, and only on the trie path**: 2.997 objects per update
>   into the trie, 0.0001 into the tail. The tail half went flat when item 1
>   landed, which is what this file predicted and nobody had re-measured.
> - **Item 5 is CLOSED** (below).

## 1. Perceus dups `$clo` at every capture read and nothing undoes it

> **LANDED 2026-09-13** (`specs/progress/2026-09-13-closure-environment-released.md`)
> and re-confirmed flat 2026-09-16. The account below is kept for its
> measurements; it is history, not an open item.

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
the closure header's `pad` word (free since 2026-09-14). Either touches the REPL/JIT,
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

## 5. `node_discovery` has pre-existing memory bugs on main — RESOLVED 2026-09-16

Closed. The fatal fault was root-caused and fixed on 2026-09-09 (a Perceus
borrowed-field lookahead gap on nested record projections,
`specs/progress/2026-09-09-nested-record-field-capture-uaf.md`); the torn-output
race it had also been quarantined for was fixed on 2026-08-21. It is back on
`runtest`, soaked 200x per ubuntu CI run, and since 2026-09-16 it is in the ASAN
gate's curated native corpus. Re-measured here: 60/60 clean, exit 0 and a
matching sorted golden every time. It is a usable oracle again; the
"compare per-signal counts across interleaved runs" workaround is retired.

**Superseded 2026-09-09:** the "`Msgpack.encode_val`/`list_append`" framing
below turned out to be a debugging artifact (an `lldb` backtrace always shows
a `list_append` recursion because lldb intercepts the FIRST, benign,
self-recovering stack-growth fault of a run, before the runtime's own
`march_sigsegv_handler` gets to service it — that fault has nothing to do with
the crash). Runtime-level fault-address instrumentation found the actual fatal
fault is a corrupted `march_string`'s `len` field read inside
`march_string_split`, reached from `NetKernel.handshake` →
`Msgpack.encode_val`'s `Str` arm, not from the later SwimPing exchange. Also
confirmed NOT caused by TRMC (byte-identical codegen with `--no-trmc`). Full
detail and next steps:
`specs/progress/2026-09-09-nested-record-field-capture-uaf.md` — FIXED the same day (a Perceus borrowed-field lookahead gap on nested record projections).
The original (now-superseded) notes, kept for the measured crash-rate data
points:

`Msgpack.encode_val` corrupts the malloc freelist (SIGTRAP in `mfm_free` under
`march_decrc`, ~8% of runs) and `Msgpack.list_append` overflows the stack
(~19%, unaffected by a 16x larger `MARCH_STACK_MAX` — that env var is actually
a compile-time `#define`, `runtime/march_scheduler.h`, never read via `getenv`,
so that experiment never tested anything).

> **Design spec (2026-09-11):** `specs/2026-09-11-codegen-leaks-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
