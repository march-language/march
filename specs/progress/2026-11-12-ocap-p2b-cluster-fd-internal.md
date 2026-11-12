# Mark the stdlib's cluster fd plumbing `@[stdlib_internal]` (2026-11-10)

Ocap phase 2b. Deferred from phase 2a (PR march-language/march#1244, which shipped the handle box, the handle types and primitives, `@[stdlib_internal]` and `File.Handle`). The task text, files, interfaces and tests are in `specs/plans/2026-11-10-ocap-p2-handles-plan.md`, Task 9. Work in progress on branch `claude/ocap-p2b-handles` (Task 5 has an unreviewed WIP commit there).

- `ClusterConn`/`NetKernel`/`ClusterNode` expose `fd : Int` publicly; mark the fd plumbing internal (prefer migrating fixtures to handles over exempting them).

## Done (2026-11-12, plan Task 9)

`@[stdlib_internal]` now marks every public function over a raw `fd : Int` (or a record holding one) in the cluster stack:

- `NetKernel`: `send_frame`, `write_framed`, `recv_frame`, `recv_frame_exact`, `handshake`, `handshake_role`, `recv_frame_until`, `handshake_addr`, `raw_allowed`, `note_raw_refused`, `link_binding`, `forget`, `sealed`, `handshake_auth`.
- `NodeSend`: `cast`, `cast_schema`, `recv_failure`, `cast_from`, `serve_one`, `serve_one_reply`, `handle_frame`. `NodeCall`: `call`, `serve_one`, `serve_loop`. `NodeQueue`: `start`, `close_fd`, `consumed`. `PeerReader.serve`. `PeerRegistry`: `no_fd`, `add_data`.
- `ClusterConn`: `listen`, `accept_split`, `accept_split_within`, `accept_split_auth`, `accept_one`, and (beyond the task list, they return `Peer` records holding fds) `connect_split`, `connect_split_within`, `connect_split_auth`, `connect_to_peer`.
- `ClusterNode.handshake`. `SessionNode`: `accept_from`, `connect_to`, `open` (the three that take a `Peer` and do I/O on its fds).

No signature changed; the public `fd` record types stay. Test: `cluster_plumbing_internal` in `test/test_stdlib_only.ml`.

Fixtures: cluster tests that drive the plumbing by hand compile with `--stdlib-source` (test/dune native rules, `scripts/two-node.sh`'s `plumbing_flag`, `specs/lang/golden/sanitize.sh`, the `cluster_frames` bench, `scripts/rpc/hot-deploy.sh`); `test_hcr_stdlib_actors` migrated to `NodeQueue.start_local`. The compiler's generated control wiring (`<control>`) may name internals (`Typecheck_builtins.span_may_name_internal`).

Known wart: the diagnostic text says "use the handle API in `NetKernel`", which has no handle API; the per-function hint is not customisable yet.
