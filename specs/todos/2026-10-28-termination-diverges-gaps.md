`[P3]` Termination phase 4: `@[diverges]`, handlers, `cap total` — what is left

Filed 2026-10-28 by phase 4 of `specs/2026-10-26-termination-checking-design.md`
(`specs/progress/2026-10-27-termination-phase4.md`). None of these can make the checker
claim a function terminates when it may not; each is a missing report, a missing
annotation, or a `cap total` error that could be avoided.

- **Class I is not swept.** The design's §7 lists `Random.next_float_open` and `Seq`
  under "no metric, `@[diverges]` or a fix". Phase 4 swept class E only (external-event
  loops). Rejection sampling terminates with probability 1 but not provably; decide per
  function, with the class's own ratchet if one is wanted.
- **`Control.await_state` loops for ever when `poll_ms <= 0`.** `left_ms - poll_ms` with
  a `left_ms <= 0` exit ends only for a positive `poll_ms`; nothing says so. It is on the
  ratchet's allow list as a time-bounded poll. A `poll_ms : {Int | _ > 0}` precondition
  plus a runtime guard (the D5 pattern) would end it, and would let the metric `left_ms`
  prove. A behaviour change, so its own PR.
- **A local `fn` takes no attribute.** Four stdlib event loops are local functions
  (`File.with_lines/do_lines`, `File.with_chunks/do_chunks`, `Seq.from_file_lines/do_lines`,
  `Seq.from_file_chunks/do_chunks`). Their enclosing functions terminate (they hand a lazy
  `Seq` on), so marking those would be false; the four are on the allow list instead.
  Attribute syntax on a block `fn` (`ELetFn`) would close it; it is a parser and AST
  change (tree-sitter rule, types-oracle).
- **The event-builtin list is hand-written.** `Refine_term.event_builtins` names the
  builtins whose result depends on an external event. A new blocking builtin must be
  added there, or a loop on it is classed `?`, not `E?`, and the ratchet misses it. The
  builtin table could carry the flag instead.
- **Deadline loops are judged terminating.** A loop that ends when the clock passes a
  deadline (`spin_until(deadline_ms)`, `Topology.watchdog`) is on the allow list, not
  marked. That rests on the clock advancing; nothing proves it. A "bounded by the clock"
  certificate (a metric over `unix_time_ms()`) would need a monotonicity axiom.
- **The editor sees `termination_unproved` only as a context diagnostic.** The LSP does
  not run the refinement checker, so it never publishes the diagnostic itself; the three
  repairs are offered when the client passes a `march --check-json` diagnostic back in a
  code-action request. Running the termination pass (it needs z3 for metrics) in the LSP
  is a separate design.
- **`cap total` cannot exempt a handler.** A handler takes no attribute, so a handler
  that blocks on purpose is always an error under `cap total`; move the blocking call out
  of the cap's module.
- **`cap total` trusts interface dispatch picked by a value.** (Since the final review,
  a dispatch on a known type, `show(Box(n))` or `"${Box(n)}"`, carries its `impl`'s
  divergence like any call.) A call through a dictionary (`show(x)` on a
  type variable) does not carry an `impl`'s divergence to the caller; the `impl` is
  judged as its own unit, and only when it is in a `cap total` module. An `impl` outside
  one that diverges (the prelude's `Show(List(a))` cycle is uncertified today: the
  structural certificate does not follow element-wise recursion through `map`) is not
  flagged at the call. The induction hypothesis keeps phase 3's stricter rule.
- **Witness runs are not skipped for "may diverge" units** (§6's optional saving).
- **The "add `@[decreases(e)]`" action is a frame.** `Refine_term.suggest_metric` infers
  nothing until phase 5; the LSP reads the compiler's `note: try `@[decreases(e)]`.`.
- **A stdlib module's bare name can resolve to an entry file's top-level function.**
  The graph resolves a bare name lexically, out to the top level, and an entry file's
  top-level declarations sit at that top level. So `List`'s `impl Show.show`, calling
  `show(h)` on an element, gets an edge to a user's top-level `fn show` (measured in the
  final review: `test/native/set_ops_shared_comparator.march`'s `fn show(s : Set(Int))`
  calls `to_string(Set.to_list(s))`, which reaches `List`'s `impl Show`, so `show` is
  now a recursive unit, `cert=unproved:no-int-parameter`; at run time there is no such
  cycle). Fail-closed (a certificate lost, never one gained); resolving the prepended
  stdlib's names without the entry file's top level would close it.
- **Dispatching builtins the interpreter probe cannot reach.** `test_refine_term.ml`'s
  "dispatching builtins" case calls every interpreter builtin with a probe value, so a
  builtin that dispatches only on a value of another shape (`own` takes a `Pid` first,
  `from_json` decodes a Json value) is listed by hand in `Refine_term.runtime_dispatch`
  and not checked by it. An actor's `inspect` answer runs `Show` on its state fields in
  the actor, not in the caller, and is not modelled (as no cross-actor call is).
