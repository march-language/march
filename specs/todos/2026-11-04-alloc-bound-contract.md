`[P3]` Allocation bounds: `@[alloc_bound(N)]` and `@[alloc_bound(per_call: N)]`

Design: `specs/2026-11-04-alloc-bound-design.md`.

Extend the `@[no_alloc]` contract (`lib/tir/alloc_contract.ml`) from a yes/no
verdict to a count checked on the final TIR. `@[alloc_bound(N)]` means at most N
heap allocations per call, transitively, with no recursion below the function.
`@[alloc_bound(per_call: N)]` means at most N per activation of a recursive
function. Both forms take `warn` and `assume`. Reused and stack-promoted cells
are not counted. The bound counts allocation events, not bytes.

Planned as four PRs:

1. `named_builtin_allocates : … -> bool` becomes a total
   `named_builtin_cost : … -> Zero | Fixed n | Unbounded`, audited against
   `runtime/*.c`, with no change to `@[no_alloc]` verdicts.
2. The constant form: parser, SCC pass, worst-path witness, the `alloc_bound`
   error code, the golden corpus, `--report-contracts` output, and a runtime
   count-parity test using `--rc-trace` allocation events.
3. The `per_call` form, the tree-sitter update, and docs.
4. LSP lens and quick fix, plus `forge fix --contracts` under an opt-in glob.

Estimate: 2.5–3.5 weeks. Symbolic bounds (`@[alloc_bound(3 * len(xs))]`, proved
by the refinement checker) are phase 2, sketched in the design but not yet
designed. Decide on them after `--report-contracts` shows how many stdlib parser
functions `per_call` bounds but can't fully state.

Motivation: the 2026-07-27/28 parser allocation-rate rewrites (json, toml,
yaml, xml, uri, regex in `specs/progress/`) have nothing pinning them; a checked
bound would.
