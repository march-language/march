`[P2]` # A stdlib parse error is reported as "Unknown module"

Filed 2026-09-02, from adding `stdlib/session.march`.

## The defect

`bin/toolchain.ml:494` catches `March_parser.Parser.Error` while loading a
stdlib file, prints one line to stderr —

```
[stdlib] parse error in .../stdlib/session.march at line 26 col 2
```

— and **returns `[]`**, so loading continues with that module silently
absent. The program then fails to typecheck with

```
Unknown module `Session`.
```

which points nowhere near the cause. The stderr line is easy to miss (it is
not a diagnostic, has no `-- ERROR --` banner, and is emitted before the
program's own diagnostics), and in this case it took a private-`HOME` run to
notice it at all, because the first suspicion was the shared `~/.cache/march`
tcenv cache.

## What triggered it, which is its own small wart

A `doc` string is only accepted before a `fn`/`pfn`. Before a `type` or a
`proof cap` it is a **parse error**:

```march
mod D1 do
  doc "a record"
  type T = { x : Int }     -- parse error
end
```

That is a plausible thing to write (every stdlib type would benefit from one),
and the parser's own message for it in a user file is the generic "I got stuck
here". In a stdlib file it becomes the "Unknown module" above.

## Acceptance

- A stdlib file that fails to parse is a **hard, banner-formatted error** naming
  the file and position, not a skipped module. There is no situation in which
  silently continuing without a stdlib module is what the user wants, and the
  manifest test (`Stdlib_manifest_test`) already treats an unlisted module as a
  correctness bug for representation reasons; an unparseable listed one is
  worse.
- Separately, either accept `doc` on `type`/`proof cap` declarations, or reject
  it with a message that says so ("`doc` goes before a function; use a `--`
  comment here").
