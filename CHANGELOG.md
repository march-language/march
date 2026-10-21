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

### Changed

- **Stdlib: the collection folds declare their types.** `Map.fold(m : Map(k, v),
  acc : b, f : b -> k -> v -> b) : b`, likewise `HashMap.fold`; `Set.fold(s :
  Set(a), acc : b, f : b -> a -> b) : b`; `Array.fold_left(v : PVec(a), acc : b,
  f : b -> a -> b) : b`; and the callback of `RRB.fold` / `RRB.fold_left` (`f : b
  -> a -> b`), `Deque.fold_left` (`f : b -> a -> b`) and `Deque.fold_right` (`f :
  a -> b -> b`), which were unannotated. These are the types the folds already
  inferred, so well-typed callers are unaffected and nothing runs differently.

### Fixed

- **`--refine-suggest-all` no longer proposes a precondition that breaks a caller.** The
  suggester re-checked only the target function, so for `go(n : Int) = need_pos(n)` with
  `caller() = go(0 - 5)` it proposed `n : {Int | _ > 0}` and reported "discharges all", although
  applying it turns `caller` into a refinement violation. Probes now include every caller in the
  unit; such a proposal is reported as `refused (caller-violation)` with the call it would break.
  A hypothesis is also judged site by site (it must prove something, break nothing and create no
  violation), and one that makes the parameters unsatisfiable is rejected.
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

- **An upgrade guide for 0.6.0.** `docs/upgrading-to-0-6-0.md` covers the two
  security fixes, the `send_wrong_actor` check and the RFC 3986 `Uri` changes. The
  landing page and the toolchain examples now name v0.6.0.

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
