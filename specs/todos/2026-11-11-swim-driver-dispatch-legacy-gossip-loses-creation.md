`[P3]` `SwimDriver.dispatch` sends Gossip as the legacy tag-3 frame, which drops creation, name and addr (2026-11-11)

`dispatch` and `dispatch_with_load` encode `Gossip(m)` as `SwimGossip(node_id, status, incarnation)`. The receiver rebuilds the member with creation 0, and `Membership.observe` then ranks it below any entry it holds at a later creation: a Suspect or Dead about a restarted node (creation 5) is ignored. The doc string says the fields are not sent. The node service uses `action_frames` (full MEMBER_GOSSIP frames); only fixtures still call `dispatch`.

Repro (`swim_driver_gossip_creation.march`):

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  -- what SwimDriver.dispatch puts on the wire for Gossip(m): the legacy tag-3 frame
  let m = Membership.member("n2", "node-two", "10.0.0.2:9100", 5, Membership.Suspect, 7)
  let wire = SwimDriver.encode_msg(SwimDriver.SwimGossip(m.node_id, m.status, m.incarnation))
  let ev = match SwimDriver.decode_msg(wire) do
    Ok(msg) -> SwimDriver.msg_to_event(msg)
    Err(_) -> None
  end
  println("received: " ++ to_string(ev))
  -- the receiver knows n2 alive at creation 5, incarnation 7: the Suspect should win
  let view = Membership.observe(Membership.empty(), Membership.member("n2", "node-two", "10.0.0.2:9100", 5, Membership.Alive, 7))
  let got = Membership.member("n2", "n2", "", 0, Membership.Suspect, 7)
  println("receiver view after legacy gossip: " ++ to_string(Membership.get(Membership.observe(view, got), "n2")))
  println("receiver view after full-member gossip: " ++ to_string(Membership.get(Membership.observe(view, m), "n2")))
end
end
```

Expected: the receiver's view moves to Suspect, as it does for the full-member frame.

Actual (interpreted / compiled): view stays `Alive` after the legacy frame / the same.

Source: `dispatch`, `dispatch_with_load`, `msg_to_event`, stdlib/swim_driver.march.

Related: specs/todos/2026-09-18-cluster-node-service-follow-ups.md notes that `SwimDriver.dispatch` / `dispatch_all` still write a peer's fd directly and that only legacy fixtures use them. Retiring `dispatch` closes this too.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
