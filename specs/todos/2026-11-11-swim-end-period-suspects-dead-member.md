`[P3]` `Swim.end_period` gossips Suspect and arms a timer for a member that is already Dead (2026-11-11)

When the probed target is already Dead at the same incarnation, `end_period` still builds a Suspect verdict, arms the suspect timer and returns `Gossip(Suspect)`. The view keeps Dead (Dead outranks Suspect), so local state is right, but a Suspect for a dead member goes out, and `expire_suspects` later re-gossips Dead. `suspect_member` already skips members that are not Alive; `end_period` does not.

Repro (`swim_suspect_dead.march`):

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let ms = Membership.observe(Membership.observe(Membership.empty(), Membership.alive("me", 0)), Membership.dead("n2", 4))
  let s = Swim.make("me", 0, ms, Swim.config(500, 5000, 3))
  let (s1, _) = Swim.begin_period(s, 1000, "n2")
  let (s2, acts) = Swim.end_period(s1, 2000)
  println("actions: " ++ to_string(acts))
  println("view n2: " ++ to_string(Membership.get(s2.members, "n2")))
  println("suspect timers: " ++ to_string(Map.entries(s2.suspect_deadlines)))
  let (s3, acts3) = Swim.expire_suspects(s2, 8000)
  println("after expiry actions: " ++ to_string(acts3))
  let (_, acts4) = Swim.suspect_member(s, 1000, "n2")
  println("suspect_member on Dead: " ++ to_string(acts4))
end
end
```

Expected: no actions and no timer for a member that is not Alive.

Actual (interpreted / compiled): `[Gossip(.. status: Suspect ..)]`, timer `(n2, 7000)`, then a second `Gossip(Dead)` / the same.

Source: `end_period`, stdlib/swim.march.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
