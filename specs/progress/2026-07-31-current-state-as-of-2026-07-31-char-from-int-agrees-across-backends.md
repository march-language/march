# Current State (as of 2026-07-31, `char_from_int` agrees across backends)

**Counts** (measured after merging `origin/main`, which brought in `@[vectorize]`
and JsonStream): `run_stdlib` 827 (+1: the new `char_from_int` byte-parity case),
with only the pre-existing environmental `MARCH_SANITIZE` failure; `run_codegen`
538 green; `run_compiler` 620, `run_eval` 256, `run_snapshots` 33, and
`test_stdlib_march` 54/54 unchanged by this work.

A note on `run_codegen`, since two entries below disagree with each other: this
branch measured **521** on its pre-merge base, where the entry below it recorded
520. The post-merge total settles it — 521 + the `@[vectorize]` group's 17 = 538,
not the 537 the `@[vectorize]` entry predicts from a base of 520. Neither number
is this branch's doing (it does not touch `test_codegen.ml`); 520 was simply one
behind when it was written.

**Measurement trap worth recording:** on first run after the merge, `run_codegen`
reported `vectorize_check / vectorize hard error fails compile` as FAILING — a
program that must be rejected compiled cleanly instead. It was **not** a
regression. A control worktree built from pristine `origin/main` passed the same
test 17/17, and this branch's diff against main touches no vectorize code at all
(`lib/tir/vectorize_check.ml` and `bin/main.ml` are byte-identical). The cause was
dune's user-global shared cache re-serving stale objects: `DUNE_CACHE=disabled
dune build --force` produced a compiler that rejects the program correctly, and
the group then passed 17/17. Clearing the CAS (`.march/cas/artifacts-v2`) did
**not** fix it, which is what ruled out the other usual suspect. The general
lesson is the one already in `specs/progress.md` for goldens: a failure that
reproduces under `dune build` but vanishes under a cache-disabled rebuild is the
cache, and `--force` alone is not enough — the env var is.

**`char_from_int` returned different bytes interpreted and compiled — a
differential-oracle bug that silently corrupted data.** The C runtime's
`march_char_from_int` is `(char)(n & 0xFF)`: a byte constructor over the full
0–255 range. The interpreter (`lib/eval/eval.ml`) instead clamped to ASCII and
returned the **empty string** for `n > 127` — no error, just a byte that
vanishes from the middle of a string. Every stdlib caller that hands it a real
byte was therefore correct compiled and corrupt interpreted: `Uri.decode`'s
percent-decode (`stdlib/uri.march`), the msgpack raw-byte walk, `Http` header
decoding, and `Gen`'s char-list builder. Measured against a pre-fix control,
`Uri.decode("caf%C3%A9")` yielded `"caf"` (3 bytes) interpreted versus `"café"`
(5 bytes) compiled; both now yield `"café"`.

The interpreter was moved to the runtime's semantics rather than the reverse.
ASCII-only was never the intended contract — it is not what the runtime, the JS
backend, or the docs describe, and adopting it would have broken URI and msgpack
decoding that works today in compiled builds. The mask (`n land 0xFF`) rather
than a range check is load-bearing for parity: the runtime wraps, so `256` must
yield byte 0 here too, not raise. `byte_to_char` keeps its range **error** on
purpose — it shares the payload and the same C function once compiled, but its
name denotes a byte, so an out-of-range argument there is a caller bug.

This is the same trap recorded in the 2026-07-30 `Json.parse` entry below, now
fixed at the source. `stdlib/json.march`'s `utf8_encode` still calls
`byte_to_char`, which was adopted as a workaround but is also the better name
for a byte builder; its comment no longer claims the two builtins disagree.
`Char.from_int`/`Char.to_int` docstrings said "code point", which was never true
of either backend, and now say byte.

**Still divergent, deliberately out of scope:** the JS backend
(`runtime/march_runtime.mjs`) implements `char_from_int` as
`String.fromCodePoint(n)` — a *third* semantics, which differs from the byte
reading above 255 and throws `RangeError` on a negative argument. That is not a
one-line fix: JS strings are UTF-16 sequences while native March strings are
byte arrays, so aligning it is a question about the JS string model, not about
this builtin. Recorded here rather than silently patched.

**Pinned by** `char_from_int: byte semantics 0-255 + wraparound, compiled +
interpreted` in `test/test_stdlib_suite.ml` (group `adversarial-regressions`),
which round-trips all 256 values through `char_to_int` and asserts a byte length
of 1 for each, plus four wraparound cases (`256`→0, `511`→255, `-1`→255,
`-256`→0). It asserts a literal expected string rather than mere
interpreted-vs-compiled equality, so it cannot go green if both backends drift
together, nor pass vacuously on a machine with no clang. Confirmed RED before
the fix — the pre-fix interpreter did not merely score 128, it *died* at n=128,
because `char_to_int` rejects the empty string `char_from_int` handed it.
