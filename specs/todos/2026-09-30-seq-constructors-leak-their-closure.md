# `Seq` constructors leak per use (compiled)

Found 2026-09-29 while fixing
`specs/progress/2026-09-30-process-spawn-lines-leaks-and-wrong-payload.md`.

Measured `--compile --opt 2` on origin/main (b931328e5), `live_allocs()` delta
over 40 iterations of a one-element sequence built and drained with `Seq.count`
(3 warm-up iterations first):

| body | delta / 40 |
|---|---|
| `Seq.count(Seq.from_list(["a"]))` | 120 (3 per iteration) |
| `Seq.count(Seq.from_string_lines("a\n"))` | 200 (5 per iteration) |
| `List.length(string_split("a\n", "\n"))` (control) | 0 |

So the leak is in `Seq` (`stdlib/seq.march`: `from_list` wraps a `go` closure in
a `Seq(fn(acc, f) -> ...)`), not in string splitting. Suspects: the closure and
the `Seq` cell are not released after the fold runs, or the captured list is
retained. It is the reason the `process_spawn_lines` leg of
`test/native/process_handle_leak_probe.march` calls the builtin directly
instead of `Process.run_stream`.

Acceptance: a leak probe over `Seq.from_list`/`from_string_lines`/`map`/`filter`
+ `count`/`fold` that stays flat, and `Process.run_stream` added as a leg of
the process probe.
