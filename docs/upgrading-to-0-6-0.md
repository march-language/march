---
layout: docs
title: Upgrading to 0.6.0
nav_order: 2.2
permalink: /docs/upgrading-to-0-6-0/
---

# Upgrading from 0.5.x to 0.6.0

0.6.0 is a small release. Most programs compile and run unchanged. Read § 1 if
you use `Uri.merge_strict` or `HttpTransport` with untrusted input, since both
have security fixes. §§ 2 and 3 cover the two changes that can affect code
that worked under 0.5.0.

The full list of changes is in `CHANGELOG.md`.

```sh
forge toolchain install v0.6.0
forge toolchain use v0.6.0
```

---

## 1. Security fixes: upgrade if these apply to you

- **`Uri.merge_strict` now rejects every `..` that climbs above the root.**
  Under 0.5.0, merging `../../../etc/passwd` against a base path `/a/b/c`
  returned `Ok(...)` with path `etc/passwd`. It is now an `Err`, and so is a
  `..` in an absolute-path reference (`/../etc/passwd`). If you use
  `merge_strict` to check relative references from users or the network,
  upgrade. Your code doesn't change.
- **`HttpTransport.request` uses verified TLS for `https://` URLs.** The simple
  request functions used to reject `https://` URLs or risk sending them over a
  plain socket. They now connect with TLS, send SNI and verify the server's
  certificate. A request to a server whose certificate does not verify now
  fails. The lower-level functions that take a raw file descriptor still reject
  HTTPS.

## 2. Sending a message to the wrong actor is a compile error

`send` used to accept any message for any pid. A message sent to an actor that
has no handler for it compiled, and was dropped silently at run time. When the
types show the mismatch, the checker now rejects it:

```
`Poke` is a message for `A`, but this pid points to an actor whose state is
`{ s : String }`, so the message would be dropped. [send_wrong_actor]
Send it to a pid spawned from `A`, or send this actor one of its own messages.
```

A program that hits this error had a bug under 0.5.0: the message never
arrived. To fix it, send the message to a pid of the actor that handles it.

The same error catches **two actors with a handler of the same name**. A bare
`Tally` resolves to only one of them, and an actor message can't be qualified
by its actor's name. Under 0.5.0 the interpreter and compiled code disagreed
about where such a message went. Rename one of the two handlers.

A pid's type is its actor's state type, so two actors whose state records have
the same shape still can't be told apart. The checker doesn't catch a wrong
send between them.

## 3. `Uri.parse` and `Uri.merge` follow RFC 3986 for relative references

- **A string without a scheme is a path unless it starts with `//`.**
  `Uri.parse("../d")` used to give host `..`. Now `../d` and `a/b` are paths,
  and `//other.com/x` has host `other.com` and path `/x`. A `://` inside a path
  or query (`/go?to=http://x`) no longer creates a scheme.
- **Merging keeps the leading `/`.** Under 0.5.0, merging `../../../x` against
  `https://example.com/a/b/c` gave `"https://example.comx"`. Now it gives
  `"https://example.com/x"`. Dot segments are also removed from absolute-path
  and network-path references, and a reference that is only a fragment keeps
  the base's query.

Code that read the old results, for example by taking the host of a
scheme-less string, gets different values now. Check the places where you
parse relative references.
