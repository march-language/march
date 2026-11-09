# Host-scoped network capabilities

**Date:** 2026-11-09
**Status:** design, not yet approved

Let a module narrow an outbound network capability to the hosts it may reach:

```march
mod A do
  needs IO.NetConnect("example.com")
end

mod B do
  needs IO.NetConnect("foo.com")
end
```

`A` may connect to `example.com` and nothing else, and `B` may connect to `foo.com` and
nothing else. If either one can reach the other's host, or any host the compiler cannot
see, the build fails.

Today this declaration is a compile error (`[invalid_cap_scope]`: only filesystem
capabilities take a scope). The only way to get the separation now is the
object-capability pattern: `main` holds `IO.NetConnect` and hands each module a closure
bound to one base URL. That works (checked 2026-11-09), but nothing in `A`'s or `B`'s
declaration states the restriction, and it breaks the moment either module declares
`needs IO.NetConnect` itself.

---

## 1. Why

Two situations, both in scope (owner, 2026-11-09):

- **A dependency you don't trust.** A library that talks to one API should not be able
  to talk to any other host, and its manifest should say which host.
- **Parts of your own app.** The billing module talks to the payment provider and the
  analytics module talks to the analytics host. Neither should reach the other's.

## 2. Goals, non-goals, anti-goals

**Goals**

- A host scope on `IO.NetConnect`, declared in `needs`, checked **at compile time**. It
  also bounds `IO.NetConnect.TLS` operations, whose connection always starts as a
  `tcp_connect` (my call: scopes only on `IO.NetConnect` itself in phase 1; a scope on
  `IO.NetConnect.TLS`, `IO.WebSocket` or `IO.Database` is a declaration error. The
  stdlib has no WebSocket *client* connect, and `IO.Database` has no builtins, so a
  scope on either could never be satisfied).
- **Fail closed** in a scoped module: a network use whose destination host the compiler
  cannot prove inside the scope is a build error (owner, 2026-11-09). This is stricter
  than the filesystem path scopes, whose static check reports only literal violations
  and leaves computed paths to the runtime sandbox.
- **A scope bounds everything the module reaches**, through other user modules and
  dependencies too, not just its own code (owner, 2026-11-09). This matches how
  per-function bounds already work (§4).
- **Destinations decided at run time inside the stdlib get a run-time guard**: HTTP
  redirects and client request steps (owner, 2026-11-09; §5). A `no_redirects` option
  on the declaration refuses redirects outright (§3).
- Unscoped `needs IO.NetConnect` keeps meaning "any host". No existing program changes
  meaning or stops compiling.
- Scopes appear in `forge audit`, `forge.caps.lock` and `forge cap inspect`, so a
  dependency that widens its host list is flagged like one that adds a capability.

**Non-goals**

- OS enforcement. Neither Seatbelt nor seccomp filters by host name, and
  `forge cap run` cannot either. The guarantee is the compiler's, plus the stdlib's
  run-time redirect guard (§5), which is March code, not a sandbox.
- Scoping `IO.NetListen` (who may connect *to* you) or `IO.Network`'s `dns_resolve`.
- Path or method scopes (`example.com/api/*`, GET-only). Host (and optional port) only.
- Proving which IP address a name resolves to. A scope is about the name the code
  connects to.

**Anti-goals** (failure even if it technically works)

- A scope that *reads* as enforcement but has a known bypass. Every route the check
  cannot see must be refused in a scoped module, not passed.
- A compile-time URL parser that disagrees with the runtime one. If a literal means
  `a.com` to the compiler and anything else to `Http.parse_url`, the feature is worse
  than absent.
- Making unscoped code pay: no new annotations, no slower builds for modules that don't
  scope.

## 3. Surface

### Declaration

```march
needs IO.NetConnect("example.com")                         -- one host
needs IO.NetConnect("example.com"), IO.NetConnect("foo.com")  -- union
needs IO.NetConnect("api.example.com:443")                 -- host and port
needs IO.NetConnect("*.example.com")                       -- any subdomain
needs IO.NetConnect                                        -- unchanged: any host
```

The grammar already accepts `needs X("...")` (path scopes); only the
`Cap_scope.is_scopable` gate and the scope algebra change, plus the option below.

### `no_redirects`

```march
needs IO.NetConnect("example.com", no_redirects)
```

The hosts in that declaration may be contacted, but no redirect is ever followed, to
any host, including the same one (owner, 2026-11-09). Two halves:

- **Compile time:** in a module whose every scope for a class carries `no_redirects`,
  a call to `HttpClient.with_redirects(c, n)` with a literal `n > 0` is a compile error.
  A computed `n` is not refused; the run-time half covers it.
- **Run time:** the redirect guard (§5) treats any `3xx` with a `Location` as refused,
  returning the redirect response's error instead of following it.

Spelling and attachment are my call: the option is a bare identifier after the host,
and it applies to the hosts of the declaration it sits in. When a call's destination
is in two declarations, one with `no_redirects` and one without, the stricter one
wins. `no_redirects` without a host (`needs IO.NetConnect(no_redirects)`) is allowed
and means "any host, never follow a redirect". This is a `parser.mly` change, so it
needs the tree-sitter grammar update the repo requires.

### Scope syntax

A scope is a **host pattern**, never a URL:

| form | matches |
|---|---|
| `example.com` | exactly `example.com`, any port |
| `example.com:8443` | exactly `example.com`, port 8443 only |
| `*.example.com` | any name ending in `.example.com`, **not** `example.com` itself |
| `203.0.113.7`, `[2001:db8::1]` | that literal address only (an IPv6 scope can only be met by `tcp_connect`: `Http.parse_url` splits the port at the first `:` and has no bracket syntax) |

Rejected at declaration (compile error): a scheme (`https://…`), a path, userinfo
(`user@host`), an empty label, a wildcard anywhere but the whole leftmost label, a bare
`*`, non-ASCII (write the punycode form; my call, to keep normalization trivial), and a
scope on `IO.NetListen` or `IO.Network` (still `[invalid_cap_scope]`).

**Normalization** before any comparison, on both sides: ASCII lowercase, one trailing
`.` stripped. No DNS, no public-suffix list. A URL with no explicit port takes its
scheme's default (80 for `http`, 443 for `https`), as the runtime does, so
`example.com:443` admits `https://example.com/` (my call).

**Subsumption** extends the path-scope rule: `a ⊒ b` iff `cap_subsumes a.cap b.cap` and
(`a.scope = None` or `b.scope`'s hosts ⊆ `a.scope`'s hosts). `*.example.com ⊒
api.example.com`; `example.com ⋣ api.example.com`; a port-less pattern subsumes the
same host with a port.

### Where else a scope may appear

- **Per-function bounds:** `fn charge(...) : R needs IO.NetConnect("api.stripe.com") do`.
  Same two checks as today's bounds (inside the module's `needs`, and the function's
  reach inside the bound).
- **`main`'s grant:** `fn main(c : Cap(IO.NetConnect("example.com")), ...)` bounds the
  whole program, dependencies included. This is the half that stops a hostile
  dependency: a dependency can write any `needs` line it likes, but `main`'s grant is
  yours. The scope is allowed inside `Cap(...)` **only** in `main`'s parameter list
  (my call: no type-level strings elsewhere; a `Cap` value passed around stays
  unscoped).
- **Protocol roles:** `role Ledger needs IO.NetConnect("ledger.internal")`, checked as
  the role grant is today. Phase 3.

## 4. What "the compiler can prove the host" means

The check runs at every **network boundary call**: a call from a module that is not
transparent (user code or a dependency) into a stdlib function or builtin whose closure
reaches a scoped capability class. `cap_attrib` already decides which module such a
call is charged to, but it keeps only per-function capability and callee sets, with no
call sites or argument atoms, so the check needs a new walk over the same pre-inline TIR
that keeps them.

Each stdlib entry point and builtin that opens a connection is annotated with **where
its destination comes from** (a table for builtins, an attribute for stdlib functions;
the spelling is the builder's call):

| kind | examples | destination |
|---|---|---|
| URL argument | `HttpTransport.simple_get(url)`, `HttpClient.get(client, url)`, `post`, `put_request`, `delete`, `stream_get`, `with_connection` | parsed from arg *i* |
| host argument | `tcp_connect(host, port)`, `tcp_connect_timeout`, `udp_connect`, `udp_resolve` | arg *i* (host), arg *j* (port, if literal) |
| handle argument | `tcp_send_all(fd, …)`, `tls_connect(fd, ctx, hostname)`, `tls_read`, `ws_send`, `HttpTransport.request_on(fd, req)` | none: the handle came from somewhere else. `tls_connect`'s `hostname` is the SNI and certificate name, **not** the destination; treating it as one would be a bypass |
| request value | `HttpTransport.request(req)`, `HttpClient.run(client, req)` | inside a `Request` built elsewhere |
| none | `dist_monitor_*`, `udp_send_batch`, anything unannotated | unknown |

In a **host-scoped module**, a boundary call is accepted only when:

1. it is a URL-argument or host-argument entry point, **and**
2. the argument is *host-evident*, **and**
3. the host (and port, if the scope names one) is inside the module's effective scope.

Everything else that reaches a scoped class from a scoped module is a compile error,
including handle-argument, request-value and unannotated entry points (fail closed).
Unscoped modules are not checked at all.

### Through other user modules

The scope bounds everything a scoped module reaches (owner, 2026-11-09), not only the
boundary calls in its own body. If scoped `A` calls `C.fetch(url)` in an unscoped user
module or dependency, and `C.fetch` reaches the network, the check follows it:

- If `C.fetch` declares which parameter carries the destination (the same annotation
  the stdlib uses, §4 table; spelling is the builder's call), `A`'s argument at the
  call must be host-evident and inside `A`'s scope. `C.fetch`'s body is then checked
  to pass that parameter, unchanged or behind a literal authority, to a URL-argument
  or host-argument entry point, and to reach the network no other way. If it does
  anything else with it, the annotation is rejected in `C`.
- If `C.fetch` declares no such parameter, `A`'s call is `cap_host_unproven`, naming
  `C.fetch` and suggesting the annotation.
- A function in `C` with a fixed destination (`C.ping()` calling a literal URL) needs
  no annotation; its literal is checked against `A`'s scope like `A`'s own.

This is reachability, the same walk that checks per-function bounds and `main`'s grant,
with one addition: it carries the destination argument through annotated calls. A
callback is still charged to whoever supplies it, so a closure built in an unscoped
`main` and called in `A` is checked against `main`, not `A`.

The same rule is what a scoped `main` grant means in phase 2: every network use in the
program must be proven inside it, so an HTTP library that takes a URL parameter needs
the annotation to be usable under a scoped grant.

**Host-evident** arguments, decided on pre-inline TIR at the call atom:

- a string literal (`ALit`);
- a variable bound by `let` to a host-evident value in the same function (local constant
  propagation, as the path-scope design §8 already plans);
- for a URL argument, `lit ++ e` (or a `++` chain starting with a literal) where `lit`
  already contains a **complete authority**: `http://` or `https://`, the host, an
  optional port, and then a `/`. Only `/` ends the authority, because only `/` ends it
  in `Http.parse_url` (`stdlib/http.march`): `"https://example.com?" ++ q` would make
  the runtime host `example.com?…`. `"https://example.com/" ++ path` is host-evident;
  `"https://example.com" ++ path` is **not**, because `path = ".evil.com/"` makes the
  host `example.com.evil.com`. The diagnostic says so and suggests the trailing `/`.

Anything else (a parameter, a record field, a value returned from a call, a string built
from config) is not host-evident.

### The compile-time URL parser

The authority is extracted by one OCaml function that must agree with the runtime parser
(`Http.parse_url`, `stdlib/http.march`) on every input. That parser is simple: the
authority runs to the first `/`, the port starts at the first `:`, and it knows nothing
of userinfo or IPv6 brackets. A literal whose authority contains anything outside
letters, digits, `-`, `.` and one `:port` is rejected outright rather than interpreted
(so `@`, `[`, `\`, `%`, `?`, `#`, whitespace and control characters all fail). A differential test feeds one corpus
to both and fails on any disagreement (§8).

## 5. Routes the static check cannot see

These are inside the stdlib, after a host-evident URL has been checked. Each is either
closed by construction or refused:

| route | handling |
|---|---|
| HTTP redirects (`HttpClient.with_redirects(n)`) | **Run-time guard** (owner, 2026-11-09): a redirect to a host outside the caller's scope is refused, and every redirect is refused under `no_redirects`. Today `handle_redirects` follows cross-host redirects and only strips credential headers. |
| Request steps that rewrite the request (`add_request_step`, `step_base_url`) | **Run-time guard** (owner, 2026-11-09): after the steps run, the request's host must be inside the caller's scope, or the call fails before connecting. |
| Keep-alive and retry reconnects (`reconnect_and_retry`) | Closed: they reconnect to the request's own host. The builder must confirm and pin it with a test. |
| Callbacks handed to a scoped module | Already handled: a call through a parameter is charged to the module that supplied the function, so a closure built in `main` is checked against `main`'s scope. |
| Integer handles (`fd`) forged or passed in | Refused in a scoped module (handle-argument entry points). See §7 for the opaque-handle follow-up. |
| Request-value entry points (`HttpClient.run(client, req)`, `HttpTransport.request(req)`) | Still refused at compile time in a scoped module: the guard checks a request built by trusted stdlib code from a checked URL, not a `Request` built anywhere. |
| Server-side TLS (`tls_server_ctx`, `tls_accept`) | Exempt from the host scope (my call): they act on connections someone made *to* you, which needs `IO.NetListen`, outside this design. They are classed under `IO.NetConnect.TLS` today, so the destination table marks them inbound. |

### The run-time guard

The compiler knows, at each accepted boundary call, the effective scope of the module
the call is charged to: its hosts, ports and `no_redirects` flags. It passes that scope
to the URL-argument entry point, and the stdlib checks every destination it decides on
by itself (a redirect's `Location`, the host after request steps) against it before
connecting. A destination outside the scope fails the call with an error value, never a
crash, and never connects. Unscoped callers pass "any host" and see no change.

How the scope travels is the builder's call. `lib/tir/cap_passing.ml` already threads
a hidden argument into builtins for test-build mocks and is the natural model; whatever
the mechanism, it must reach `handle_redirects`, `run_request_steps` and the retry and
keep-alive paths, and it must not let user code supply or widen a scope (a scope value
is never constructible in March source).

The error is a new variant on the client's error type (for example
`HttpClient.RedirectOutOfScope(host)`, and one for a step-rewritten host); naming is the
builder's call. It must name the refused host.

## 6. Diagnostics

New codes (names are the builder's call; these are placeholders):

- `cap_host_scope`: a host-evident destination outside the scope.
  ``"`fetch` connects to `foo.com`, but module `A` may reach only `example.com` (needs IO.NetConnect("example.com"))."``
- `cap_host_unproven`: a scoped module reaches the network with a destination the
  compiler cannot see. Names the call and the reason (`url` is a parameter; the literal
  prefix ends before the path; `request_on` takes a socket handle) and the fix: pass a
  literal, end the prefix with `/`, or move the call to a module that holds an unscoped
  capability and hand this module a closure.
- `invalid_cap_scope`: extended with the host-pattern errors in §3.

Like the other capability errors, one diagnostic per module, the first offending call as
the primary span, each further one as a label.

## 7. Phasing

**Phase 1: per-module scopes.** Scope algebra for host patterns (next to
`lib/caps/cap_scope.ml`), lifting the `is_scopable` gate for `IO.NetConnect`, the
`no_redirects` option (parser, AST, tree-sitter), the boundary check on pre-inline TIR,
the walk through other user modules with destination-parameter annotations (§4), the
destination table and stdlib annotations, the run-time guard (§5), the URL-parser
differential test, the diagnostics, and per-function bounds. `--compile` runs the full check; `--check` runs
the same subset policy the ceiling uses today (no false positives, documented gap).

**Phase 2: grants and audit.** Scopes inside `main`'s `Cap(...)`; hosts recorded in
`forge.caps.lock`, reported by `forge audit`, `forge cap inspect` and the embedded
capability manifest; a dependency's host list widening counts as a capability widening.

**Phase 3: roles and handles.** Per-role host grants. An opaque connection type returned
by checked connects, so handle-argument entry points can be allowed in scoped modules
(and integer fds stop being forgeable for everyone).

Phase 1 alone is honest: a scoped module is fully checked. It must not be described as
stopping a hostile dependency until phase 2, because a dependency can simply declare
`needs IO.NetConnect` unscoped.

## 8. Testing

| test | guards |
|---|---|
| `A` scoped to `example.com` connects to `example.com` → accepted | no false positives |
| `A` connects to `foo.com` literal → `cap_host_scope` | the feature's point |
| `A` connects via a parameter / config value → `cap_host_unproven` | fail closed |
| `"https://example.com" ++ p` → unproven; `"https://example.com/" ++ p` → accepted | the authority rule |
| `"https://example.com?" ++ p` → unproven | only `/` ends the authority |
| `"https://example.com@foo.com/"`, `"https://foo.com\@example.com/"` → rejected | parser-confusion literals |
| scoped HTTPS through `HttpClient.get` with only `needs IO.NetConnect("…")` → accepted | the TLS child is covered by the `tcp_connect` scope |
| scoped `A` calls `tls_connect(fd, ctx, "example.com")` → unproven | SNI name is not a destination |
| `*.example.com` admits `api.example.com`, not `example.com` | wildcard semantics |
| `example.com:8443` rejects port 443 | port scopes |
| scoped `A` calls `tcp_send_all(fd, …)` → unproven | handle route closed |
| scoped `A` calls an unannotated network stdlib function → unproven | fail closed on new APIs |
| unscoped module: every existing network fixture unchanged | backward compatibility (`scripts/ir-oracle.sh`, `scripts/types-oracle.sh`) |
| closure built in an unscoped `main`, called in scoped `A` → accepted | callbacks charged to the supplier |
| compile-time vs `Http.parse_url` over a shared corpus | the two parsers agree |
| scoped `A` calls unscoped `C.fetch(url)`, unannotated → unproven | the scope follows other modules |
| same, `C.fetch` annotated, `A` passes `"https://example.com/x"` → accepted; `"https://foo.com/x"` → `cap_host_scope` | annotations carry the destination |
| `C.fetch` annotated but rewrites its URL parameter before connecting → annotation rejected in `C` | annotations can't lie |
| redirect from `example.com` to `foo.com` under scope `example.com` → error value naming `foo.com`, no connection to `foo.com` | the run-time guard (needs a local test server) |
| same-host redirect under `no_redirects` → refused | `no_redirects` at run time |
| literal `with_redirects(c, 5)` in a `no_redirects` module → compile error | `no_redirects` at compile time |
| request step rewriting the host to `foo.com` → error value, no connection | the guard covers steps |
| unscoped client follows a cross-host redirect exactly as before | the guard costs unscoped code nothing |
| every network builtin in `builtin_cap_table` has a destination-table row | a new builtin cannot slip in unclassified |

The last row is the walk-completeness guard for this feature: a network builtin or
stdlib entry point added later without a destination row must fail a test, not pass the
check.

## 9. Decisions (owner, 2026-11-09)

- Host-level scopes, declared in `needs`: `A` gets `example.com`, `B` gets `foo.com`,
  neither reaches the other.
- Checked at compile time; a scoped module fails closed on any destination the compiler
  cannot see. Unscoped modules are unchanged.
- Both the untrusted-dependency case and the own-app separation case are in scope.
- A scope bounds everything the module reaches, through other user modules too (§4).
- Redirects and request steps get a run-time guard, and a `no_redirects` option on the
  declaration refuses redirects outright (§3, §5).

## 10. Left to the builder

Attribute spelling for destination annotations (stdlib and user); how the scope reaches
the stdlib at run time (§5); the guard's error variant names; diagnostic code names; where the boundary
check lives (extending `cap_attrib` or a sibling pass on the same pre-inline TIR); the
exact list of annotated stdlib entry points (the §4 table is the shape, not the full
list); error-message wording within §6.
