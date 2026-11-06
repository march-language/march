`[done]` Refinement reflection: functions over Float, String, records and tuples reflect.

Closes the "Float and String" and "Records and tuples" items of
`specs/todos/2026-10-31-reflection-encoder-gaps.md` (design
`specs/2026-10-29-refinement-reflection-design.md` §2.3, §3.2, D9). Each was a decline in the
body translator: the analysis already admitted these functions, but no logic symbol was built.

- **Float (D9).** `Float` is the checker's `Float64` sort; every Float operation in a body
  (`+. -. *. /.`, negation, `<` and friends at Float) is an opaque, total symbol
  (`|r:float:fadd|` …, `Reflect_state.float_ops`), and `==` at Float stays the opaque program
  equality. Nothing about NaN or signed zero is ever concluded. The float well-sortedness gate
  (`Refine_encode.float_term`, `mentions_float`) accepts a reflected call's Float result and a
  float argument at a Float parameter.
- **String (D9).** `String` is the opaque `$Str` with `$strlen`; `string_byte_length` is
  `$strlen`. A body literal is the nullary symbol `|r:str:<md5>|` (`Reflect_state.str_lit_sym`),
  one per content; stage 2 (`Refine_reflect.unfold`) states each literal's byte length and that
  literals of different content differ, and a predicate's own literal constant (`$strN`, in
  `Refine_call` and `Refine_post`) is equated with it. `query_instance_preamble` adds the
  string preamble when a reflected symbol needs `$Str`; `mentions_str`/`wellsorted` accept a
  reflected call's String result; `len` of one is `$strlen`.
- **Records.** The declared record sort: `p.x` is its selector, a literal and `{ p with … }`
  its constructor, a `{ x, y }` pattern its selectors. The typechecker's records are
  structural, so `Refine_reflect.record_of_fields` maps one to the single registered,
  monomorphic, unconflated record with exactly its field names and field sorts, else declines.
- **Tuples.** One datatype per arity, `$Tup<n>` with constructor `$tup<n>`
  (`Refine_encode.tuple_adt`), registered on first use. `(a, b)` constructs, a tuple pattern
  takes apart.
- **Destructuring `let`.** A `let` whose pattern only binds (tuple or record) translates; one
  that tests anything declines.
- **Predicates.** A tuple or record literal at a reflected call's tuple or record parameter is
  that constructor (`Refine_scope`'s reflected-call arm).

- **Parity net.** `Reflect_parity` draws record inputs and hands tuples and records to the
  interpreter as tuples and records (`to_value`), and reads a tuple or record result back
  (`same`); a new `reflect-parity` case pins `agree` for six tuple and record functions. Two
  existing cases used a Float function as "no logic definition"; one now uses a parametric
  record, which still declines.

- **A shadowed stdlib alias is not reflected.** Making String functions reflectable made the
  stdlib's `String.byte_size` reflected; a program whose entry module is `String` and defines
  its own `byte_size` (accept/t127) then got a false violation, because the termination graph
  resolved its `String.byte_size(t)` to the stdlib unit. When the encoder's alias gate has
  withdrawn the spelling (`string_byte_size_is_stdlib`, `list_length_is_stdlib`,
  `array_length_is_stdlib`), the stdlib unit is blocked (R6), so no such call gains a
  definition.

Tests: `float_body`, `string_body`, `record_body`, `tuple_body` in `test/test_refine_lemma.ml`,
each with a red case (an opaque Float comparison and IEEE `==`, a false string literal claim, an
update that drops a field, a false tuple claim).

Left open in the todo: a tuple- or record-typed variable in a predicate, parametric records,
and how a tuple or record literal is printed in a report.
