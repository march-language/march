# 63-bit Int wrap blocks LLVM accumulator TRE (bench/fib +20%)

`specs/progress/2026-09-30-int-63-bit-overflow-parity.md` made compiled `Int`
arithmetic wrap to 63 bits (`Llvm_ctx.emit_wrap_int63`, `shl 1` + `ashr exact 1`
after `+ - *` etc.). On `bench/fib.march` (`fib(n-1) + fib(n-2)`) the result now
reaches `ret` as `sbfx x0, x19, #0, #63`, and LLVM's accumulator tail-recursion
elimination no longer fires: two recursive `bl _fib` per level instead of one call
plus a loop. Same-box A/B (wrap stubbed to the identity vs. on, `--opt 2`, 5
interleaved runs, 2026-10-01): fib ~450 -> ~540 ms. list_ops and tree_transform
were within noise.

Fix direction: lazy normalisation. `+ - * shl neg` are ring operations, so the wrap
commutes with them. Leave register values unnormalised, tag with a plain `shl 1`
(not `shl nsw`, which drops bit 63 for free and stays correct), and normalise only
where the value is observed: icmp, sdiv/srem/ashr, ctpop, int_to_string, C calls,
NativeIntArr stores, function args/returns. The difficulty is enumerating every
observation point; the parity test `test_compiled_int_overflow_parity` covers the
known ones. Alternative: a narrower peephole that keeps `add` visible to TRE.
