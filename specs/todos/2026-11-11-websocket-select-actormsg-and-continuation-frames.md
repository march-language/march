`[P3]` `WebSocket.select` can never return `ActorMsg`; fragmented messages close the socket (2026-11-11)

1. `select` passes `0` as the actor notification pipe to `ws_select`, so the `ActorMsg` constructor of `SelectResult` is unreachable from the stdlib API. The doc string says so.
2. The runtime's frame reader has no case for opcode 0 (continuation) and ignores the FIN bit: a fragmented message is reported as `Close(1002, "unknown opcode")` (runtime/march_http.c, `march_ws_recv`, the `default:` arm of the opcode switch). The `recv` doc string says so.

Repro: none that runs standalone; classified from the current source (see the pointer below).

Expected: `ActorMsg` is either deliverable or removed; a fragmented text message is reassembled.

Actual (interpreted / compiled): by source reading only (needs a WebSocket peer).

Source: `select`, stdlib/websocket.march; `march_ws_recv`, `march_ws_select`, runtime/march_http.c.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
