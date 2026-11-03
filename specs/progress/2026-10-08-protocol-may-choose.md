# Protocol expand builds expose choice availability

Each generated chooser module now provides a nullary
`may_choose_<label>() : Bool` alongside its `choose_<label>` transition.
It is false only when `--protocol-expand` holds that label; other labels
remain true. This constant query neither consumes the state nor weakens the
existing panic if code attempts a held choice anyway.

The deploy-plan split text names the generated guard, and the topology and
choreography docs recommend it instead of comparing role fingerprints.
This closes the expand-build availability-predicate TODO.

Validation: five focused endpoint tests pass, including plain/expand
availability, unchanged existing labels, and typechecking a predicate call.
The Forge protocol deploy-plan tests pin the guard's rendered name.

CI follow-up: the shared exact generated-function list now includes
`may_choose_more` and `may_choose_done`; the existing labelled and unlabelled
shape tests pin these additions alongside their corresponding transitions.
