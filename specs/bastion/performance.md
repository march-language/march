# Bastion: Performance

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Design Decisions for Performance

| Decision | Performance Impact |
|---|---|
| Compiled templates (IO lists) | Sub-millisecond render times, zero runtime parsing |
| Pattern-matched routing | Compiler-optimized dispatch, O(path depth) lookup |
| One process per connection | Minimal memory overhead, proven at scale |
| WASM islands (not full SPA) | Smaller client bundles, faster initial page load |
| Native static file serving | No proxy overhead in simple deployments |
| Typed middleware pipeline | Zero runtime type checks, all verified at compile |
| Vault (in-memory store) | Lock-free reads, per-key write locking, no external dependencies |
| Fragment caching | Avoid re-rendering expensive template partials |
| ETag + 304 responses | Save bandwidth and render time for unchanged content |

---

## Benchmarking Targets

Bastion should aim to compete with high-performance frameworks:

- **JSON serialization**: Target top-10 in TechEmpower benchmarks
- **Template rendering**: Sub-millisecond for typical pages (comparable to compiled Rust templates)
- **Routing dispatch**: Sub-microsecond for typical route sets
- **WebSocket throughput**: Handle 100K+ concurrent connections per node
- **WASM island size**: < 50KB per island (after compression) for typical components
- **Time to first byte**: < 5ms for cached/simple responses

---

## Scalability Model

- **Vertical**: March's green threads on OCaml 5.3.0 multicore efficiently use all CPU cores
- **Horizontal**: Stateless request handling means standard load balancer distribution works; Channel state can be distributed via PubSub backed by Redis or a distributed March cluster

---

## Template Rendering

Templates compile to IO lists — efficient lists of binary fragments that are concatenated once when serializing to the network. At runtime, rendering a template is just calling a function that returns an IO list — no parsing, no interpretation.

```
~H"""...""" sigil
    │
    ▼
March AST (IO list construction: ["<div class=\"card\">", user.name, "</div>"])
    │
    ▼
Compiled March Function (efficient binary/string concatenation)
```

---

## Route Dispatch

The March compiler can optimize pattern-matched routes into an efficient dispatch table at compile time. Since all routes are known statically (function heads), the compiler can:

1. Build a trie of path segments for O(n) lookup where n is the path depth
2. Warn on overlapping or unreachable routes at compile time
3. Generate optimized binary pattern matching for path segments

---

## WASM Island Size

Each island is compiled to a separate `.wasm` bundle. The target is < 50KB compressed for typical interactive components. Island bundles are content-hash named and cached aggressively by the browser — users only download a bundle once per version.

---

## Open Questions

- **OpenTelemetry overhead**: What's the performance impact of tracing in production? Should spans be sampled by default?
- **Embedded asset size limits**: For `--embed-assets`, how large can embedded static assets be before they degrade binary startup time?

See [open-questions.md](open-questions.md) for details.
