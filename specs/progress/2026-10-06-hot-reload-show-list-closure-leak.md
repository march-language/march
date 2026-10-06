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

## Resolution (FIXED 2026-10-06)

Not the self-recursive-closure drop. The leaked object is the per-element lambda itself,
and it leaks in any `--hot-reload` build, not only in an actor handler (a top-level
`to_string(xs)` looped 100 times left 100; `List.map(xs, fn x -> x * 2)` and a fold left
two per call).

A call through a closure hands its callee one reference to the closure
(`Borrow.infer_module` pins every apply function's `$clo` owned), and an apply function
releases it, except a capture-free, non-recursive one, whose body never names `$clo`
(case 1 of `Perceus.insert_apply_fn_clo_drop`). Natively that is right: codegen builds such
a lambda as one immortal static closure (`Llvm_emit`'s static-lambda arm), where the
reference costs nothing. The REPL has no static closures, so case 3 of the same function
gives the apply its drop when `~repl` is set. A hot-reload build disables static lambdas
outright too ("static lambdas are disabled outright whenever hot-reload is configured at
all"), but Perceus was never told: every call leaked the heap closure's reference.

Fix: `Perceus.perceus ~heap_lambdas`, set by `Contract_pipeline` when hot reload is
configured, enables case 3 exactly as `~repl` does. Should the two ever disagree, the drop
on an immortal static closure is a no-op (`march_decrc` skips immortals), so the only
possible failure is the old leak.

Test: `test/native/hot_reload_lambda_released.march`, compiled `--hot-reload Main`: no
growth over 100 calls of each shape (RED before: 100 and 200).
