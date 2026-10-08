# Shell: type-directed result rendering with a limit at every depth

Logged 2026-10-07. Observe plan R5.7
(`specs/plans/2026-09-28-observe-recon-shell-plan.md`, "Type-directed
rendering with a limit").

## What was wrong

A shell input's fragment returned `to_string(result)`, after first trying a
renderer that cut a top-level `List` at the limit. Observed on a live node:

- a record (`{ a: 1, b: "two" }`) printed `#<tag:0>`;
- a tuple inside a list printed `#<tag:0>`, so `Json.parse("{\"a\": 1}")`
  printed `Ok(Object([#<tag:0>]))`;
- strings inside containers were unquoted (`[a, b]`), and a top-level string
  printed raw;
- `limit:` cut only a top-level list;
- a function printed `#<tag:0>`, a Map its HAMT internals
  (`HamtMap(HLeaf(269157861, 1, ...))`).

## What the shell does now

`eval_expr` (bin/shell_cmd.ml) typechecks the input once on its own, as
`:t` does, to get its static type, then generates a renderer for that type
(`bin/shell_render_gen.ml`) into the fragment module and compiles
`let __r = (input)  let __l = N  <renderer>(__r)`. The node is unchanged.
The probe typecheck writes into a type table of its own, not the session's
(which lowering reads), so its spans cannot leak into the compiled
fragment's.

The renderer, by type:
- `String`, `List`, `Array` (`PVec`), `Map`, `Set`: a call into the new
  stdlib module `ShellRender` (`string`, `list`, `array`, `map`, `set`),
  given the limit and the element renderer as a closure. A collection shows
  at most N elements then `… n more`; a string at most N codepoints, quoted
  and escaped, then `… n more chars`. The limit reaches every depth.
  `limit: all` / `:limit 0` is no limit.
- A tuple, a record, an ADT: one generated `pfn` per (instantiated) type,
  memoised by its printed type, so a recursive type (`JsonValue`, whose
  `Object` holds `List((String, JsonValue))`) recurses through them.
  Constructors render as `Name(a, b)`, tuples as `(a, b)`, records as a
  record literal `{ a: 1, b: "two" }` (March records are structural); a
  record type that derives Show keeps derive Show's `Name { a = 1 }` form.
- A type with a hand-written Show impl: `ShellRender.show_cut(show(v))`,
  cut at 16 KiB on a codepoint boundary with `… (n more bytes)`. List,
  Option and Result are excluded (prelude's impls are hand-written, but
  those types render structurally).
- `()`: `"()"` (compiled `to_string(())` prints `0`); a function: `"<fn>"`.
- Everything else (Int, Float, Bool, Pid, an opaque `ptype`, an unresolved
  type variable): `to_string`, the runtime's value printer.

Hand-written vs derived Show is read from the program's declarations (stdlib
included): a derived impl's method name carries the synthetic file `<none>`
(Desugar_derive.respan_derived_decl), a hand-written one its source file.

If anything goes wrong on the way (the input does not typecheck, reaches
code that differs from the node's, or the generated renderer itself fails
to compile), the input falls back to the plain `to_string` fragment, whose
compile reports the input's errors exactly as before. `MARCH_SHELL_DEBUG=1`
prints each generated renderer, and why one did not compile.

## Design choice: generate calls, not a limit-aware derive

The plan suggested a limit-aware variant of derive Show
(`lib/desugar/desugar_derive.ml`) generated as impls. Generating plain
functions in the fragment's own module is simpler and enough: there is no
interface dispatch to extend, nothing is registered in the type
environment, and a type that derives Show prints the same text (derive
Show is mechanical: `Ctor(` ++ show of each argument ++ `)`).

**The spike (a type declared in another module).** No re-typecheck of that
module is needed. The generated function matches on the type's constructors
by their module-qualified names (`Json.Object(__a0) -> ...`), which the
fragment's typecheck resolves like any input's; the constructor argument
types come from the environment's `ctor_info` (`ci_arg_tys`, its
parameters substituted with the instance's arguments). The limits:
- a type whose constructors are private (`ptype`: Map, Set, Array are
  special-cased through their `to_list`) cannot be matched from outside, so
  it falls back to `to_string`;
- the typechecker's type names are bare, so two types with one name in two
  modules are told apart only by preferring the entry module's, then the
  prelude's; otherwise `to_string`;
- other stdlib containers (`HashMap`, `Deque`, `OrderedMap`, ...) are
  opaque and print through `to_string`, as before.

## A trap found on the way

The first version named the generated functions `__shell_render1..k` in
every input. `Repl_jit.shell_compile` keeps an input's non-entry functions in
the session's lowered program (`lower_more`'s library functions), by name,
so a later input's `__shell_render1` collided with an earlier one's: after
`Actor.inspect_state(..)` (a `Result(String, InspectError)` renderer), a
`Json.parse(..)` ran the earlier renderer on a JsonValue and the node died
with SIGSEGV. The names now carry the input number
(`__shell_render<input>_<k>`).

## Cost

One extra typecheck of the input (to get its type) and a few more small
functions to compile. Against the old client (which, for a non-list, paid a
failed list-renderer compile before the plain one), on macOS under load
average ~45: compile p50 113.7 ms before, 118.8 ms after (54 inputs each,
alternated, `MARCH_SHELL_TIMING=1`). Within the plan's 10-20 ms budget.

## Tests

- `test/shell/session.txt` (golden `test/native/shell_session.expected`)
  gains: an anonymous record, tuples in a list, a Json value (tuples inside
  a recursive ADT), quoted strings in a list, nested limits (a list of
  records whose strings and lists are cut), a 10 000-element list at the
  default limit (`… 9950 more`), `()`, a derived-Show recursive ADT, a
  hand-written Show (short, and 20 000 bytes cut at 16 KiB), a Pid, a
  function, an escaped string cut at the limit, and a Map inside an Option.
  `test/native/shell_node.march` gains `Item`, `Twig` (derives Show), `Blob`
  (hand-written Show) and `items`; `shell_node_skew.march` gets the same.
  `Actor.inspect_state`'s result is now shown quoted (`Ok("{ n: 42 }")`).
- `test/native/shell_link.expected`: Json values and strings now print in
  full and quoted.
- `test/stdlib/test_shell_render.march` (21 cases, `scripts/run-tests.sh
  stdlib_march`): quoting and escaping, codepoint-counted cuts, the 16 KiB
  cut on a codepoint boundary, list / map / set / array limits, a nested
  limit, limit 0, the 10 000-element case, ctor / tuple / record forms.

RED proof (by file copy):
- `bin/shell_cmd.ml` from origin/main: `native_shell_session.out` differs
  from the new golden in 10 lines (`#<tag:0>` for the record, the Json
  value and the function, `[a, b]`, the uncut nested strings and lists, the
  uncut 20 000-byte Show, the raw string, the Map's HAMT internals);
  `native_shell_link.out` in 4.
- `stdlib/shell_render.march` emptied: 21/21 unit cases fail. Perturbing
  `take_render` so `limit 0` cuts at 0: the "limit 0 is no limit" case
  fails.
