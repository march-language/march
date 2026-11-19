# A discarded `Result(_, CapError)` in statement position is never reported (2026-11-19)

Found by the ocap phase 4 PR B final review (Important 2). `cap_result_unhandled`
fires only where a `T` is required. A capability operation's `Result(_, CapError)`
written as a statement, or returned from `main`, is dropped without a word, so a
refusal is silent:

```march
mod Srv do
  needs IO.Console, IO.NetListen
  fn main() do
    HttpServer.new(18592) |> HttpServer.plug(app) |> HttpServer.listen()
    println("after")
  end
end
```

Under `MARCH_GRANT=IO.Console` this passes `--check`, prints `after` and exits 0.
The same holds for a bare `HttpServer.bind_host("127.0.0.1")` statement and for
`File.write(...)` and friends. It predates phase 4, but `listen` and `bind_host`
used to return `()`, so every existing server program keeps compiling unchanged and
loses its only failure signal (the repo's own callers were migrated to
`Authority.must(...)` by hand; the CHANGELOG entry tells users to do the same).

What to do: report a `Result(_, CapError)` whose value is discarded (a non-final
block expression, `let _ = ...`, or `main`'s result) as a warning with the
`Authority.must(...)` / `Authority.ignore(...)` fix, following the same position
rules `cap_result_unhandled` already uses. Decide whether `let _ = op` (an explicit
discard) stays silent. Check the stdlib and corpus for statement-position checked
operations before turning it on, and add `test/errors` cases.
