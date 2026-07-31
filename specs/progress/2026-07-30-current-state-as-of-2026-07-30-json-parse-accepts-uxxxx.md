# Current State (as of 2026-07-30, `Json.parse` accepts `\uXXXX`)


**Counts:** `run_stdlib` 826 (unchanged — the new coverage is 11 `describe`/`test`
cases inside `test/stdlib/test_json.march`, which the OCaml suites count as one
test), with only the pre-existing environmental `MARCH_SANITIZE` failure;
`run_compiler` 619, `run_codegen` 520, `run_eval` 256, `run_snapshots` 33 unchanged.
`test/stdlib/test_json.march` 197/197.

**`Json.parse` rejected `\uXXXX`, which is most of the non-ASCII JSON in the
world.** `unescape` decoded the eight two-byte escapes (`\" \\ \/ \n \r \t \b
\f`) and returned `Err("unknown escape sequence")` for everything else — so a
document containing `"A"`, valid per RFC 8259 §7 and the form nearly every
serializer emits for a non-ASCII character, failed to parse outright. The
serializer side was never the problem: `escape_str` emits raw UTF-8, which is
also valid, so March could write documents it could not read back from other
producers.

`\u` is the only JSON escape whose length is not fixed at two bytes, so it is
handled beside `unescape` rather than inside it: `unescape_u` returns the
decoded text *and* the index just past the escape, and `scan_string` resumes
from that index — preserving the existing run-slicing discipline (a run of
unescaped bytes is still materialized with one `string_slice`). A high
surrogate must be followed by a second `\uXXXX` low surrogate, and the pair
decodes to one astral code point; a surrogate appearing alone is rejected
rather than emitted, since it is not a Unicode scalar value.

**`char_from_int` was the wrong primitive for the UTF-8 encoder.** It is
documented as single-byte `n & 0xFF` — true of `march_char_from_int` in the C
runtime, but the *interpreter* returns `VString ""` for anything above 127
(`lib/eval/eval.ml`), so a first version of `utf8_encode` built from it produced
the empty string for every multi-byte code point while the ASCII case passed.
`byte_to_char` is the builtin that covers the full 0–255 range in both
backends (it maps to the same `march_char_from_int` when compiled), and is what
`utf8_encode` uses. Worth noting as a general trap: the two builtins share a C
implementation but not an interpreter implementation, and the divergence is
silent — no error, just an empty string. Output verified identical interpreted
and compiled (`--compile`) for 1-, 2-, 3- and 4-byte results.

**Pinned by** 11 new cases in `test/stdlib/test_json.march`: the four encoder
widths (`A`, `é`, `中`, the `😀` pair), an escape
adjacent to literal runs, an escape in an object key, and five rejections
(lone high surrogate, high surrogate followed by a non-surrogate, lone low
surrogate, fewer than four hex digits, a non-hex digit, and a `\u` truncated by
end of input). The six accept cases were confirmed RED before the fix.
