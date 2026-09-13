# `[P2]` Linearity does not survive generic code or containers

Filed 2026-09-13 from the probe sweep in
`specs/plans/2026-09-13-linearity-holes-plan.md` (step 8). **Decided
2026-09-13: Option B**: type variables are unrestricted by default, and a
generic function must opt in to accepting a linear type. Step 0's
measurement still runs first, as the size estimate for the stdlib
annotation work, not as a vote between options.

## The hole

Linearity is a property of a **binding whose own type is linear**: a `TLin`
wrapper, or a `TCon` that `resolves_always_linear`. Two things fall outside
that definition, and a linear value passes through both unchecked.

**Type variables.** A polymorphic function can duplicate or drop a value of
its type parameter, and nothing stops that parameter being instantiated with
a linear type:

```march
fn dup(x) do (x, x) end
fn drop_it(x) : Int do 0 end
...
let (a, b) = dup(S1(1))        -- accepted; one S1 is now two
println(int_to_string(sink(a) + sink(b) + drop_it(S1(2))))   -- accepted; S1(2) leaks
```

**Containers.** A tuple, list, or ADT holding a linear value isn't itself
linear, so the container can be used freely:

```march
let s = S1(1)
let p = (s, 1)
let (a, _) = p
let (b, _) = p                 -- accepted; a and b are the same S1
println(int_to_string(sink(a) + sink(b)))
```

## Measured (main `8eb0d7ee`)

| shape | result |
|---|---|
| `fn dup(x) do (x, x) end`, `dup(S1(1))` destructured and both consumed | **accepted** |
| `fn dup2(x : a) : (a, a)`, same | **accepted** |
| `fn drop_it(x) : Int do 0 end`, `drop_it(s)` | **accepted** |
| `let f = fn st -> print_line("…")`, `f(S1(1))` | **accepted** |
| `let xs = [s]`, `List.length(xs) + List.length(xs)` | **accepted** |
| `let p = (s, 1)`, destructured twice, both halves consumed | **accepted** |
| `let xs = [s, s]` | rejected (correct: `s` itself is used twice) |

The record case, one level deep, is handled separately by sentinels in
[[2026-09-10-linear-actor-state-field-retained-after-consume]]. This item is
everything that approach can't reach: nesting, tuples, lists, ADT payloads,
and polymorphism.

## Why no scope-local fix works

`dup`'s body is checked once, with `x : a`. `a` is a type variable, nothing
about `x` is linear there, and the scheme is generalised as `a -> (a, a)`.
The linear type only appears at a **call site**, in a different function,
after `dup` has been checked and generalised. So the check has to live in
the relation between a scheme and its instantiation, not in any body.

## Options for type variables

**A. Inferred usage summaries.** When generalising, compute for each
quantified variable how many times a value of that type can be used on each
path (0, 1, or many), and store it with the scheme. At instantiation, a
variable used anything but exactly once must not be instantiated with a
linear type. No annotations. But the summary has to see through recursion,
higher-order parameters (`List.map`'s `f`), and data structures. That is
linearity inference, a research-sized design with its own soundness
questions.

**B. Linear-kinded type variables (chosen).** Type variables are
**unrestricted by default**: instantiating one with a linear type is an
error. A function opts in by marking the variable linear. The spelling is
part of the design: `fn id(linear x : a) : a` already parses (a
per-parameter qualifier), while a per-variable form (`linear a` on the
quantifier) would say it once for every use of `a`. The parameter is then
tracked linear in the body, which the existing machinery already enforces. Data constructors are linear-safe by
construction (each argument is stored exactly once), so `Some`, `Ok`,
tuples, and user ADT constructors are exempt. `Option(S1)` and
`Result(Handle, E)` keep working.

Pros: local, explicit, sound, and it matches how `always_linear` is already
a declared property rather than an inferred one. Cons: every generic
function that should accept linear values has to be annotated, stdlib
included. Until it is, `List.map(handles, close)` is rejected.

**C. First-order spot check.** At an instantiation that puts a linear type
into a variable, count the callee's uses of its parameters of that
variable's type, syntactically, and reject a callee that drops or
duplicates one. Cheap, catches `dup` and `drop_it`, and misses anything
higher-order or recursive. A lint, not a guarantee.

## Options for containers

**Containment rule.** A type is linear if a linear type occurs in an
**owning** position: a tuple component, a record field, an ADT payload, a
`List` element. A binding of such a type is tracked linear, exactly like an
`always_linear` one (`auto_lin` and `bind_pattern_bindings` gain a
`contains_linear ty env` check).

This is sound, and on its own it's close to unusable. `List.length(xs)` then
consumes `xs`, and with option B, `List.length : List(a) -> Int` can't even
be instantiated with `S1`, because it drops the elements. Collections of
linear values need **consuming** operations (`List.consume_each(xs, close)`)
and eventually **borrowing** reads, and March has neither. That is honest,
though: today those programs compile and are wrong.

## Recommendation

1. **Step 0, buildable now: measure.** A **warning**, not an error: "`S1`
   is linear, but `dup`'s type parameter `a` is not; `dup` may drop or
   duplicate it." Emit it wherever an instantiation (in `instantiate`, at a
   non-constructor scheme) binds a quantified variable to a type that is or
   contains a linear type. Run it over the corpus, stdlib, the session
   goldens, and `~/code/bastion_todos`, and count. That count decides
   between B and C, and says how much of stdlib would need annotating.
2. **Then B**, with the constructor exemption and a chosen opt-in spelling,
   using step 0's warning as its error.
3. **Containment after B**, since without B a container rule is trivially
   bypassed by passing the container to a generic function.

## Out of scope

- Borrowing / shared references. They are the real ergonomic answer to
  "read a linear collection", and a separate language feature.
- A once-callable closure type (`FnOnce`), which
  [[2026-09-13-linear-capture-unchecked-outside-infer-mode-lambdas]] notes
  as the answer to the capture rule's false positives. It's related (a
  closure capturing a linear value is a container of it) but separable.

## Tests, when designed

Reject: `dup(S1(1))`; `drop_it(S1(1))`; the tuple destructured twice;
`List.length(xs)` twice on a list holding an `S1`.

Accept: `Some(S1(1))` matched and consumed; `Ok(h)` through `let?`; an
opted-in `fn id(linear x : a) : a do x end` at `S1`; every generic stdlib
call at unrestricted types (the corpus must not move).
