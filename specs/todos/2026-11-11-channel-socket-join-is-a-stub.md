`[P2]` ChannelSocket: phx_join spawns no channel, connect_fn is never called, replies go to pid 0 (2026-11-11)

`route_msg` handles `phx_join` by registering the transport pid itself as the channel pid: no channel process is spawned, the handler named by the route is never looked up, and no join reply is sent. The `connect_fn` stored by `make_config` is never called anywhere, so the documented authentication hook does not run. `ws_loop` passes `0` as `transport_pid`, so heartbeat replies and error pushes are cast to pid 0 and never reach the client. The module comments say so, but the endpoint cannot serve a Phoenix client. The second and third points are by source reading only.

Repro:
```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let routes = [Channel.channel_route("room:*", "RoomChannel")]
  let cfg = ChannelSocket.make_config("/socket", routes, fn (p, s) -> Ok(s))
  let join = Channel.make_msg("1", "1", "room:lobby", "phx_join", "{}")
  -- transport pid 999; a spawned channel process would have a different pid
  let ac = ChannelSocket.route_msg(ChannelSocket.empty_channels(), join, routes, cfg, 999)
  println("channel pid registered for room:lobby after phx_join: " ++ to_string(ChannelSocket.lookup_channel(ac, "room:lobby")))
end
end
```

Expected: a pid other than the transport pid (a spawned channel), a join reply, `connect_fn` consulted.

Actual (interpreted / compiled): `Some(999)`, the transport pid passed in (interpreted).

Source: `route_msg`, `ws_loop`, `make_config` in `stdlib/channel_socket.march`.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
