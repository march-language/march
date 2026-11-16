`[P2]` Path scopes on `IO.NetConnect` — DONE (2026-11-09).

Phase 1 of `specs/2026-11-09-dependency-grants-and-restrict-design.md` (§3); plan
`specs/plans/2026-11-09-path-scopes-plan.md`; roadmap
`specs/plans/2026-11-09-grants-restrict-roadmap.md`.

- `lib/caps/host_scope.ml`: patterns carry a path prefix (`host/v1/weather/`); segment-wise
  `path_within`, the refusal rules in `path_ok`, `permits_request`,
  `permits_host_ignoring_path`, `url_path_of_literal`; spec strings carry paths.
- `stdlib/http.march`: the scope matcher moved here from `HttpClient` (shared with
  `HttpTransport`), with paths; `ScopeRefusal`. `HttpClient.PathRefused`;
  `HttpTransport.simple_get_scoped` and `Refused`.
- `lib/tir/net_scope.ml`: destinations carry the visible path (`DPath`/`DPrefix`/
  `DUnknown`) and whether the call is guarded; literal paths outside a scope are
  `cap_host_scope`, an unknown path reached through another function is
  `cap_host_unproven`; `HttpTransport.simple_get` is rewritten to its twin
  (`Net_dest.guarded`).
- Tests: `test/test_host_scope.ml` (algebra, declarations, OCaml-vs-March path
  differential), `test/test_cap_net_scope.ml` (8 end-to-end path cases),
  `test/stdlib/test_http_client.march`, `test/stdlib/test_http_transport.march`.
