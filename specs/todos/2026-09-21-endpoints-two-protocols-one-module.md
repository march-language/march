# `[P2]` Two `@[endpoints]` protocols in one module break the first one's sends

**Filed:** 2026-09-21, found while writing `test/session/in_process.march` for
`Session.in_process()`. Pre-existing on `main` (`8b04cd168`); independent of
the transport.

## Repro

Take `test/session/stream_endpoints.march` unchanged (it passes) and add a
second protocol to the same module, before the `Marker` type:

```march
  @[endpoints]
  protocol Other do
    A -> B : Int
    B -> A : String
  end
```

Interpreted, the first send of the ORIGINAL protocol now panics:

```
Prod sends Item(1)
panic: match failure -- Non-exhaustive pattern match: no branch matched the value Msg_Prod_Cons_1(1).
  [0] Stream_Prod.send_Msg_Prod_Cons_1()
```

`Other` is never used. A user who puts two protocols in one module (the
natural layout for a service speaking two of them) gets a runtime match
failure in generated code, with no diagnostic.

## Not yet known

The cause. Hypothesis, unverified: each protocol generates a `<P>_Msg`
module whose message type derives `Json`; if both types share a short name,
the derived `to_json`/`encode` dispatch resolves to the second protocol's
impl (compare the FQN impl-dispatch identity work, and the return-type-directed
`from_json` collision fixed in `414baa5a` that `stream_endpoints.march`'s
`Marker` type guards). Check with `--dump-tir` which `encode` the send calls.
Also check compiled, which was not run.

## Acceptance

Two `@[endpoints]` protocols in one module each run their own session, on
both backends; a fixture in `test/session/` pins it. Until then
`test/session/in_process.march` and `in_process_logging.march` are split
one protocol per file because of this.
