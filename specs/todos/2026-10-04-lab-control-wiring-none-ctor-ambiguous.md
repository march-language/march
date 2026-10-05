# `[P2]` A protocol branch labelled `none` breaks the control-plane wiring of a `[control]` app

Found 2026-10-04 by the multi-host lab (`scripts/lab/`, docs/lab.md) while writing its app.

A topology app whose `topology.toml` has a `[control]` section gets
`lib/desugar/control_wiring.march` spliced into its entry module. If any `@[endpoints]`
protocol in that module has a `choose` branch labelled `none`, the generated message type
`Order_Msg.Order_Message` gains a constructor `None`, and every bare `None` in the wiring
(`Option`'s) stops resolving. `forge build` fails with 49 errors, each pointing into the
wiring and calling itself a compiler bug:

```
Constructor `None` is ambiguous between multiple modules:
  • `Order_Msg.None` — from type `Order_Message` in module `Order_Msg`
  • `.None` — from type `Option` in module ``
Use a qualified form to disambiguate.

1601 |           None
    in the control plane's generated wiring (lib/desugar/control_wiring.march): a compiler bug
```

The same protocol builds without `[control]`: the user's own code in the same module uses
`None` (an `Option`) and is not affected, so the wiring alone resolves constructors
differently.

## Repro

`examples/lab_app` with its `out` branch renamed back to `none`:

```march
choose by Stock:
  have -> Stock -> Shop : String
          ...
  none -> Stock -> Shop : String
          skip: Stock -> Ledger : Int
          stop
end
```

then `forge build` in the project (the topology has `[control]`). The lab renamed the
branch to `out`.

## Fix direction

The wiring should not depend on which constructors the user's protocols generate:
qualify `Option`/`Result` constructors in `control_wiring.march` (or splice it as its own
module scope), and add a regression case with a `none`/`some`/`ok`/`err` branch label to
the control-wiring tests. Check `Some`, `Ok`, `Err` too (`some`, `ok`, `err` labels).
