`[P2]` Refinement: a refined session payload type obliges nobody

Found 2026-11-11 while building the refinement must-reject corpus
(`specs/lang/refine/INDEX.md`). A protocol step may declare a refined payload, and a
`Chan.send` of a value outside it files no obligation: `--refine-report` counts nothing at
the send, `cap verified` accepts the module, and nothing checks the value at run time
either (the program below, given a `main`, sends 0 and the server prints it).

```march
mod A03 do
  cap verified
  type Client = Client
  type Server = Server
  protocol Ping do
    Client -> Server : {Int | _ > 0}
  end
  fn client(c : Chan(Client, Ping)) : Unit do
    let c2 = Chan.send(c, 0)     -- 0 obligations today; should be violated
    Chan.close(c2)
  end
end
```

The checker's walks skip `DProtocol` ("message types, no bodies"), and `Chan.send` has no
signature the refinement checker reads the payload type from. An actor message's refined
parameter is obliged at the `send` (`<Actor>.<Msg>`); this is the session-typed twin.

Fix direction: at `Chan.send(c, v)`, when the channel's current step has a refined payload
type, check `v` against it through `check_call` as a message argument is, and give the
value `Chan.recv` binds that refinement as a fact. Where the channel's state is not known to
the checker, record a skip. The runtime half (a receiver that does not trust its peer) is
`specs/todos/2026-11-06-protocol-runtime-monitors.md`.

Pinned as wrongly accepted by `specs/lang/refine/reject/a03_session_payload.march`, listed in
`specs/lang/refine/known-accepted.txt`. Done when that fixture is reported violated and its
line is removed.
