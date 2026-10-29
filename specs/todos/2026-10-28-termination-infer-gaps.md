`[P3]` Termination phase 5: metric inference — what is left

Filed 2026-10-28 by phase 5 of `specs/2026-10-26-termination-checking-design.md`
(`specs/progress/2026-10-28-termination-phase5.md`). None of these can make the checker
claim a function terminates when it may not: inference only proposes a metric that the
phase-2 obligations prove, and a proposal changes nothing until it is written. Each item
is a metric the search does not find, or a proposal it cannot write.

- **A tuple return's component carries no measure fact.** `List.chunks`' `go` does
  `let (chunk, rest) = split_at(lst, size)` and recurses on `rest`. Even with a
  `split_at` declaring `(List(a), {List(a) | len(_) < len(xs)})`, the termination
  obligation `len(rest) < len(lst)` is not proved: `push_tuple_projs` launders tuple
  components for container (element) entries, not for a measure over the component.
  (`split_at` also declares no such post today.) A single-list helper (`pop_front`)
  works; the `chunks` test uses one.
- **A local `fn`'s metric is shown, never written.** 9 of the 27 stdlib proposals are
  local loops (`List.sort_by/merge/go`, the four `make_branch/go`s, ...). Attribute
  syntax on a block `fn` would let `--refine-infer-apply` write them (shared with the
  phase-4 item in `2026-10-28-termination-diverges-gaps.md`).
- **No mixed structural-and-Int tuple.** §3.3 leaves "a mixed structural and Int tuple"
  to phase 5; the §3.5 candidate table does not list one, and none is generated. A
  cycle where one argument shrinks structurally on some calls and an `Int` falls on the
  others stays uncertified.
- **No descending bound.** `b - i` is generated for an index climbing to a bound; an
  index falling to a parameter (`i - lo` with an `i <= lo` exit) is not a candidate
  (the first-`Int`-parameter default covers only a literal 0 floor).
- **The guard search is not path-sensitive.** A comparison anywhere in the body offers
  `b - i`; the obligations decide whether it was the exit. Harmless (a wrong candidate
  fails), but it spends the budget of 8: 9 stdlib units hit the cap.
- **A byte test is opaque.** `Json.skip_ws` stops when `string_byte_at(s, i)` is not
  a space; no builtin contract says a non-negative byte means `i < string_byte_length(s)`,
  so the scanner candidate `len(s) - i` does not prove. Over a `List` reader with such
  a contract (the test assumes one) it does.
- **A String's `len` in a callee's return refinement does not meet the metric's.** With
  `@[assume] fn byte_at(s : String, i : Int) : {Int | _ < 0 || (i >= 0 && i < len(s))}`,
  `@[decreases(len(s) - i)]` on the scanner is still refuted (`e.g. len(s) = 1, i = 0,
  c = 13`); the same program over `List(Int)` proves. The post's `len(s)` and the
  termination formal's String length look like two encodings of one length. Not a
  soundness issue (a proof is lost), but it blocks a builtin byte contract from helping.
- **An inferred metric does not feed the induction hypothesis until it is written.**
  Inference is a proposal; the IH reads only phase-2 certificates of the program as
  written.
- **Proposals for a cycle whose `@[decreases]` fails are shown, not written.**
  `--refine-infer-apply` does not overwrite a metric the user wrote; the editor's
  quick fix does, one function at a time.
