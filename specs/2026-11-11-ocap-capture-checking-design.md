# Capture checking: the static layer of object capabilities

**Date:** 2026-11-11
**Status:** approved by the owner 2026-11-12
**Phase:** 8 of `specs/2026-11-10-object-capability-design.md` (called "the ocap design"
below; `§n` without a document name means a section of the ocap design). Implementation
depends on phase 4 (run-time authority). This document does not.
**Builds on:** the ocap design §5 (function values), §6 (handles), §13 (the surface the
owner agreed to), §21 (module-level code), and the existing per-function reach solver
(`lib/caps/cap_rows.ml`, `check_fn_bounds` in `lib/typecheck/typecheck.ml`).

The owner asked for the draft without a question round, so every decision here is
**(my call)** unless it is marked **(owner)**, which means the owner already decided it in
the ocap design. §17 lists my calls for the owner to check, most important first.

```march
mod Weather do
  needs IO.NetConnect

  type Client = Client(fetch : String -> Result(Forecast, Error))

  -- A public signature says what its result captures. Parentheses are needed, because a
  -- trailing `needs` on a header is the function's own clause (§4.3).
  fn new() : (Client needs IO.NetConnect("api.weather.com/v1/")) do
    Client(fn city -> HttpClient.get_json("https://api.weather.com/v1/" ++ city))
  end
end

mod Report do
  needs IO.Console

  -- `print` calls nothing it was handed, so it lists no capture variable.
  fn print(c : Client needs c0) : () do
    match c.fetch("oslo") do              -- error: `print` calls `c.fetch`, which may use `c0`
      Ok(f) -> println(Forecast.show(f))
      Err(_) -> println("no forecast")
    end
  end
end
```

The second function is wrong on purpose. `Report.print` calls a function it was handed, so
its own clause must say that calling `print` may use what `c` carries: `fn print(c :
Client needs c0) : () needs c0`. §11 shows the message.

---

## 1. Why

Phase 4 makes the run-time rule complete. A function value runs under the authority it
captured where it was made (§5), so passing a closure never fails, and nothing a closure
does is charged to whoever calls it. That is the right run-time rule, but it is invisible.
Reading `Report.print(weather)`, nobody can tell that `weather` reaches the network, or that
`print` will use that reach. A closure that captures a scoped file handle can outlive the
handle, and you only find out from an `Err(Closed)` at run time.

The static layer makes authority visible in types and turns what the compiler can see into
build errors (owner: "acceptable", with `needs c` on public higher-order signatures):

- **Visibility.** Every function value, and every value that holds one, has a type that
  says what it can reach: `Client needs IO.NetConnect("api.weather.com/v1/")`. Hover,
  `--dump-captures` and `march query` show it.
- **Honest signatures.** A public higher-order function says in its signature that
  calling it runs what it was handed. A public function that hands out a capturing value
  says what the value can reach.
- **Escape.** A scoped handle (`File.with_open`'s `h`) cannot leave its callback, by
  itself or inside a closure or a data structure (§13). This is the one class of bug that
  the static layer catches and the run-time layer only reports late.

The static layer never changes what a program does. It erases before lowering, and the
run-time rule stays complete without it (§13: "the run-time rules above are complete on
their own").

## 2. Goals, non-goals, anti-goals

**Goals**

- Capture sets on function types and on values that hold function values or scoped
  handles, written in the scope language the rest of the design uses.
- Inferred everywhere except public signatures (owner). A bare type in a public
  signature means "captures nothing" (owner).
- Sound: a value's static capture set covers everything the value can do when called,
  under the phase 4 rule. When the types say a value reaches only `IO.FileRead("./data/")`,
  it does not reach anything else.
- Scoped-handle escape is a build error in every mode (`--check`, interpreter, REPL,
  `--compile`, JS), as phase 3 established for the other checks.
- The stdlib's higher-order functions carry `needs c` in the same change that turns the
  public-signature rule on (§17).

**Non-goals**

- Removing run-time checks. Computed scopes, launcher narrowing and refusals stay at run
  time (§13 "What stays at run time"). Using static sets to skip storing a captured
  authority is allowed (§10.3) but is optional and not part of this phase.
- Tracking authority reached *through a pid*. A pid is the right to send (§7), and the
  actor is its own principal. Holding a pid adds nothing to a capture set.
- Tracking ordinary handles. An open `File.Handle` is authority over one resource and is
  checked when it is opened (§6). Only *scoped* handles are tracked (§7).
- Effect polymorphism for anything but capture. This is not an algebraic-effects system.

**Anti-goals**

- A type that claims less than the value can do. One unsound rule makes every type a
  guess.
- Annotations on private functions, locals or lambdas. Inference must cover them, or the
  layer costs more than it gives.
- Different answers in different modes. The check runs once, in the typechecker, before
  any backend.
- Capture-set parameters on type declarations (`type Client(c) = ...`). The owner's
  rule is that the set attaches to the value's type (§13, ocap §19 item 9).

## 3. What a capture set is

A **capture set** is a finite set of three kinds of element:

| Element | Written | Means |
|---|---|---|
| A scope | `IO.FileRead("./data/")`, `IO.NetConnect`, `IO.Console` | the value can perform operations inside this scope |
| A tracked name | `h` (a scoped parameter) | the value holds the scoped handle `h`, directly or inside something it holds |
| A capture variable | `c`, `c0` (any other lowercase name) | whatever the value bound to `c` carries; quantified like a type variable |

- **Scopes** are the ocap scope language unchanged (§8): every kind, every scope form,
  host, path, method, prefix and limit arguments. Two scopes of one kind combine by the
  existing union, and one set covers another by the existing covering relation
  (`lib/caps/cap_scope.ml`, the one `needs` checks use today).
- **The empty set** is written by writing nothing: a bare `a -> b` captures nothing.
  `needs ()` is accepted as an explicit spelling of it.
- **The full set** is `needs IO`, the root of the existing lattice: any authority at all.
  It covers every scope. It does **not** cover tracked names: no set covers `h` except one
  that names `h` or a variable bound to something that does. That one rule is what makes
  escape checking work (§7).
- **What a set means.** A value of type `T needs S` can, when it is called or when
  something it holds is called, perform only operations inside `S`, and touch only the
  scoped handles named in `S`. The set is an upper bound. The value may do less, either
  because its captured authority was narrower at run time or because a refusal stops it.

What a capture set does **not** contain: pids, `Vault(v)` handles, ordinary handles, scope
values (`Scope` is data that grants nothing, §8), proof capabilities.

## 4. Where capture sets live in types

### 4.1 Function types

```march
String -> () needs IO.FileWrite("./out/")       -- captures a write scope
a -> b needs c                                   -- captures whatever c is
() -> String needs h                             -- holds the scoped handle h
(Int, Int) -> Int                                -- captures nothing
```

`needs` binds to the nearest arrow: `a -> b -> c needs S` is `a -> (b -> c needs S)`.
For a function whose *result* carries a set, parenthesise the result:
`a -> (Client needs S)`.

### 4.2 Values that hold function values

The set attaches to the value's type, not to a type parameter (owner, ocap §19 item 9):

```march
type Client = Client(fetch : String -> Result(Forecast, Error))

let c = Weather.new()     -- c : Client needs IO.NetConnect("api.weather.com/v1/")
let f = c.fetch           -- f : String -> Result(Forecast, Error) needs IO.NetConnect("api.weather.com/v1/")
```

- **In a type declaration, a bare arrow in a field captures the enclosing value's set**,
  not the empty set. `Client` is declared once, and each `Client` value says what its own
  `fetch` captures. Building `Client(g)` gives `Client needs S` where `S` is `g`'s set;
  reading `.fetch` from a `Client needs S` gives a function `needs S`.
- A field may write an explicit set: `type Sink = Sink(write : String -> () needs IO.Console)`.
  Then every `Sink` value's `write` captures at most `IO.Console`, and `Sink` without
  `needs` is enough in signatures. Building one from a closure that reaches more is an
  error (§8.2).
- **Type arguments carry their own sets.** `List(String -> () needs IO.Console)` is a list
  of functions that each capture at most `IO.Console`. The list value itself carries no
  extra set: the set lives in the argument. `Option(Client needs S)` is likewise.
- **A record or tuple value's set** is the union of what its fields' types put at top
  level: `(f, 1)` with `f : () -> () needs S` has type `(() -> () needs S, Int)`; nothing
  is lifted out of the components.
- Nesting is always the same rule: a value's top-level set covers what its own declared
  fields hold; component types say the rest.

### 4.3 Function signatures and the function's own clause

A header has two places a set can appear, and they mean different things:

```march
fn map(xs : List(a), f : a -> b needs c) : List(b) needs c
fn new() : (Client needs IO.NetConnect("api.weather.com/v1/"))
```

- **Inside a parameter or result type**, `needs` is a capture set (4.1, 4.2).
- **A trailing `needs` on the header** is the function's clause, as today. The ocap
  design gives its concrete scopes a run-time meaning (a limit around the function, §3,
  §4), which this design does not change. A capture variable or tracked name in the
  clause has **no run-time meaning**: it says that calling this function may run what the
  named value carries. `map ... needs c` says that calling `map` may use `c`, because
  `map` calls `f`.
- **A clause that lists only capture variables and tracked names sets no limit.**
  `fn map(...) : List(b) needs c` is unlimited in its own reach, exactly like a `map` with
  no clause today. To limit the function's own reach as well, write the concrete scopes
  next to the variables: `needs IO.Console, c`, or `needs (), c` for "no operations of its
  own". (My call. The alternative, "a clause with only variables means `needs ()` plus the
  variables", would add a run-time limit to every migrated higher-order function. §17
  item 2.)
- A result type's own set needs parentheses because the trailing `needs` is already the
  clause. When a body returns a capturing value from a public function whose result type
  is unparenthesised, the diagnostic (§11.3) says to add parentheses.

### 4.4 Handles

Ordinary handle types (`File.Handle`, `Socket`, `Listener`, `Process`, `File.Dir`) carry
no set. A **scoped** handle is a parameter marked `scoped` in a callback type:

```march
fn with_open(path : String, mode : Mode, body : scoped File.Handle -> r needs c)
    : Result(r, FileError) needs IO.FileRead, IO.FileWrite, c
```

Inside the callback, the parameter (say `h`) is a tracked name, and every value built from
it carries `h` (§7). `scoped` is a new keyword, valid only on the parameter of an arrow type
(parser, tree-sitter grammar, keyword allowlist).

## 5. Public signatures and inferred ones

| Where | A bare arrow or data type means | Sets are |
|---|---|---|
| Public function signature (`fn`), interface method signature | captures nothing (owner) | written |
| Field in a type declaration | the enclosing value's set (4.2) | inherited, or written |
| Private function (`pfn`), local `let`, lambda | — | inferred |
| Parameter of handle type in a public signature | borrows any tracked name; may not let it escape (§7.3) | written to let it escape |

- **Public means exported**: a `fn` (not `pfn`) in a module, and every method of a public
  interface. The REPL and test modules are treated as private: everything is inferred.
- **Capture variables are implicitly quantified** at the signature, like type variables.
  `fn compose(f : b -> d needs p, g : a -> b needs q) : (a -> d needs p, q)`.
- **A parameter name in a set means that parameter's set**: `fn wrap(f : () -> () needs c)
  : (Box needs f)` is the same as `needs c`. This is the form the ocap design wrote
  (`() -> String needs h`), and it is how a signature talks about a handle parameter (§7.3).
- **Private functions generalise** their inferred capture variables, so a private
  higher-order helper used with two different closures checks both. **Local `let`s do
  not generalise** captures (my call): a local function value has one inferred set, the
  union of its uses' requirements. This matches the way locals behave elsewhere and
  keeps inference simple.
- **A public signature may write more than the body needs.** `fn new() : (Client needs
  IO.NetConnect)` is accepted for a body that only reaches one host. Callers see the
  wider set.

## 6. Inference

### 6.1 What a function value's set contains

Where a function value is made, its set is the **reach** of what it can run, narrowed by
the **static authority** at that point:

- **Reach** is the union of:
  - the operations its body performs, as the existing reach solver computes them today
    (literal targets give scoped elements, `IO.NetConnect("api.weather.com/v1/")`;
    computed targets give the unscoped kind, `IO.NetConnect`);
  - the reach of every named function it calls directly, transitively, each narrowed by
    that function's concrete clause (the solver already does this);
  - the set of every value it captures (a captured closure, a captured `Client needs S`,
    a captured scoped handle `h`);
  - the set of every function value it calls that is one of its own parameters (that
    parameter's type's set, often a variable);
  - the set of every function value it creates (an inner lambda, a partial application),
    and the reach of every task or actor it spawns, because those run under its captured
    authority (§5, §7).
- **Static authority at a point** is the meet of the literal limits lexically around it:
  the concrete part of the enclosing function's clause, every enclosing `restrict` with a
  literal scope (phase 5), and the package's grant (phase 6). With none of these it is
  `IO`, and the set is the reach.
- Tracked names and capture variables are never narrowed by static authority.

The three ways a value is made (§5) all follow this:

- **A lambda**: where the `fn` is evaluated.
- **A named function used as a value** (`List.map(paths, File.read)`): where the name is
  used. Reach is the function's own reach narrowed by its clause. `File.read` as a value
  has type `String -> Result(...) needs IO.FileRead`.
- **A partial application**: where it is formed, plus the sets of the captured arguments.

**Module-level code** (§21): a function value created by a top-level `let` captures
nothing at run time and behaves as a named function. Its static set is its reach, as for
a named function used as a value.

### 6.2 Values returned by calls are not narrowed at the call site

The ocap design's §13 shows `Weather.new()` called inside `restrict
IO.NetConnect("api.weather.com/v1/", methods(get))` with the type
`Client needs IO.NetConnect("api.weather.com/v1/", methods(get))`. **This design does not
derive that type**, and I think it should not (my call, §17 item 1):

- The narrowing would be sound only if every capturing value a call returns had been
  created during the call. A function can also return a value it was handed, read from a
  `Vault`, or received in a message. Such a value keeps the authority it was created
  with, which can be wider than the call site's (§5: values brought into a `restrict`
  keep theirs).
- So the type of `Weather.new()` is what `Weather.new`'s signature says,
  `Client needs IO.NetConnect("api.weather.com/v1/")`, whatever surrounds the call. The
  run-time narrowing to GET still happens; the type just does not show it.
- Narrowing *does* apply to values created lexically inside a literal `restrict` (6.1),
  because those certainly captured under it:

  ```march
  let f = restrict IO.FileRead("./data/") do
    fn p -> File.read(p)        -- f : String -> Result(...) needs IO.FileRead("./data/")
  end
  ```

- Tooling may show the extra run-time bound as a note ("created inside `restrict` at
  line 28; at run time at most `IO.NetConnect(..., methods(get))`") without putting it in
  the type. That is the builder's.

### 6.3 Solving

- **Shapes are unchanged.** Hindley-Milner unification decides `a -> b` against `a -> b`
  exactly as today. Capture sets are a second layer: every arrow and every data type in a
  value position gets a set variable, and every flow point (argument to parameter, body
  to result, value to annotated `let`, field to constructor, branch to `if` or `match`
  result, element to list literal) adds an inclusion constraint *source set ⊆ sink set*.
- Constraints are solved for the least solution: each variable is the union of its lower
  bounds. Concrete upper bounds (written signatures, explicit field sets, `IO`) are then
  checked against the solution. Union and covering on scopes are the existing lattice
  operations; there is no intersection in the constraints except the static-authority
  narrowing at creation sites, which is a constant.
- **Variance**: function parameters are contravariant and results covariant; arguments of
  immutable declared types (`List`, `Option`, records, user ADTs) are covariant; arguments
  of `Vault`, `Pid`, `Chan`, and any other type through which a value can be both written
  and read, are invariant. The full table per builtin type is the builder's.
- The reach solver already computes per-function reach, parameter dependencies (`deps`)
  and untraceable calls (`unknown`). Capture sets replace `deps` and remove the need for
  `unknown`: an untraceable value now has a type, and its type has a set. Whether the
  capture layer is built inside `cap_rows.ml` or beside it is the builder's.

## 7. Scoped handles and escape

### 7.1 The rule

Inside a callback whose parameter is `scoped`, the parameter is a tracked name `h`.

- `h` itself has type `File.Handle needs h`.
- Any value built from `h` carries `h`: a closure that captures it, a record or list that
  holds it, a closure that captures such a record.
- `h` is in scope only inside the callback. **A type that mentions `h` cannot be the type
  of anything outside the callback.** Since nothing outside can name `h`, and no set
  covers `h` except one naming it (§3), every escape is an inclusion failure:
  - returning it from the callback: the callback's result type `r` is chosen outside, so
    `r`'s set cannot contain `h`;
  - storing it in a `Vault` made outside: the vault's element type was fixed outside;
  - sending it to an actor: the pid's message type was fixed outside;
  - capturing it in a detached task or a spawned actor: their signatures require `needs IO`
    on the function they take (§9.2), and `IO` does not cover `h`;
  - capturing it in a closure that does any of these.
- Inside the callback, everything else is allowed: passing `h` to functions, building
  local data around it, awaiting a task that holds it.

### 7.2 Passing a scoped handle to a function

`File.read_line(h)` inside a `with_open` callback must work, and `read_line`'s signature
is `fn read_line(h : File.Handle) : ...`.

- **A bare handle-typed parameter in a public signature borrows**: it accepts a value
  carrying any tracked name, and the function's body is checked not to let the parameter
  escape (no result type, stored value, message or spawned closure mentions it). This is
  the default because nearly every function that takes a handle only uses it.
- To let it escape, the signature names it:

  ```march
  fn BufReader.new(h : File.Handle) : (BufReader needs h)
  ```

  A caller inside a `with_open` callback then gets a `BufReader needs h`, which cannot
  leave the callback either. A caller with an ordinary handle gets `BufReader needs ()`,
  because an ordinary handle carries nothing.
- The same holds for a data-typed parameter that can hold a handle.
- Private functions infer which handle parameters escape.

This is asymmetric with function-typed parameters, where bare means "captures nothing"
(owner). The difference is intended: a function parameter's set includes authority the
callee would *use*, which the owner wants written down; a handle parameter's set only
ever holds tracked names, and borrowing is almost always what is meant.

### 7.3 What is not covered

- Ordinary handles are not tracked. `let h = File.open(...)` followed by `File.close(h)`
  and a later use is still a run-time `Err(Closed)`. Linear handles are a non-goal of the
  ocap design.
- Only callback parameters can be scoped. There is no `scoped let`.

## 8. Checking: what becomes a build error

### 8.1 The rules

1. **Escape** (§7): a value carrying a tracked name reaches a position outside the name's
   callback.
2. **Capturing value into a narrower position**: a value whose set is not covered by the
   position's set. The common case is passing a closure that captures something to a
   public parameter typed with a bare arrow, which means "captures nothing". Also: a
   closure into a field with an explicit set, an element into a `Vault` whose element type
   has a smaller set.
3. **A public signature that says too little**: a public function returns a value whose
   inferred set is not covered by its declared result type (`Weather.new` declares one
   host and the closure reaches two).
4. **An unlisted call**: a public function calls a function value whose set contains a
   capture variable or tracked name, and its clause does not list it. `map` calls `f :
   a -> b needs c`, so `map` must say `needs c`. Concrete scopes in a called value's set
   are not charged to the clause: a function value runs under its own authority (§4),
   and its concrete reach was already fixed where it was made.

Rule 4 is the owner's "a public signature must write this", made checkable. It rejects
nothing at run time and adds no limit (4.3).

### 8.2 What stays allowed

- Calling any function value you hold, under any `restrict`. A closure brought into a
  `restrict` keeps its outside authority (§5), and its type says so.
- A public function writing a wider set than its body needs.
- A closure with any concrete reach passed to a parameter typed `needs c`, or `needs IO`.
- Ordinary handles anywhere.

### 8.3 What is checked against what

The static set never weakens an existing check. The phase 3 ceiling and per-function bound
checks run as before; the static layer adds the four rules above. A closure's reach is
still checked against its defining module's `needs` line for the module's own operations
(§4).

## 9. Actors, tasks, tables, messages, interfaces

### 9.1 Actors and pids

- **A pid carries no set**, and sending to one is never a capture error unless the message
  carries a tracked name (§7).
- **A message type is a type declaration**, so a bare arrow in a message field captures
  the message value's set (4.2). A pid's message parameter is implicitly `needs IO` on
  scopes (my call): sending a closure to an actor hands over its authority, which is
  allowed (§7, actors are principals). Tracked names still cannot be sent.
- An actor's state is checked like any data.

### 9.2 Tasks

- `Task.async(f : () -> a needs c) : (Task(a) needs c) needs c` (shape; the stdlib's
  names are the builder's). The task value carries `c` because it holds `f`, so a task
  over a scoped handle cannot leave the callback but can be awaited inside it.
- A detached spawn takes `f : () -> () needs IO`. It accepts any authority and no tracked
  name.

### 9.3 Vault tables

`Vault(v)` is invariant in `v`. A table whose element type is a function type stores
values of that set: `Vault(Event -> () needs IO.Console)`. A table created by name has
its element type from its creation, as today (`Vault(v)` is already typed).

### 9.4 Interfaces

- An interface method's signature is public: bare arrows capture nothing, and capture
  variables are written. The existing `md_needs` clause on interface methods takes capture
  variables the same way as a function clause.
- An impl is checked against the method signature with the usual rules: its result may
  capture at most what the method declares.
- Interface method calls are direct calls (§21), so a generic function calling `show(x)`
  needs no capture variable for it.

## 10. Interaction with the run-time layer (phase 4)

### 10.1 The invariant

For every function value `v` with static set `S`, every operation `v` performs at run time
is inside `S`, and every scoped handle it touches is named in `S`. Phase 4 decides whether
the operation is *allowed*. The static set says only what it could *attempt*.

This holds because `S` covers the value's reach, every way authority moves at run time is
covered by reach (direct calls, captured values, created values, spawns), and narrowing
happens only where the run-time authority is certainly at most the narrowing (6.1).

### 10.2 What stays at run time

Everything phase 4 does. Computed scopes in `restrict` and in scope values, launcher
narrowing (`--grant`, `MARCH_GRANT`), grants on computed targets, every refusal and its
`CapError`. Capture checking adds no run-time code and no run-time data.

### 10.3 Optional use by codegen

Phase 4 already lets a function value whose body reaches no capability operation skip
storing a captured authority (§5 "Cost"). A static set of `()` is the same fact in the
type. Codegen may use it. Nothing in this phase requires it, and the IR of every program
must be byte-identical with the capture layer on or off (`scripts/ir-oracle.sh`).

### 10.4 Erasure

Capture sets are erased before lowering. TIR, monomorphisation, defunctionalisation and
every backend are unchanged.

## 11. Error messages

Wording, slugs and codes are the builder's; these show the shape and the information each
message must carry. They follow the existing diagnostic style (`test/errors/`).

### 11.1 Capturing value into a pure parameter

```
-- CAPABILITY ---------------- src/app.march

`Cache.memo` takes a function that captures nothing, but this one captures `IO.FileRead`. [capture_into_pure]

12 |   let load = Cache.memo(fn p -> File.read(p))
                             ^^^^^^^^^^^^^^^^^^^^^
    It captures `IO.FileRead` because it calls `File.read` (line 12).
    `memo` is declared: memo(f : a -> b) : a -> b

help: if `memo` should accept functions that capture, its signature needs a capture variable:
      fn memo(f : a -> b needs c) : (a -> b needs c)
```

### 11.2 Scoped handle escapes

```
-- CAPABILITY ---------------- src/app.march

`h` cannot leave the `File.with_open` callback, but this closure captures it and is returned. [capture_escape]

20 |   File.with_open("log.txt", Read, fn h -> fn () -> File.read_line(h))
                                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^
    `h` is a scoped handle: `with_open` closes it when the callback returns.
    The closure captures `h` here (line 20).

help: read what you need inside the callback and return the data instead of a function that reads it.
```

Each escape route gets its own second line: "and is stored in the `Vault` `cache` (line
31)", "and is sent to `logger` (line 40)", "inside the `Reader` it builds (line 18)".

### 11.3 A public signature that says too little

```
-- CAPABILITY ---------------- lib/weather.march

`new` says its result captures `IO.NetConnect("api.weather.com/v1/")`, but the `Client` it returns reaches `IO.NetConnect("stats.example.com")`. [capture_exceeds_signature]

 9 |     Client(fn city -> report(city))
                ^^^^^^^^^^^^^^^^^^^^^^^
    `report` connects to "stats.example.com" (line 14).

help: widen the result type:
      fn new() : (Client needs IO.NetConnect("api.weather.com/v1/", "stats.example.com"))
```

The variant for an unparenthesised result type says: "`new`'s result type `Client` means
a `Client` that captures nothing. To say what it captures, write `(Client needs ...)`: a
trailing `needs` after the result type is the function's own clause."

### 11.4 Unlisted call

```
-- CAPABILITY ---------------- lib/report.march

`print` calls `c.fetch`, which may use what `c` carries (`c0`), but `print`'s needs clause does not say so. [capture_unlisted_call]

 6 |     match c.fetch("oslo") do
               ^^^^^^^
    fix (`forge fix` applies it):

 5 -   fn print(c : Client needs c0) : () do
 5 +   fn print(c : Client needs c0) : () needs c0 do
```

### 11.5 Every message

- Names the value, the set element that failed, and **why the value has it**: the call
  or capture that put it there, with a line. For a transitive reach, the chain, as the
  ceiling diagnostics print it today.
- Prints sets in source syntax, with tracked names by their source name and capture
  variables by the name in the signature (or `c1`, `c2` for inferred ones, never an
  internal name; the internals lint in `test/run_errors.exe` applies).
- Offers a machine fix where there is one obvious edit (adding a variable to a clause,
  widening a written set, adding parentheses).
- Has an `--explain` page.

## 12. Tooling

- **Hover and `march query`** show a value's type with its set. A value created inside a
  `restrict` also shows the run-time bound as a note (6.2).
- **`march --dump-captures FILE`** lists every function value creation site with its set
  and the reason for each element. It is the debugging tool for this layer.
- **Inlay hints** (LSP) may show inferred sets on `let`s; the builder's.
- **`forge audit`** may list, for each dependency, the capture variables in its public
  signatures: which of your function values it runs. That is a follow-up, not this phase.

## 13. With `restrict` and scope values (phase 5)

- A literal `restrict R do ... end` narrows the sets of values **created lexically**
  inside it to `reach ∩ R` (6.1). Values returned by calls inside it, and values brought
  in, keep their types (6.2).
- A `restrict` over a computed scope value narrows nothing statically.
- A `restrict` block's own type is its body's type.
- Scope values (`Scope`) carry no set and are not tracked; holding one grants nothing.
- `mock` (phase 7) blocks narrow nothing statically. A closure created inside a `mock`
  keeps the mock at run time; its static set is its reach.

## 14. With dependency grants (phase 6)

- A grant is part of the static authority (6.1) for every function value created in the
  granted package: its set is `reach ∩ grant`.
- A dependency's public signatures are checked against its body **without** its grant:
  the same package can be used ungranted, and its signatures must be true either way. So
  the grant only narrows inferred sets inside the package, and the consumer sees the
  dependency's signatures as written.
- Capture variables in a dependency's clauses are not charged to the grant: a callback
  you pass runs with your authority (§10). The grant check stays a check of the
  dependency's own reach, as phase 6 defines it.
- The grant set is already part of every cache key that can skip a check (§10), so the
  capture results are cached under it too.

## 15. Migration

- **Phase 8a and 8b add no new errors to existing correct programs** except real escapes
  of scoped handles (§16).
- **Phase 8c turns on the public-signature rule.** Every public higher-order function
  whose parameter or result carries a function value needs a capture variable, and every
  public function that returns a capturing value needs a written result set. The stdlib
  changes in the same PR: `List`, `Map`, `Seq`, `Enum`, `Option`, `Result`, `Task`,
  `HttpServer` handlers, `Check`, and every interface with a function-typed method.
- **`forge fix`** rewrites both: it adds `needs c` to function-typed parameters that
  receive capturing values and to the clause where the function calls them, and writes
  the inferred set on results. It writes inferred sets as they are, kind-level where the
  inference is kind-level. Rewrites never add a concrete scope to a clause, so no
  migration adds a run-time limit (4.3).
- **`### Changed`** CHANGELOG entry for 8c; `### Added` for 8a and 8b.

## 16. Phasing inside phase 8

Each step ships on its own; all of them wait on phase 4.

| Step | What | Errors it adds |
|---|---|---|
| 8a | Capture sets in the typechecker's types, inference, solving, erasure; hover, `march query`, `--dump-captures`; the soundness tests (§18) | none |
| 8b | `scoped` parameters, escape checking, `File.with_open` and the other scoped opens declared with `scoped` | escape (rule 1) |
| 8c | Public-signature rule: bare means "captures nothing", rules 2–4, the stdlib migration, `forge fix` | rules 2, 3, 4 |

8b before 8c because escape is the one check that catches a real bug class, and it only
needs inferred sets, not the signature rule.

## 17. My calls, for the owner to check

Most important first.

1. **No call-site narrowing of returned values** (6.2). The ocap design's §13 example type
   for `Weather.new()` inside a `restrict` is not derivable soundly, so types show only
   reach plus narrowing at creation sites. The run-time narrowing is unchanged and tooling
   may show it as a note.
2. **A clause with only capture variables sets no limit** (4.3). `fn map(...) needs c` is
   unlimited in its own reach. `needs (), c` limits it to nothing of its own.
3. **Bare handle parameters borrow** (7.2), unlike bare function parameters, which capture
   nothing (owner). To let a handle escape, the signature names it: `(BufReader needs h)`.
4. **Only scoped handles are tracked** (§3, §7.3), through a new `scoped` keyword on a
   callback parameter. Ordinary handles carry no set.
5. **The full set is `IO`**, the existing lattice root, and it does not cover tracked
   names (§3). No new keyword for "any authority".
6. **A trailing `needs` on a header stays the function's clause**; a result's own set
   needs parentheses (4.3).
7. **A bare arrow in a type declaration's field captures the enclosing value's set** (4.2),
   while a bare arrow in a public signature captures nothing (owner).
8. **Unlisted-call rule** (rule 4, §8.1): a public function that calls a function value
   must list the value's variables in its clause; concrete scopes are not charged.
9. **A pid's message parameter accepts any scopes** (9.1). Sending a closure hands over its
   authority, which actors as principals allow.
10. **Private functions generalise capture variables; local `let`s do not** (§5).
11. **Phasing 8a, 8b, 8c** in that order (§16).

## 18. Testing (shape)

- **Soundness oracle.** An instrumented run (test builds only) records, for each function
  value, every operation it performs and every scoped handle it touches; a test asserts
  each is inside the value's static set. Run over the capture fixtures, the stdlib tests
  and the conformance suite from phase 4. This is the test that catches an unsound rule,
  and it must be shown to go red on a deliberately unsound rule before it is trusted.
- **Inference**: a lambda, a named function as a value, a partial application, a closure
  capturing a closure, a closure creating a closure, a closure spawning a task and an
  actor, a closure inside a literal `restrict` (narrowed), a closure returned by a call
  inside a `restrict` (not narrowed), a top-level `let` closure, a closure in a granted
  package (narrowed by the grant).
- **Data**: `Client needs S` built and read; a field with an explicit set accepts a
  narrower closure and rejects a wider one; a list of closures; an `Option` of a client;
  a `Vault` of closures (invariant).
- **Escape**: every route in §7.1 rejected, with its message; every allowed use inside
  the callback accepted; `BufReader.new` with a named handle parameter; a borrowing
  public function that tries to store its handle parameter rejected at its definition.
- **Public signatures (8c)**: each of rules 2–4 rejected with its message and fixed by
  `forge fix`; the stdlib migrated and its test suite green.
- **Golden diagnostics**: one `test/errors/` case per slug, with the `.json` form.
- **Every mode**: the escape and signature cases reject under `--check`, the interpreter,
  the REPL, `--compile` and `--target js`.
- **No run-time change**: `scripts/ir-oracle.sh` identical with the layer on and off;
  typecheck time over the stdlib and `bench/` within 5% of the base (my call on the
  number).

## 19. Out of scope

- Run-time changes of any kind (§10).
- Removing run-time checks, or proving a computed scope statically.
- Tracking ordinary handles, use after close of an ordinary handle, linear handles.
- Authority reachable through pids or actors.
- Call-site narrowing of returned values (6.2), and any "freshness" analysis that would
  make it sound.
- Capture-set parameters on type declarations.
- Capture sets across nodes: an authority crossing nodes travels as a scope list at run
  time (§21); a value received from another node has the full set `IO` statically.
- `forge audit` listing of capture variables per dependency (§12).
- Interaction with refinement types and proof capabilities: none intended.

## 20. Left to the builder

How sets are represented in `Typecheck_types.ty` (a slot on `TArrow` and `TCon`, or a side
table); whether the solver lives in `cap_rows.ml`; the variance table for every builtin
type; the names of inferred capture variables in messages; diagnostic slugs, codes and
exact wording; the `--dump-captures` format; how the soundness oracle instruments
function values; which stdlib functions get `scoped` parameters besides `File.with_open`;
the exact stdlib signatures in the 8c migration.
