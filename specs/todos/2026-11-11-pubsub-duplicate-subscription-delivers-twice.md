`[P3]` PubSub.subscribe_state does not deduplicate, so a pid subscribed twice gets every broadcast twice (2026-11-11)

Subscribing an already subscribed pid adds a second list entry. `broadcast_to` sends once per entry and it takes two unsubscribes to remove the pid. The doc string describes this, but a rejoin after a reconnect then double-delivers.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let s1 = PubSub.subscribe_state(PubSub.new_state(), "room:lobby", 7)
  let s2 = PubSub.subscribe_state(s1, "room:lobby", 7)
  println("subscribers after subscribing pid 7 twice: " ++ to_string(PubSub.get_subscribers(s2, "room:lobby")))
  println("count: " ++ to_string(PubSub.subscriber_count(s2, "room:lobby")))
  let s3 = PubSub.unsubscribe_state(s2, "room:lobby", 7)
  println("after one unsubscribe: " ++ to_string(PubSub.get_subscribers(s3, "room:lobby")))
end
end
```

Expected: `[7]`, count 1.

Actual (interpreted / compiled): `[7, 7]`, count 2, still `[7]` after one unsubscribe (interpreted).

Source: `subscribe_state` and `broadcast_to` in `stdlib/pubsub.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
