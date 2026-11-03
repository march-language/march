# DONE 2026-10-12: A1 check 4, representation invariants at emission

Observability plan section 6, check 4: "promote the `MARCH_REPR_AUDIT` recorder to a check over
`k_table`: niche/unboxed decisions consistent with every `EAlloc`/`ECase` on the type;
`collision_set` tags agree across all uses."

## Design: at emission, from codegen's own record

The invariant is about what codegen commits to, so check 4 reads codegen's decisions instead of
re-deriving them from the kind table. Re-deriving can disagree with codegen: several sites decide
from the argument, not `Kind`, such as the `Some(x)` allocation's niche path. `MARCH_REPR_AUDIT`
already records every allocation, reuse, match and equality site's encoding (`Llvm_ctx`). Under
`--verify-tir` / `MARCH_VERIFY_TIR=1`, `emit_module` forces that recording on
(`Llvm_ctx.repr_audit_forced`). After emission, it raises `Tir_verify.Failed ("llvm-emit", ...)`
on any finding; the driver renders it and exits 3 like the TIR-stage checks.

`Llvm_toplevel.check4_findings` combines three pure functions, exported for tests:

- **`repr_mix_findings`, `repr/mixed`.** The audit's own conditions, now failures: one payload
  encoded by two families, or a site with no payload to go on disagreeing with one that had it
  (the `Option(Option(_))` null-vs-boxed bug shape the audit was written for). Different payloads
  may differ (`Option(Int)` niche, `Option(Float)` boxed).
- **`collision_repr_findings`, `repr/collision`.** `Kind.repr_of` forces a type in a collision
  group (one short name, several declaring modules) to Boxed. A recorded niche, newtype or unboxed
  encoding of one means a site decided without the kind table.
- **`collision_tag_findings`, `repr/collision`.** The group's constructor tags, read from the
  `ctor_info` codegen installed, are in the collision range and pairwise distinct. A match on the
  bare short name tells the declaring modules apart only by tag.

The audit report (`MARCH_REPR_AUDIT=1`) prints what it printed before, from the same flagged list.
`march query verify` stops before emission, so it does not run check 4.

## Red

- **Unit tests** (`test_codegen`, group `tir_verify`): mixed families (same payload, and an unknown
  payload; different payloads and one family clean; unforced recording off), a colliding type
  encoded as a niche or unboxed (Boxed and non-colliding clean), and collision tags (shared tag
  and out-of-range tag reported, distinct in-range clean).
- **End to end**, by perturbing the emitter and restoring it:
  - The match site recorded `Boxed` for a niche decode. `march --verify-tir` exits 3 on an
    `Option(String)` program with `repr/mixed: Option is encoded as Boxed and Niche
    (same-payload conflict)`, naming every site; without the flag it exits 0.
  - Colliding types got ordinary index tags. `test/native/local_colliding_type` and
    `colliding_type_drop` exit 3 with `repr/collision` findings: tag 0 outside the range, and
    `CRDT.GCounter.T.GCounter` and `CRDT.LWWRegister.T.LWWRegister` sharing a tag.

## Sweep

The stdlib's CRDT modules declare four types named `T`, so every program that links the stdlib has
a collision group, and check 4c runs on all of them. Results:

- 450 programs (`test/native`, `bench`, `test/snapshots/src`) with the verifier on: clean at
  `--no-opt`, `--opt 0` and `--opt 2`. 446 emit IR; the four that do not fail before emission, as
  without the flag.
- The 90 programs of `examples/` and `specs/lang/golden/` at `--opt 2`: clean.
- The audit alone (`MARCH_REPR_AUDIT=1`, before this change) flagged no type in any of the 450 at
  `--no-opt` or `--opt 2`.

Check 4 found no bug. It guards the class the audit was built after (`86c62b98`).
