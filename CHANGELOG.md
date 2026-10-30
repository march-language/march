# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change (including everything that shipped
before this file existed) lives in `specs/progress/` and `specs/todos/`;
git log is authoritative for exact commits.

**Past releases.** Older releases live in one file each under [`changelog/`](changelog/):

- [0.5.0](changelog/0.5.0.md) - 2026-10-13
- [0.4.0](changelog/0.4.0.md) - 2026-09-10
- [0.3.0](changelog/0.3.0.md) - 2026-08-23
- [0.2.0](changelog/0.2.0.md) - 2026-07-23
- [0.1.1](changelog/0.1.1.md) - 2026-07-21

## [Unreleased]

### Added

- **The JS target (`--target js`) runs real programs: tail calls, native arrays,
  binary strings.** Self and mutual tail calls compile to loops, so deep recursion no
  longer overflows the stack. `NativeI32Arr`/`NativeU8Arr`/`NativeIntArr` are typed
  arrays with the native wrap and bounds behaviour (`set` updates in place, since RC
  is erased on JS). A `String` holding binary data keeps its exact bytes, and
  `byte_at`/`byte_length`/`slice`/`index_of` agree with native in O(1) per byte
  (`march_bytes_to_string` builds such strings from JS externs). `process_argv` returns
  Node's arguments. `march --target js -o dir/x.mjs` copies every module the output
  imports, including relative-path extern modules, into `dir/`. forge.toml
  `[package] js_entrypoint` names a separate entry file for `--target js` builds. See
  "Byte Strings" and "Int on the JS target" in
  `docs/specs/2026-06-21-march-js-backend-design.md`.
- **`--js-int-check`** (forge: `MARCH_JS_INT_CHECK=1 forge build --target js`) makes an
  Int `+ - *` result or literal outside ±(2^53 − 1) throw on the JS target, naming the
  function, to find code that needs more than 53 bits. Release builds are unchanged.
- **`march --check --reflect-report`: which functions a predicate will be able to use.**
  One line per function of your code: `reflected`, or `no` with the first rule that
  blocks it and where (`R3:calls println (app.march:14:5)`, `R6:calls mid, which is not
  reflected`, `R4:division by b not proved`, …). This is phase 0 of refinement reflection
  (`specs/2026-10-29-refinement-reflection-design.md`): the report only, nothing uses
  reflection yet and no verdict changes. See "Which functions are reflected" in the
  refinement-types reference.
- **`--refine-report-sites=all`: every refinement obligation, any verdict.** One line per
  obligation (`proved`, `skip`, `violated`, `trusted`), with its site, kind, callee and
  predicate. The bare `--refine-report-sites` still lists only skips, unchanged.
- **`scripts/refine-oracle.sh monotone <dir>`.** A refinement-checker gate that allows
  proofs to be gained but never lost: it compares every obligation's verdict, by site,
  against a baseline over `test/native` and `stdlib`, fails on any proved obligation that
  is no longer proved or any site that appears or disappears, and lists new proofs, new
  violations and withdrawn violations for review.

- **`int_div_floor(a, b)` and `int_mod_floor(a, b)`: floor division and modulo.** The
  quotient rounds toward negative infinity and the remainder takes the divisor's sign, so
  `int_div_floor(-1, 86400)` is `-1` and `int_mod_floor(-1, 86400)` is `86399` (truncating
  `/` gives `0` and `-1`). A zero divisor panics like the other division builtins. In
  compiled code a positive literal divisor is emitted inline, not as a runtime call, so
  LLVM can strength-reduce it. `DateTime.from_timestamp` now uses them (design:
  `specs/2026-10-29-floor-division-and-const-divisors-design.md`).

- **`march --check --termination-report FILE`** prints one line per recursive function
  in your code, with how it recurses: structurally on a component, on an `Int` metric
  that a guard bounds (`fib`) or does not (`down(n - 1)` with an `n == 0` exit),
  lexicographically, through a lambda or a function value, or with no metric at all
  (`spin(n)`). It is a report only and changes no verdict. It is the first step of
  termination checking (`specs/2026-10-26-termination-checking-design.md`).
- **`@[decreases(e, ...)]`: a termination metric for a recursive function.** The checker
  proves with the solver that the metric stays at least 0 and falls at every recursive
  call (several components are compared left to right, as for Ackermann's
  `@[decreases(m, n)]`). An annotated function whose metric is not shown to fall gets a
  `termination_unproved` warning with a counterexample (`down(n - 1)` with an `n == 0`
  exit: `e.g. n = -1`), an error in a `cap verified` module. Unannotated recursion is
  never warned about; `--termination-report` checks it too, with the first `Int`
  parameter as the default metric (`fib` is `cert=metric`). A metric outside the
  fragment (a local, a `Float`, a bare list) is an `invalid_decreases` error.
  `--refine-report`'s `by kind:` line counts `termination` obligations when there are
  any. A proved metric licenses the induction hypothesis (next entry).
- **`march --refine-infer` (and `forge refine --infer`) now also proposes
  `@[decreases(...)]`** for a recursive function the checker could not show to
  terminate. It tries at most 8 candidate metrics per cycle (each `Int` parameter,
  `b - i` for a counter climbing to a bound, `len(xs)`, and pairs of those), and
  proposes one only when every recursive call proves it decreases:
  `fn up(n : Int) : Int do if n >= 100 do 0 else up(n + 1) end end` gets
  `@[decreases(100 - n)]`. `--refine-infer-apply` writes the attribute in front of the
  `fn` and re-checks; a metric for a local `fn` is shown but not written.
  `--termination-report` lists what the search found (`infer` lines), and an editor
  quick fix adds the metric a `termination_unproved` diagnostic names. A plain
  `--check` never searches.
- **An unknown function attribute is warned about** (`unknown_attribute`), with a
  did-you-mean: `@[decrease(n)]` used to be ignored in silence.
- **Refinements: a recursive function's return refinement can now use itself at its
  recursive calls (the induction hypothesis), when its recursion is proved to
  terminate.** `fn sum_to(n : {Int | _ >= 0}) : {Int | _ >= 0}` with body
  `if n == 0 do 0 else n + sum_to(n - 1) end` is proved, and so is a caller's
  `need_nn(sum_to(k))`; both used to be skipped. The hypothesis needs a `structural` or
  `metric` certificate for the cycle and for every recursive function it calls, and a
  recursive call whose preconditions are all proved. A cycle of several functions is
  accepted all together or not at all. A function that may never return
  (`fn loopy(x : Int) : {Int | _ < 0} do loopy(x) end`) gets no hypothesis, so its
  contract stays unproved. That includes a function that calls a diverging one through
  an `alias`, a `use` or `import`, an interface method's `impl` (including one a
  builtin runs: string interpolation `"${e}"`, `to_string` and `println` run `Show`,
  `to_json`/`from_json` the Json codecs, `own` the `Drop` impl) or a top-level `let`
  lambda, and one that calls a name the checker cannot resolve (listed on the
  `--termination-report`'s new `unresolved:` line). A `match` on a parameter after
  `let xs = Cons(0, xs)` (or any other rebinding of it) is not structural recursion. Data type returns (`{List(Int) | len(_) == n}`), element
  returns (`List({Int | _ > 0})`) and a local `fn`'s element return use it at a call to
  themselves. Separately, a call inside arithmetic in a return expression
  (`1 + len2(t)`) now carries the callee's proved contract, as a bare call or a
  `let`-bound one already did.
- **Refinements: a definer passed through to `Map.filter` proves its return.**
  `fn mfilt(m, keep : k -> v -> Bool[p], cmp) : Map(k[p], v[p]) do Map.filter(m, keep,
  cmp) end` is proved, and so are its callers' demands. The callee's `p` and the
  caller's `p` were confused because they are spelled the same.
- **Refinements: a two-argument lambda may capture the caller's variables.**
  `filt(a, fn (k, v) -> v > k + n)` gives a relation over the caller's `n`, read with
  `n`'s own refinement, as a one-argument lambda already could. A captured name that
  equals a parameter of the callee, or a slot binder, stays the caller's.
- **Refinements: a return that is a `let`-bound call is proved from the callee's
  return.** `let r = a(x)` then `r` (or `r + 1`) now proves `b`'s `{Int | _ > 0}`
  when `a`'s return is proved or `@[assume]`d, as the bare tail `a(x)` already did.
  Chains of such `let`s work. An unproved return, the function's own, or a cycle's
  is never used, and a binding is dropped when its name or a name its call mentions
  is rebound before the return.
- **Refinements: `--refine-infer` / `forge refine --infer` propose this month's
  shapes.** Inference now proposes the contracts the checker learned to prove in
  October:
  - a return relating the result to a parameter (`inc(x : Int) : {Int | _ > x}`, read
    off the body's tail);
  - two-argument abstract refinements (`keep : k -> v -> Bool[p]` with
    `Assoc(k[p], v[p])`);
  - a relation between two container slots that a caller demands
    (`Assoc({x : Int | true}, {y : Int | y > x})`);
  - each key and value slot of a `Map` (`Map(String, {Int | _ > 0})`);
  - `Deque.Deque(a[p])` for a filtering wrapper;
  - fold accumulators with a parameter or `0 - 1` initial value, or in a `fold_right`
    step.

  Fixed on the way, all inside inference:
  - every applied abstract (`Bool[p]`) proposal failed its own re-check and was
    reverted (exit 3);
  - relational candidates were never ordered weakest-first;
  - a slot's trivial `true` goal could make a vacuous proposal look useful.
  Plain `--check` is unchanged.
- **Refinements: `SortedSet.fold` and `OrderedMap.fold` carry accumulator invariants.**
  The parametricity check now matches a record-typed parameter (`{cmp: …, tree: …}`)
  field by field, so `need_nn(OrderedMap.fold(m, 0, fn (a, _k, _v) -> a + 1))` is proved
  (it was a `parametric-source-unproved` skip), as is a user fold over a record
  parameter. `OrderedMap.filter` still carries no entry fact: its public type is an
  anonymous record, which has no element slots.
- **Refinements: `Map`'s own functions keep a refined map's facts.** `Map.insert`,
  `get`, `get_or`, `remove`, `keys`, `values`, `merge`, `map_values` and `singleton`
  are annotated with their generic types, and an opaque container (`ptype` /
  `opaque type`) whose representation hides its parameters now counts as a source for
  the parametric element rule. So `need_vals(Map.insert(m, "b", 5, cmp))` with `m :
  Map(String, {Int | _ > 0})` is proved, `Map.insert(m, "b", 0, cmp)` is a skip, and
  `one_pos(Map.get(m, "a", cmp))` is proved. Nothing new is assumed: the bodies are
  checked parametric. A too-weak declared map through these functions is now reported
  like a too-weak list through `List.reverse` (a violation). `Map.empty()` is not a
  source yet.
- **Refinements: `HashMap.filter` keeps what its predicate says.** It is now
  `@[assume] fn filter(m : HashMap(k, v), pred : k -> v -> Bool[p]) : HashMap(k[p],
  v[p])`, the `Map.filter` recipe: `need_vals(HashMap.filter(m, fn _k -> fn v -> v >
  0))` against `HashMap(String, {Int | _ > 0})` is proved, as are key demands and a
  key/value relation; a weaker lambda is an `abstract-refinement-too-weak` skip. The
  entry fact is assumed (one `trusted` postcondition), and property tests in
  `test/stdlib/test_hash_map.march` check it at run time.
- **Refinements: `Map.filter` keeps what its predicate says.** `Map.filter(m, pred,
  cmp)` is now `pred : k -> v -> Bool[p]` returning `{Map(k[p], v[p]) | subset(keys(_),
  keys(m))}`, so `need_vals(Map.filter(m, fn _k -> fn v -> v > 0, cmp))` against
  `Map(String, {Int | _ > 0})` is proved, as are a key demand and a relation between
  key and value (`fn k -> fn v -> v > k` into `Map({x : Int | true}, {y : Int | y >
  x})`); a weaker lambda is an `abstract-refinement-too-weak` skip. The entry fact is
  ASSUMED, like every other `Map` contract: `@[assume]` on a function whose return
  has element refinements now assumes them (one `trusted` postcondition per entry in
  `--refine-report`, accepted under `cap verified`), and a property test in
  `test/stdlib/test_map.march` checks it at run time. The input map's own element
  facts are not carried through, and `Map`'s other functions (`insert`, `remove`,
  `get`, `merge`, `map_values`), `HashMap.filter` and `OrderedMap.filter` carry no
  element fact yet.
- **Refinements: two-argument abstract refinements.** A callback of two arguments
  can define an abstract refinement `p` of two, and the return can relate two
  sibling slots through it:
  `fn filt(a : Assoc(k, v), keep : k -> v -> Bool[p]) : Assoc(k[p], v[p])`, the
  shorthand for
  `keep : ({x : k | true}) -> ({y : v | true}) -> {Bool | _ == p(x, y)}` returning
  `Assoc({x : k | true}, {y : v | p(x, y)})` (both spellings are accepted; with a
  one-argument `p`, `Assoc(k[p], k[p])` is still two separate slot facts).
  The body proves the return (`keep(k, v)` is `p(k, v)`); at a call `p` is what the
  passed lambda, `let`-bound lambda, named predicate, or a callback parameter that
  itself defines a two-argument `p` computes, so
  `need_pos(filt(a, fn (_k, v) -> v > 0))` and
  `need_arel(filt(a, fn (k, v) -> v > k))` are proved and a weaker lambda is an
  `abstract-refinement-too-weak` skip. A parameter can carry the relation too, read
  at the call's actuals when it also names another parameter of the callee. A
  callback chain ending in a concrete `{Bool | _ == e}` is not a contract (nothing
  checks the callable passed for it yet), and a lambda that binds one name twice
  (`fn (x, x) -> …`, `fn k -> fn k -> …`) instantiates nothing.
  Malformed signatures are `abstract_refinement_misuse` errors: `p` applied to
  only some of the callback's arguments, `p` on a single slot (`Assoc(k, v[p])`,
  fix `Assoc(k[p], v[p])`; this includes `List(Int[p])` under
  `Int -> Int -> Bool[p]`, which used to apply `p` to the last argument only and
  was silently inert), one argument at two types, a container that is not
  entry-shaped, or one `p` at two arities. `(a, a) -> Bool[p]` stays a parse
  error, whose message now says the tuple is ONE argument and writes
  `a -> a -> Bool[p]`. See "Two arguments" under abstract refinements in the
  refinement types reference.
- **Refinements: relational element refinements.** A slot predicate may name a
  sibling slot's binder, relating the two components of every entry:
  `Assoc({x : Int | true}, {y : Int | y > x})` reads "each entry's value exceeds
  its key". A construction owes the relation once per entry
  (`need_arel(ACons(5, 2, ANil))` is a violation naming the entry `(5, 2)`), a
  `match` gives its binders the relation (`ACons(k, v, _) -> need_gt(k, v)` is
  proved), and a declared relation implies a demand on fewer slots
  (`Assoc({x : Int | x > 0}, {y : Int | y > x})` meets `Assoc(Int, {Int | _ > 0})`).
  Before, the sibling name was a free variable, which gave false violations
  (that projection, with `x = -1`) and undecided skips. A relation the checker
  cannot hold per entry (a constructor carrying one of the related values without
  the other, a container-typed slot, a slot inside a nested container) is warned
  `refinement_unchecked` and ignored. A relation does not flow through a
  polymorphic call (a recorded skip). See "Relational element refinements" in the
  refinement types reference.
- **`march --refine-infer` proposes every refinement the checker can verify,
  module-wide.** Beyond the sign contracts `--refine-suggest-all` proposes, it
  finds element refinements (`xs : List({Int | _ > 0})`, element and tuple
  returns), relational preconditions (`i : {Int | _ < n}`, taken from the demand a
  callee makes), abstract refinements for `filter`-shaped helpers
  (`pred : a -> Bool[p]` with `List(a[p])`, `Option(a[p])` or `partition`'s pair)
  and fold accumulator invariants. Candidates are mined from the program, every
  proposal is proved by the real checker and must help some caller, and a
  precondition that would break an existing caller is refused with that call.
  `--refine-infer-json` emits JSON v1. `--refine-infer-apply` writes the
  proposals, re-checks, and reverts everything (exit 3) if the result differs
  from the prediction; `--refine-infer-diff` previews them; `forge refine --infer
  [--diff|--apply]` runs it over the whole project as one checked unit, so a caller
  in another file counts, passes `--apply-public` / `--allow-caller-violations`
  through, and names every file it could not infer for (`--fixpoint` is now an
  alias). The editor offers
  "Infer refinements for `f`" / "in this file" with identical edits, and
  `--refine-report --refine-infer` adds the if-applied ledger line.
- **TLS uses post-quantum key exchange by default.** Every client and server context
  offers the hybrid X25519MLKEM768 first (classical X25519 / P-256 / P-384 / P-521 after
  it), so sessions with a peer that supports it are safe from record-now, decrypt-later
  attacks. Needs OpenSSL 3.5+ linked; an older OpenSSL keeps its default groups and
  handshakes still succeed. New: `Tls.negotiated_group(conn)`, `Tls.is_post_quantum(conn)`,
  `Tls.post_quantum_available()`, and `Tls.set_groups(ctx, groups)` to override the list
  (e.g. require post-quantum).
- **Post-quantum cryptography: `MlKem` (ML-KEM-768, FIPS 203) and `MlDsa` (ML-DSA-65,
  FIPS 204).** `MlKem.keypair()`, `encapsulate(pk)` -> `(ciphertext, shared_secret)` and
  `decapsulate(sk, ct)` give two parties a 32-byte secret no quantum computer is known to
  recover; `MlDsa.keypair()`, `sign(sk, msg)` (hedged), `sign_deterministic` and
  `verify(pk, msg, sig)` sign and check. Seeded variants (`keypair_from_seed`,
  `encapsulate_with_coins`) reproduce published vectors. Backed by the vendored, portable-C
  mlkem-native / mldsa-native (no OpenSSL needed); the compiled and interpreted backends run
  the same code, and the outputs match OpenSSL's byte for byte.
- `march --compile --static` builds a self-contained executable: on Linux a fully
  static binary that runs in a `scratch` image (musl hosts such as Alpine; refused on
  glibc), on macOS one that loads nothing outside `/usr/lib` and `/System`. A missing
  static library is an error naming the package to install, and the compiler checks
  the finished binary before keeping it. See "Static binaries" in the tooling docs,
  including how a static binary finds TLS certificates.
- **Refinements: a lambda passed for an abstract refinement may now have a real
  body.** `List.filter(ys, fn y -> is_pos(y) && y < 100)`, an `if` or a `match`
  on a Bool, `fn y -> gt(y, 0)` (a several-parameter helper with a proved
  `{Bool | _ == e}` return, its arguments substituted) and calls to `let`-bound
  lambdas are read as the exact predicate they compute, so
  `sum_pos(List.filter(ys, fn y -> is_pos(y) && y < 100))` is proved where it was
  an `abstract-refinement-uninstantiated` skip. A too-weak skip now prints what
  the lambda was read as (`` `fn y -> is_pos(y) || y < 100` (read as
  `y > 0 || y < 100`) ``), and a declined body names the construct it could not
  read. A helper with refined parameters is inlined only where those are proved
  at the call (`fn y -> y > 0 && weird(y)` is read; `fn y -> weird(y)` is not).
- **Refinements: every parameter of a multi-parameter lambda now gets its element
  fact.** `List.zip_with(xs, ys, fn (x, y) -> need_pos(x) + need_pos(y))` with
  both lists `List({Int | _ > 0})` is proved, as are
  `sum_pos(List.zip_with(xs, ys, fn (x, y) -> x + y))`,
  `List.fold_left(xs, 0, fn (acc, x) -> acc + need_pos(x))` and
  `List.sort_by(xs, fn (a, b) -> need_pos(a) < need_pos(b))`; before, only a
  one-parameter lambda received one and each of these was a skip (an error
  under `cap verified`). A fold's accumulator still gets no fact, a lambda with
  a refinement-annotated parameter gets none, and a fact naming one of the
  lambda's own parameters is not given.
- **Refinements: an abstract refinement may be negated and combined in an element
  slot.** `fn rej(xs : List(a), pred : a -> Bool[p]) : List({a | !p(_)})` (also
  spelled `not(p(_))`) is accepted where it was a hard
  `abstract_refinement_misuse` error, its body is checked, and
  `sum_nonpos(rej(ys, fn y -> y > 0))` is proved. A slot may combine `p(_)` with
  `&&`, `||`, `!` and ordinary predicates (`{String | p(_) && len(_) > 0}`), sit at
  a concrete base (`List(Int[p])` for `f : Int -> Bool[p]`), and an accumulator
  helper's own `acc : List(a[p])` parameter is now checked inside the definition
  that declares `p`.
- **Refinements: a scalar demand on a call that returns one of its own inputs is
  now checked through the callee's arguments.** `need_pos(Option.unwrap_or(o, 1))`
  with `o : Option({Int | _ > 0})` is proved: by parametricity the result is
  either an element of `o` or the default, and both are positive. The same holds
  for a nested call, `Option.unwrap_or_else(o, fn () -> 1)`, an element of a
  list literal, `List.fold_left(xs, 1, fn (acc, x) -> x)`, an annotated `let`,
  `need_pos(List.head(xs) + 1)` and a return tail
  (`fn f(o) : {Int | _ > 0} do Option.unwrap_or(o, 1) end`); each was an
  `unreflectable-subject` skip (an error under `cap verified`). An argument that
  fails the demand (`Option.unwrap_or(o, 0)`) is a `parametric-source-unproved`
  skip, never a violation, since whether it is returned depends on the data. A
  fold's accumulator still gets no fact, and a demand that names another
  parameter (`_ < len(xs)`) is not traced.
- **Refinements: a local `fn` with a container return now lends it to its later
  calls.** Inside a block, `fn two(n : {Int | _ > 0}) : List({Int | _ > 0}) do
  [n, n + 1] end` followed by `sum_pos(two(k))` is proved, as is a `let ys =
  two(k)` used later and a top-level function whose tail is the local's call:
  once every tail of the local is proved, its declared element refinement is a
  fact at each later call in the block (the same rule a top-level function
  follows). A local that is not proved, is shadowed by another of the same name,
  or whose return names a captured variable lends nothing. A local's scalar
  return tail (`fn f(p) : {Int | _ > 0} do Option.unwrap_or(p, 1) end`) is now
  checked through its sources, as a top-level one's is.
- **Refinements: `List.partition` carries its predicate into both halves.** It
  now declares `(List(a[p]), List({a | !p(_)}))`, proved on its own definition
  side, so after `let (pos, neg) = List.partition(ys, fn y -> y > 0)` both
  `sum_pos(pos)` and `sum_nonpos(neg)` are proved (a single-arm tuple `match`
  works the same way); before, each was an `unreflectable-subject` skip, an
  error under `cap verified`. Any function may declare a tuple of element-refined
  containers as its return: every tail is now checked component by component
  (such a return used to be accepted and never checked), and a destructured call
  to it carries each component's fact. Only `let`/single-arm `match`
  destructuring carries a component; `partition`'s behaviour is unchanged.
- **Refinements: a demand on a fold's result is checked as the accumulator's
  invariant.** `need_nn(List.fold_left(ys, 0, fn (acc, _x) -> acc + 1))` is
  proved: the initial value meets `_ >= 0`, and the step, assuming it of `acc`,
  keeps it. The same holds at a return tail (a running maximum
  `: {Int | _ >= 0}`), for `List.fold_right`, the curried `Enum.fold`,
  `Enum.reduce` (its elements are the base), a step using a refined capture or
  the element's own refinement, and any user-written function generic in its
  return variable with a callback that consumes it; each was a
  `parametric-source-unproved` skip (an error under `cap verified`). A failing
  half is a skip, never a violation, with its own reason:
  `accumulator-base-unproved` (`0` for `_ > 0`) or `accumulator-step-unproved`
  (`acc - x` for `_ >= 0`). A callee that can make a value of the variable
  itself, or is `@[trusted]`/`@[assume]` or an `impl` method, gets nothing. A
  relational return (`: {Int | _ >= lo}`) is not traced yet.
- **Refinements: a bare `filter(...)` and the `Enum`/`Iterable`/`Range` filters
  carry their predicate.** `Prelude.filter` (what a bare `filter` is),
  `Enum.filter`, `Enum.take_while` and `Iterable.filter` now declare
  `List(a[p])`, `Enum.find` and `Iterable.find` declare `Option(a[p])`, and
  `Range.filter` declares `f : Int -> Bool[p]` returning `List(Int[p])`, each
  proved on its own definition side. So `sum_pos(filter(ys, fn y -> y > 0))`
  and `one_pos(Enum.find(ys, fn y -> y > 0))` are proved where each was a
  `parametric-source-unproved` skip (an error under `cap verified`). The four
  rewritten filters keep their order and results; they now share
  `List.filter`'s single-pass body and run about 35% faster compiled.
- **Refinements: list-building fold accumulators.** An element demand on a
  fold's result is now the accumulator's invariant too:
  `sum_pos(List.fold_left(pos, [], fn (acc, x) -> Cons(x, acc)))` is proved
  (the initial `[]` meets `List({Int | _ > 0})`, and the step, assuming `acc`
  does, conses a positive `x` onto it), as are `List.fold_right`, the curried
  `Enum.fold`, a nested fold and a declared `List({Int | _ > 0})` return; each
  was an `unreflectable-subject` skip (an error under `cap verified`). It is not
  specific to folds: any call whose declared return is a bare type variable
  (`fn pick(c, x : b, y : b) : b`) is checked through its sources when its
  value must meet an element refinement. A step pushing an unrefined element
  is an `accumulator-step-unproved` skip, an initial list that fails it an
  `accumulator-base-unproved` skip. A curried step's inner parameter
  (`fn a -> fn x -> …`) now gets its element refinement while the step is
  checked, so `need_pos(Enum.fold(pos, 1, fn a -> fn x -> a + x))` is proved.
- **Refinements: an annotated fold accumulator is checked, assumed and
  carried.** `List.fold_left(ys, 1, fn (acc : {Int | _ > 0}, _x) -> acc + 1)`
  states the invariant: the annotation is now an obligation of its own (the
  initial value must meet it, and the step must keep it given an accumulator
  that does), and when it holds `acc` assumes it inside the step and the call's
  result carries it, so `let s = List.fold_left(…)` then `need_pos(s)` is
  proved with no demand on the call. Before, the annotation was silently
  neither checked nor assumed. A failing initial value or step is an
  `accumulator-base-unproved` / `accumulator-step-unproved` skip (never a
  violation; an error under `cap verified`), and the annotation is then not
  assumed. A `cap verified` module with an annotated accumulator that does not
  hold, and no demand on the fold, used to be accepted and is now rejected.
  Same parametricity gates as the demand rule; a one-parameter lambda keeps
  the pass-site check, and an annotation on the element parameter is still
  neither checked nor assumed.
- **Refinements: element refinements see into `List(a)` (and other container)
  constructor fields, and `Deque.filter` carries its predicate.** In
  `type Dq(a) = Dq(Int, List(a), List(a))`, `Dq(1, [0 - 1], [])` against
  `Dq({Int | _ > 0})` is now a refinement violation (it was an
  `unreflectable-subject` skip), a positive construction is proved, and
  `match d do Dq(_, f, b) -> …` gives `f` and `b` the element refinement. The
  same holds for a field `Option(a)`, `Result(a, Int)` or any other variant
  type whose arguments are bare parameters. `Deque.filter` now declares
  `pred : a -> Bool[p]` and returns `Deque(a[p])`, so
  `sum_pos(Deque.to_list(Deque.filter(d, fn y -> y > 0)))` is proved where it was
  a `parametric-source-unproved` skip. It filters the deque's two lists in
  place instead of rebuilding it from a list: same elements, same order, about
  2x faster compiled. A field that holds a parameter any other way
  (`List(List(a))`, `List((k, v))`, `Int -> a`) is still a recorded skip.
- **Refinements: a container return that names a parameter is a fact at the
  call.** `fn below(n : Int) : List({Int | _ < n})`, once its tails are proved,
  carries `_ < 10` at `below(10)` and `_ < k` at `below(k)`, so
  `sum_small(below(10))` (or `let ys = below(k)` with `k : {Int | _ <= 10}`) is
  proved, and `sum_lt5(below(10))` is a violation; before, every such call was an
  `unreflectable-subject` skip, an error under `cap verified`. Only variables,
  literals and linear arithmetic over them are substituted, and a stored fact is
  dropped when a name it mentions is rebound. A recursive call is read at its own
  arguments (`clamp(t, n)` inside `fn clamp(xs, n) : List({Int | _ <= n})`), and
  tuple components and block-level `fn`s whose return names only their own
  parameters work the same way. A call whose fact names a caller variable that
  nothing constrains (`sum_small(below(n))`, `n : Int`) is a skip, not a
  violation.
- **Refinements: the collection folds carry the accumulator invariant.** A
  demand on the result of `Map.fold`, `Set.fold`, `HashMap.fold`,
  `Array.fold_left`, `RRB.fold`, `RRB.fold_left`, `Deque.fold_left` or
  `Deque.fold_right` is now checked as the accumulator's invariant, as for
  `List.fold_left`: `need_nn(Map.fold(m, 0, fn (acc, _k, _v) -> acc + 1))` is
  proved (it was an `unreflectable-subject` or `parametric-source-unproved`
  skip, an error under `cap verified`), and a step that can break the demand is
  an `accumulator-step-unproved` skip. `NativeArray`'s and `Seq`'s folds stay
  skips, as do `SortedSet.fold` and `OrderedMap.fold` for now (their record-typed
  collection parameter is not yet seen through).
- **Refinements: `Hamt.fold`, `Enum.scan` and `Queue` now carry what the checker
  can prove through them.** Their signatures were unannotated, so no demand
  could pass through them; they now declare the types they already had.
  `need_nn(Hamt.fold(h, 0, fn acc -> fn _k -> fn _v -> acc + 1))` and
  `sum_nn(Enum.scan(ys, 0, fn acc -> fn _x -> acc + 1))` are proved as
  accumulator invariants, and a queue built from a refined list keeps its
  elements' refinement through `to_list`, `peek_front`, `peek_back`,
  `push_back` and `push_front` (`sum_pos(Queue.to_list(Queue.from_list(pos)))`
  is proved). Each was a skip before (an error under `cap verified`). Not yet:
  a parameter typed `Queue.Queue({Int | _ > 0})` or `Deque.Deque(…)` gives no
  element fact.

### Changed

- **Termination: `@[diverges]`, actor handlers and `cap total`.** Mark a function meant
  to run for ever `@[diverges]` (an accept loop, a frame reader, a ticker): it files no
  termination obligation, never gets the induction hypothesis, and neither does a cycle
  that reaches it; `--termination-report` lists it as `cert=diverges` and lists the
  callers that may diverge through it, which do not have to repeat the attribute.
  `@[diverges]` together with `@[decreases]` or `@[measure]`, or a measure calling a
  `@[diverges]` function, is a `diverges_conflict` error. The report also names an actor
  handler that may not return for a message (`handler Counter.Spin may not return`);
  `send(self(), …)` is not recursion. A module that declares the new `cap total` must
  prove every function terminates (`main` and `@[diverges]` functions exempt): anything
  else is a `termination_unproved` error, including a function in a recursive cycle with
  a `@[diverges]` one that is not marked itself, and a call on a known type
  (`"${Box(n)}"`, `show(Box(n))`) whose `impl` may not terminate. The standard library's 23 event loops
  (`ClusterNode`, `NetKernel`, `NodeCall`, `PeerReader`, `Csv`, `File`, `SessionNode`,
  `Topology`, …) carry `@[diverges]`, and a test keeps new ones from landing unmarked.
  `termination_unproved` on an `n == 0` exit with a negative counterexample now notes
  the `n <= 0` repair, which the editor offers when asked (it changes what the program
  does, so it is not a machine fix and `forge fix` never applies it), plus "mark
  `@[diverges]`".

- **Refinements: the `@[measure]` termination check now covers mutual recursion.** Two
  measures that call each other in a cycle, `ma(Z) -> mb(Z) -> ma(Z) + 1`, were accepted,
  because only a measure's calls to itself were checked. They are now `invalid_measure`
  unless every call in the cycle passes a component of a parameter of one type, or of
  types defined in terms of each other.
  `--termination-report` gains a certificate column (`cert=structural` or
  `cert=unproved:<reason>`), and it lists a function that calls a value of a non-positive
  type such as `type Fix = Fix(Fix -> Int)`.
- A parameter list or pattern that binds the same name twice is now a compile
  error (`duplicate_binder`): `fn (a, a) -> …`, `fn two(a, a)`, a multi-head clause
  such as `fn pick(0, a, a)`, and patterns like `(a, a)` or `Pair(x, x)`. Such
  programs used to be accepted, and the interpreter and compiled code disagreed
  about which value the name meant (`fn (a, a) -> a` applied to `(1, 2)` gave `1`
  interpreted and `2` compiled). Rename one binder or use `_`; to match equal values,
  bind two names and compare them in a `when` guard. Shadowing across scopes
  (`fn a -> fn a -> a`, a match arm rebinding a parameter) is unchanged.
  `march --explain duplicate_binder` has the details.
- A compiled program that uses `Compress.Zstd` or `Compress.Brotli` on a build host
  without that library now fails to compile with a message naming the package to
  install, instead of building a binary whose codec returns `Err("... not available")`
  at run time. Each codec is linked only when the program uses it, so a gzip program
  loads zlib alone.
- A compiled program now loads OpenSSL only when it uses TLS, and zlib/zstd/brotli
  only when it uses `Compress`: a hello-world depends on libc alone, where it used to
  need six libraries. `--hot-reload` builds still link the whole runtime.
- `SessionNode.run_cluster` and `SessionNode.run_cluster_hosted` take a `fingerprint`
  argument after `session` (the generated `cluster_<Role>` runners pass the
  protocol's); pass `""` to check nothing.
- **Stdlib: the collection folds declare their types.** `Map.fold(m : Map(k, v),
  acc : b, f : b -> k -> v -> b) : b`, likewise `HashMap.fold`; `Set.fold(s :
  Set(a), acc : b, f : b -> a -> b) : b`; `Array.fold_left(v : PVec(a), acc : b,
  f : b -> a -> b) : b`; and the callback of `RRB.fold` / `RRB.fold_left` (`f : b
  -> a -> b`), `Deque.fold_left` (`f : b -> a -> b`) and `Deque.fold_right` (`f :
  a -> b -> b`), which were unannotated. These are the types the folds already
  inferred, so well-typed callers are unaffected and nothing runs differently.

### Fixed

- **On the JS target a `let` local named like a module function is the local.** It was
  emitted as that function's closure (`{ o with x: px }` stored a closure when the module
  also had `fn px`).
- **Bytes built from byte values are those bytes on the JS target.** `Bytes.from_list` and
  `Bytes.from_hex` with bytes ≥ 0x80 (via `byte_to_char`) gave each byte's UTF-8 encoding,
  shifting every later byte offset (Herald's font data drew glyphs a pixel off).
- **`let x = match t do (a, _) -> a end` on a tuple works on the JS target.** The
  compiler's non-exhaustive default was emitted after the tuple's one branch and
  overwrote `x` with a "non-exhaustive pattern match" throw.
- **A JS build ignores another module's `main`.** `--target js` now emits only what the
  entry's own `main` reaches, so a library module with its own `main` (a game's desktop
  entry beside its browser one) no longer fails the build with "extern ... cannot be
  called on the JavaScript target".
- **A module with JS-module externs compiles natively.** An `extern "./x.mjs"` block gave
  its functions native symbols like `./x.mjs_fn`, so any native build that loaded the
  module (say, a library's browser backend) failed in clang even when nothing called them.
- Every `march --compile` on a musl host (Alpine) failed since 2026-10-12: the
  runtime's scheduler included `<execinfo.h>`, which musl does not have. It is now
  guarded as the rest of the runtime guards it (no symbolised fatal-fault frames on
  musl).
- **A record or variant whose only refinements are on container elements is now
  checked when it is built.** With `type Box = { n : Int, xs : List({Int | _ > 0}) }`,
  `{ n: 10, xs: [0 - 5] }` was accepted with no obligation at all, even under
  `cap verified`, because a constructor was only checked when some field had a
  refinement of its own (`n : {Int | _ > 0}`). A record literal, a `{ r with … }`
  update and a variant application such as `W([0 - 5])` for
  `type W = W(List({Int | _ > 0}))` now check every element slot (`List`, `Option`,
  `Map` values, nested lists). A bad element is a refinement violation, or a recorded
  skip (an error under `cap verified`) where the checker cannot decide it, such as a
  value passed through a generic call like `Map.singleton`. A slot that names another
  field (`xs : List({Int | _ < n})`) stays a recorded skip. The same holds for an
  actor message: `on Push(xs : List({Int | _ > 0}))` let the handler body rely on
  `xs`'s elements while `Push([0 - 1])` was never checked; that construction is now
  a violation. An actor `init` state literal whose field set another record shares
  now has its element slots checked as well.

- **`List.range_step` with a zero step no longer hangs.** `List.range_step(5, 0, 0)`
  recursed on the same value forever (interpreted and compiled); with `start <= stop`
  it returned `[]`. `step` is now `{Int | _ != 0}`, so a literal zero is a compile-time
  refinement error, and a zero the checker cannot see panics with
  `List.range_step: step must be non-zero`, as `Range.new_step` already did.

- **`Range.to_list` and `Range.each` with a zero step no longer hang.** A range is a
  plain record, so `{start: 5, stop: 0, step: 0}` bypassed `Range.new_step`'s check and
  the walk never advanced. Every Range function that walks a range (`to_list`, `each`,
  `map`, `filter`, `reduce`, `reverse`, `all`, `any`, `sum`) now takes
  `{v : IntRange | v.step != 0}` (`Range.IntRange` is the new name for the
  `{start, stop, step}` record; records are structural, so literals still fit), and
  `to_list`/`each` panic with `Range.to_list: step must be non-zero` /
  `Range.each: step must be non-zero` for a zero the checker cannot see.
  `Range.new` and `Range.new_step` return that refined type, so
  `Range.to_list(Range.new_step(3, 0, -1))` is proved.

- **`Control.chunks` with a size of 0 or less no longer hangs.** `Control.chunks(hex, 0)`
  never advanced its offset and a negative size walked it backwards, both forever.
  `size` is now `{Int | _ > 0}` (as `List.chunks` already was), and a size the checker
  cannot see panics with `Control.chunks: size must be positive`. This includes an
  empty artifact with a size of 0, which used to come back as one empty chunk.

- **`List.chunks` with a size of 0 or less no longer hangs.** It already had
  `size : {Int | _ > 0}`, so a literal 0 was a compile-time error, but a size the checker
  could not see made `split_at(lst, 0)` return the same list forever. It now panics with
  `List.chunks: size must be positive`, including on an empty list.

- **`Duration.format` of the smallest Int no longer recurses forever.** A negative
  duration was formatted as `"-" ++ format(Duration(-ms))`, and `-ms` of the smallest
  Int is itself, so it looped interpreted and overflowed the stack (SIGBUS) compiled.
  It now splits the value into seconds and milliseconds before negating, so every
  Int formats exactly: `Duration.milliseconds(-4611686018427387904)` is
  `"-7625142226 weeks, 1 day, 15 hours, 36 minutes, 27 seconds, 904 milliseconds"`.
  Output for every other value is unchanged.

- **Refinements: a value-creating function used as a value no longer counts as
  parametric (a false proof).** The check that a generic function cannot make a value
  of its type variable looked only at what it CALLS, so a function that creates one
  (an interface method `fn dflt : Int -> t`, a decoder, an extern) went unnoticed when
  it was passed as an argument, `let`-bound, or stored in a record. For example,
  `fn sneak(xs : List(v), _d : v) : List(v) do Cons(apply1(dflt, 1), xs) end` was proved
  to keep a `List({Int | _ > 0})` positive while running it put `-5` in the list. Every
  name a body mentions is now checked. No standard-library or test-corpus proof was
  lost.
- **Refinements: a `let`-bound list literal keeps its length.** `let t = [1, 2, 3]`
  then `List.head(t)` or `Stats.mean(t)` was an `unconstrained-subject` skip while
  `List.head([1, 2, 3])` proved; the binding now records `len(t) == 3` (any
  Cons/Nil chain ending in `Nil`, `[]` included), retired when `t` is rebound. This
  was half the user-code skips in a 67-program corpus sweep
  (`examples/stats_basic.march`).
- **Refinements: `Cons(h, t)` is known to be one longer than `t`.** `need_ne(Cons(x,
  t))`, `let ys = Cons(x, t)` then `need_ne(ys)`, and `List.nth`'s own recursive call
  `nth(t, n - 1)` inside a `Cons(h, t)` arm were skipped; `len`'s defining equation
  now applies at call arguments, `let`s and `match` arms, and all three prove. The
  one skip inside `stdlib/list.march` is gone.
- **Refinements: an `elts && len` list return is lent whole.** A function proved to
  return `{List(a) | subset(elts(_), elts(xs)) && len(_) == len(xs)}` gave a direct
  caller neither half: the call site translated the conjunction for one measure and
  dropped all of it. Each proved conjunct is now lent on its own.
- **Refinements: `List.length(e)` as an argument or a `let` means `len(e)`.** The
  `len` alias worked in guards only, so `need_nn(List.length(xs))` was
  `unreflectable-subject`, and `let n = List.length(xs)` then `if i >= 0 && i < n do
  List.nth(xs, i)` was a `partial-conjunct` skip. Both prove now, under the alias's
  existing gate (the stdlib's own `List.length`, not withdrawn).
- **`String.slice` with a negative start no longer reads out of bounds in wasm-compiled programs.**
  The wasm runtime's `march_string_slice` did not clamp a negative `start` and read before
  the string's buffer; it now clamps exactly like the native runtime and the interpreter
  (negative start -> 0, start past the end -> empty, negative length -> 0, over-long length
  stops at the end).

- **Refinements: a module-qualified container keeps its element fact.** `d :
  Deque.Deque({Int | _ > 0})` and `q : Queue.Queue({Int | _ > 0})` were no element
  source, so `sum_pos(Deque.to_list(d))` and `sum_pos(Queue.to_list(q))` were
  `parametric-source-unproved` skips, and so was `sum_pos(Deque.to_list(dfilter(d,
  fn y -> y > 0)))` for a user `dfilter : … -> Deque.Deque(a[p])`. A qualified name
  `M.T` now resolves to its declaration when exactly one module declares `T` and `M`
  names it; all three are proved. An ambiguous `T` is still unknown (a skip).
- **Refinements: a recursive local `fn` proves its element return through its own
  self-call.** `find_index`'s shape, a local `go(lst, i : {Int | _ >= 0}) :
  Option({Int | _ >= 0})` whose tails are `None`, `Some(i)` and `go(t, i + 1)`, was
  three `unreflectable-subject` skips (`return of go`, `return of` the enclosing
  function, and the `Some(i) -> need_nn(i)` use). A self-call with a structural
  argument (`t` from `Cons(h, t)` of `lst`) now carries the declared return, the rule
  a top-level function already had, and only after the local's return is proved with
  it, so a `Some(0 - 1)` tail is still a violation and lends nothing. The same holds
  for a recursive local returning `List({…})`. `--refine-infer` now proposes the
  `Option` return.
- **Refinements: a `List.filter` lambda may capture the caller's variables.**
  `fn small(xs : List(Int), n : Int) : List({Int | _ < n}) do List.filter(xs, fn y
  -> y < n) end` was an `abstract-refinement-uninstantiated` skip at its return, and
  `small(ys, 10)` an `unreflectable-subject` skip at the call. Both are proved now,
  and so is `sum_lt10(List.filter(xs, fn y -> y < k))` with `k : {Int | _ <= 10}`.
  An abstract refinement's lambda may mention a local of the call (a parameter,
  `let`, lambda parameter or `match` binder); the element fact names it and is
  read in the caller's scope. A module-level name is still declined, and so is a
  `let`-bound lambda or result whose captured variable is rebound before its use.
  A capture over an unconstrained variable (`fn y -> y > m`, `m : Int`) is now a
  `solver-undecided` skip instead of `abstract-refinement-uninstantiated`.
  `--refine-infer` now proposes the `small` return.
- **Refinements: a length contract on a list return is now checked whatever the body
  looks like.** `fn f(xs : List(Int)) : {List(Int) | len(_) == len(xs) + 5} do xs end`
  used to pass with no error and no obligation in `--refine-report`: only a body that
  was a constructor or one `match` on a parameter was checked. A bare variable, a
  `let`, an `if`, a call or a `match` on anything else is now checked tail by tail, so
  that false contract is reported (`but f([]) returns [].`) and the true
  `len(_) == len(xs)` is proved. A mixed `elts(_) == elts(xs) && len(_) == len(xs)`
  contract now proves too, where it used to be undecided. A list or datatype return
  contract the checker cannot prove is a recorded skip, and inside `cap verified` it is
  now an error (it used to pass silently there). A refined return the checker does not
  model at all, such as a guarded clause, is a recorded skip instead of nothing.
- **Refinements: return contracts compose through calls.** A return whose tail is a
  call now uses the callee's proved (or `@[assume]`d) return:
  `fn b(x : {Int | _ > 0}) : {Int | _ > 0} do a(x) end` proves from `a`'s
  `{Int | _ > 0}`, through any number of hops. It was an `unreflectable-subject` skip
  before. A function never uses its own unproved return this way, so self-recursive and
  mutually recursive tails stay skipped. A relational return lent at a call
  (`inc(x) : {Int | _ > x}`) now brings the caller's facts about its arguments with it,
  so `need_pos(inc(n))` with `n : {Int | _ >= 0}` is proved (it was
  `solver-undecided`). **Soundness:** a named return binder (`{r : Int | r > x}`) is now
  renamed apart before the arguments are substituted. Before, `inc(r)` with a caller
  variable `r` read `r > r`, and that false assumption "proved" any demand on the call.
  `--refine-infer` now proposes returns along such a chain (`a` and `b` both get
  `{Int | _ > 0}`). Its probes also lend only proved returns, as the real check does,
  so `--refine-infer-apply` no longer fails its re-check ("did not match the
  prediction") on a program with an unproved declared return. A parameter refinement that
  names an unrefined sibling (`k : {Int | _ > x}`) no longer sends z3 a malformed query
  when a return is checked. That return used to be skipped silently; it is now decided.
- **`--refine-infer` no longer proposes a precondition that only makes the demanding
  branch dead.** In `if j >= n do v else Array.set(v, j, …) end`, `n : {Int | _ <= j}`
  "proved" the `Array.set` index by making the `else` unreachable. A precondition
  whose closed sites are closed only that way is now rejected as `vacuous-branch`
  (printed by `--refine-infer`, `rejected[].reason` in `--refine-infer-json`). A
  precondition that genuinely proves a site still counts every site it closes. On
  `test/native` the one accepted proposal (this one) is gone. A plain `--check` is
  unchanged.
- **Refinements: a lambda or helper that binds one name twice is no longer read as a
  predicate.** `let h = fn (a, a) -> a > 0` then `List.filter(xs, fn y -> h(y, 1))`
  was read as `y > 0`, and a function `two(a : Int, a : Int) : {Bool | _ == (a >
  0)}` lent `two(y, 1) == (y > 0)` at a call; which argument the body's `a` names
  differs between the interpreter (the first) and compiled code (the last), so both
  are now declined (`abstract-refinement-uninstantiated`, or no postcondition fact).
- **`--refine-suggest-all` no longer proposes a precondition that breaks a caller.** The
  suggester re-checked only the target function, so for `go(n : Int) = need_pos(n)` with
  `caller() = go(0 - 5)` it proposed `n : {Int | _ > 0}` and reported "discharges all", although
  applying it turns `caller` into a refinement violation. Probes now include every caller in the
  unit; such a proposal is reported as `refused (caller-violation)` with the call it would break.
  A hypothesis is also judged site by site (it must prove something, break nothing and create no
  violation), and one that makes the parameters unsatisfiable is rejected.
- The in-browser REPL (stdlib "Try it" pages, playground, landing page) now runs a
  pasted doc transcript one `march> ` line at a time and ignores the expected-output
  lines between them. Pasting a transcript whole used to evaluate it as one block and
  print the value of its last line, the transcript's own expected output, which on
  Sort.html made `Sort.heapsort_by` look as if it dropped the largest element.
- `march --compile` no longer serves a cached binary that was linked under a different
  host library probe: whether the build host has OpenSSL, zstd or brotli decides what
  the binary links and whether its zstd/brotli codecs work, and is now part of the
  build cache key.
- A hot deploy that changed an actor's state no longer hands an actor spawned by
  not-yet-redeployed code (such as a closure `main` built) an old-layout state to run
  the new handlers on, which read garbage fields and could crash: the state is now
  migrated from the version of the code that built it before the actor's first
  message.
- On macOS, `forge deploy hot` now finds a patch's `migrate_state`: it looked for the
  `__migrate_<Actor>` symbol with `nm -D`, which lists nothing for a Mach-O library,
  so every deploy that changed an actor's state was refused as missing its migration.
- Two nodes built from different versions of a protocol no longer form a session
  through `<P>_Run.cluster_<Role>` and find the skew mid-session: each role registers
  its protocol fingerprint beside its endpoint, and a peer with a different one, or
  none (a node built before the check), is refused with `Err(Connect(...))` before the
  session forms, as the direct runner already refused it at the hello.
- `--hot-reload` programs built with `--cap-sandbox` now keep their reload and observe
  sockets when they withhold `IO.NetListen`: the reload server's listener is bound
  before the sandbox is installed instead of racing it on its own thread, and the
  observe socket starts before the install instead of after it (where its bind was
  always refused). An over-long reload socket path is now refused instead of silently
  truncated.
- **Refinements: a correct call under a condition the checker cannot read is no
  longer a violation.** With `k : {Int | _ <= 100}` and
  `xs : List({Int | _ < k})`, `if small(k) do need_lt5(xs) else 0 end` (where
  `small(k)` is `k < 5`) was reported violated with the example `k = 6`, a value
  that never reaches the call; so were a call inside a `Some(3) ->` arm, after an
  arm whose failure the checker does not record, and in a later `match do` cond
  arm. These are now skips, as the same call with a plain `Int` argument already
  was. An `Int` literal arm (`3 ->`) now records that the scrutinee is 3 (and,
  past an unguarded one, that it is not), so such a call can be proved. The
  same false violation through a `Bool` local (`let ok = k < 5; if ok do …`) is
  fixed too: such a local is read as its comparison in a guard (so the call,
  and the plain `Int` twin `if ok do n5(k)`, are now proved), and a local the
  checker cannot pin down (`let ok = small(k)`) makes the call a skip.
- **Refinements: a pattern binder spelled like a name its element refinement
  mentions no longer proves anything.** With `xs : List({Int | _ < n})`,
  `match xs do Cons(n, _) -> need_neg(n)` gave the new `n` the fact `n < n`, a
  contradiction, so `need_neg(n)` was proved (and accepted under `cap verified`)
  although `g(5, [3])` passes 3. `let n = hd(xs)` through a parametric head had
  the same hole. Such a binder now gets no fact from the slot.

- **Refinements: a local `fn`'s container return is checked.** A block-level
  `fn bad(n : Int) : List({Int | _ > 0}) do [n, 0] end` filed no obligation for
  its tails, so it was accepted silently, even under `cap verified`, although
  `bad(5)` returns a list holding 0. Every tail element is now an obligation, as
  for a top-level function: the `0` is a violation. `--refine-audit` already
  called this position enforced; it now is.
- **Refinements: a recursive combinator that recurses with a DIFFERENT
  predicate no longer proves its abstract element return.**
  `fn filt(xs, pred : a -> Bool[p]) : List(a[p])` whose body recursed as
  `filt(t, fn y -> true)` (or passed a swapped or rebound callback) had its
  return proved by the structural induction hypothesis, so a caller's
  `sum_pos(filt(ys, fn y -> y > 0))` was reported proved while the result could
  hold `-3`. The hypothesis now applies only when every predicate position of
  the recursive call receives the function's own, unshadowed parameter (an
  alias such as `let q = pred` is declined too). The hole predates the tuple
  returns above for single-container returns; the tuple form had it from the
  start.
- **Refinements: an interface method's result no longer counts as parametric.**
  `fn pick(o : Option(a), d : a) : a` returning `dflt(1)`, where the only impl of
  `dflt : Int -> t` is written at `Int` and returns -5, was accepted as generic
  in `a`, so `need_pos(pick(o, 1))` was proved (and `cap verified` compiled it)
  although `pick(Some(3), 1)` returns -5; the element rule had the same hole
  (`sum_pos(mk(pos))` with `mk` consing `dflt(1)`). A call to an interface
  method whose result mentions a type variable, including a non-creating
  `t -> t` and one adopted from a single `impl`, now makes the caller
  non-parametric: those demands are skips.
- **Refinements: a callback parameter's own refinement annotation is no longer
  assumed when a demand on the call's result is checked.**
  `need_pos(List.fold_left(pos, 1, fn (acc : {Int | _ > 100}, x) -> acc - 50))`
  was proved from the unchecked annotation (`List.fold_left([5], 1, …)` is
  -49); it is now a skip.
- **Refinements: a named function passed as a callback lends its declared
  return only when its own preconditions are met.** With
  `fn dec2(a : {Int | _ > 100}, _x : Int) : {Int | _ > 0} do a - 50 end`,
  `need_pos(List.fold_left(ys, 1, dec2))` was proved (and `cap verified`
  compiled it) although `List.fold_left([5], 1, dec2)` is -49: `dec2`'s return
  holds only when `a > 100`, and nothing checked what `fold_left` passes it.
  The same held for an element position (`fn g(_a : Int, x : {Int | _ > 0})`
  over an unrefined list), for `List.map` with a named function, and for a
  callback parameter passed on. A refined parameter of the named function must
  now follow from what the callee guarantees at that position (the demand on
  the accumulator, or the list's element refinement); otherwise the demand is
  a skip naming the unmet precondition.
- **Refinements: a recursive helper's element return is no longer trusted when
  its own recursive call skips a precondition.** A helper such as
  `pfn go(lst, acc : List({Int | _ > 0})) : List({Int | _ > 0})` that recursed
  as `go(t, Cons(f(h), acc))` with an unproved push recorded only a skip at that
  push, yet its return (by structural induction) and every caller's demand were
  reported proved. The induction now needs every element precondition of the
  recursive call PROVED; a skip or a violation there leaves the return unproved
  and its callers unproved with it. The same held for an abstract slot
  (`acc : List(a[p])`, pushing without testing `pred`, or pushing an element of
  another list): such a push is now an `unconstrained-subject` skip (or, on the
  branch where `pred` rejected the element, a violation) and lends nothing.
- **Refinements: a caller's own abstract refinement is no longer mistaken for the
  callee's.** A caller declaring its own `p` that passed a list to a callee slot
  such as `xs : List({Int | p(_) == false})` had the callee's `p` read as its
  own, so the call was reported proved whatever predicate it passed; a slot shape
  not read at a call is now an `abstract-refinement-uninstantiated` skip, and a
  `!p(_)` slot is instantiated with the callee's predicate.
- **Refinements: a return value bound inside a `match` arm or `let` under a
  parameter's name no longer proves a false return contract.** In
  `fn g(n : {Int | _ < 0}, p : Option(Int)) : {Int | _ > 0}` with the arm
  `Some(n) -> if n > 5 do 0 - 7 else 1 end`, the checker read the parameter's
  `n < 0` and the arm's guard `n > 5` as facts about one `n`, and the
  contradiction "proved" the `-7` tail, so `cap verified` accepted it
  (`g(0 - 1, Some(10))` returns -7). `Some(n) -> n` with a refined parameter `n`
  was proved the same way. The inner binding is now kept apart: the first is a
  violation, the second a skip. The same fix covers a lambda's tail inside a
  demanded call, a function passed where a container return is expected, and a
  lambda inside the returned call that captures the inner binding
  (`Some(n) -> ap(1, fn z -> n)`).
- **Refinements: a container that hides a type parameter inside another type no
  longer passes element checks vacuously.** For `type Wrap(k, v) = Wrap(List((k, v)))`,
  `fn mk() : Wrap(Int, {Int | _ > 0}) do Wrap([(1, 0 - 5)]) end` was counted
  *proved* and `need(Wrap([(1, 0 - 5)]))` filed no obligation at all. Such a
  construction is now a recorded `unreflectable-subject` skip naming the
  constructor and the hiding type (an error under `cap verified`), and the
  function's element return is no longer trusted at its call sites.
  The same applies to a self-reference whose type arguments are permuted or
  nested (`type T(a, b) = … | N(T(b, a))`). A `match` binder at such a field no
  longer inherits the outer container's element facts, which had produced a
  false proof.
- **Element refinements that name a parameter no longer prove false contracts.**
  A slot like `xs : List({Int | _ < n})` was read in whatever scope it reached,
  so the refinement checker proved calls and functions that break it, and
  `cap verified` compiled them: `need_lt(ys, 10)` was proved from a caller's
  unrelated `let n = 1000`; a return tail under `let n = 100` was checked
  against the local `n`; `xs`'s fact survived `let n = 0`; `List.map(xs, fn n ->
  …)` gave the lambda's `n` a fact about itself; and a demand was read under a
  lambda parameter of the same name. The slot is now read at the call's
  arguments (`need_lt(ys, 10)` demands `_ < 10`, so a correct
  `need_lt(ys, 200)` with `ys : List({Int | _ < 5})` is no longer a false
  violation; a demand naming a caller variable no fact constrains, such as
  `need_lt(ys, k)` after `k`'s fact was retired, is a skip rather than a
  violation), and each of the other shapes is a recorded skip. Two related
  shapes are skips too: a record field's or an expected codomain's element
  refinement naming another field or parameter, and a lambda return expression
  that mentions a name bound inside the lambda (`fn y -> let k = 0 - 5; k`
  was proved against a caller's `k : {Int | _ > 0}`).

### Documentation

- **What March 1.0 will promise, in writing.** New pages: [Compatibility &
  Deprecation](docs/compatibility.md) (what a 1.x release keeps working, including the
  cluster control plane's release format and messages; `@[deprecated]` and stdlib
  stability tiers are marked as planned), [Supported Platforms](docs/platforms.md)
  (tier 1: darwin-arm64, linux-x86_64, linux-aarch64; Intel macOS is tier 2; Windows,
  WASM and JS are tier 3), and one claim page each for
  [deploys](docs/claim-deploys.md), [capabilities](docs/claim-capabilities.md),
  [performance](docs/claim-performance.md) and
  [refinement types](docs/claim-refinements.md), each with its assumptions, what it does
  not claim, and which CI checks defend it and which are still planned. A new
  [Capability Threat Model](docs/capability-threat-model.md) replaces three pages that
  disagreed: `docs/capability-audit.md` no longer says an undeclared builtin call is only a
  warning (it has been an error since 2026-08-06), and the provable-sandbox design notes
  that per-function grants were removed on 2026-08-13.

- **Every public stdlib function is documented, and about 1,500 doc examples have a Try it
  button.** 468 undocumented public functions now have docs, and 1,240 more functions gained
  `march>` examples that are checked natively and in the browser REPL. 87 modules (was 32)
  opt into Try it. Functions that do IO, use the network or actors, or live in modules the
  browser cannot load get plain usage snippets instead. Several wrong docs were corrected
  along the way, such as the stability claims for the sorts.

- **An upgrade guide for 0.6.0.** `docs/upgrading-to-0-6-0.md` covers the two
  security fixes, the `send_wrong_actor` check and the RFC 3986 `Uri` changes. The
  landing page and the toolchain examples now name v0.6.0.

- **The refinement-types page makes the October features easy to find.** It has a dated
  "What's new" box, contents entries for relational element refinements, one- and
  two-argument abstract refinements, fold accumulator invariants and module-wide
  inference (`march --refine-infer` / `forge refine --infer`), a table of the new surface
  forms under Syntax, and a Limitations list of the known gaps (for example `Map`'s
  other functions and `HashMap.filter` carry no element fact yet). The skip-reason table
  now lists all sixteen reasons, and the page says that `fn (a, a) -> …` is a
  `duplicate_binder` type error. The relational element refinements section and the
  two-argument abstract refinements part are rewritten around one running example, with
  checked examples for building, matching and projecting an entry.

## [0.6.0] - 2026-10-17

### Highlights

0.6.0 is a short release: two security fixes and two small breaking changes,
three days after 0.5.0. Read **Security** and **Breaking changes**
before upgrading. Every change is listed in full in the sections after them.

- **Better crash reports.** In a compiled program, the crash report now gives
  the file and line of the `panic` that caused it. Each backtrace frame names
  the function as written in the source, on Linux as well as macOS.
  `Diagnostics.observe_crashes` lets a program see every crash that nothing
  else handles.
- **The in-browser REPL can use the whole standard library.** It also handles
  deep recursion, and it downloads a tenth as much as before. 249 runnable
  "Try it" examples on the stdlib pages are checked in CI against the native
  REPL and the browser REPL.
- **The release archives can compile programs again.** The v0.5.0 archives
  were missing the vendored C libraries.

### Security

- **`Uri.merge_strict` rejected too few `..` segments.** A reference such as
  `../../../etc/passwd` merged against a base path `/a/b/c` was accepted. If
  you use `merge_strict` to check untrusted relative references, upgrade.
- **`HttpTransport.request` checks the certificate on `https://` URLs.** The
  simple request functions used to reject `https://` URLs or risk sending them
  over a plain socket. They now use TLS with SNI and verify the certificate.

### Breaking changes

- **Sending one actor's message to another actor's pid is a compile error**
  (`send_wrong_actor`) when the pid's state type is a different record from the
  state of the actor that owns the message. Code that compiled under 0.5.0 and
  dropped the message silently at run time is now rejected. Send it to the
  right pid. Two actors that share a handler name are caught by the same check.
  Rename one of the handlers.
- **`Uri.parse` and `Uri.merge` follow RFC 3986 for relative references.** A
  string without a scheme is now read as a path unless it starts with `//`, so
  `Uri.parse("../d")` no longer has host `..`. Merging keeps the leading `/`.
  Code that relied on the old results gets different values.

### Known issues

The four known issues listed for 0.5.0 are still open:

- **Each hot deploy keeps one patch `.so` mapped until the node restarts.**
- **A coordinated type-signature change can still reach a running caller.**
  Restart for signature changes.
  (`specs/todos/2026-10-13-hcr-coordinated-sig-change-running-caller-frame.md`)
- **Two nested types with the same short name are one type to the checker.**
  Give the types distinct names.
  (`specs/todos/2026-10-13-same-short-name-nested-types-unify.md`)
- **A function from another module used as a value fails to compile.** Wrap it
  in a lambda (`fn xs -> List.length(xs)`).
  (`specs/todos/2026-10-13-other-module-fn-as-value-undefined-symbol.md`)

### Added

- **Compiled crash reports say where the panic was called, and name every frame.**
  A `Diagnostics` crash report's `location` is now the exact file and line of the
  `panic`, `todo` or `unreachable` call in compiled programs, as it already was
  interpreted. Compiled backtrace frames now give each function's source name (no
  more `$lam0__…`), file and definition line, on Linux as well as macOS: the
  compiler records the program's functions in a small table instead of relying on
  the symbols the executable exports.

- **"Try it" on 33 stdlib pages, and documentation examples are now checked.**
  String, Json, Uri, Crypto, Regex, Task, Vault and 12 more modules have runnable
  examples (249 "Try it" examples in all, up from 107), and every one is verified
  against both the native REPL and the in-browser REPL in CI, so a documented result
  that drifts from the real one fails the build. Converting them corrected dozens of
  wrong examples (for instance `String.split(s, "")` splits into bytes, not "returns
  the whole string"). Actor's module example is now a complete program you can run.
  The browser REPL now accepts `|>` pipes and a `main` that takes `Cap(IO)`.

- **`Diagnostics`: observe crashes the runtime owns.** `Diagnostics.observe_crashes`
  registers a callback that receives a `CrashReport` (kind, message, backtrace, the
  failing actor, and context) for every panic nothing handles, in an actor or in
  `main`, before the supervisor restarts the actor or the process exits.
  `Diagnostics.with_context` attaches request or job metadata that the report
  carries even though the panic unwound past it. Observers run in registration
  order. One that panics is skipped without changing the outcome, and a panic caught
  by `__try_call` or a test is not reported. Interpreted backtraces have file and
  line; compiled ones name the functions on macOS (Linux needs a later change), with
  no line yet. It is vendor-neutral: an error-service integration such as Sentry
  is a package built on top.

- **"Try it" on the stdlib API reference.** On march-lang.org/docs/stdlib, the
  examples of the modules that opt in (`-- doc: try` in the module header, or a
  ```` ```march try ```` fence) have a **Try it** button that opens a REPL sidebar and runs
  the example, one result per line as in the docs. The REPL loads on the first click,
  so the pages stay fast. 107 examples across 14 modules (List, Option, Http, Path,
  HashMap, ...) to start. `forge doc --try-it` generates the same buttons.

- **The in-browser REPL can use the whole standard library, and reports what it
  can't do.** Modules load the first time you use them, so `HashMap`, `Uri`, `Csv`
  and about a hundred others now work on the playground and cookbook pages (197 of
  the 210 stdlib doc examples run in the browser, up from 63) without slowing startup.
  Modules that need a file system, sockets, processes or the cluster runtime say so
  instead of failing obscurely. The browser REPL's `Int` is 32-bit, so a result that
  would overflow it is reported, where it used to silently give a wrong answer
  (`65536 * 65536` was `0`).

- **The in-browser REPL can clear the screen without forgetting your definitions.**
  Every REPL on the site (playground, landing page, cookbook sidebar) has a **clear**
  button, `:clear` and Ctrl+L, which wipe the screen and keep what you defined, next to
  **reset**, which also forgets it. The cookbook sidebar previously had neither.

### Changed
- **The stdlib API reference loads much faster.** Every page inlined a sidebar listing
  all 2,964 entries of every module, and fetched the whole search index on load, so a
  page was about 400 KB plus a 424 KB index download. The sidebar now lists the modules
  and expands only the one you are reading, and the search index loads when you first
  open search: a page is now 60-95 KB (8.3 MB for all 133 pages, down from 50.5 MB).

- A compiled program whose scheduler is about to resume a corrupt or freed
  green-thread context now stops with a `march_sched[BUG]: dispatch of pid N
  ... with a context it did not save` line (the pid, the saved stack pointer
  and the stack bounds) and aborts. Before, that switch blocked SIGSEGV
  through the garbage signal mask and then faulted, so the process died with
  only the shell's `Segmentation fault (core dumped)` and no `march: fatal`
  line, which is all one CI crash of `native_run_until_idle_ping_pong` left.

### Fixed

- **`HttpTransport.request` now sends HTTPS over verified TLS.** The convenience
  request APIs no longer reject `https://` URLs or risk sending them over a plain
  socket: they establish TLS with SNI and certificate verification, then issue the
  HTTP/1.1 request. The lower-level APIs that take a raw file descriptor still
  reject HTTPS, because a descriptor alone does not establish a TLS session.

- **Sending one actor's message to another actor's pid is a compile error when the
  types show it.** `send` didn't relate the message to the target, so
  `send(logger_pid, Increment(1))` compiled and the message was silently dropped at run
  time. When the pid's state type is a different record from the message's actor's
  state, it is now rejected (`send_wrong_actor`). Two actors whose state records have
  the same shape still can't be told apart, since a pid's type is its actor's state.
  The same error catches two actors sharing a handler name, where a bare name picks
  one of them and compiled and interpreted code used to disagree.
- **`forge test` no longer segfaults calling an interface impl through a generic
  helper.** Under `--test`, an `impl` method that read the clock, the console or any
  other mockable operation was compiled with a hidden capability parameter, but a
  call reaching it through the interface from generic code didn't pass one, so every
  argument shifted by one (#708). Such impls are now compiled without the hidden
  parameter; an operation inside one runs on the real capability rather than a
  `with_cap` mock.
- **A session that forms just as a peer node dies no longer outlives it.** For a
  moment after a node's connection closed, the cluster node still handed out that
  connection to sessions being set up. A session that linked to it in that window
  never heard that the node was gone and waited for that link's end for ever,
  so a SIGTERM drain on its node ran to its hard deadline and exited 1. A dead
  connection is now no longer handed out from the moment it closes.

- **`march --jit` names the program's own atoms.** `to_string(:zz)` printed
  `:<atom>` under `--jit` (both the ORC and clang backends) for any atom the stdlib
  does not itself use; it now prints `:zz`, as the interpreter and `--compile` do.

- **Security: `Uri.merge_strict` now rejects every path traversal above the root.**
  The guard was off by one: the empty segment before a path's leading `/` absorbed one
  `..`, so against a base path `/a/b/c` the reference `../../../etc/passwd` was accepted
  as `Ok(...)` with path `etc/passwd`, and only four `..` were rejected. Any `..` with
  nothing left to remove is now an `Err`, including one in an absolute-path reference
  (`/../etc/passwd`). If you used `merge_strict` to vet untrusted relative references,
  upgrade.
- **`Uri.merge` keeps the leading `/` (RFC 3986 §5.2.4).** Surplus `..` segments turned
  the path relative, so `../../../x` against `https://example.com/a/b/c` gave
  `"https://example.comx"`; it now gives `"https://example.com/x"`. Merging also follows
  §5.2 in the remaining cases: dot segments are removed from absolute-path and
  network-path references too, a base with an empty path merges as `/` + the reference,
  and a fragment-only reference keeps the base query.
- **`Uri.parse` reads relative references per RFC 3986 §4.2.** A scheme-less string not
  starting with `/` was split as `host/path` (`Uri.parse("../d")` had host `..`), and
  `//other.com/x` put everything in the path. Now only `//` introduces an authority:
  `../d` and `a/b` are paths, `//other.com/x` has host `other.com` and path `/x`, and
  `Uri.to_string` writes such a reference back with its `//`. A `://` inside a path or
  query (`/go?to=http://x`) no longer makes a scheme.
- **The in-browser REPL no longer runs out of stack.** On the playground, cookbook and
  "Try it" pages, `List.map` over more than about 200 elements, or a recursive function
  a few hundred calls deep, failed with "Maximum call stack size exceeded". The
  interpreter is now compiled so that recursion depth is limited by memory: a
  100,000-element list or 100,000-deep recursion works. Call-heavy code runs about a
  third slower, and the download is about 10% smaller. Also, defining a function after
  `main` no longer runs `main` again.

- **`march repl` no longer crashes on an atom inside a value.** `Err(:invalid)`,
  `Some(:a)`, `[:a, :b]`, `(:a, 1)` and `UUID.parse("not-a-uuid")` killed the REPL with a
  segmentation fault; they now print. A `None` inside a list or tuple prints as `None`
  instead of `null`. Compiled programs had a related bug: an `Option(Atom)` built from a
  literal atom (`Some(:a)`) did not match its own atom (`x == :a` was `false`) and printed
  as `Some(:<atom>)`. Both are fixed.

- **`march repl` prints negative numbers inside lists, options and tuples correctly.**
  The native REPL showed `[-1, 2]` as `[9223372036854775807, 2]` (and likewise
  `Some(-1)`, `(-1, 2)`, `NativeArray.to_list_i32(...)` with a negative element). Only
  the printed result was wrong; the values themselves, `--compile` and the interpreter
  were always right.

- **The in-browser REPL downloads a tenth as much, and the Tetris playground compiles
  again.** The REPL on the playground, cookbook and landing pages loaded a 19.7 MB
  development build (2.1 MB compressed); it is now a 1.9 MB release build (408 KB
  compressed). Editing the Tetris playground and pressing Run had failed on every
  program since at least July; it compiles and runs again. Both are now rebuilt
  automatically after every compiler or stdlib change, which also fixes `Json` in the
  REPL (`unbound variable: string_byte_at`).

- **A topology app under continuous session traffic stops on Ctrl-C/SIGTERM.**
  A node whose hook tasks kept starting sessions (an `initiate_<Role>` loop) never
  drained: each new session kept the count above zero, so every drain ran to its
  `[drain] hard_ms` (120 s by default) and exited 1, and under `forge run
  --processes` the pools after it then waited their own turn. A draining node now
  starts no new session (`initiate_<Role>` returns `Err(Left("draining"))`); a
  session whose initiating node died while it formed now gives up once the cluster
  declares that node dead instead of holding its slot for 30 s; and a second
  SIGTERM or SIGINT to a draining node stops it at once, as documented, instead of
  being ignored.
- **The release archives include the vendored C libraries, so a prebuilt
  `march` can compile programs again.** The v0.5.0 archives bundled
  `runtime/*.c` and `*.h` but not `runtime/third_party/` (BLAKE3 and mimalloc,
  vendored since 0.4.0), so every `march --compile` from a prebuilt toolchain
  failed with `'third_party/blake3/blake3.h' file not found`. The packaging now
  copies the directory, and the release build compiles and runs a program with
  each packaged archive before publishing. The v0.5.0 archives were rebuilt
  and replaced; reinstall with `forge toolchain install v0.5.0`.

### Documentation

- **Overstated claims on the landing page and in the docs are corrected.** The
  tree-transform benchmark showed numbers no recorded run produced (Rust 9977 ms,
  "19x faster than Rust"); it now shows the `bench/RESULTS.md` medians (March 579 ms,
  OCaml 3670, Rust 4902, Elixir 2369) and says the other languages allocate a fresh
  tree each pass. The README's FBIP table and its "7x faster than C" claim (no C
  program is benchmarked) are replaced the same way. The landing page no longer calls
  actors "typed" or says shared mutable state is a compile error, since `send` does not
  check a message against the target actor. The hot-reload page gains a "Current limitations" section listing the open issues,
  and the memory-model chapter describes the march-lean oracle instead of calling it
  "not started".
- **`Actor.call`'s timeout under the interpreter is described accurately.** The actors chapter said the timeout is real on both backends. Compiled, the caller stops waiting at `timeout_ms`; under the interpreter the handler runs to completion first and a late reply is then discarded and reported as `Err`, so a slow handler still blocks the caller for its full duration. The chapter now says so, in the call section and in the list of backend differences.

- **The stdlib API reference has syntax highlighting, and Http is documented.**
  Code examples on march-lang.org/docs/stdlib/ were plain monochrome text: the
  generator only coloured fences tagged with a language, and the pages shipped
  no highlight colours. Examples are now highlighted as March in both themes.
  The paragraphs after the first in many doc comments no longer render as code
  blocks, and the comment above a `type` now appears as its description. Every
  `Http` function and type has a description, and its examples are now run in CI.

[Unreleased]: https://github.com/march-language/march/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/march-language/march/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/march-language/march/releases/tag/v0.1.1
