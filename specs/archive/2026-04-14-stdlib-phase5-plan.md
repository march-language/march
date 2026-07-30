# Stdlib hardening — Phase 5: missing high-demand APIs

**Status:** Plan + Logger in progress. Other items parked.
**Date:** 2026-04-14
**Background:** Phases 0–4 closed every blocker, security finding, and
convention drift uncovered by the adversarial review.  Phase 5 is the
parking lot for *missing* functionality — features the stdlib doesn't
yet have but which production code keeps reaching for.

## Why these and not others

Each Phase 5 item came from the original adversarial review's "Missing
high-demand APIs" section.  The shared property: **every item is
something a real-world user has had to work around outside the
stdlib.**  Trivia and nice-to-haves were filtered out in Phase 4
("polish"); Phase 5 is the gap between "stdlib hardening done" and
"stdlib actually usable for production services."

## Items

| Priority | Item | Why it matters | Sketch of API |
|----------|------|----------------|---------------|
| 1 | **Logger v2** | Today's `Logger` is `println`-with-severity.  Production deployments need structured fields, multiple sinks, per-module level filtering, and trace/span context propagation. | `LogValue` ADT + appenders + formatters + per-module levels + scoped fields + tracing helpers — see [`2026-04-14-logger-v2-design.md`](2026-04-14-logger-v2-design.md). |
| 2 | **Structured concurrency** | `Task.async`/`await`/`await_many` exist but there is no `race`, `any`, `all_settled`, or cancellation scope.  Composing async ops requires hand-rolled supervision. | `Task.race(tasks) : Result(a, ...)`, `Task.any(tasks)`, `Task.all_settled(tasks)`, `Task.with_cancel_scope(thunk)`. |
| 3 | **`Test.assert_eq` (generic)** | `assert_eq_int` / `assert_eq_str` / `assert_eq_bool` exist; users keep writing the missing one for tuples, records, custom types.  Small change, big QoL win. | `Test.assert_eq(expected, actual)` using structural equality + auto `to_string` on failure. |
| 4 | **UUID v7** | Timestamp-ordered UUIDs are the modern default for DB primary keys (better B-tree locality than v4).  Needs new runtime builtin. | `UUID.v7() : UUID`, `UUID.v7_at(unix_ms : Int) : UUID`. |
| 5 | **DateTime timezones** | `DateTime` is UTC-only.  Timezone-aware code falls outside the stdlib. | `LocalDateTime`, `Tz` ADT, `to_utc`/`from_utc`, IANA identifiers (probably load tzdata at runtime; embedding is too heavy). |
| 6 | **Streams (`Seq.from_*`)** | `Seq` is a church-encoded fold; no source constructors, no back-pressure, no stream-of-streams composition. | `Seq.from_file`, `Seq.from_http`, `Seq.from_channel`, `Seq.batched`, plus a back-pressure sketch. |
| 7 | **Stats.quantile / iqr** | `percentile(xs, p)` exists with a single hard-coded interpolation method.  Real statisticians want the standard 9 methods (R/Python convention). | `Stats.quantile(xs, q, method)`, `Stats.iqr(xs)`, `Stats.QuantileMethod` ADT. |
| 8 | **Random non-uniform** | `Random.int`/`float`/`bool` only.  Property tests and simulations want normal, exponential, etc. | `Random.normal(rng, mu, sigma)`, `Random.exponential(rng, lambda)`, `Random.choice_weighted(rng, items_with_weights)`. |

Open side tasks (already spawned, unrelated to Phase 5):
- `BigInt.compare` stack-overflow on trivial inputs (pre-existing bug).
- `channel_socket` pid-ownership design clarification.

## Recommended order

1. **Logger v2** — most user-visible gap; blocks production deployments.
2. **Structured concurrency** — second-most-requested; affects every async-using app.
3. **`Test.assert_eq`** — small change; fits in a single PR; can land alongside any other work.
4. **UUID v7** — small new builtin + ~50 lines of March; pair with the BigInt.compare fix as a "small fixes" PR.
5. **DateTime timezones** — large; pick IANA-loading vs static map first.
6. **Streams** — depends on `Seq` redesign.
7. **Stats.quantile / Random distributions** — independent; can land any time.

Each item should land as its own PR with its own design note (this
file is the umbrella; per-item docs live alongside).

## Out of scope

- Anything that requires a new compiler feature (effects, capabilities).
- Anything that would change the runtime ABI (stays for a v0.2 spec).
- Bastion-related work (lives in the Bastion repo since Phase 0).
