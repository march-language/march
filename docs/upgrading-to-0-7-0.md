---
layout: docs
title: Upgrading to 0.7.0
nav_order: 2.15
permalink: /docs/upgrading-to-0-7-0/
---

# Upgrading from 0.6.x to 0.7.0

0.7.0 changes what Int arithmetic does on overflow, so read § 1 even if nothing
else here applies to you. § 2 matters only if you use `cap no_panic`, § 3 only
if you wrote a `Show`, `Eq`, `Ord` or `Hash` impl by hand, and § 4 only if you
hot-deploy to running nodes. § 5 lists smaller changes in the refinement and
termination checkers.

The full list of changes is in `CHANGELOG.md`.

```sh
forge toolchain install v0.7.0
forge toolchain use v0.7.0
```

---

## 1. Int `+`, `-`, `*` and unary `-` panic on overflow

Under 0.6.0 these operators wrapped: `int_max_value() + 1` was
`int_min_value()`. A result outside the 63-bit range [-2^62, 2^62) is now a
run-time panic, with the same message in the interpreter, in compiled code and
on `--target js`:

```
The program stopped with a run-time error: attempt to add with overflow
```

The other three messages say `subtract`, `multiply` and `negate`.

Most programs never reach the edge of the range and need no change. Code that
relied on wrapping does: a hash, a checksum, a random-number mixer. Switch
those sites to the new wrapping functions:

```march
int_wrapping_add(a, b)
int_wrapping_sub(a, b)
int_wrapping_mul(a, b)
```

`int_wrapping_add(int_max_value(), 1)` is `int_min_value()`, as `+` used to
give.

What did not change:

- `/`, `int_abs`, `int_pow` and `int_shl` still wrap.
- Derived `Hash` instances, the SIMD vector `Hash` impls and `Msgpack`'s int64
  decoder already use the wrapping functions, so their results are the same as
  under 0.6.0.
- Float arithmetic is unaffected.

The change exists because the refinement checker reasons about unbounded
integers. Under wrapping, it could "prove" `x + 1 > x` for an `x` where
`x + 1` was negative at run time.

## 2. `cap no_panic` must prove Int arithmetic cannot overflow

Because `+`, `-`, `*` and unary `-` can now panic, each one is a panic site.
A module that declares `cap no_panic` has to show that every such operation
stays in range, from the refinements, guards and `let` values in scope. One
that it cannot show is the new error `int_overflow`:

```
this addition may overflow Int in a `cap no_panic` module: nothing in scope
keeps the result within [-2^62, 2^62) (e.g. x = 4611686018427387903). [int_overflow]
```

Every Int the program holds counts as in range, so many common shapes pass
unchanged: `x - 1` where `x >= 0` is known, `x + 1` where `x < n` is known. A
bare `x + 1` on an unrefined `x` is now an error. You have three ways to fix
one:

- Bound the operand with a refinement, such as `{Int | _ < 1000000}`.
- Guard the operation: `if x < n do x + 1 else ... end`.
- Use `int_wrapping_add`, `int_wrapping_sub` or `int_wrapping_mul` where
  wrapping is what you want, or where the value is bounded by something the
  checker cannot see.

Modules without `cap no_panic` are not checked this way.

## 3. `Show`, `Eq`, `Ord` and `Hash` impls may not perform I/O

The four built-in interfaces are now bounded by `needs ()`. A hand-written
`show`, `eq`, `compare` or `hash` that prints, logs, reads the clock or uses
any other capability is rejected at the impl:

```
`show` in `impl Show(Box)` is bounded by built-in interface `Show`'s
`needs ()`, but reaches `IO.Console` (via println). [cap_bound]
```

Derived impls are unaffected. To fix a hand-written one, move the I/O out of
the impl and into the code that calls it.

## 4. Hot reload: rebuild and restart the base binary once

0.7.0 moves the hot-reload ABI to version 5, which older running servers
cannot accept. `forge` refuses to upload a 0.7.0 patch to a node started from
a 0.6.x binary, and says that a restart is needed. Rebuild the base binary
with 0.7.0 and restart each node once. After that, hot deploys work as before.

One more case now needs a restart. If a proof depended on the body of a
reflected function, a patch that changes that body is refused. Deploy that
change with a restart, or mark the function `@[opaque]` so that no proof can
depend on its body.

## 5. Stricter refinement and termination checks

These affect only code that uses `@[measure]` or the termination checker.

- **`@[measure]` must be reflectable.** A measure that cannot be reflected is
  the error `invalid_measure`, including when the reason is in a function it
  calls, such as one that prints, panics or loops. Under 0.6.0 some of these
  were accepted.
- **Mutually recursive measures are checked.** Two measures that call each
  other in a cycle are `invalid_measure` unless every call in the cycle passes
  a component of a parameter.
- **`@[diverges]` marks a function meant to run for ever**, such as an accept
  loop or a ticker. Nothing requires it unless a module declares the new
  `cap total`, which must prove that every function other than `main` and
  those marked `@[diverges]` terminates.
