`[P4]` Evaluate local constraint elimination and invariant synthesis against existing inference.

Research experiment supporting `2026-11-06-verification-ladder-roadmap`, not a commitment to
replace March's current inference, reflection or z3 backend.

## Research and hypothesis

[Local Refinement Typing, ICFP 2017](https://arxiv.org/abs/1706.08007) uses Fusion to eliminate
local refinement unknowns, with signatures at exported and cyclic boundaries. The hypothesis is
that eliminating acyclic intermediate constraints could avoid repeated candidate rechecks in
March. The paper's precision results are relative to its logic and typing system, not a promise
that arbitrary March contracts can be inferred.

[Horn Clause Solvers for Program Verification, 2015](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/nbjorner-yurifest.pdf)
and [ICE, CAV 2014](https://pranav-garg.com/papers/cav14.pdf) suggest a separate experiment for
recursive summaries: a candidate must include initial states, exclude bad states and be closed
under transitions. Passing examples alone cannot establish that closure.

## Bounded experiment

1. Freeze a baseline on current inference using higher-order pipelines, private helpers,
   joint parameter/return relations and recursive SCCs. Record proved/skipped obligations,
   public annotations, candidate probes, module rechecks, elapsed time and solver resource use.
2. Prototype local elimination only for an explicitly supported acyclic pure fragment. Keep
   public signatures fixed; annotated recursive boundaries remain cut points. Measure formula
   growth as well as solve cost; apply a size budget with fallback to existing inference.
3. Independently try constrained Horn clauses or ICE-style candidates for a small arithmetic
   recursive function and actor counter invariant. Use positive, negative and implication
   constraints; recheck any returned candidate's initialization, preservation and safety in
   March's ordinary checker. A synthesized summary or solver answer is not automatically trusted.
4. Candidate contracts must respect caller obligations: strengthening a precondition does not
   prove the original function correct for all its previous inputs. Never rewrite a public API
   silently or use the target theorem as its own assumption.

## Done when

Publish a reproducible comparison and go/no-go decision for each prototype. A useful outcome
may be to retain current inference. Include a false candidate fitting all sampled executions,
unsupported higher-order input, formula-budget exhaustion and a recursive case requiring an
annotation. No regression of default checking or claim of general invariant inference.
