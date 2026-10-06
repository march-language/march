`[P2]` **`--hot-reload` builds leak a 24-byte closure per `to_string` of a `List(String)`.**

Found by LeakSanitizer (Linux, `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1`) during
observe R4b ([progress](../progress/2026-10-05-observe-r4b-signed-debug-verbs.md)).
Repro, one actor handler:

```march
mod Main do
  needs IO.Console
  actor C do
    state { n : Int, tags : List(String) }
    init  { n: 0, tags: ["x"] }
    on Show() do
      let s = to_string(state.tags)
      println(s)
      state
    end
  end
  fn main(_c : Cap(IO.Console)) do
    let c = spawn(C)
    send(c, Show())
    run_until_idle()
  end
end
```

Without `--hot-reload` the only leaks are the live actor's state at exit
(`march_main`, 48 bytes). With `--hot-reload Main` there is one more: `Direct
leak of 24 byte(s)` allocated in `Show$List.show$List_String`. That object is
the non-capturing per-element closure (`$lam1$apply`), captured by the
recursive `go` closure that maps the list. The `go` closure itself is freed;
its captured field is not. A plain top-level function calling `to_string(xs)`
does not leak, in either build. `Actor.inspect_state` hits the same path
for any `List` field (one leak per inspect).

Likely the self-recursive-closure drop (it needs two drops, see the memory
note on `selfrec_closure_leak`) is missed under the hot-reload dispatch
lowering. Check the post-Perceus TIR of `Show$List.show$List_String` with
and without `--hot-reload` first.
