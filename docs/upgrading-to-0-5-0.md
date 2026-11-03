---
layout: docs
title: Upgrading to 0.5.0
nav_order: 2.3
permalink: /docs/upgrading-to-0-5-0/
---

# Upgrading from 0.4.x to 0.5.0

**0.5.0 has breaking changes.** Most programs compile unchanged, but the type
checker now rejects several shapes that used to typecheck and then crash at run
time, a few standard-library APIs changed their signatures, and hot-reload
servers need one restart after the upgrade.

Read § 1 first if you run anything with `--hot-reload` or `forge deploy hot`.
Everything else is fixed at compile time: the compiler tells you where, and
usually how.

The full list of changes, including everything that is new, is in
`CHANGELOG.md`.

---

## 1. Hot-reload servers need one cold restart

The hot-reload ABI is now `march-hcr-v4`. A server built by 0.4.x cannot take a
hot patch built by 0.5.0. The first `forge deploy hot` after you upgrade the
toolchain is refused **before upload**, with a message telling you to restart the
server once on a base build from the new toolchain. Nothing is deployed, and the
server stays up.

**What to do:** rebuild each hot-reload server with 0.5.0 and restart it once.
Hot deploys work again from then on. A patch built by 0.4.x sent to a 0.5.0
server is refused with "rebuild the patch".

## 2. `forge deploy hot` refuses two more kinds of deploy

**A patch that changes a parameter's borrow mode.** Whether a `String`, `List` or
ADT parameter is borrowed or owned is decided by the function's body, and running
callers depend on it. A body edit that flipped it used to deploy and then free a
value a running caller still used. Such a deploy is now refused, naming the
parameter (`parameter 1 of Handler.count changed from borrowed to owned`). Deploy
that build with a restart. Body-only changes that keep the modes deploy hot as
before.

**A topology pool whose derived capabilities widen.** When `topology.toml` leaves a
pool's `caps` out, the compiler derives them, and a deploy that gives the pool a
capability it did not have at the environment's last completed deploy now stops
before anything is built. Either name the new capability:

```
forge deploy hot --env prod --grant-cap IO.FileWrite
```

or write the pool's `caps` in `topology.toml`, which takes the pool out of the
check. `forge build` warns about each pool that widens.

## 3. The type checker rejects more programs

Every item here used to typecheck and then fail at run time, or was a warning.

**Calling or passing a function at the wrong arity** (`arity_mismatch`,
`callback_arity_mismatch`). March has no partial application, so a two-argument
function applied one argument at a time crashed. This is now caught for a function
passed as a callback, through a `let h = add` alias, and for a callback passed to a
let-bound lambda. Call the function with all its arguments, or pass the curried
wrapper the hint suggests:

```march
-- before: typechecked, then crashed
Map.insert(m, k, v, lt)                  -- lt : (a, a) -> Bool
-- after
Map.insert(m, k, v, fn a -> fn b -> lt(a, b))
```

**Signature type variables are rigid** (`annotated_tyvar_fixed`). A body that fixes
a signature's `a` to a concrete type, or makes two signature variables the same
type, is an error. It was a warning since 0.4. Write the concrete type the hint
names, or make the body generic.

**Linearity holes are closed.** These are now errors:

- discarding a linear value with `let _ = …` or a `_` pattern;
- consuming a linear value on only some branches of an `if` or `match`;
- capturing a linear value in a closure or a local `fn`;
- consuming a record's linear field and keeping the record;
- a parameter that holds a `linear` type variable without being marked;
- a module-level `let` of a linear type.

**A module-level `let` annotation is checked.** `let x : Int = "hello"` directly
inside a `mod` used to be accepted.

**A path scope that cannot take effect is an error.** Only `IO.FileRead`,
`IO.FileWrite` and `IO.FileSystem` take a scope, and it must be absolute:
`needs IO("/srv")` becomes `needs IO.FileSystem("/srv")`.

## 4. Standard-library changes

**`RingBuf` is linear.** Every operation consumes the buffer and hands it back:

```march
let rb = RingBuf.push(rb, x)
let (n, rb) = RingBuf.size(rb)
```

In actor state, write `{ state with buf: RingBuf.push(state.buf, x) }`. A buffer
can now be sent in a message, which moves it.

**`Config` reads through typed keys.**

```march
-- before
Config.put(:myapp, :port, 4000)
Config.get(:myapp, :port)
-- after
let port = Config.key(:myapp, :port, Config.int())
Config.put(port, 4000)
Config.get(port)                         -- Option(Int)
```

The same change applies to `put_in`/`get_in` (use `Config.key_in`), to
`store_put`/`store_get`, and to `from_env*`, `validate`, `get_with_default` and
`require`.

**A running cluster node is a capability.** `ClusterNode.start(io, cfg)` takes the
root capability first and returns `Result(Cap(ClusterNode.Live), String)`. The
`ClusterHandle` type is gone. Start the node in `main(io : Cap(IO))`, write
`Cap(ClusterNode.Live)` where you wrote `ClusterNode.ClusterHandle`, and add
`needs ClusterNode.Live` to a module whose signatures name it.

**Finding an actor you were not handed takes a capability.** `Actor.whereis`,
`registered`, `list`, `top_by_mailbox` and `over_mailbox` take a
`Cap(Actor.Introspect)` first. Mint it once with `let c = Actor.introspect(io)`.
`pid_of_int` is replaced by `Actor.pid_from_int(c, n)`.

**Contract preconditions moved into signatures.** `Stats.median`, `std_dev`, `iqr`,
`iqr_default` and `quantile_default` take a non-empty list; `Seq.batched` and
`Flow.batch` take a positive size; `Gen.frequency` takes a non-empty list. A
provably bad argument is a compile error, and a function that passes its own
unrefined argument gets a warning. `march --check --refine-suggest <fn> file.march`
prints the refinement to add to your function, or guard the call with a `match`.

**A program that cannot be executed is an `Err`.** `Process.run`, `run_stream`,
`spawn_async` and `System.cmd` return `Err("cannot execute …")` for a missing or
non-executable program. Compiled code used to return `Ok` with exit code 127, so
match `Err` instead. Children now start with default signal handling, and on macOS
they inherit only stdin, stdout and stderr.

**Programs that use the cluster transport directly** (`NetKernel`, `ClusterConn`,
`NodeSend`, `NodeQueue`, …) under a narrow grant need `IO.Mut` and `IO.Clock`.

**Choreography API.**

- `run_<Role>` and its fronts return `Result(Session.Outcome, RunError)`. Code that
  matches `Ok(_)` is unaffected.
- A hosted role's `cancel` takes the session: `cancel(s, parked)`.
- A session frame refused with `DELIVERY_FAILED` fails its session, and no longer
  reaches `ClusterNode.on_delivery_failed`.

**Corrected signatures.** `get_actor_field` returns `Option(Int)`; `sha256` is
`Bytes -> String`; `Plot.save` returns `Result(Unit, File.FileError)`; the
`Compress` functions return `Compress.Error`; `RRB` and `AhoCorasick` use
`Array.PVec(a)`.

## 5. Flags and tooling

- `--trmc`, `--no-trmc` and `MARCH_NO_TRMC` are gone; tail-recursion-modulo-cons
  always runs. The `respond` builtin is gone.
- `forge.toml` is parsed strictly: a malformed line is an error that names its line,
  and an unknown key is a warning.
- Compiled `int_shl` / `int_shr` with a shift count outside `[0, 62]` panic, and
  interpreted `int_shr` is an arithmetic shift.

## Known issues in 0.5.0

- Each hot deploy keeps one patch `.so` mapped until the node restarts.
- A hot deploy that changes a boundary function's types can still reach a caller
  that is already running old code. Restart for signature changes.
- Two nested types with the same short name (`A.Note`, `B.Note`) are one type to
  the checker. Give them distinct names.
- `let k = List.length` then `k(xs)` runs interpreted but does not compile. Wrap it:
  `fn xs -> List.length(xs)`.

## Quick checklist

1. Rebuild and restart every hot-reload server once on 0.5.0.
2. Run `march --check` (or `forge check`) and fix each new error; the hints name
   the fix.
3. Search for `Config.put(`/`Config.get(`, `ClusterNode.start(`, `Actor.whereis`,
   `pid_of_int` and `RingBuf.` and migrate them as in § 4.
4. Replace any exit-code-127 check on `Process.*` with a match on `Err`.
5. Remove `--trmc` / `--no-trmc` from build scripts.
