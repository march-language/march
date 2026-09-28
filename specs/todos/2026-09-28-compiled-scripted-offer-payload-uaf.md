# `[P2]` Compiled: a scripted peer's `Expect_` callback reads a String-field payload corrupted

Filed 2026-09-28 while writing `test/session/control_peers.march` (dd step 12a).

**Symptom.** Compiled only. In that fixture's "scripted Agent against the real
Control" case, the scripted `Ctl.Agent` receives the real Control role's first
`apply` order through `Ctl_Agent.Expect_Apply(fn o -> ...)`. Its Int fields read
correctly; its String fields read back bytes of strings allocated LATER in the
callback:

```
interpreted: script: ordered step 1 of release 42: activate(render) want mr2, 1 line(s)
compiled:    script: ordered step 1 of release 42: script: ordered step  want 1, 1 line(s)
```

`o.action` came back as the callback's own first string, `o.want` as
`int_to_string(o.step)`: the record's String fields were freed before the callback
ran and their memory reused. Messages cross `Session.in_process()` as encoded
`Bytes`, so the record is freshly decoded on the receiving side; the premature free
is there (the generated offer walker of `script`, or the decode), not in the sender.

**Allocation-dependent.** A different format string in the same callback printed
correctly, and a minimal protocol (same loop, `choose`, an 8-field String record,
scripted on both sides with heap-allocated strings) does not reproduce it. It was
first seen with the protocol declared inside `stdlib/control.march` and persists with
it in the entry module.

**Where it is pinned.** `test/session/control_peers.march` prints only the order's Int
fields in that callback, so the golden does not depend on freed memory. To reproduce,
append `++ ": " ++ o.action ++ " want " ++ o.want ++ ", " ++ int_to_string(List.length(Control.order_lines(order_of(o)))) ++ " line(s)"` to `show_order` there (it still reproduces with the protocol's own `WireOrder` payload) and compare
the two backends. Next step: an ASAN build (on macOS that needs a Linux container).

**Why it matters.** The real Agent (`agent_role` in that fixture, reading the same
fields through `Control.agent_apply`) produced correct results compiled in every
test, but if a received record's strings can be freed early, it may be reading freed
memory and getting lucky.
