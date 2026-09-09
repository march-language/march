# `[P2]` Compiler: let? / Result-propagation (found during Core March widening slice 8, 2026-07-10)

## Closed 2026-09-09

The dedicated production landed: `parser.mly:1312-1321` now has
`LET; QUESTION; simple_pattern; type_annot` producing the specific message
("A `let?` binding can't have a type annotation — its type is inferred from
the `Ok` payload of the `Result` on the right"), not the generic missing-`=`
recovery. Re-ran `let? x : Int = f()` through `--check` and got the specific
message. The witness `specs/lang/types/reject/t70_letq_type_annotation.march`
carries its own comment noting the dedicated production landed, and its
`.expected.json` matches live output.

- [ ] **The tutorial's dedicated "`let?` cannot have a type annotation" parser error production was never implemented — `let? x : T = e` is rejected by the GENERIC missing-`=` recovery instead.** `let-propagation.md` §5.2 shows a planned `LET; QUESTION; simple_pattern; COLON; error` production emitting "`let?` bindings cannot have a type annotation — the type is inferred from the Result:". That production is absent from `parser.mly` (only `LET QUESTION simple_pattern EQUALS expr` and `LET QUESTION simple_pattern error` exist). So `let? x : Int = e` hits the generic `error` recovery and reports `` I was expecting `=` in the let? binding here: `` — correct REJECTION, less-specific MESSAGE. Live-verified during slice 8; reject witness `types/reject/t70_letq_type_annotation` pins the actual (generic) text. Fix (optional, cosmetic): add the dedicated COLON error production for a clearer diagnostic. Tutorial reconciled (§2.10.2 + let-propagation.md implementation note both record the deviation). NOT a soundness issue.
