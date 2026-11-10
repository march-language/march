# Path scopes on IO.NetConnect: implementation plan (phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `needs IO.NetConnect("api.vendor.test/v1/weather/", methods(get))` limits a module
to a path prefix on a host, checked at compile time where the path is visible and at run
time on every request.

**Architecture:** Extend the host-scope algebra with an optional path prefix; move the
stdlib scope matcher into `Http` so both `HttpClient` and `HttpTransport` use it; give
`HttpTransport.simple_get` a guarded `_scoped` twin; extend `Net_scope` so destinations
carry an optional literal path and a path-scoped host refuses raw connections and unguarded
unknown paths.

**Tech Stack:** OCaml 5.5.1, March stdlib, alcotest.

**Spec:** `specs/2026-11-09-dependency-grants-and-restrict-design.md` §3, on top of
`specs/2026-11-09-host-scoped-network-capabilities-design.md`. Roadmap:
`specs/plans/2026-11-09-grants-restrict-roadmap.md`.

## Global Constraints

- Pattern syntax: `host[:port][/path/prefix/]`; the path starts at the first `/` after the
  host and port. A host-only pattern is unchanged.
- Matching is by whole segment: `/v1/weather/` admits `/v1/weather` and
  `/v1/weather/today`, not `/v1/weatherman`. Query string and fragment never count.
- A request path containing a `.` or `..` segment, `%2e`/`%2E`/`%2f`/`%2F`/`%5c`/`%5C`,
  `\`, or `//` is **refused**, not normalized. A path scope containing any of these, or
  `%`, `?`, `#`, is rejected at declaration (`invalid_cap_scope`).
- Under a path scope every request is checked at send time; the compiler reports only
  violations it can see (a literal path outside the prefix, or a literal prefix whose path
  already leaves it).
- A path-scoped host admits no raw connection (`tcp_connect`).
- The scope spec string grows a path: entry `[!]host[:port][/path/][@m+m]`; `""` still
  means any host. OCaml (`Host_scope`) and March (`Http`) must agree, pinned by the
  existing differential tests extended with path cases.
- Unscoped and host-only programs behave and compile exactly as before.
- Build with `--root .`; after editing `stdlib/*.march` restage with
  `dune build --root . _build/default/stdlib/<file>.march`; never `git add -A`.
- Every commit updates `specs/todos/` / `specs/progress/`; user-visible changes get a
  `CHANGELOG.md` bullet under `## [Unreleased]`.

## Review Focus

- `https://api.vendor.test/v1/weather` (no trailing slash) under scope `/v1/weather/` is
  admitted, and `/v1/weather?x=1` too (Task 1 test `boundary_and_query`).
- A literal prefix `"https://api.vendor.test/v1/weather/" ++ "../admin"` compiles and is
  refused at run time (Task 3 test `dotdot_after_prefix_refused`, Task 4 e2e).
- Upper-case percent escapes (`%2F`) and lower-case (`%2f`) are both refused (Task 1
  `refused_encodings`).
- A redirect from an admitted path to another path on the same host is refused (Task 3
  `redirect_to_other_path_refused`).
- Two declarations for one host with different path prefixes admit both prefixes and
  nothing else (Task 1 `two_prefixes`).

---

### Task 1: Path prefixes in the host-scope algebra

**Files:**
- Modify: `lib/caps/host_scope.ml`, `lib/caps/host_scope.mli`
- Test: `test/test_host_scope.ml`

**Interfaces:**
- Produces:
  - `pattern` gains `path : string list option` (normalized segments; `None` = any path).
  - `val path_ok : string -> bool`: the request-path refusal rules (Global Constraints).
  - `val path_within : prefix:string list -> string -> bool`: segment-wise prefix match on
    a request path (query/fragment stripped first).
  - `val permits_request : decl list -> host:string -> port:int -> meth:string option -> path:string option -> bool`:
    `meth = None` means unknown (not checked), `path = None` means unknown (admitted only
    by declarations without a path; callers that rely on the run-time guard use
    `permits_host_ignoring_path`).
  - `val permits_host_ignoring_path : decl list -> host:string -> port:int -> meth:string option -> bool`
  - `val url_path_of_literal : prefix:bool -> string -> string option`: the path of a
    literal URL (`prefix:false`, whole path) or the path part of a literal prefix up to and
    including its last `/` (`prefix:true`).
  - `permits_raw` is false for any covering declaration with a path.
  - `encode_spec` / `decode_spec` carry the path (`host/v1/weather/`).

- [ ] **Step 1: Failing tests** in `test/test_host_scope.ml`:
  `path_pattern_parses` (`"api.x.test/v1/weather/"` → host `api.x.test`, path `["v1";"weather"]`; `"api.x.test:8443/v1/"` keeps the port),
  `path_pattern_rejects` (each of `"a.test/v1/../x/"`, `"a.test/v1//x/"`, `"a.test/%2e/"`, `"a.test/v1?x"`, `"a.test/v1#x"`, `"a.test/a\\b/"` is `Error _`),
  `boundary_and_query` (`path_within ~prefix:["v1";"weather"]` admits `/v1/weather`, `/v1/weather/`, `/v1/weather/today`, `/v1/weather?x=1`; refuses `/v1/weatherman`, `/v1`, `/`),
  `refused_encodings` (`path_ok` false for `/v1/./x`, `/v1/../x`, `/v1//x`, `/v1/%2e%2e/x`, `/v1/%2E/x`, `/v1%2fx`, `/v1%2Fx`, `/v1%5cx`, `/v1\\x`; true for `/v1/weather/today`, `/v1/a%20b`),
  `two_prefixes` (decls `a.test/v1/x/` and `a.test/v2/` admit `/v1/x/1` and `/v2/y`, refuse `/v1/y`),
  `raw_refused_under_path` (`permits_raw` false for `a.test/v1/`),
  `spec_roundtrip_paths` (encode/decode identity with paths, methods and `!`),
  `url_path_of_literal_cases` (`~prefix:false "https://a.test/v1/w?q=1"` → `Some "/v1/w"`; `~prefix:true "https://a.test/v1/"` → `Some "/v1/"`; `~prefix:true "https://a.test/v1/wea"` → `Some "/v1/"`).
- [ ] **Step 2:** `./_build/default/test/run_compiler.exe test host_scope` → FAIL (missing fields/functions).
- [ ] **Step 3: Implement** in `host_scope.ml`; `parse_pattern` stops rejecting `/` and splits host from path; the old `"drop the path"` error becomes the path-validity errors.
- [ ] **Step 4:** run → PASS; existing host-scope tests still PASS.
- [ ] **Step 5: Commit** `feat(caps): path prefixes in host scopes`.

### Task 2: Declarations and diagnostics accept path scopes

**Files:**
- Modify: `lib/typecheck/typecheck.ml` (the `DNeeds` arm's host-scope error text), `specs/lang/capabilities.md` host-scopes section, `docs/` via `scripts/gen-lang-docs.py`
- Test: `test/test_host_scope.ml` (declaration tests, `accepts` / `rejects_with` helpers already there)

**Interfaces:** Consumes Task 1's `parse_pattern`.

- [ ] **Step 1: Failing tests:** `path_scope_declared` (`needs IO.NetConnect("api.x.test/v1/weather/", methods(get))` typechecks), `bad_path_scope_declared` (`needs IO.NetConnect("api.x.test/v1/../admin/")` → `invalid_cap_scope` mentioning `..`).
- [ ] **Step 2:** run → FAIL. **Step 3:** adjust the message (the hint names the path form). **Step 4:** PASS; `scripts/check-docs.sh` passes after the docs edit.
- [ ] **Step 5: Commit** `feat(caps): path scopes in needs declarations`.

### Task 3: Run-time path check in the stdlib guard

**Files:**
- Modify: `stdlib/http.march` (new public scope helpers), `stdlib/http_client.march` (its `hc_*` helpers delegate to `Http`; `hc_check_request` checks the path), `stdlib/http_transport.march` (`simple_get_scoped` twin; `TransportError` gains `Refused(String)`), `stdlib/http_client.march`'s mirrored `TransportError` (same variant)
- Test: `test/stdlib/test_http_client.march`, `test/stdlib/test_http.march` (create if absent), `test/test_host_scope.ml` (differential)

**Interfaces:**
- Produces (March, public in `Http`, so `HttpTransport` can use them without depending on `HttpClient`):
  - `fn scope_check_request(spec : String, req) : Result(Unit, String)`: `Err` carries
    `"OutOfScope host"`, `"MethodRefused METHOD host"` or `"PathRefused host/path"`; `""`
    spec is always `Ok`. `HttpClient.hc_check_request` maps these to its `OutOfScope`,
    `MethodRefused` and a new `PathRefused(String)` variant.
  - `fn scope_permits_request(spec, host, port, meth, path) : Bool`
  - `pfn simple_get_scoped(url, scope)` in `HttpTransport`; `simple_get(url)` is
    `simple_get_scoped(url, "")`. A refusal is `Err(Refused(msg))`.
- `Net_dest.redirect_capable` is renamed `guarded` and includes `HttpTransport.simple_get`.

- [ ] **Step 1: Failing March tests:** `path scope admits prefix`, `path scope refuses other path` (`PathRefused`), `dotdot_after_prefix_refused` (request path `/v1/weather/../admin` under `a.test/v1/weather/` → `PathRefused`), `encoded slash refused`, `query ignored`, `redirect_to_other_path_refused` (`hc_redirect_target` from `/v1/weather/` to `/v2/` under `a.test/v1/weather/`), `simple_get_scoped refuses before connecting` (an out-of-scope URL returns `Err(Refused(_))`; use a host that does not resolve so a wrongful connect attempt shows as `ConnectionRefused`, not `Refused`).
- [ ] **Step 2: Failing differential test** `path_matcher_agrees` in `test/test_host_scope.ml`: corpus of (spec, host, port, method, path) cases including every Task 1 refusal case; compares `Http.scope_permits_request` with `Host_scope.permits_request`.
- [ ] **Step 3:** run `scripts/run-tests.sh stdlib_march` and the compiler test → FAIL.
- [ ] **Step 4: Implement.** Keep every existing `hc_*` public helper with its current behaviour for host-only specs (they are documented and tested).
- [ ] **Step 5:** `scripts/run-tests.sh -q stdlib stdlib_march` and `run_compiler.exe test host_scope` → PASS.
- [ ] **Step 6: Commit** `feat(stdlib): path scopes in the HttpClient and HttpTransport guard`.

### Task 4: Compile-time path check and the `simple_get` rewrite

**Files:**
- Modify: `lib/caps/net_dest.ml(i)` (`guarded`, rename at its two uses), `lib/tir/net_scope.ml` (`dest_use` gains `path : string option`; `url_evidence` fills it from `Host_scope.url_path_of_literal`; the check uses `permits_request` / `permits_host_ignoring_path`; the rewrite covers every `guarded` name)
- Test: `test/test_cap_net_scope.ml`

**Interfaces:** Consumes Tasks 1 and 3.

Rules (spec §3):
- Literal whole URL: its path is checked; outside the prefix → `cap_host_scope` naming the path.
- Literal prefix: if its path part already leaves every covering prefix (e.g. `/v2/` under `/v1/`) → `cap_host_scope`; otherwise admitted, and the run-time guard checks the rest.
- Unknown path to a path-scoped host is admitted only at a direct call to a `guarded` entry point in the scoped module (it is rewritten to the twin); through a helper in another module → `cap_host_unproven` ("the path guard cannot follow through `C.fetch`").
- Raw connection to a path-scoped host → `cap_host_unproven`.

- [ ] **Step 1: Failing end-to-end tests:** `literal_path_in_scope_ok`, `literal_path_outside_rejected` (mentions `/v1/admin`), `prefix_inside_ok` (`"https://a.test/v1/weather/" ++ p`), `prefix_leaving_rejected` (`"https://a.test/v2/" ++ p` → `cap_host_scope`), `simple_get_rewritten` (`--dump-tir` shows `HttpTransport.simple_get_scoped` and the spec literal), `helper_unknown_path_unproven`, `raw_to_path_scoped_unproven`, `host_only_programs_unchanged` (an existing host-scope fixture's `--dump-tir` for an unscoped module contains no `_scoped` call).
- [ ] **Step 2:** run `./_build/default/test/run_compiler.exe test cap_net_scope` → the new cases FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** all `cap_net_scope`, `host_scope`, `cap_scope` cases PASS; `scripts/run-tests.sh -q stdlib stdlib_march errors codegen` PASS; `scripts/oracle-base.sh ir` shows changes only in programs that use `HttpTransport.simple_get` (expected: the public function now calls its twin).
- [ ] **Step 5:** `CHANGELOG.md` (`### Added`: path scopes), `specs/progress/` entry, roadmap row 1 marked done; **Commit** `feat(caps): compile-time path scopes and guarded simple_get`.
