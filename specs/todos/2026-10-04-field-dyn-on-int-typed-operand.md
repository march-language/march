`[P2]` Invalid IR: `march_record_field_dyn` handed an `Int`-typed operand

**Filed:** 2026-10-04, from `scripts/compile-time-bench.sh` (branch
`bench/compile-time-harness`) compiling `examples/topology_app/src/topology_app.march`
WITHOUT its `--topology` digest (`--compile --opt 2`). clang rejected the IR:

```
topology_app.<pid>.tmp.ll:29145:50: error: '%w635505' defined with type 'i64' but expected 'ptr'
  %cr5506 = call ptr @march_record_field_dyn(ptr %w635505, ptr @.str154, i64 11)
```

## What the IR says

`%w635505` is not counter 635505. It is the lazy Int63 normaliser's prefix
`w63` plus counter `5505` (`%w63N = ashr exact i64 %w63sM, 1`), and `%cr5506`
is the next fresh name. So `emit_field` (`lib/tir/llvm_emit_data.ml`) got an
`EField` whose operand's TIR type is `Int`. `get_record_fields` found no shape,
so it took the by-name `march_record_field_dyn` path, and the operand was
emitted (untagged) as an i64. The emitter then spliced that i64 in as `ptr`
without checking its type. The defect is upstream, in whatever typed a record
value as `Int`: lowering, mono or defun. An emitter coercion cannot repair it,
because the `ashr` has already halved the cell's address.

## Not reproduced

On `f2088b568` (the bench branch's compiler source is identical), all of these
produced valid IR and a linking binary:

- `--emit-llvm` with the real `HOME`
- `--compile` with the real `HOME`
- `--compile` with a fresh `HOME` (cold stdlib caches), then a comment-edit
  recompile

The bench session also noted that the first compile in a fresh `HOME` produces
a different post-TIR key than later ones. So the TIR depends on cache state,
which is the best lead. Repro attempts stopped at load average 250-340 from
other sessions: a single `--dump-tir` took 46 minutes.

## What landed meanwhile

- `emit_field`'s two dyn paths now go through `dyn_record_obj`, which fails
  with `llvm_emit: field .F read from X, whose TIR type T emits as i64, not a
  record pointer` instead of writing invalid IR. A recurrence names the
  operand and its type. Unit test:
  `test_codegen` / `field_dyn_on_scalar_operand_refused`.
- A main-less compile no longer emits the whole stdlib
  ([`progress/2026-10-04-mainless-compile-emits-whole-stdlib.md`](../progress/2026-10-04-mainless-compile-emits-whole-stdlib.md)).
  Whatever function carried the bad `EField` may now be pruned from this
  repro, so to chase it, use a stdlib-wide root (e.g. the pre-fix driver)
  or a program that reaches it.

## Next

Under normal load: loop fresh-`HOME` / warm-`HOME` / comment-edit compiles of
the topology app with a pre-pruning driver plus the assertion, until the ICE
fires. Then `--dump-tir` that state and trace the operand's type back through
`tir-lower` / `tir-mono` / `tir-defun` (`MARCH_DUMP_TXT`). Also diff
`--dump-tir` between a fresh-`HOME` first compile and a second one, per the
bench note above.
