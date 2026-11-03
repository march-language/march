`[P3]` Stdlib API reference: 616 public items still render as empty stubs (2026-10-14)

From the audit in `specs/progress/2026-10-14-stdlib-docs-highlighting-and-http.md`.
An item counts as undocumented when its generated `docs/docs/stdlib/<Mod>.html` entry
has an empty description. 616 of 2,814 (22%).

Worst by count (undocumented / public):
DataFrame 60/148, HttpServer 31/37, ClusterNode 29/120, HttpClient 27/40, Plot 27/28,
NetKernel 22/34, SwimDriver 21/23, DistLink 19/21, Seq 19/29, File 16/18, Logger 16/60,
Membership 16/16, NodeSend 16/19, Set 16/17, GlobalRegistry 15/21, JsonStream 15/22,
Node 14/14, NodeQueue 13/18, Map 12/25, RemoteCall 12/17.

No description at all: Membership, Node, WebSocket, GlobalPid, WorkDispatch, NodeCall,
PeerReader, Forge, LazyNicheProbe.

Other findings:
- No module description: `Handle`, `Session` (their comment sits inside `mod X do`, after
  `needs`; the generator reads only the comment above `mod`).
- Doc text naming functions that do not exist: `Html.to_string` (html.march:147),
  `Http.get_request` (http_client.march:365), `NodeRpc.connect` (cluster.march:4,7),
  `DistLink.monitor` (dist_supervisor.march:5), `ChannelServer.init_state` /
  `handle_in_msg` / `handle_leave` (channel_server.march), `ChannelSocket.handler`.
- Doctests: only 10 modules are on `scripts/check-stdlib-doctests.py`'s pure allowlist;
  110 of 210 `march>` examples are skipped (most for non-primitive output).
- `Http.encode_query` does not percent-encode (now documented); worth deciding whether it
  should.

Prioritise user-facing modules (HttpServer, HttpClient, Map, Set, Seq, File, Logger,
DataFrame, Plot) over cluster internals.
