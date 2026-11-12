`[P3]` Presence.untrack broadcasts a leave even when the user has other connections (2026-11-11)

`Presence.untrack(sock, key, meta_json)` takes no PresenceState and always casts a `presence_diff` leave to the channel. A user with two devices who closes one is shown as gone to every subscriber. The doc string says so; the function should consult the state (`connection_count`) or take it as an argument. Classified by source reading only: the function is a single `actor_cast`.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let s1 = Presence.track_state(Presence.new_state(), "room:lobby", "alice", 7, "{}")
  let s2 = Presence.track_state(s1, "room:lobby", "alice", 8, "{}")
  println(to_string(Presence.connection_count(s2, "room:lobby", "alice")))
  -- Presence.untrack(sock, "alice", "{}") would still broadcast leave_diff_json("alice", "{}")
  println(Presence.leave_diff_json("alice", "{}"))
end
end
```

Expected: no leave diff while `connection_count` is above 1.

Actual (interpreted / compiled): `untrack` has no access to the state and always sends the leave diff (source reading).

Source: `untrack` in `stdlib/presence.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
