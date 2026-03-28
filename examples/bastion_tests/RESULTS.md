# Bastion Framework — Adversarial Test Results

## Summary

| File | Tests | Result |
|------|-------|--------|
| `test_routing.march` | 42 | ✅ All pass |
| `test_caching.march` | 37 | ✅ All pass |
| `test_sessions_adversarial.march` | 35 | ✅ All pass |
| `test_csrf_adversarial.march` | 44 | ✅ All pass |
| `test_dashboard.march` | 64 | ✅ All pass |
| `test_html_adversarial.march` | 54 | ✅ All pass |
| `test_islands.march` | 70 | ✅ All pass |
| **Total** | **346** | **✅ 346/346** |

Existing stdlib tests (`test/stdlib/`) were also verified — no regressions:
- `test_csrf.march`: 49/49
- `test_session.march`: 49/49
- `test_html.march`: 52/52
- `test_bastion_dev.march`: 76/76

---

## Bugs Found and Fixed

### Bug 1: `Islands.wrap_with_css` had two definitions; the first used weak CSS escaping

**File:** `stdlib/islands.march`

**Problem:** The function `wrap_with_css` (and `wrap_eager_with_css`) were defined twice. The first definition used a private helper `escape_css_attr` that only escaped double quotes. The second definition used `escape_attr_value` which correctly escapes `&`, `"`, `<`, and `>`. In March, the second definition shadows the first, so the stronger version was active — but the dead first definition and its helper `escape_css_attr` caused confusion and bloat.

**Fix:** Removed the first (weak) definitions of `wrap_with_css`, `wrap_eager_with_css`, and the now-unused `escape_css_attr` private function. The remaining second definitions use `escape_attr_value`, which handles all four HTML special characters correctly.

### Bug 2: Test assertions too strict for XSS-neutralisation checks

**File:** `examples/bastion_tests/test_html_adversarial.march`

**Problem:** Two tests asserted that the injected event-handler keyword (`onmouseover`, `onclick`) was completely absent from the output. After HTML-escaping double quotes, the keyword still appears as literal text inside the escaped attribute value — which is safe but not absent.

- `"XSS via event handler in attribute value"`: `assert (!String.contains(result, "onmouseover"))` — wrong; text appears escaped.
- `"attribute injection via quote in value"`: `assert (!String.contains(s, "onclick"))` — same issue.

**Fix:** Changed assertions to verify that (a) double quotes are escaped (`&quot;` is present) and (b) the raw unescaped injection sequence (`" onmouseover=` / `" onclick=`) is absent. These are the semantically correct security checks.

### Bug 3: Lambda arity mismatch in `Bastion.Cache.fragment` tests

**File:** `examples/bastion_tests/test_caching.march`

**Problem:** `Bastion.Cache.fragment` calls its generator with 0 arguments. Test lambdas were written as `fn _ -> expr` (1-arg wildcard), causing "arity mismatch: expected 1 args, got 0" for 3 fragment tests.

**Fix:** Changed all fragment generator lambdas from `fn _ ->` to `fn () ->` (zero-arg lambda syntax).

### Bug 4: `pfn` defined inside `describe` blocks caused parse errors

**Files:** `examples/bastion_tests/test_routing.march`, `examples/bastion_tests/test_csrf_adversarial.march`

**Problem:** March does not allow `pfn` (private function) declarations inside `describe` blocks. Two files had helper `pfn`s scoped inside describe blocks.

**Fix:** Moved all `pfn` helpers to module top-level scope.

### Bug 5: `Option(String)` equality inside lambdas

**File:** `examples/bastion_tests/test_routing.march`

**Problem:** Inside pipeline plug lambdas, comparing `HttpServer.get_assign(conn, "key") == Some("value")` triggered a type error: `Option(String)` does not implement `Eq` in that context.

**Fix:** Replaced with explicit `match ... do Some(v) -> assert (v == "x") None -> assert false end` pattern matching.

### Bug 6: `state` is a reserved keyword

**File:** `examples/bastion_tests/test_islands.march`

**Problem:** Used `let state = ...` as a local variable name, but `state` is a reserved keyword in the March lexer.

**Fix:** Renamed all local `state` variables to `json_st`.

### Bug 7: Type constructors used with module qualifier

**File:** `examples/bastion_tests/test_islands.march`

**Problem:** Used `Islands.Eager`, `Islands.Lazy`, `Islands.Descriptor`, etc. — March type constructors are not qualified by module name when used outside their defining module.

**Fix:** Replaced with unqualified `Eager`, `Lazy`, `OnIdle`, `OnInteraction`, `Descriptor`.

---

## Areas Tested

### 1. Request → Router → Response path (`test_routing.march`, 42 tests)
- `run_pipeline` with empty/single/multi-plug pipelines
- Halt semantics: halted conn skips remaining plugs; `halt()` vs `send_resp`
- Method dispatch: GET/POST matching and mismatches
- 404 fallback for unknown paths
- Path parameter extraction (single and nested params)
- Response helpers: `text`, `json`, `html`, `redirect`, `send_resp`, `put_resp_header`
- `Bastion.Depot.with_pool` assigns pool under `"db"` key
- Request header access (case-insensitive `get_req_header`)
- `path_info` parsing from URL segments

### 2. Caching (`test_caching.march`, 37 tests)
- ETag generation: header present, wrapped in quotes, deterministic, different bodies → different ETags, empty body
- Conditional requests: 304 on `If-None-Match` match, full response on mismatch
- `Bastion.Cache.cached`: miss/hit semantics, status code preserved, key independence, TTL=0 persistence
- `Bastion.Cache.fragment`: miss/hit semantics, key independence, empty fragment cached
- `Bastion.Cache.invalidate`: removes response entries, removes fragment entries, no-op for missing key/table
- `Bastion.Cache.invalidate_prefix`: removes all matching-prefix entries, leaves other tables unaffected
- `cache_control`, `no_cache`, `public_cache` helpers: correct header values, no body/status side-effects

### 3. Sessions (`test_sessions_adversarial.march`, 35 tests)
- Edge case values: empty string, values with `=`/semicolons/unicode/spaces
- Overwrite semantics (last `put` wins)
- 20-key sessions (large session capacity)
- Flash: `put_flash`/`get_flash` round-trip, double `put_flash`, read twice (None second time)
- Flash-vs-regular key collision (they're stored separately)
- Vault backend: overwrite, nonexistent SID returns empty session, `clear` empties all keys
- Multi-cookie header parsing
- Unknown backend (non-vault, non-cookie) falls back gracefully

### 4. CSRF protection (`test_csrf_adversarial.march`, 44 tests)
- Body parsing: leading/trailing `&`, consecutive `&&`, many fields before/after token
- Token case sensitivity (wrong case fails)
- Special characters in tokens: `+`, `/`, `=` (base64 alphabet)
- Multiple `_csrf_token` fields: first wins; injection attempt via appended token
- Empty token handling; empty body with session token → 403
- All mutating methods (PUT/PATCH/DELETE) checked
- JSON content-type exemption (`application/json`, with charset, PUT, DELETE); non-JSON not exempt
- `skip` + `protect` interaction; `skip` idempotency
- Pipeline integration: `ensure_token` → `protect` → handler

### 5. Dev dashboard (`test_dashboard.march`, 64 tests)
- `request_timer`/`finish_timer`/`server_timing` header injection
- `conn_inspector`: returns conn unchanged, logs to INFO
- `live_reload_script`: generates EventSource JS, correct SSE endpoint
- `inject_live_reload`: injects before `</body>`, passes through non-HTML/unhalted, appends if no `</body>`
- `live_reload_handler`: 200 + SSE headers on `/_bastion/live_reload`, pass-through otherwise
- `error_overlay_html`: contains error message, stack trace, 500 badge, DOCTYPE, XSS-escaped
- `error_overlay` middleware: 500 status, halted, text/html content-type
- Dashboard HTML structure: sections present, XSS escaped
- `inc_ws`/`dec_ws` WebSocket counter increments/decrements

### 6. HTML templates (`test_html_adversarial.march`, 54 tests)
- XSS vectors: `<script>`, `onerror`, `onmouseover`, SVG, HTML comments, IMG tags
- HTML null byte passthrough (no panic)
- Double-escaping prevention: `&` escaped once; re-escaping produces `&amp;amp;`
- `~H` sigil: string interpolation auto-escapes; `IOList`/`Html.Safe` not double-escaped
- `Html.tag`: attribute value escaping for `>`, `<`, `&`, and `"` injection
- `Html.layout`: title XSS escaped; body IOList not escaped; valid DOCTYPE output
- `Html.list`/`render_collection`: XSS in list items escaped
- `Html.content_hash`: deterministic, unique, 16 hex chars, order-sensitive

### 7. Islands (`test_islands.march`, 70 tests)
- `hydrate_attr` for all four strategies (`eager`/`lazy`/`idle`/`interaction`)
- `wrap` output structure: all four data attributes present, inner HTML embedded, div wrapper
- State JSON escaping: single quotes → `&#39;`; double quotes pass through (inside single-quoted attr)
- Backslash, empty JSON, complex nested JSON in state
- Island name variants: simple, hyphenated, underscore, empty
- `wrap_with_css`: CSS attribute present, double-quote/ampersand/`<`/`>` escaping
- `wrap_eager` matches `wrap(_, Eager, _, _)`; `wrap_eager_with_css` matches `wrap_with_css(_, Eager, ...)`
- `client_only`: no inner HTML, correct data attributes
- `bootstrap_script`: type=module tag, correct src path, custom base URL
- `preload_hint`: rel=modulepreload, correct href with .wasm extension
- `Registry`: empty, register, find by name, case-sensitive lookup, multi-island, preload hints
- `Descriptor` accessors: name, hydrate strategy, wasm_path
- Integration: island HTML embeds in `Html.tag`; island in `Html.layout` with bootstrap script

---

## Known Limitations / Not Tested

- **TTL expiry**: `Bastion.Cache` TTL values >0 (time-based expiry) are not tested because the test runner has no time-advancement mechanism.
- **Cookie signing in sessions**: The `BastionSession.CookieBackend` signs cookies in production; the test uses the Vault backend exclusively.
- **CSRF `generate_token`**: Token generation (random bytes) is not adversarially tested; only validation/protection flow.
- **HTTP/2 and WebSocket upgrade paths**: Not exercised.
- **Island WASM compilation (Tier 4)**: Not yet implemented in the compiler; `Islands.Interface` and WASM exports are documented but not executable.
