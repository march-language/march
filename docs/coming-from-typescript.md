---
layout: cookbook
title: "Coming from TypeScript"
permalink: /docs/coming-from-typescript/
---

# Coming from TypeScript

You already think in types. March's type system will feel familiar; the main differences are syntax, how errors are handled, and what replaces classes.

---

## Functions

TypeScript and March functions look similar. The key syntax difference: `do...end` instead of `{}`, no `return` keyword; the last expression is the result.

```march
-- TS:   const add = (x: number, y: number): number => x + y
fn add(x : Int, y : Int) : Int do x + y end
```

Named functions use `fn`, anonymous functions use `fn param -> body`:

```march
let double = fn x -> x * 2
let add    = fn (x, y) -> x + y
```

Private (module-internal) functions use `pfn`:

```march
pfn validate(email : String) : Bool do
  String.contains(email, "@")
end
```

---

## Types look different, behave the same

TypeScript generics use `<T>`, March uses `(a)` in lowercase:

| TypeScript | March |
|------------|-------|
| `Array<string>` | `List(String)` |
| `Option<User>` | `Option(User)` |
| `Result<User, string>` | `Result(User, String)` |
| `[string, number]` | `(String, Int)` |
| `string \| null` | `Option(String)` |
| `{ name: string; age: number }` | `{ name : String, age : Int }` |

Type parameters on type declarations use lowercase names by convention:

```march
type Pair(a, b) = { first : a, second : b }
type Tree(a)    = Leaf | Node(Tree(a), a, Tree(a))
```

---

## Sum types instead of discriminated unions

TypeScript discriminated unions:

```typescript
type Shape =
  | { kind: "circle"; r: number }
  | { kind: "rect"; w: number; h: number }
```

March sum types are cleaner: no discriminant field needed:

```march
type Shape = Circle(Float) | Rect(Float, Float) | Point
```

Pattern matching is exhaustive-checked:

```march
fn area(s : Shape) : Float do
  match s do
    Circle(r)  -> 3.14159 *. r *. r
    Rect(w, h) -> w *. h
    Point      -> 0.0
  end
end
```

---

## No `null` / `undefined`: use `Option`

March has no nullable types. A value that might be absent is `Option(a)`:

```march
fn find_user(id : Int) : Option(User) do
  -- returns Some(user) or None
end

match find_user(42) do
  None       -> "not found"
  Some(user) -> user.name
end
```

`Option.unwrap_or` is the safe equivalent of `?? default`:

```march
Option.unwrap_or(find_user(42), default_user)
```

---

## No `try/catch`: use `Result`

TypeScript exceptions are invisible in types. March errors are explicit:

```typescript
// TS: can throw — nothing in the type tells you
async function fetchUser(id: number): Promise<User> { ... }
```

```march
fn fetch_user(id : Int) : Result(User, String) do
  -- Ok(user) or Err("not found")
end
```

`let?` chains fallible operations: it short-circuits on `Err` and returns early, like `try/catch` but tracked in the type system:

```march
fn load(id : Int) : Result(Profile, String) do
  let? user  = fetch_user(id)
  let? prefs = fetch_prefs(user.id)
  Ok({ user: user, prefs: prefs })
end
```

This is the same as TypeScript's `async/await` + `try/catch` pattern, but without the hidden control flow.

---

## No classes: modules + record types

TypeScript:

```typescript
class UserService {
  private db: Database;
  constructor(db: Database) { this.db = db; }
  async getUser(id: number): Promise<User | null> { ... }
  async createUser(data: CreateUserDto): Promise<User> { ... }
}
```

March keeps data and behavior separate. A module is the namespace; a record is the data:

```march
mod UserService do
  type Config = { db : Database }

  fn get_user(cfg : Config, id : Int) : Result(User, String) do
    Db.find(cfg.db, id)
  end

  fn create_user(cfg : Config, name : String, email : String) : Result(User, String) do
    Db.insert(cfg.db, { name: name, email: email })
  end
end
```

---

## Interfaces via `interface`/`impl`

TypeScript structural interfaces:

```typescript
interface Printable { toString(): string; }
function print<T extends Printable>(x: T) { console.log(x.toString()); }
```

March uses nominal interfaces with explicit impl blocks, more like Rust traits than TypeScript interfaces:

```march
interface Show(a) do
  fn show : a -> String
end

impl Show(Int) do
  fn show(x) do String.from_int(x) end
end

fn print_it(x : a) : () when Show(a) do
  println(show(x))
end
```

---

## `let` bindings, no `const`/`let`/`var`

All bindings are immutable by default. No `const` vs `let` distinction:

```march
let x = 10         -- immutable, always
let y = x + 1
```

Record update syntax creates a new record instead of mutating:

```march
let user   = { name: "Alice", age: 30 }
let older  = { user with age: 31 }    -- user is unchanged
```

---

## Concurrency & shared state

A `Promise<T>` maps to a `Task(T)`: a value being computed concurrently. `await`
becomes `Task.await`, and `Promise.all` becomes `Task.await_many`.

```typescript
// TypeScript
const [a, b] = await Promise.all([fetchUser(1), fetchUser(2)]);
```

```march
-- March
let t1 = Task.async(fn () -> fetch_user(1))
let t2 = Task.async(fn () -> fetch_user(2))
let results = Task.await_many([t1, t2])   -- waits for both
```

For mutable, long-lived state (what you'd put in a class instance field), use an
**actor**: a process that owns its state and receives messages:

| TypeScript | March |
|------------|-------|
| `Promise<T>` | `Task(T)` |
| `await p` | `Task.await(t)` |
| `Promise.all([...])` | `Task.await_many([...])` |
| `async function f()` | `Task.async(fn () -> …)` |
| `class` with mutable fields | `actor` with `state { … }` |

See [Actors](actors.md) and [Parallelism](parallelism.md).

---

## What's the same

- Generics / type parameters (different syntax, same concept)
- Union types → sum types (pattern matching instead of narrowing)
- Modules / namespacing
- Type inference everywhere
- `List.map`, `List.filter`, `List.reduce`: same idea, different name
- Arrow functions: `fn x -> x + 1` vs `x => x + 1`
