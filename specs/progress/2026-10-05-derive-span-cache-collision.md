# Derived code could be lowered with another program's types (synthetic spans collided with the cached stdlib's)

**FIXED 2026-10-05.** Found chasing the multi-host lab's finding 6 ("adding a branch to a
protocol makes `forge deploy` restart every pool: 272 functions changed, 263 derived `Eq`
signatures among them"; the todo is on the lab part 2 branch,
`2026-10-05-lab-protocol-branch-forces-restart.md`, and stays open, see "Left").

## Symptom

`examples/lab_app` built twice under one `HOME`, v1 then v2 (v2 = `protocol_later.py`'s
third branch), `--compile --compile-so --hot-reload LabApp --topology ...`: the manifests
differed in 272 functions, among them every derived `Eq` of an untouched type
(`Eq$Action.eq`, `Eq$CallError.eq`, the control wiring's `Eq$Ctl*`), with changed
signature hashes. `--dump-phases` showed v2 lowering

```
Eq$Action.eq(a: Result((Int, List(Event)), DecodeError), b: Result(...)) : Result(...)
```

from `tir-lower` on. v1 was right (`(a: Action, b: Action) : Bool`), and so was v2 built
under an empty `HOME`, cold or warm from its own cache.

## Cause

Every node `derive` generates gets a synthetic span so the typechecker's span-keyed type
map gives each its own entry (`Desugar_derive.fresh_synthetic_span`). The key was
`{file = "<none>"; start_line = <process-wide counter>}`: unique within one process only.
The stdlib's desugared AST is cached on disk (`stdlib_ast_*` blobs under
`~/.cache/march`), carrying the counter values of the process that wrote it. A later
compile of a different program counted from its own start, minted the same spans for its
own derived nodes, and the type map handed them the types of whatever cached node shared
the key. So derived code was lowered with unrelated types whenever the stdlib cache had
been written by another program. Here the victim was dead code (DCE removed it) and
only its hash moved. A live one would be lowered with the wrong representation.

## Fix

`lib/desugar/desugar_derive.ml`: the key is now (a 60-bit structural hash of the
generated decl, its derive-site span included; an ordinal within that decl), set by
`respan_derived_decl`. The salt goes in the columns, so the file stays `"<none>"` and the
line a positive ordinal, as the synthetic-code filters expect. The same decl gets the
same spans in every process; different decls get different keys.

## Effect

Same v1/v2 build pair: 186 functions changed (was 272); no derived `Eq` among them, and
`Eq$Action.eq` lowers as `(Action, Action) : Bool`.

## Test

`test/test_compiler.ml`, "derive spans keyed by the decl" (`tag_and_typestate`): the same
decl respanned before and after others gets identical spans; a different decl a
different key. Red before the fix.

## Left (finding 6 stays open)

The plan is still a restart. Simulating forge's `Deploy_plan.undeliverable` on the
v1/v2 manifests: 151 changed functions have no dispatch slot and no slotted changed
caller. They are (a) the protocol's generated functions (`Order_Run.*`, `Order_Ledger.*`,
`Order_Shop.*`, ...), which genuinely change and have no slot, and (b) lifted lambdas
(`go$apply$1602` ...) whose names come from a global counter, so one name denotes
different bodies in the two builds, plus ~1,900 `$jp` join points added and removed under
renumbered names.
