`[P2]` A record whose only refinements are element slots is never obliged

Found 2026-10-18 while designing the element-flow follow-ups
(`specs/2026-10-18-element-flow-followups-design.md` §0.5, probes `p4v`/`p4w`),
re-confirmed after its phase 0 landed. A record type whose fields carry element
refinements but no SCALAR refinement (`type Box = { n : Int, xs : List({Int | _ >
0}) }`) files **zero** obligations at a construction: `{ n: 10, xs: [0 - 5] }`
type-checks, `--refine-report` counts nothing (not even a skip), and `cap verified`
compiles it. Give one field a scalar refinement (`n : {Int | _ > 0}`) and the same
`[0 - 5]` is a violation, so the element check itself works; the record is just
never registered. `collect_ctor_sigs` (`lib/refinecheck/refine_scope.ml`) only
registers a record whose fields have a scalar refinement and has no counterpart
of `has_elem_param` (which covers functions only). Fix direction: register a
record (and a variant constructor) whose fields carry any element refinement, so
`check_field_elements` runs; it already turns a slot naming another field into a
recorded skip.

```march
mod P4v do
  type Box = { n : Int, xs : List({Int | _ > 0}) }
  fn go() : Box do
    { n: 10, xs: [0 - 5] }     -- 0 obligations today; should be violated
  end
end
```
