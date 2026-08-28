---
layout: docs
title: Coding Standards
nav_order: 15.7
permalink: /docs/coding-standards/
---

# March Coding Standards

Canonical reference for March style, safety, and idiom rules. This document is the
single source of truth: the linter (`forge lint`), the LSP, and LLM tooling all derive
their rule definitions from here.

Each rule has:
- A stable **slug** used as the diagnostic code in the linter and LSP
- A **severity**: `error`, `warning`, or `hint`
- An **auto-fix** flag: whether the LSP can fix it automatically

---

## Table of Contents

- [Naming](#naming)
- [Style](#style)
- [Safety](#safety)
- [Dead Code](#dead-code)
- [Actors](#actors)
- [Configuration](#configuration)

---

## Naming

> **Some violations never reach the linter; the parser rejects them first.** March
> reserves leading-*uppercase* identifiers for types, modules, and constructors, and
> leading-*lowercase* identifiers for values, so several "Bad" examples below (an
> uppercase function name, a lowercase type/module/constructor name, an untyped state
> field) are hard parse errors, not lint findings you will see at all. The rules here exist
> for the cases that *do* parse (a `camelCase` function name, a `snake_case`
> constructor written where the parser happens to allow it), and it's those the linter
> and LSP flag. Individual rules no longer repeat this caveat.

### `naming/snake-case-functions`

**Severity:** warning  
**Auto-fix:** yes (rename)

Function names must use `snake_case`. This includes top-level functions, `pfn` private
functions, and local `let`-bound functions.

**Why:** Consistency with the standard library and readability when scanning function
lists. PascalCase names are reserved for types and modules.

```march
-- Bad (camelCase — parses, flagged by the linter)
fn myFunction(x : Int) : Int do
  x + 1
end

-- Good
fn my_function(x : Int) : Int do
  x + 1
end
```

---

### `naming/pascal-case-types`

**Severity:** warning  
**Auto-fix:** yes (rename)

Type names (type aliases, variant types, record types) must use `PascalCase`.

**Why:** Instantly distinguishes type names from value names when reading code.

```march
-- Bad
type my_result = Ok(Int) | err(String)

-- Good
type MyResult = Ok(Int) | Err(String)
```

---

### `naming/pascal-case-modules`

**Severity:** warning  
**Auto-fix:** no

Module names must use `PascalCase`. This is consistent with the `mod Name do` syntax
and mirrors how modules are referenced at call sites (`ModuleName.function`).

```march
-- Bad
mod my_module do
  ...
end

-- Good
mod MyModule do
  ...
end
```

---

### `naming/pascal-case-constructors`

**Severity:** warning  
**Auto-fix:** yes (rename)

Variant constructors within a type definition must use `PascalCase`. Lowercase or
`snake_case` constructors look the same as variable names on the page, which
makes pattern matches harder to read.

```march
-- Bad
type Status = active | inactive | pending(String)

-- Good
type Status = Active | Inactive | Pending(String)
```

---

## Style

### `style/prefer-match`

**Severity:** hint  
**Auto-fix:** no

Prefer `match` over `if/else` chains that test the same discriminant against multiple
values. A chain of two or more `else if` branches on the same variable is a match in
disguise.

**Why:** `match` is exhaustiveness-checked, self-documenting, and easier to extend.
`if/else` chains on a single variable silently allow missing cases.

```march
-- Bad
if status == 200 do
  "ok"
else if status == 404 do
  "not found"
else if status == 500 do
  "server error"
else
  "unknown"
end
end
end

-- Good
match status do
  200 -> "ok"
  404 -> "not found"
  500 -> "server error"
  _   -> "unknown"
end
```

This rule also triggers when an `if` condition tests a constructor that could be a
match pattern (requires type information):

```march
-- Bad (when x : Option(Int))
if Option.is_some(x) do
  unwrap(x) + 1
else
  0
end

-- Good
match x do
  Some(v) -> v + 1
  None    -> 0
end
```

---

### `style/extract-arm-branches`

**Severity:** hint  
**Auto-fix:** no

A `match` arm with a body that contains another `match` or an `if/else` should be extracted
into a private function with multiple heads. Deeply nested branching is hard to read
and test.

**Why:** Multi-head private functions are the idiomatic March way to handle
multi-dimensional dispatch. They keep each arm body flat and each case independently
readable.

```march
-- Bad
match result do
  Ok(v) ->
    match v.kind do
      Query   -> run_query(v)
      Command -> run_command(v)
    end
  Err(e) -> handle_error(e)
end

-- Good
match result do
  Ok(v)  -> dispatch(v)
  Err(e) -> handle_error(e)
end

pfn dispatch(v) when v.kind == Query   do run_query(v) end
pfn dispatch(v) when v.kind == Command do run_command(v) end

-- Better still, with constructor patterns on the inner type
pfn dispatch({kind: Query,   ..} = v) do run_query(v) end
pfn dispatch({kind: Command, ..} = v) do run_command(v) end
```

This rule triggers on:
- A match arm with a body that is a `match` expression
- A match arm with a body that is an `if/else` with two or more branches (single
  `if` without `else` is allowed; it often reads as a guard)

---

### `style/prefer-pipe`

**Severity:** hint  
**Auto-fix:** no

Three or more levels of nested function calls should be written as a pipeline using
`|>`. Pipelines read left-to-right in the order operations are applied; deeply nested
calls read inside-out.

```march
-- Bad
map(filter(sort(xs), is_active), to_string)

-- Good
xs |> sort |> filter(is_active) |> map(to_string)
```

The threshold is three levels of nesting. Two levels (`f(g(x))`) are fine inline.

---

### `style/no-boolean-literal-compare`

**Severity:** warning  
**Auto-fix:** yes

Never compare a boolean expression to `true` or `false` with `==` or `!=`. Use the
expression directly, or negate it with `!`.

```march
-- Bad
if is_valid == true do ...
if done == false do ...
if !ready != true do ...

-- Good
if is_valid do ...
if !done do ...
if ready do ...
```

---

### `style/de-morgan`

**Severity:** hint  
**Auto-fix:** yes

Apply De Morgan's law to simplify negated boolean expressions.

| Pattern | Simplification |
|---------|---------------|
| `!(a && b)` | `!a \|\| !b` |
| `!(a \|\| b)` | `!a && !b` |
| `!a && !b` | `!(a \|\| b)` |
| `!a \|\| !b` | `!(a && b)` |

**Why:** The simplified form often reads closer to how the condition is reasoned about.
The auto-fix rewrites in whichever direction removes a negation level.

```march
-- Bad
if !(user.active && user.verified) do
  deny()
else
  ()
end

-- Good
if !user.active || !user.verified do
  deny()
else
  ()
end
```

---

### `style/doc-comment-public-fn`

**Severity:** hint  
**Auto-fix:** no

Every public function (non-`pfn`) should have a `doc` annotation. Use triple-quoted
`doc """ ... """` for multi-line descriptions; `doc "..."` is fine for one-liners.

**Why:** Doc strings are first-class in March: queryable in the REPL with `h(fn_name)`,
surfaced in LSP hover, and the basis for future `march doc` generation. An undocumented
public function is a missing contract.

```march
-- Bad
fn connect(url : String) : Result(Conn, Error) do
  ...
end

-- Good (one-liner)
doc "Opens a TCP connection to `url`. Returns Err if the host is unreachable."
fn connect(url : String) : Result(Conn, Error) do
  ...
end

-- Good (multi-line)
doc """
Opens a TCP connection to `url`.

Returns `Err(ConnectionRefused)` if the host actively refuses the connection,
or `Err(Timeout)` if no response is received within the default timeout.
"""
fn connect(url : String) : Result(Conn, Error) do
  ...
end
```

---

### `style/annotate-public-fns`

**Severity:** hint  
**Auto-fix:** yes (inserts inferred type)

Public functions (non-`pfn`) should have explicit return type annotations. Parameter
type annotations are encouraged but not required by this rule.

**Why:** Explicit return types form a stable public API contract. They catch accidental
type changes at the definition site rather than the call site, and make the LSP hover
useful without requiring inference.

```march
-- Bad
fn greet(name) do
  "Hello, " ++ name
end

-- Good
fn greet(name : String) : String do
  "Hello, " ++ name
end
```

---

## Safety

### `safety/discard-result`

**Severity:** warning  
**Auto-fix:** no

A call that returns `Result` must not have its return value discarded. Either bind it
with `let`, propagate it with `let?`, or explicitly handle both arms.

**Why:** Silently discarding a `Result` hides errors. Every `Result`-returning call is
a potential failure path that must be acknowledged.

```march
-- Bad
write_file("out.txt", data)   -- return value dropped

-- Good: propagate with let?  (preferred in Result-returning functions;
-- there is no postfix `?` operator, only the `let? x = e` binding form)
let? _ = write_file("out.txt", data)

-- Good: handle explicitly
match write_file("out.txt", data) do
  Ok(_)  -> ()
  Err(e) -> log_error(e)
end
```

---

### `safety/partial-let-pattern`

**Severity:** warning  
**Auto-fix:** no

A `let` binding that uses an irrefutable pattern on a fallible (multi-constructor) type
will panic at runtime if the value does not match. Use `match` instead.

**Why:** `let Some(x) = expr` is a runtime panic if `expr` is `None`. The exhaustiveness
checker cannot catch this at the `let` site; it must be a lint rule.

```march
-- Bad
let (Some(user)) = find_user(id)   -- panics if None (a bare constructor pattern
let (Ok(conn))   = connect(url)    -- panics if Err   needs parens in a `let`)

-- Good
match find_user(id) do
  Some(user) -> use_user(user)
  None       -> handle_missing()
end
```

---

### `safety/no-panic-in-lib`

**Severity:** warning  
**Auto-fix:** no

Library modules must not call `panic` directly. Return `Result` or `Option` and let
the caller decide how to handle failure. `panic` is acceptable in application entry
points (`main`), test code, and truly unrecoverable situations (e.g. allocator failure).

**Why:** A `panic` in a library is an unilateral abort that the caller cannot recover
from. It breaks composability and makes libraries hostile to use in contexts where
uptime matters.

```march
-- Bad (in a lib module)
fn parse_int(s : String) : Int do
  match try_parse(s) do
    Some(n) -> n
    None    -> panic("not a number: " ++ s)
  end
end

-- Good
fn parse_int(s : String) : Result(Int, String) do
  match try_parse(s) do
    Some(n) -> Ok(n)
    None    -> Err("not a number: " ++ s)
  end
end
```

Detection: a `panic` call in a file that is not the application entry point
(`main.march`) and is not test code, i.e. neither a `_test.march` file nor a
file under a `test/` (or `tests/`) directory.

---

## Dead Code

### `dead-code/unused-private-fn`

**Severity:** warning  
**Auto-fix:** no

A `pfn` that is not reachable from any public function root is dead code and should be
removed.

**Why:** Unreachable private functions accumulate over time, making codebases harder to
navigate and refactor. The compiler can prove they are unreachable via reachability
analysis from public roots.

```march
-- Bad: pfn helper is never called
pfn helper(x : Int) : Int do x * 2 end
fn public_api(x : Int) : Int do x + 1 end

-- Good
fn public_api(x : Int) : Int do x + 1 end
```

---

### `dead-code/unreachable-after-diverge`

**Severity:** warning  
**Auto-fix:** no

Code that follows a diverging call (a call that never returns: `panic`, `exit`, or a
function with return type `Never`) is unreachable and should be removed.

**Why:** Unreachable code is confusing and often indicates a logic error: either the
diverging call is wrong, or the code after it was left behind from a refactor.

```march
-- Bad
panic("unrecoverable")
cleanup()   -- never runs

-- Good
panic("unrecoverable")
```

---

## Actors

### `actors/handler-delegates-to-fn`

**Severity:** warning  
**Auto-fix:** no

Actor `on` handler bodies should be thin: a single delegating call or a state update
expression. Complex logic (nested `match`, `if/else`, or more than three `let`
bindings) belongs in a `pfn`, which can be called from the handler and tested
independently without sending a message.

**Why:** Handler bodies that contain business logic couple the protocol layer to the
implementation. Extracting to `pfn` makes each handler a readable one-liner dispatch
table and keeps the logic unit-testable.

```march
-- Bad
on Process(job) do
  let result = match job.kind do
    Query   -> run_query(job.data)
    Command -> run_command(job.data)
  end
  send(job.reply_to, Done(result))
  { state with processed: state.processed + 1 }
end

-- Good
on Process(job) do handle_process(state, job) end

pfn handle_process(state, job) do
  let result = dispatch_job(job)
  send(job.reply_to, Done(result))
  { state with processed: state.processed + 1 }
end

pfn dispatch_job(job) when job.kind == Query   do run_query(job.data) end
pfn dispatch_job(job) when job.kind == Command do run_command(job.data) end
```

Triggers when `on` body contains a `match`, an `if/else`, or more than three `let`
bindings.

---

### `actors/declare-message-type`

**Severity:** hint  
**Auto-fix:** no

Define a named variant type for the messages an actor accepts, declared adjacent to
(immediately before) the actor. Without it, the full message protocol is only
discoverable by reading every `on` clause.

**Why:** An explicit message type gives the actor a public contract that can be
referenced in type signatures, documentation, and by other actors that send to it.

```march
-- Bad: protocol is implicit, scattered across handler clauses
actor Counter do
  state { count : Int }
  init { count: 0 }
  on Increment() do ... end
  on Reset()     do ... end
  on GetCount()  do ... end
end

-- Good: protocol is explicit and referenceable
type CounterMsg = Increment | Reset | GetCount

actor Counter do
  state { count : Int }
  init { count: 0 }
  on Increment() do ... end
  on Reset()     do ... end
  on GetCount()  do ... end
end
```

---

### `actors/no-spawn-in-handler`

**Severity:** warning  
**Auto-fix:** no

Do not call `spawn` inside an `on` handler body. Process topology (which actors
create which other actors) should be declared in `init` or via the `supervise`
config, not wired up dynamically in response to messages.

**Why:** Spawns inside handlers make the process tree implicit and hard to reason
about. Supervision config and `init` make the topology visible and restartable.

```march
-- Bad
on Start(config) do
  let worker = spawn(Worker)
  send(worker, Run(config))
  { state with worker: Some(worker) }
end

-- Good: use supervision config for managed child actors — spawn topology is
-- declared once, not wired up dynamically in a handler. (There is no valid
-- surface-syntax type for a state field holding a raw `Pid` from a manual
-- `spawn` — `Pid(Worker)` is a type-arity error and bare `Pid` doesn't unify
-- with what `spawn` actually returns — so `supervise` is the only working
-- way to keep a spawned child's identity in an actor's own state.)
actor Supervisor do
  state { worker : Int }
  init  { worker: 0 }
  supervise do
    strategy one_for_one
    max_restarts 5 within 60
    Worker worker
  end
end
```

---

### `actors/annotate-state-fields`

**Severity:** warning  
**Auto-fix:** no

All fields in an actor's `state { ... }` block must have explicit type annotations.
Actor state is long-lived, potentially serialised, and inspected by supervision
tooling; implicit types are a maintenance hazard.

```march
-- Bad (illustrative only — untyped state fields don't parse; see the note at
-- the top of Naming. Every state field requires `: Type`.)
actor Cache do
  state { entries, ttl, hits }
  ...
end

-- Good
actor Cache do
  state {
    entries : Map(String, Bytes),
    ttl     : Int,
    hits    : Int
  }
  ...
end
```

---

## Configuration

Rules are configured per-project in `.march-lint.toml` at the project root. This file
is generated automatically by `forge new`.

Each rule can be set to `"error"`, `"warning"`, `"hint"`, or `"off"`.

```toml
# .march-lint.toml
# Generated by forge new. Adjust severities or disable rules as needed.
# Valid values: "error" | "warning" | "hint" | "off"

[rules]
# Naming
"naming/snake-case-functions"         = "warning"
"naming/pascal-case-types"            = "warning"
"naming/pascal-case-modules"          = "warning"
"naming/pascal-case-constructors"     = "warning"

# Style
"style/prefer-match"                  = "hint"
"style/extract-arm-branches"          = "hint"
"style/prefer-pipe"                   = "hint"
"style/no-boolean-literal-compare"    = "warning"
"style/de-morgan"                     = "hint"
"style/doc-comment-public-fn"         = "hint"
"style/annotate-public-fns"           = "hint"

# Safety
"safety/discard-result"               = "warning"
"safety/partial-let-pattern"          = "warning"
"safety/no-panic-in-lib"              = "warning"

# Dead code
"dead-code/unused-private-fn"         = "warning"
"dead-code/unreachable-after-diverge" = "warning"

# Actors
"actors/handler-delegates-to-fn"      = "warning"
"actors/declare-message-type"         = "hint"
"actors/no-spawn-in-handler"          = "warning"
"actors/annotate-state-fields"        = "warning"
```

### `forge lint` flags

| Flag | Effect |
|------|--------|
| *(none)* | Exit 0 if no errors; exit 1 if any `error`-severity violations |
| `--strict` | Treat `warning` as `error`; exit 1 on any warning or error |
| `--all` | Also report `hint`-severity findings |
| `--json` | Emit machine-readable JSON (for CI/editor integration) |
