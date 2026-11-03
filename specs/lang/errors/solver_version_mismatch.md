---
layout: docs
title: "solver_version_mismatch"
permalink: /docs/errors/solver_version_mismatch/
---

# `solver_version_mismatch`: a different z3 than the pinned one

The z3 this run used (from `MARCH_Z3` or `PATH`) is not the version this
toolchain is pinned to. It is used anyway, and refinements are checked, but
another z3 version can prove or fail to prove different obligations, so a
verdict here may differ from CI's and from other machines'.

It appears once per run, and only for a program with refinements of its own.

## The fix

Use the z3 that ships with the toolchain: unset `MARCH_Z3`, or reinstall the
toolchain if `libexec/z3` is missing.

```sh
unset MARCH_Z3
forge toolchain install
```

If you manage z3 yourself, install the version in `z3.version` (in the March
repository) and point `MARCH_Z3` at it.

## Why the rule exists

A verdict depends on the query, the z3 version and the resource limit. Pinning
the version is what makes a proof that passes on one machine pass on every
other, so using another one is allowed but never silent.

See also: [refinement types](../refinement-types.md).
