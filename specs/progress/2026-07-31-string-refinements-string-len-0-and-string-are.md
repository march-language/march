- String refinements: `{String | len(_) > 0}` and `{String | _ != ""}` are
  checkable contracts. `String` is encoded as an uninterpreted SMT sort, `len`
  as an uninterpreted `Str -> Int` with a non-negativity axiom, and each
  distinct string literal in a VC as a constant with its BYTE length pinned
  (matching `string_length`, which aliases `march_string_byte_length`) and
  pairwise distinctness asserted — deliberately inside EUF + linear arithmetic,
  with no SMT string theory. `len` overload resolution keys on the value's
  DECLARED base type, never on inference, so list `len` is unchanged. Two
  encoding hazards found and fixed during the work: the SMT symbols now carry a
  `$` (illegal in a March identifier) so a program variable named `len` cannot
  collide with the `len` function declaration, and ill-sorted terms mixing a
  string with an Int are dropped — either one made z3 emit an error line, which
  desynchronised the shared long-lived `z3 -in` channel and silently disabled
  refinement checking for the REST of the compilation. Known gaps (documented):
  an `s == ""` guard establishes no length in the else-branch (no injectivity
  axiom), no prefix/suffix/contains/regex, and String return refinements are
  checked at the definition but do not propagate to call sites.
