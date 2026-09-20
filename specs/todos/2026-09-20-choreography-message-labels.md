# `[P2]` Choreography: let a protocol step name its message

Filed 2026-09-20 by the choreography UX pass
([[2026-09-20-choreography-ux-hardening]]), the top finding.

Every generated name carries a synthesised message name: `Echo_Server.S_recv_Msg_Client_Server_1`,
`Fan_C.recv_Msg_B_C_1`, `Stream_Cons.await_Msg_Prod_Cons_1`, `Got_Msg_Prod_Cons_1`. A
two-message protocol yields a 41-character state type, and the `_1` is noise for the common
case of one message per pair. Branch heads already get user names (`More`, `choose_more`,
`Got_More`) through the `choose` label, so the machinery for a name is there; plain messages
lack a way to supply one.

Proposal: a label on a message step, reusing the branch-label rule in
`Desugar_endpoints.annotate`:

```march
protocol Stream do
  loop do
    item: Prod -> Cons : Int
    choose by Cons:
      more -> Cons -> Prod : Bool
      done -> Cons -> Prod : Bool
              stop
    end
  end
end
```

giving `send_Item`, `S_recv_Item`, `Got_Item`, `await_Item`. Unlabelled steps keep today's
names, so nothing existing changes. Parser: `lower_name COLON` before a message step (the
branch form already parses `label ARROW`). Generator: `annotate` takes the label when
present. Docs: the naming rule as a table.

Not proposed: dropping the `_1` suffix when a pair exchanges one message. It would rename
every generated function in every existing program and test, for less than the label gives.
