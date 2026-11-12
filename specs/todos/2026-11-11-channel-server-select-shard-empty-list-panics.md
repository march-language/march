`[P3]` ChannelServer.select_shard([]) panics with modulo by zero (2026-11-11)

With an empty shard list `select_shard` calls `PubSub.topic_shard(topic, 0)`, which computes `h % 0`. `ChannelSocket.make_config` builds a config with an empty shard list by default. The panic is documented; returning an Option or a clear error would be safer.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  println(to_string(ChannelServer.select_shard([42], "room:lobby")))
  println(to_string(ChannelServer.select_shard([], "room:lobby")))
end
end
```

Expected: an Option/Result or a descriptive error.

Actual (interpreted / compiled): `modulo by zero` runtime error (interpreted and compiled).

Source: `select_shard` in `stdlib/channel_server.march`, `topic_shard` in `stdlib/pubsub.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
