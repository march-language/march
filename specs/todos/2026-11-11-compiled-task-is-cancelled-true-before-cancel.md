`[P2]` Compiled, `task_is_cancelled(tok)` answers `true` BEFORE a later `task_cancel(tok)`

Found 2026-11-11 while writing golden `g49` (the user-type-vs-built-in identity fix); unrelated
to it, the program declares no type.

```march
mod Main do
  needs IO.Console
  fn main(c : Cap(IO.Console)) do
    let b = task_cancel_token_new()
    print_line(to_string(task_is_cancelled(b)))
    task_cancel(b)
    print_line(to_string(task_is_cancelled(b)))
  end
end
```

- Interpreted: `false`, `true`.
- `--compile`: `true`, `true`.

Without the `task_cancel(b)` line the compiled program prints `false`, so the first query sees the
later cancel: either the two queries are merged as one pure call, or the cancel is hoisted above
the first. Not investigated further. Start with `scripts/triage.sh` on the program above and the
`--dump-tir` of `main`.
