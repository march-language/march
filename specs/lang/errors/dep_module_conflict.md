---
layout: docs
title: "dep_module_conflict"
permalink: /docs/errors/dep_module_conflict/
---

# `dep_module_conflict`: under dependency grants, a module name is defined by two packages

A dependency grant (`grant = [...]` on a dependency in `forge.toml`) limits every
function defined in that dependency's package. A module belongs to the package
whose library root holds its file. When a build has grants, each granted package,
the code under no granted root (your project and any ungranted dependency), and
the standard library are separate sides, and one module name may be defined on
only one of them. This error reports a module name defined on two sides, or a
granted library root that lies inside one of your project's own directories.

## A program that triggers it

Your project's library and a granted dependency both define `Weather`:

```march
mod Weather do
  fn forecast() : String do "sunny" end
end
```

and, in the dependency `weather` (granted `IO.Console` in `forge.toml`):

```march
mod Weather do
  fn forecast() : String do "rain" end
end
```

`march --check` (or `forge build`) reports:

```text
Module `Weather` is defined twice under dependency grants: in `lib/weather.march`
(outside any granted package) and in `deps/weather/lib/weather.march` (package
`weather`). [dep_module_conflict]
```

The same error is reported when a dependency defines a module the standard
library defines (`List`, `Csv`, ...), or when a granted dependency's library root
lies inside your project's source directory or library directory.

## The fix

Rename one of the modules, or remove the copy that should not be built. If the
dependency sits inside your project's tree, move it out (or drop its grant).

## Why the rule exists

Without grants, the compiler keeps the first module of a given name it finds and
silently ignores the others. With a grant in force that would be a hole: a
dependency's module could replace one of yours (or of the standard library) and
run with your authority instead of under its grant, or one of your modules could
end up counted as the dependency's. Builds with no grants keep the old behaviour.

See also: [the language reference](../capabilities.md).
