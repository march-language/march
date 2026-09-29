# `[P2]` An `@[endpoints]` protocol inside a nested, library or stdlib module does not typecheck

Filed 2026-09-28 (dd step 12a). Blocks moving the control plane's `Ctl` and
`CtlFetch` protocols into `stdlib/control.march`; they live in
`test/session/control_peers.march` until this is fixed.

**Repro.**

```march
mod Deep do
  needs IO
  needs IO.Console
  needs Session.Live
  mod Outer do
    needs IO
    needs IO.Console
    needs IO.Mut
    needs Session.Live
    @[endpoints]
    protocol Pq do
      hi: A -> B : Int
    end
    fn run(c : Cap(IO)) : () do
      let t = Session.in_process()
      let s = Session.attach(c, t.ops)
      let _ = Pq_B.script(s, Pq_B.register(s, 0), [Pq_B.Expect_Hi(fn n -> print_line("got " ++ int_to_string(n)))])
      let _ = Pq_A.script(s, Pq_A.register(s, 0), [Pq_A.Send_Hi(5)])
      t.drain(())
    end
  end
  fn main(c : Cap(IO)) do Outer.run(c) end
end
```

`Unknown module `Pq_B`` (and, inside the generated code, `Unknown module `Pq_Msg``).
The same protocol at `Deep`'s top level works. The generated role modules call their
siblings (`Pq_Msg`, `Pq_Run`) and user code calls them by their relative names, and
the typechecker does not resolve a relative reference to a sibling submodule below
the entry module's top level.

**How it showed up.** With `Ctl` declared inside `stdlib/control.march`, ordinary
programs still checked, because the stdlib is typechecked on its own (the cached seed
env), where `Control` is a top level. But any program whose entry module shadows a
stdlib module's name (`mod Test`, as ten `test/native` fixtures are) takes the
combined from-scratch check, where `Control` is nested, and failed with
`Unknown module `Ctl_Msg``.

**Also needed for stdlib protocols.**

- The lowering half, qualifying sibling-submodule calls, is fixed:
  [../progress/2026-09-28-nested-module-sibling-call.md](../progress/2026-09-28-nested-module-sibling-call.md).
- The cost: an eagerly loaded stdlib protocol is paid by every program. `Ctl` plus
  `CtlFetch` measured about +0.07 s warm and +0.8 s cold on `hello.march`, and the
  frontend is superlinear in protocols per module
  ([2026-09-24-endpoints-frontend-superlinear-in-protocol-count.md](2026-09-24-endpoints-frontend-superlinear-in-protocol-count.md)).
  A stdlib protocol probably wants an opt-in load path, not the eager manifest.

**Acceptance.** The repro above typechecks and runs on both backends, a protocol in a
MARCH_LIB_PATH module does too, and `Ctl`/`CtlFetch` can move into
`stdlib/control.march` without breaking an entry module named `Test`.
