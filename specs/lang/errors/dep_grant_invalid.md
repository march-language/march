---
layout: docs
title: "dep_grant_invalid"
permalink: /docs/errors/dep_grant_invalid/
---

# `dep_grant_invalid`: a dependency grant, or the grants file, is malformed

A dependency grant is a list of strings in `needs` syntax
(`grant = ["IO.Console", "IO.FileRead(\"/srv/data/\")"]`; `grant = []` grants
nothing). forge passes the grants to the compiler in a grants file named by
`MARCH_DEP_GRANTS` (or `march --dep-grants FILE`): one package per line, with its
library root, the `forge.toml` position of the grant, and the grant text. This
error reports a grant that is not a valid scope list, or a grants file whose
entry is malformed, names a library root that does not exist, or names one that
is neither a library directory of the build nor a parent of one.

## A program that triggers it

```toml
[deps]
weather = { path = "../weather", grant = ["IO.FileRead(\"data/\")"] }
```

A path scope must be absolute, so `data/` is rejected, and the error points at the
`forge.toml` line.

## The fix

Write the grant as you would write the dependency's `needs` clause: capability
names from the lattice, path scopes absolute, host scopes as `host/path`. If you
wrote the grants file by hand, give each line four tab-separated fields and an
absolute library root that is on `MARCH_LIB_PATH`.

## Why the rule exists

A grant that cannot be read cannot be enforced, and silently ignoring it would
leave the dependency with more authority than you meant to give it.

See also: [the language reference](../capabilities.md).
