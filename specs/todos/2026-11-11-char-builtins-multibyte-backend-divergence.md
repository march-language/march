`[P2]` char_* builtins: the interpreter stops on input that is not exactly one byte, native code reads the first byte (2026-11-11)

The char builtins (`char_is_alpha`, `char_is_digit`, `char_is_alphanumeric`, `char_is_whitespace`,
`char_is_uppercase`, `char_is_lowercase`, `char_to_uppercase`, `char_to_lowercase`, `char_to_int`)
match `[VString c] when String.length c = 1` in the interpreter and otherwise stop with
"expected single-char string". Compiled code and the native REPL take the first byte of whatever
string they get (0 for the empty string). A multi-byte character such as "é", a two-character
string, or "" therefore stops one backend and gives a silent answer on the other.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(char_to_int("é")))
end
end
```

Expected: the same result on every backend (either a stop everywhere or one documented value).
Actual (interpreted / compiled): `run-time error: char_to_int: expected single-char string`, exit 1 / `195`, exit 0.
Also: `char_is_digit("12")` stops / `true`; `char_to_uppercase("ab")` stops / `A`;
`char_to_int("")` stops / `0`; `char_is_alpha("é")` stops / `false`.

Source: the `char_*` entries in lib/eval/eval_builtins.ml (about lines 1687-1722) against the
`march_char_*` functions in runtime/march_runtime.c. Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.

## Decision (2026-11-23, owner)

First-byte semantics on every engine, as the C runtime documents: each `char_*` builtin reads
the first byte of its argument. The interpreter stops refusing input that is not exactly one
byte; the JS runtime stops using `codePointAt` and Unicode classes; the whitespace set is the same
everywhere. To settle in the fix and document in the builtin reference: the answer for `""`, and
whether `\f` and `\v` count as whitespace (C says yes, the interpreter no).

Order: fix 2026-11-11-bytes-from-list-out-of-range.md first, because natively `byte_to_char` is
`march_char_from_int`.
