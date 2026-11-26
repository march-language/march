`[P3]` Inlay hints for inferred capture sets (2026-11-24)

Capture inference (ocap phase 8a, `specs/progress/2026-11-24-ocap-p8a-capture-sets.md`)
shows a value's set on hover and in `march --dump-captures`. The design
(`specs/2026-11-11-ocap-capture-checking-design.md` §12) also allows inlay hints on `let`
bindings. Not built: `Analysis.inlay_hints_for` (`lsp/lib/analysis.ml`) would read
`Capture.result.binders`, which already lists every binding that holds a set with its
printed type. The capture result is lazy per analysis, and inlay hints are requested on every
edit, so this wants the pass's cost on the open file measured first
(`scripts/capture-cost.sh`).
