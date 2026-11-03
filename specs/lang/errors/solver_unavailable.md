---
layout: docs
title: "solver_unavailable"
permalink: /docs/errors/solver_unavailable/
---

# `solver_unavailable`: refinements were not checked

March proves refinement types with the z3 SMT solver. Every release archive
ships the pinned z3 at `libexec/z3`, next to `bin/march`. This warning means
the compiler could not use any z3 on this run, so none of the program's
refinements were checked. The build still succeeds; under `cap verified`, where
an unproved obligation is an error, that error says the solver could not be run.

It appears once per run, and only for a program with refinements of its own.

## What triggers it

- No z3 was found. March looks in `MARCH_Z3`, then next to the running `march`
  (`<install>/libexec/z3`, through symlinks such as forge's `~/.march/current`),
  then on `PATH`. A source build (`dune install`, opam) has no `libexec/z3`.
- `MARCH_Z3` names a file that does not exist.
- The z3 found does not start, or `z3 --version` fails or prints something that
  is not a version.
- z3 exited, or stopped answering for 60 seconds, partway through the run.

## The fix

Reinstall the toolchain, which puts the pinned z3 back:

```sh
forge toolchain install
```

Or point `MARCH_Z3` at a z3 of the pinned version (`z3.version` in the March
repository):

```sh
export MARCH_Z3=/path/to/z3
```

## Why the rule exists

Without a solver every obligation comes back undecided, and before this warning
that looked exactly like a program whose refinements all happened to be hard: an
install that "worked" and checked nothing.

See also: [refinement types](../refinement-types.md).
