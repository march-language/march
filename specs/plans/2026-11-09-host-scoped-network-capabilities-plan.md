# Host-scoped network capabilities: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship phase 1 of host scopes: `needs IO.NetConnect("example.com")` per module,
checked at compile time and fail-closed, with a run-time redirect/request-step guard and
a `no_redirects` option.

**Architecture:** A pure OCaml host-scope algebra (`lib/caps/host_scope.ml`) is shared by
the typechecker (declaration validation, per-module storage) and a new pre-mono TIR pass
(`lib/tir/net_scope.ml`) that runs right after lowering on the compile path. The pass
summarises every function's network reach, checks scoped modules' boundary calls, and
rewrites redirect-capable `HttpClient` calls in scoped modules to private `*_scoped`
twins that take the module's scope as a string literal. The stdlib checks every
destination it decides on itself against that string.

**Tech Stack:** OCaml 5.5.1 (dune, menhir, alcotest), March stdlib, tree-sitter grammar.

**Spec:** `specs/2026-11-09-host-scoped-network-capabilities-design.md`

## Global Constraints

- Scopes are accepted on `IO.NetConnect` only. A scope on `IO.NetConnect.TLS`,
  `IO.WebSocket`, `IO.Database`, `IO.NetListen`, `IO.Network` or `IO` stays `[invalid_cap_scope]`.
- Unscoped `needs IO.NetConnect` means any host. No existing program changes meaning or
  output: `scripts/ir-oracle.sh` and `scripts/types-oracle.sh` (via `scripts/oracle-base.sh ir types`) must be green apart from fixtures this branch adds.
- Host pattern: `host`, `host:port`, `*.suffix` (leftmost whole label only), IPv4, `[IPv6]`.
  Normalize: ASCII lowercase, strip one trailing `.`. Reject scheme, path, userinfo,
  empty label, bare `*`, non-ASCII.
- A URL with no explicit port takes 80 (`http`) / 443 (`https`).
- The authority of a literal URL ends only at `/` (matching `Http.parse_url`). Its
  characters must be letters, digits, `-`, `.`, plus one `:port`; anything else
  (`@ [ \ % ? #`, whitespace, control) makes the literal not host-evident.
- `tls_connect`'s `hostname` argument is never treated as a destination.
- Server-side TLS (`tls_server_ctx`, `tls_accept`) is exempt from host scopes.
- The check and the rewrite run on the `--compile` path only, like the capability
  ceiling. `--check` and the interpreter do not run them; documentation says so.
- Diagnostics: codes `cap_host_scope`, `cap_host_unproven`, `cap_host_annotation`; one
  diagnostic per module, first offending call primary, the rest as labels.
- `no_redirects` is stored in the existing `DNeeds` scope string as `"<pattern>;no_redirects"`
  (`";no_redirects"` with no pattern means any host). The AST type does not change. (Plan call.)
- A parser change needs `tree-sitter-march/grammar.js` updated in the same PR
  (`scripts/check-tree-sitter.sh`).
- Every commit updates `specs/todos/` / `specs/progress/` per `CLAUDE.md`; user-visible
  behaviour gets a `CHANGELOG.md` bullet under `## [Unreleased]`.
- Build and test from the worktree with `--root .` or `scripts/run-tests.sh`; never `git add -A`.

**Cut from phase 1** (plan calls, recorded in Task 7's follow-up todo): scoped per-function
bounds (`fn f() needs IO.NetConnect("x")` needs an AST change to `fn_needs`), and the
run-time guard through an annotated user wrapper: a scoped module reaching a
redirect-capable `HttpClient` entry point *through* another user module's
`@[net_dest(p)]` function is `cap_host_unproven` until the twin rewrite can clone that
chain.

## Review Focus

- `https://Example.COM./x` under scope `example.com` is accepted: normalization applies
  to both sides (Task 1 test `case_and_trailing_dot`).
- `http://example.com/` under `example.com:443` is rejected (port 80), and
  `https://example.com:443/` under `example.com` is accepted (Task 1 test `default_ports`).
- A scoped module that imports an unscoped module but never calls its network functions
  builds clean: summaries are per function, not per module (Task 5 test `unused_import_is_free`).
- A relative `Location` (same origin) is followed under a scope and refused under
  `no_redirects` (Task 3 test `relative_redirect`).
- A lambda written in scoped `A` and handed to a stdlib callback (a request step that
  calls `HttpTransport.simple_get`) is checked against `A`'s scope (Task 5 test
  `lambda_in_scoped_module`).

---

### Task 1: Host-scope algebra

**Files:**
- Create: `lib/caps/host_scope.ml`, `lib/caps/host_scope.mli` (add to `lib/caps/dune` if modules are listed)
- Create: `test/test_host_scope.ml`; register in `test/dune` (`test_compiler` modules list) and `test/test_compiler.ml` next to `("cap_scope", Test_cap_scope.tests)`

**Interfaces:**
- Produces:
  - `type pattern = { host : string; wildcard : bool; port : int option }`
  - `type decl = { patterns : pattern list; no_redirects : bool }` (`patterns = []` means any host)
  - `val parse_pattern : string -> (pattern, string) result` (error string is the user-facing reason)
  - `val parse_decl : string option -> (decl, string) result` (splits `;no_redirects`; `None` → `{patterns=[]; no_redirects=false}`)
  - `val normalize_host : string -> string`
  - `val matches : pattern -> host:string -> port:int -> bool`
  - `val permits : decl list -> host:string -> port:int -> bool` (empty list = no scoping = true; any decl with `patterns=[]` = true)
  - `val forbids_redirects : decl list -> host:string -> port:int -> bool` (true if any decl that matches the host has `no_redirects`)
  - `type authority = { a_host : string; a_port : int }`
  - `val authority_of_url : prefix:bool -> string -> authority option` (`prefix:true` requires the `/` terminator; `prefix:false` accepts a whole URL with or without a path)
  - `val encode_spec : decl list -> string` and `val decode_spec : string -> decl list` (the run-time string; `""` = any host; entries `,`-separated, each `pattern` with a leading `!` when `no_redirects`, `!` alone = any host with no redirects)

- [ ] **Step 1: Write failing tests** in `test/test_host_scope.ml`:
  `parse_rejects` (each of `"https://a.com"`, `"a.com/x"`, `"u@a.com"`, `"a..com"`, `"*"`, `"a.*.com"`, `"é.com"` is `Error _`),
  `wildcard` (`*.example.com` matches `api.example.com`, `a.b.example.com`; not `example.com`, not `badexample.com`),
  `case_and_trailing_dot` (`example.com` matches host `Example.COM.`),
  `ports` (`example.com:8443` matches port 8443 only; `example.com` matches any port),
  `default_ports` (`authority_of_url ~prefix:false "http://example.com/"` = port 80; `"https://example.com"` = 443; `"https://example.com:8443/x"` = 8443),
  `authority_prefix` (`~prefix:true "https://example.com/"` is `Some`; `"https://example.com"`, `"https://example.com?"`, `"https://a.com@b.com/"`, `"https://a.com\\@b.com/"`, `"ftp://a.com/"`, `"https://a.com:/"` are `None`),
  `no_redirects_decl` (`parse_decl (Some "a.com;no_redirects")` → `no_redirects=true`; `Some ";no_redirects"` → any host, no redirects),
  `spec_roundtrip` (`decode_spec (encode_spec ds) = ds` for three decl lists, and `encode_spec [] = ""`),
  `permits_union` (decls for `a.com` and `b.com` permit both, not `c.com`).
- [ ] **Step 2:** `scripts/run-tests.sh compiler` → the new cases FAIL (module missing).
- [ ] **Step 3: Implement** `host_scope.ml`. Pure string code, no regex library; no DNS.
- [ ] **Step 4:** `scripts/run-tests.sh compiler` → PASS.
- [ ] **Step 5: Commit** `feat(caps): host-scope algebra for IO.NetConnect`.

### Task 2: Declarations: accept, validate, store

**Files:**
- Modify: `lib/caps/cap_scope.ml` (`is_scopable` accepts `IO.NetConnect`; keep FS-only consumers FS-only: `effective_scopes`/`manifest_json` already filter by FS class, assert it in a test)
- Modify: `lib/typecheck/typecheck.ml:9139-9178` (the `DNeeds` arm: route `IO.NetConnect` scopes through `Host_scope.parse_decl`, FS scopes through the existing absolute-path check; new message for a scope on another network cap names `IO.NetConnect` as the one that takes a host)
- Modify: `lib/typecheck/typecheck_env.ml:338-345,869` (add `module_need_scopes : (string * (string * string option) list) list`, default `[]`)
- Modify: `lib/typecheck/typecheck.ml:8485-8528` (populate `module_need_scopes` alongside `module_caps'`, same keys: qualified and short name)
- Modify: `lib/parser/parser.mly:1452-1454` (`scoped_cap_path` adds `cap_path ( STRING , no_redirects )` and `cap_path ( no_redirects )`; `no_redirects` is an identifier compared by text, not a new keyword; encode per Global Constraints)
- Modify: `lib/format/format.ml` (print the encoded form back as `("a.com", no_redirects)` / `(no_redirects)`)
- Modify: `tree-sitter-march/grammar.js:593` (`scoped_capability` accepts the two new shapes) and add a corpus case per the repo's tree-sitter workflow
- Test: `test/test_host_scope.ml` (compile-level cases using the `compile_with`/`rejects_at_typecheck` pattern from `test/test_cap_ceiling.ml:101-195`)

**Interfaces:**
- Consumes: `Host_scope.parse_decl`.
- Produces: `Typecheck_env.env.module_need_scopes`; `Typecheck.declared_net_scopes : env -> entry_module:string -> (string * Host_scope.decl list) list` (per module, entry module keyed by the TIR module name as `bin/main.ml:5165-5169` does for `module_caps`; decls only for `IO.NetConnect` entries; a module with an unscoped `IO.NetConnect` or `IO`/`IO.Network` declaration maps to `[]` = unscoped).

- [ ] **Step 1: Failing tests:** `net_scope_accepted` (`needs IO.NetConnect("example.com")` typechecks), `net_scope_bad_pattern` (`needs IO.NetConnect("https://example.com")` → `invalid_cap_scope` mentioning "scheme"), `tls_scope_rejected` (`needs IO.NetConnect.TLS("a.com")` → `invalid_cap_scope`), `no_redirects_parses` (both new forms typecheck), `fs_scope_unchanged` (`needs IO.FileRead("/etc")` still accepted, relative still rejected), `fs_manifest_ignores_net` (`Cap_scope.manifest_json [("IO.NetConnect", Some "a.com")]` = `None`), `declared_net_scopes_per_module` (two nested modules, `A` → `a.com`, `B` → `b.com`, `C` unscoped → `[]`), `format_roundtrip` (format a module with `("a.com", no_redirects)` prints it unchanged).
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** implement the listed changes.
- [ ] **Step 4:** `scripts/run-tests.sh compiler` and `scripts/check-tree-sitter.sh` → PASS; `dune build --root .` clean.
- [ ] **Step 5: Commit** `feat(caps): accept host scopes and no_redirects on IO.NetConnect`.

### Task 3: Run-time guard in the stdlib

**Files:**
- Modify: `stdlib/http_client.march`
- Test: `test/stdlib/test_http_client.march`; a differential test in `test/test_host_scope.ml`

**Interfaces:**
- Produces (March, public `hc_` helpers like the existing `hc_same_origin`, so tests can call them):
  - `fn hc_scope_permits(spec : String, host : String, port : Int) : Bool`: same meaning as `Host_scope.permits (decode_spec spec)`.
  - `fn hc_scope_forbids_redirects(spec : String, host : String, port : Int) : Bool`
  - `fn hc_redirect_target(spec : String, from_req, target_req) : Result(Unit, HttpError)`: `Err(RedirectRefused(host))` when forbidden, `Err(OutOfScope(host))` when the target is outside, else `Ok(())`.
  - `HttpError` gains `OutOfScope(String)` and `RedirectRefused(String)`.
  - Private twins, one extra trailing `scope : String` parameter: `pfn get_scoped(client, url, scope)`, `post_scoped`, `put_request_scoped`, `delete_scoped`, `stream_get_scoped`, `with_connection_scoped`. Each public function is its twin with `""`.
  - Internals take `scope`: `run`, `run_on_fd`, `handle_redirects`, `stream_get`, the retry/reconnect path. Before every connection the request host (after request steps) must pass `hc_scope_permits`, else `Err(OutOfScope(host))` without connecting.

- [ ] **Step 1: Failing March tests** in `test_http_client.march`: `scope empty permits anything`, `scope permits listed host only`, `wildcard scope`, `port scope uses scheme default`, `relative_redirect` (same-origin target: `Ok` under `"example.com"`, `Err(RedirectRefused(_))` under `"!example.com"`), `cross-host redirect refused` (`from` example.com, `target` foo.com under `"example.com"` → `Err(OutOfScope("foo.com"))`), `cross-host redirect allowed when both scoped` (`"example.com,foo.com"` → `Ok(())`), `unscoped follows cross-host` (`""` → `Ok(())`).
- [ ] **Step 2: Failing differential test** `matcher_agrees` in `test/test_host_scope.ml`: for a fixed corpus of (spec, host, port) triples (at least the Task 1 cases), run one interpreted March program that prints `hc_scope_permits` per line and compare with `Host_scope.permits (decode_spec spec)`. Same harness compares `authority_of_url ~prefix:false` against `Http.parse_url`'s host/port for every literal Task 1 accepts.
- [ ] **Step 3:** run `scripts/run-tests.sh stdlib_march compiler` → FAIL.
- [ ] **Step 4: Implement** the helpers, variants, threading and twins. Keep every existing doctest's output unchanged.
- [ ] **Step 5:** `scripts/run-tests.sh stdlib_march stdlib compiler` → PASS.
- [ ] **Step 6: Commit** `feat(stdlib): HttpClient scope guard for redirects and request steps`.

### Task 4: Destination table and `@[net_dest]`

**Files:**
- Create: `lib/caps/net_dest.ml`, `lib/caps/net_dest.mli`
- Modify: `stdlib/http_client.march`, `stdlib/http_transport.march` (annotate URL entry points)
- Modify: `lib/typecheck/typecheck.ml` (validate `net_dest:<p>` in `fn_attrs`: `p` must name a parameter, else `cap_host_annotation`)
- Modify: `lib/errors/code.ml` (add `cap_host_annotation` to the lists at `:258`, `:285`, `:496`; Task 6 adds the other two codes)
- Test: `test/test_host_scope.ml`

**Interfaces:**
- Produces:
  - `type dest = Url of int | Host of int * int option | Handle | Inbound | Unknown`
  - `val builtin_dest : string -> dest option`: rows for every builtin whose `builtin_cap_table` capability is `IO.NetConnect` or a descendant, or `IO.WebSocket`. `tcp_connect`/`tcp_connect_timeout` → `Host (0, Some 1)`; `udp_connect`/`udp_resolve` → `Host (0, Some 1)`; `tls_server_ctx`/`tls_accept` → `Inbound`; `tls_connect` and every fd-taking op → `Handle`; `dist_monitor_*`, `udp_send_batch`, `udp_send_many` → `Unknown`.
  - Attribute `@[net_dest(p)]` on a function: parameter `p` is a URL destination. Stdlib annotations: `HttpTransport.simple_get(url)`, `HttpClient.get/post/put_request/delete/stream_get/with_connection(…, url, …)`.
  - `val redirect_capable : string -> bool`: true for the six `HttpClient` names with twins (Task 3).

- [ ] **Step 1: Failing tests:** `every_net_builtin_classified` (iterate `Typecheck.builtin_cap_table`; every network-family entry has `builtin_dest <> None`), `tls_connect_is_handle`, `bad_net_dest_param` (`@[net_dest(nope)] fn f(url)` → `cap_host_annotation`).
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** `scripts/run-tests.sh compiler stdlib_march` → PASS.
- [ ] **Step 5: Commit** `feat(caps): network destination table and @[net_dest]`.

### Task 5: The static check

**Files:**
- Create: `lib/tir/net_scope.ml`, `lib/tir/net_scope.mli`
- Test: `test/test_cap_net_scope.ml` (register in `test/dune` and `test/test_compiler.ml`); end-to-end via the `compile_with` pattern of `test/test_cap_ceiling.ml:101-195`, since `--check` does not run this pass

**Interfaces:**
- Consumes: `Host_scope`, `Net_dest`, `Cap_attrib.cap_of_call`, `Typecheck.declared_net_scopes`.
- Produces:
  - `type violation = { code : string; owner : string; fn_name : string; message : string; span : March_ast.Ast.span option }` (`code` is one of the three Global Constraints codes)
  - `val check : scopes:(string * Host_scope.decl list) list -> transparent:(string -> bool) -> transparent_fns:(string -> bool) -> annotated:(string * int) list -> Tir.tir_module -> violation list`
  - `annotated` maps a TIR function name (as lowered, pre-mono) to its `@[net_dest]` parameter index; `bin/main.ml` builds it from AST `fn_attrs` the way the vectorize pass maps attributes to TIR names.

Rules (spec §4, implemented as written there):
- Owner of a function = `Cap_attrib`'s owner rule (module prefix; entry module = `tm_name`). Only owners with a non-empty decl list are checked.
- Per-function summary, fixpoint over the call graph: `Fixed of authority list` (every network reach host-evident without the function's parameters), `Through of int` (annotated), `Opaque`. Recursion without an annotation is `Opaque`.
- Host-evident atom: `ALit (LitString s)` with `authority_of_url ~prefix:false s`; a `let`-bound variable whose RHS is host-evident; `++(a, e)` where `a` is a literal (or let-bound literal) with `authority_of_url ~prefix:true a`.
- In a scoped owner, a call to a `Url i` / `Host (i, j)` builtin or annotated callee needs a host-evident arg `i` that `Host_scope.permits`; a call to a non-transparent `Fixed` callee checks each authority; `Through` callee checks the arg; `Opaque`, `Handle`, `Unknown`, unannotated transparent callees that reach a network class → `cap_host_unproven`. `Inbound` is ignored.
- A call to a redirect-capable name through a non-transparent annotated callee from a scoped owner → `cap_host_unproven` ("the redirect guard cannot follow through `C.fetch` yet").
- Calls through a local/parameter are not edges (callbacks charged to the supplier, as in `Cap_attrib.walk`); lambdas lifted from a function belong to its owner.
- Annotation validity (every non-transparent annotated function, scoped or not): the parameter reaches a destination position of a `Url`/`Host` builtin or annotated callee unchanged (itself or a `let` alias), and the function's other network reach is `Fixed`; else `cap_host_annotation`.
- In an owner whose every matching decl has `no_redirects`, `HttpClient.with_redirects(c, ALit (LitInt n))` with `n > 0` → `cap_host_scope` ("`no_redirects` …").

- [ ] **Step 1: Failing end-to-end tests** (`MARCH_LIB_PATH` two-file programs, `HttpTransport.simple_get` / `HttpClient.get`):
  `own_host_ok`, `other_host_rejected` (expects `cap_host_scope` naming `foo.com`), `param_unproven`, `prefix_needs_slash` (`"https://example.com" ++ p` unproven, `"https://example.com/" ++ p` ok), `query_prefix_unproven`, `handle_unproven` (`tcp_send_all`), `tls_connect_unproven`, `through_unannotated_unproven`, `through_annotated_ok_and_rejected`, `lying_annotation_rejected`, `fixed_callee_checked` (`C.ping()` with a literal `foo.com` called from `A` scoped to `example.com` → rejected), `unused_import_is_free`, `lambda_in_scoped_module`, `closure_from_unscoped_main_ok`, `unscoped_module_unchecked`, `no_redirects_literal_rejected`, `two_modules_two_hosts` (the owner's example: `A`→`example.com`, `B`→`foo.com`, each OK alone, each rejected reaching the other).
- [ ] **Step 2:** these fail until Task 6 wires the pass; write unit tests of `Net_scope.check` on lowered TIR for the same rules first if the lowering helper in `test/test_compiler.ml` makes that cheap, and run them → FAIL.
- [ ] **Step 3: Implement** `net_scope.ml`.
- [ ] **Step 4:** unit tests PASS (end-to-end ones pass after Task 6).
- [ ] **Step 5: Commit** `feat(caps): compile-time host-scope check (Net_scope)`.

### Task 6: Wire in, rewrite to twins, diagnostics

**Files:**
- Modify: `lib/tir/net_scope.ml` (add `rewrite`)
- Modify: `bin/main.ml` (call `check` then `rewrite` right after lowering, before `Cap_passing`, around `bin/main.ml:4869-4898`; compile path only; render violations through the same diagnostic pipeline as `[cap_ceiling]` (`bin/main.ml:5233` onward); exit 1)
- Modify: `lib/errors/code.ml` (`cap_host_scope` and `cap_host_unproven`, added to the lists at `:258`, `:285`, `:496`)
- Modify: `lib/tir/cap_passing.ml` only if the new parameter breaks its arity analysis (check with `MARCH_CAP_PASSING=1` on one scoped program)

**Interfaces:**
- Produces: `val rewrite : scopes:(string * Host_scope.decl list) list -> Tir.tir_module -> Tir.tir_module`: in a scoped owner, `EApp (HttpClient.<name>, args)` with `Net_dest.redirect_capable name` becomes `EApp (HttpClient.<name>_scoped, args @ [ALit (LitString (Host_scope.encode_spec decls))])`. Unscoped owners untouched.

- [ ] **Step 1: Failing tests** in `test/test_cap_net_scope.ml`: `rewrite_targets_twin` (`--dump-tir` of a scoped module calling `HttpClient.get` contains `HttpClient.get_scoped(` and the literal `"example.com"`), `unscoped_not_rewritten`, `diagnostic_shape` (one `-- CAPABILITY --` block, code `[cap_host_scope]`, primary span on the call, second offending call as a label), plus all Task 5 end-to-end tests.
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** `scripts/run-tests.sh compiler codegen` → PASS.
- [ ] **Step 5:** `scripts/oracle-base.sh ir types` → only fixtures this branch added differ.
- [ ] **Step 6:** `march --compile --opt 2 bench/list_ops.march -o /tmp/hs_list_ops && /tmp/hs_list_ops` runs; compile time of `bench/list_ops.march` within noise of `main` (the pass is linear).
- [ ] **Step 7: Commit** `feat(caps): wire host-scope check and redirect-guard rewrite into --compile`.

### Task 7: Documentation and records

**Files:**
- Modify: `specs/lang/capabilities.md` (new section "Host scopes on IO.NetConnect" after path scopes; state compile-path only, interpreter/`--check` gap, redirect guard), `specs/lang/capability-enforcement.md:80` (the path-scopes paragraph: scopes now also on `IO.NetConnect`, not OS-enforced), `specs/lang/capability-threat-model.md` (what host scopes claim and don't)
- Run: `scripts/gen-lang-docs.py`; commit the regenerated `docs/` chapters
- Modify: `CHANGELOG.md` (`### Added` bullet)
- Modify: `specs/2026-11-09-host-scoped-network-capabilities-design.md` (status: phase 1 implemented; note the two cuts and compile-path-only)
- `git mv specs/todos/2026-11-09-host-scoped-network-capabilities.md specs/progress/`, and create `specs/todos/2026-11-09-host-scope-phase-2.md` listing: scoped `main` grant, `forge.caps.lock`/audit/inspect hosts, scoped per-function bounds, guard through annotated wrappers, per-role grants, opaque connection handles.

- [ ] **Step 1:** write the docs. **Step 2:** `scripts/gen-lang-docs.py` then `scripts/check-docs.sh` → PASS.
- [ ] **Step 3:** full suite `scripts/run-tests.sh` → PASS (compare any failure against `main` before attributing it).
- [ ] **Step 4: Commit** `docs: host-scoped network capabilities`.
