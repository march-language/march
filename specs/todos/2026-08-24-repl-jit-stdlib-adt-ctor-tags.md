# `[P3]` REPL JIT: stdlib ADT values print as `#<tag:0>`, with tag 0 for every constructor

```
$ march
march(1)> Logger.Warn
= #<tag:0>
march(2)> Http.Post
= #<tag:0>
```

`MARCH_REPL_INTERP=1` prints `Warn` / `Post`. Expect the tag to be wrong for
`match` on these values too, exactly as it was for prompt-declared types before
`specs/progress/2026-08-24-repl-jit-nullary-ctor-tags.md` — worth confirming
before fixing, since a wrong constructor tag is a wrong evaluation, not just a
wrong rendering.

Same root cause as that entry, one layer further out. An expression fragment
numbers its constructor tags from the `~types` list it is emitted with
(`Llvm_toplevel.build_ctor_info`), and a missing type falls back to
`ctor_entry`'s `ce_tag = 0`. `Repl_jit.precompile_stdlib`'s **cache-hit** path
(the common one) dlopens `~/.cache/march/stdlib_prelude_*.so` and reads the
`.names` file — it deliberately never lowers stdlib to TIR, which is the whole
point of the cache — so no stdlib `type_def` is ever available to hand to a
fragment, and none reaches `ctx.global_type_defs` for the printer either.

Fix direction: cache the stdlib `type_def` list next to the `.so` (a third
companion file, or extend `.names`) and load it into `ctx.loaded_tir_types` +
`ctx.global_type_defs` on the hit path, so both codegen and the printer see the
same numbering the `.so` was compiled with. Do NOT rebuild the list from a
partial lowering: `build_ctor_info` is first-wins and order-sensitive, and the
colliding-type path (`reserve_global_tag`) allocates global tags in list order,
so a differently-ordered list would hand out tags that disagree with the
already-compiled prelude.
