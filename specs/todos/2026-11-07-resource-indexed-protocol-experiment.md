`[P4]` Evaluate arithmetic-indexed protocols on bounded outstanding work.

Adjacent experiment after `2026-11-06-session-theory-loops-crash` establishes the needed semantic
fragment. [Rast, LMCS 2022](https://arxiv.org/abs/2012.13129) combines arithmetic refinements,
sessions and resource accounting. Borrow its small arithmetic index discipline; do not import
full dependent types, its whole cost model or its guarantees into March by analogy.

## Scope

Build a crash-free looping worker/client protocol indexed by available credits and outstanding
requests. Sending an accepted request consumes one credit; its correlated completion restores
one. Prove credits >= 0, outstanding >= 0, and credits + outstanding == capacity. Account for
in-flight requests and replies; a local mailbox length is not the outstanding count.

Keep index constraints in linear integer arithmetic initially. Specify whether indices are
explicit or reconstructed and preserve existing HM inference for ordinary code. A protocol
index does not establish wall-clock latency, bounded whole-process memory or eventual service.

## Failure boundary

Start with reliable delivery and no cancellation or restart. Extend only with a stated policy:
late or duplicate replies cannot mint credits; timeouts alone cannot prove work stopped; a new
worker epoch must not reuse outstanding credits unsafely. Crash branches require their own
conservation rules. Do not equate an ordinary send attempt with accepted work.

## Done when

The conservation theorem holds in the supported protocol model, the report states its assumptions,
and runtime traces check the same observable transitions. Negative controls: double acknowledgment,
credit reuse after timeout and a lost credit on an error branch. Compare required annotations and
runtime cost with an ordinary linear-token API. Decide whether a new language feature is warranted;
if the library API suffices, record that result instead.
