# Capability-Based Library Security

**Date:** 2026-03-19
**Status:** Design

## Summary

External libraries (both March packages and FFI) are sandboxed by default — they cannot perform IO, network access, filesystem operations, or any side effect unless the caller explicitly grants capabilities. This is enforced through two complementary mechanisms:

1. **Package manifests** (`needs` declarations) — compile-time contract declaring what capabilities a module requires
2. **Function signatures** — runtime enforcement via explicit `Cap(...)` parameters at every call site

The compiler guides the user through correct usage with actionable diagnostics.

## Motivation

A third-party March library you import should not be able to silently open network connections, read your filesystem, or perform any IO. The capability system makes side effects **opt-in and visible**: you see exactly what permissions you're granting, both at the import level (manifest) and at every call site (function params).

This extends March's existing `Cap(IO)` design to the library boundary.

## Capability Hierarchy

Capabilities form a tree rooted at `Cap(IO)`. A parent capability subsumes all its children (subtyping).

```
Cap(IO)
├── Cap(IO.Console)          -- print, read_line
├── Cap(IO.FileSystem)
│   ├── Cap(IO.FileRead)     -- read files, list directories
│   └── Cap(IO.FileWrite)    -- write files, create directories
├── Cap(IO.Network)
│   ├── Cap(IO.NetConnect)   -- outbound TCP/HTTP
│   └── Cap(IO.NetListen)    -- bind/listen on ports
├── Cap(IO.Process)          -- env vars, args, exit, spawn
└── Cap(IO.Clock)            -- current time, sleep
```

**Subtyping rule:** If `A` is an ancestor of `B` in the tree, then `Cap(A)` is accepted wherever `Cap(B)` is expected. For example, `Cap(IO)` satisfies `Cap(IO.FileRead)`.

**FFI capabilities** are separate roots, one per foreign library: `Cap(LibC)`, `Cap(LibSSL)`, etc. They do not live under the `IO` tree.

## Package Manifest: `needs` Declarations

Every module that requires capabilities declares them with `needs` at the top of the module body:

```march
mod Http do
  needs IO.Network
  needs IO.Clock

  pub fn get(net : Cap(IO.Network), url : String) -> Result(Response, HttpError)
  pub fn post(net : Cap(IO.Network), url : String, body : String) -> Result(Response, HttpError)
end
```

### Manifest rules

1. **Every `Cap(X)` in any function (public or private) must be covered by a `needs X`** (or a `needs` for an ancestor of `X`).
2. **Every `needs X` must be used** — at least one function must take `Cap(X)` or a descendant. Unused `needs` are a compiler warning.
3. **Transitive needs propagate** — if module `A` uses module `B`, and `B` needs `IO.Network`, then `A` must either (a) declare `needs IO.Network` itself, or (b) have access to `Cap(IO.Network)` in the functions that call into `B`.
4. **Modules with no `needs` are pure** — they cannot perform any side effects. This is the default.

### Why both manifest and signatures?

The manifest answers **"should this library be allowed to do X?"** — it's the contract you review before importing. The function signatures answer **"is this specific call doing X?"** — they're the enforcement at every call site. Together they provide auditability (manifest) and precision (signatures).

## Compiler Diagnostics

The compiler guides users through correct capability usage with four categories of diagnostics.

### Error: Missing capability access

When you call a library function that requires a capability your function doesn't have:

```march
fn process(fs : Cap(IO.FileRead)) do
  let data = Http.get(???, "https://api.com/data")
end
```

```
error: `Http.get` requires Cap(IO.Network), but `process` only has
       access to Cap(IO.FileRead)

  ┌─ src/app.march:2:14
  │
2 │   let data = Http.get(???, "https://api.com/data")
  │              ^^^^^^^^
  │
  = note: Http declares `needs IO.Network` (see http/package.march:2)
  = help: add Cap(IO.Network) to this function's parameters:

    fn process(fs : Cap(IO.FileRead), net : Cap(IO.Network)) do
```

### Error: Capability not passed at call site

When you have the capability but forget to pass it:

```march
fn fetch(net : Cap(IO.Network)) do
  let data = Http.get("https://api.com")
end
```

```
error: `Http.get` expects Cap(IO.Network) as first argument

  ┌─ src/app.march:2:14
  │
2 │   let data = Http.get("https://api.com")
  │              ^^^^^^^^
  │
  = help: pass your network capability:

    let data = Http.get(net, "https://api.com")
```

### Warning: Unused `needs` declaration

When a module declares a capability requirement it doesn't use:

```march
mod BadLib do
  needs IO.Network

  pub fn compute(x : Int) -> Int do x + 1 end
end
```

```
warning: module `BadLib` declares `needs IO.Network` but no public
         function requires Cap(IO.Network)

  ┌─ src/badlib.march:2:3
  │
2 │   needs IO.Network
  │   ^^^^^^^^^^^^^^^^
  │
  = help: remove the unused capability declaration, or add it to
    a function that performs network operations
```

### Hint: Overly broad capability

When a narrow capability would suffice but a broad one is used:

```march
fn read_config(io : Cap(IO)) do
  let content = File.read(io, "config.toml")
end
```

```
hint: `File.read` only requires Cap(IO.FileRead), but you're
      passing Cap(IO) — consider narrowing for least-privilege

  ┌─ src/app.march:2:28
  │
2 │   let content = File.read(io, "config.toml")
  │                            ^^
  │
  = help: narrow the function signature:

    fn read_config(fs : Cap(IO.FileRead)) do
```

This is a hint, not a warning — `Cap(IO)` is valid via subtyping. The hint encourages least-privilege but doesn't force it. `main` typically takes `Cap(IO)` and that's fine.

## Capability Attenuation

Deriving a narrow capability from a broader one:

```march
fn main(io : Cap(IO)) do
  -- Subtyping: Cap(IO) is accepted where Cap(IO.FileRead) is expected
  let content = File.read(io, "config.toml")

  -- Explicit attenuation for passing to untrusted code
  let fs_read = Cap.narrow(io, IO.FileRead)
  UntrustedLib.process(fs_read)   -- can only read files, nothing else
end
```

`Cap.narrow(broad_cap, TargetCapability)` is a built-in that returns a `Cap(TargetCapability)` derived from the broader capability. The type system ensures:

- You can only narrow **down** the hierarchy, never widen
- The source capability must be an ancestor of (or equal to) the target
- The returned capability is a fresh value — the original is unaffected

### When to use subtyping vs. explicit narrowing

- **Subtyping (implicit):** When you're calling a function and happen to have a broader cap. Natural and concise: `File.read(io, path)`.
- **`Cap.narrow` (explicit):** When you want to **restrict** what you pass to another module. Communicates intent: "I'm deliberately limiting this library's access."

## Stdlib Integration

Existing stdlib modules gain `needs` declarations:

```march
mod IO do
  needs IO.Console

  pub fn println(cap : Cap(IO.Console), s : String) : Unit
  pub fn print(cap : Cap(IO.Console), s : String) : Unit
  pub fn read_line(cap : Cap(IO.Console)) : String
end

mod IO.File do
  needs IO.FileRead, IO.FileWrite

  pub fn read(cap : Cap(IO.FileRead), path : String) : Result(String, IOError)
  pub fn write(cap : Cap(IO.FileWrite), path : String, content : String) : Result(Unit, IOError)
  pub fn exists(cap : Cap(IO.FileRead), path : String) : Bool
  pub fn list_dir(cap : Cap(IO.FileRead), path : String) : Result(List(String), IOError)
end
```

**Backward compatibility:** `main(io : Cap(IO))` continues to work unchanged. `Cap(IO)` subsumes all sub-capabilities, so existing code that passes `io` to stdlib functions works via subtyping.

**Note:** This spec supersedes the IO function signatures in `stdlib_design.md` (which used `Cap(IO)` everywhere). The narrow signatures here (`Cap(IO.Console)`, `Cap(IO.FileRead)`, etc.) are the intended design. `stdlib_design.md` should be updated to match.

## FFI Interaction

FFI extern blocks already declare per-library capabilities:

```march
extern "libc" : Cap(LibC) do
  fn malloc(size : Int) : linear Ptr(a)
  fn free(ptr : linear Ptr(a)) : Unit
end
```

This design extends naturally. A March library that wraps an FFI library must declare both:

```march
mod Database do
  needs IO.Network       -- for TCP connections
  needs LibPQ            -- for the PostgreSQL C library

  pub fn connect(net : Cap(IO.Network), pg : Cap(LibPQ), url : String) -> Result(Conn, DbError)
end
```

The `needs` for FFI capabilities uses the same syntax and same compiler checks. A consumer importing `Database` sees both the March-level and FFI-level capability requirements.

## Pure by Default

Modules without `needs` declarations are **provably pure**:

```march
mod Json do
  -- no `needs` — this module cannot perform IO, network, or any side effect

  pub fn parse(s : String) -> Result(Value, ParseError)
  pub fn stringify(v : Value) -> String
end
```

The compiler enforces this: if a module has no `needs`, none of its functions (public or private) may take `Cap(...)` parameters or call functions that require capabilities. This is the default state for all modules — capabilities are strictly opt-in.

## Capability Kinds: IO Permissions vs. Actor References

March has two distinct uses of `Cap`:

- **IO capabilities** (`Cap(IO)`, `Cap(IO.FileRead)`, `Cap(LibC)`, etc.) — permission tokens that grant access to side effects. They have no identity or epoch. They are the subject of this spec.
- **Actor capabilities** (`Cap(A, e)` where `A` is an actor type and `e` is an epoch) — unforgeable references to specific actor instances. These are defined in the existing design spec and are not changed by this proposal.

The two kinds are distinguished by arity: `Cap(IO.Network)` (one type param, IO permission) vs. `Cap(Counter, e)` (two type params, actor reference). The type checker resolves which kind based on whether the first parameter names a capability in the IO/FFI hierarchy or an actor type.

Actor capabilities remain non-`Sendable` (node-local, as specified in the existing design). IO capabilities are freely passable within a node — they are permission tokens, not references to external resources. IO capabilities are not `Sendable` across actor boundaries either — each actor receives its own capabilities at spawn time.

**Namespace:** `IO` is both a module name and a capability root. This is intentional — the module that provides IO functions *is* the capability namespace. `Cap(IO)` refers to the capability, `IO.println` refers to the module's function. There is no ambiguity because `Cap(...)` always wraps a capability name while bare `IO.println` is always a module path. Users cannot define their own `mod IO` — `IO` is a reserved stdlib module, like `List` or `Option`.

## Closures and Capability Capture

Closures can capture capabilities freely. The security boundary is at the **function signature** level, not at closure creation:

```march
fn make_reader(fs : Cap(IO.FileRead)) -> (String -> Result(String, IOError)) do
  fn (path) -> File.read(fs, path)
end
```

This returns a plain `String -> Result(String, IOError)` — a regular function type. The capability was already checked when `make_reader` was called (the caller had to provide `Cap(IO.FileRead)`). The closure packages existing access, it doesn't grant new access.

**Why this is safe:** The creator of the closure already had the capability. Passing the resulting closure to someone without the cap is deliberate capability delegation — the same as any callback pattern. The security invariant holds: you cannot perform IO without *someone* in the call chain having the capability.

**Why not track captures in the type?** A `Cap(X) => a -> b` annotation would make closures incompatible with all existing higher-order functions (`List.map`, `List.filter`, etc.), creating a major usability cliff. The practical benefit is small — the capability was already checked at creation — and the cost is high.

**Interaction with HOFs:** Closures that capture capabilities work with all existing HOFs without changes:

```march
fn main(io : Cap(IO)) do
  let files = ["a.txt", "b.txt", "c.txt"]
  let contents = List.map(files, fn (f) -> File.read(io, f) end)
end
```

The closure captures `io` and is passed to `List.map` as a normal `String -> Result(String, IOError)`. This is sound because `main` already has `Cap(IO)`.

## Nested Modules

Nested modules declare their own `needs` independently:

```march
mod Outer do
  needs IO.Console

  mod Inner do
    needs IO.Network

    pub fn fetch(net : Cap(IO.Network), url : String) -> String
  end

  pub fn greet(io : Cap(IO.Console)) -> Unit do
    IO.println(io, "hello")
  end
end
```

**Rules:**
1. **No inheritance** — nested modules do not inherit parent `needs`. Each module declares exactly what it requires.
2. **Parent must cover children** — if `Outer` exposes `Inner` publicly, then `Outer`'s effective needs are the union of its own and its children's. The compiler tracks this transitively and surfaces the full set in error messages and documentation (e.g., "module Outer requires: IO.Console, IO.Network").
3. **Private nested modules** are internal implementation details — their `needs` don't propagate to the parent's public contract, but the parent must still have access to the required capabilities in functions that call into the nested module.

## Private Function Enforcement

`needs` covers **all** capability usage within a module, not just the public API:

```march
mod Lib do
  needs IO.Console

  -- Private helper — still must be covered by `needs`
  fn log(io : Cap(IO.Console), msg : String) do
    IO.println(io, msg)
  end

  pub fn process(io : Cap(IO.Console), x : Int) -> Int do
    log(io, "processing")
    x + 1
  end
end
```

If a private function uses `Cap(IO.FileRead)` but the module only declares `needs IO.Console`, that's a compiler error. The manifest is a complete inventory of the module's capability requirements — no hidden side effects, even in private code.

## `needs` Syntax

Both forms are valid and equivalent:

```march
-- Separate lines
needs IO.FileRead
needs IO.FileWrite

-- Comma-separated
needs IO.FileRead, IO.FileWrite
```

The compiler normalizes these to the same representation. For FFI capabilities, use the bare library name: `needs LibC`, not `needs Cap(LibC)`.

## `Cap.narrow` Typing

`Cap.narrow` is a built-in with the following behavior:

```march
Cap.narrow(cap, Target) : Cap(Target)  where cap : Cap(A), A :> Target
```

- The second argument (`Target`) is a **type-level argument** — a capability name like `IO.FileRead`, not a runtime value. Syntactically it looks like a module path; the compiler resolves it as a capability name.
- `A :> Target` means `A` is an ancestor of `Target` in the capability hierarchy (or `A == Target`)
- The hierarchy is known to the compiler — it's a fixed tree, not user-extensible
- **This is a compile-time-only operation** — at runtime, capabilities are erased or represented uniformly. `Cap.narrow` produces a value with a more restrictive type but no runtime cost.
- If `A` is not an ancestor of `Target`, it's a compile-time type error — `Cap.narrow` cannot fail at runtime.

The `A :> B` constraint is a built-in the type checker knows about, similar to how it knows `Int` satisfies `Eq`. It's not expressed via interfaces — it's structural, derived from the fixed capability tree.

## Capability Revocation

Capabilities cannot be revoked once granted. Once you pass `Cap(IO.Network)` to a library, it retains that permission for the lifetime of the value. This is a deliberate simplification:

- Revocation adds complexity (indirection, runtime checks, potential for confused-deputy problems)
- The capability model already limits blast radius through attenuation — pass the narrowest cap possible
- For long-running applications, actor boundaries provide natural capability scoping — when an actor terminates, its capabilities become unreachable

## Sandboxed Execution (Future)

In the future, the runtime could provide restricted capabilities to `main`:

```march
-- Normal execution
fn main(io : Cap(IO)) do ... end

-- Sandboxed: only console and file read
fn main(console : Cap(IO.Console), fs : Cap(IO.FileRead)) do ... end
```

This would allow running untrusted March scripts with limited permissions, similar to Deno's `--allow-read` model. The capability hierarchy makes this natural — the runtime simply provides a subset of capabilities. This is deferred to a later design.

## Open Questions (deferred to implementation)

1. **Actor capability injection:** How actors receive IO capabilities at spawn time. Options: (a) actors declare `needs` and the runtime provides matching caps, (b) caps are passed as init arguments to the actor constructor. To be resolved alongside the actor system design.
2. **Runtime representation:** Whether `Cap` values are fully erased (phantom/zero-sized) or represented uniformly (unit value in a register slot). Affects ABI and calling conventions. Likely erased for IO caps since enforcement is compile-time only.
3. **`needs` in module signatures (`sig`):** Whether `sig` declarations must include `needs` for completeness. Likely yes — the sig is the public contract.

## Design Principles

1. **Deny by default** — no module can perform side effects unless it declares `needs` and the caller passes capabilities
2. **Visible at every level** — manifests show library-level permissions, signatures show per-call permissions
3. **Compiler as guide** — errors tell you exactly what's missing and how to fix it
4. **Least-privilege encouraged** — hints nudge toward narrow capabilities, but broad caps work via subtyping
5. **Consistent with existing design** — extends the current `Cap(IO)` pattern, no new mechanisms for threading
6. **Pure is the happy path** — modules are pure by default; capabilities are the exception that must be justified
