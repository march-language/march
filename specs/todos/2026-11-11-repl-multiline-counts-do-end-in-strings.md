`[P3]` REPL multi-line detection counts `do` and `end` inside string literals and comments (2026-11-11)

`do_end_depth` splits the input buffer on non-identifier characters and counts the words `do` and
`end`, so a `do` inside a string literal or after `--` opens a block that never closes. The REPL
then waits for more input and swallows every following line (at a terminal it looks like a hang)
until a stray `end` arrives, at which point the joined lines are a syntax error. The function's own
comment records it as a known limitation.

Repro (`printf '...' | march repl`):

```march
"a do b"
1 + 1
```

and

```march
1 + 1 -- do it
2 + 2
```

Expected: `= "a do b"` then `= 2`; `= 2` then `= 4`.
Actual (REPL): no value is printed for any line; the session ends at EOF still inside input 1.
Interpreted / compiled: not applicable (REPL input handling only).

Source: `count_token` / `do_end_depth` in lib/repl/multiline.ml. Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
