Host and method scopes: whole-branch review follow-ups (PR on top of #1213).

- **`Other("get")` passed a GET-only scope.** `hc_method_lower` lowercased `Other(x)`, so a
  non-standard lowercase `get` was sent while the guard saw GET. `Other(_)` now maps to a
  sentinel no `methods(...)` entry can name. Test: `test/stdlib/test_http_client.march`.
- **Diagnostics leaked compiler names** (`Fetch$B.T.fetch`, `Fetcher_spawn`, `Fetcher_Go`).
  `lib/tir/net_scope.ml` renders `source_phrase`: mono/impl suffixes stripped, actor glue
  shown as ``actor `Fetcher` `` / ``handler `Go` of actor `Fetcher` ``. The host check runs
  on `--compile` only, so the golden errors corpus (`--check`) cannot reach these; the
  tests are end-to-end in `test/test_cap_net_scope.ml`.
- **`format.ml` duplicated `Host_scope.split_options`.** The `DNeeds` arm now calls it
  (`march_format` depends on `march_caps`).
- **Same-short-name modules shared one scope** (confirmed bug, not just suspected).
  `module_need_scopes` also filed each nested module under its short name, so a top-level
  `Inner` and `P1.Inner` collided: a valid program was rejected and an out-of-scope call
  accepted, depending on declaration order. Now keyed by qualified name only.
- **Ceiling transparency by name.** `Cap_attrib.attribute`'s `~transparent` now excludes
  user modules (a real `DMod` span outside the stdlib root, `user_module_names` in
  `bin/main.ml`), so a user `mod Yaml` is charged for its own capabilities. Test:
  `test/test_cap_ceiling.ml`.
