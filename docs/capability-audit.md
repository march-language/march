---
layout: docs
title: Capability Audit
nav_order: 15.5
permalink: /docs/capability-audit/
---

# Capability Audit

**The question:** a dependency you already trusted ships an update. Did it start
touching the filesystem? Opening sockets? Reading environment variables?

In most ecosystems that question has no mechanical answer. `npm audit`,
`cargo audit` and `pip-audit` answer a different one: *does this version appear
in a vulnerability database?* That is a lookup of what someone has already
reported. No field in a `package.json` or `Cargo.toml` states what a package is
allowed to do, so "what authority does this code hold?" can only be approximated
by sandboxing it, scanning it heuristically, or reading it.

March can answer it by reading declarations, because March has declarations to
read: every module states the capabilities it needs, and the compiler checks
those declarations against what the code does.

How strongly it checks depends on how the capability is obtained, and the
difference matters enough to state up front:

- A capability passed as a value (a function taking `Cap(IO.FileWrite)`) **must**
  be covered by a declared `needs`, or the module does not compile.
- A capability builtin called directly (`file_write(path, data)`) produces a
  **warning** when undeclared, not an error. The code still builds.

So a package's declared capability set is a strong signal, checked by the
compiler and impossible to drift silently for capability-passing code. It
is not yet a hard lower bound for every code path. See
[what this does not prove](#what-this-does-and-does-not-prove) for what follows
from that.

Two commands use that.

| Command | Asks | Needs a build? | Attributes to a dependency? |
|---|---|---|---|
| `forge audit` | Did my dependencies' **declared** capabilities change? | No | **Yes** |
| `forge cap inspect <binary>` | What does this **compiled artifact** actually hold? | Yes | **Yes** (per module) |

They answer different questions and neither replaces the other. This page is
about the first; see [`forge cap inspect`](#auditing-a-compiled-binary) below for
the second.

---

## `forge audit`: capability diffing on dependency update

Record the capability set of your dependency tree once, and commit it:

```
$ forge audit --record
recorded 4 dependencies to forge.caps.lock
```

`forge.caps.lock` is a small, reviewable file:

```toml
[[package]]
name = "liba"
caps = ["IO.FileRead"]
```

From then on, `forge audit` compares the tree against that baseline. When
no declaration has changed it is quiet:

```
$ forge audit
capabilities unchanged across 4 dependencies
```

When a dependency asks for more than it used to, it reports it and **exits 1**:

```
$ forge audit
  ! liba — now ALSO needs: IO.FileWrite, IO.NetConnect

1 dependency is asking for capabilities it did not have.
Review the change, then accept it with `forge audit --record`.
```

That is the whole workflow: review the change like any other diff, then
`forge audit --record` to accept it and commit the updated baseline.

### In CI

The exit code is the gate. No plugin, no service:

```yaml
- name: Dependency capability audit
  run: forge audit
```

A pull request that bumps a dependency into new authority fails until someone
records the new baseline, which puts the change in the diff, where a reviewer
sees it.

### What counts as a failure

Only **new** authority fails the audit:

| Change | Reported | Exit code |
|---|---|---|
| A dependency gains a capability | `! name: now ALSO needs: …` | 1 |
| A new dependency that declares capabilities | `+ name: new dependency, declares: …` | 1 |
| A new dependency that declares none | `+ name: new dependency, declares no capabilities` | 0 |
| A dependency drops a capability | `- name: no longer needs: …` | 0 |
| A dependency is removed | `- name: dependency removed` | 0 |

Narrowing does not fail. A gate that fires when a dependency becomes *safer* is
a gate people learn to skip, and skipped gates are a step down from absent ones.

---

## What this does and does not prove

This section is the important one. A capability report that is trusted further
than it deserves is more harmful than no report, because it converts an open question
into a settled one.

### It proves

- **A change in declared authority is surfaced, transitively.** Every
  dependency, including dependencies of dependencies, is traversed and compared.
- **The comparison is exact.** Capability paths are compared as declared. There
  is no fuzzy matching and no heuristic scoring to tune.
- **Attribution is per-dependency.** You learn *which* package changed, not just
  that your application's total authority moved.
- **Capability-passing code cannot under-declare.** Where a capability is
  threaded as a `Cap(X)` value, an undeclared use is a compile error, so the
  declaration is a true lower bound for that code.

### It does not prove

- **That a dependency declared everything it uses.** A module calling a
  capability builtin directly (`file_write(…)` rather than receiving
  `Cap(IO.FileWrite)`) gets a *warning* when it has not declared the
  capability, and still compiles. A dependency that ignores that warning will
  show a smaller capability set here than its behaviour justifies. The warning
  is visible when you build, so this is obvious rather than silent, but `forge
  audit` on its own will not catch it. Treat the declared set as a floor that
  capability-passing code cannot go under, not as an upper limit on everything.
- **What the code does with a capability.** `IO.Network` covers a telemetry ping
  and an exfiltration channel equally. The audit narrows *what is possible*; it
  does not characterise intent.
- **Anything past an `extern` block.** A dependency that calls into C declares
  `IO.Foreign`, and the compiler's knowledge stops at that boundary. The C can
  do anything the process can. Treat `IO.Foreign` as *"the list above is no
  longer complete"* rather than as one more row.
- **That the shipped artifact matches this source.** `forge audit` reads the
  dependency sources resolved into your project. If you want a statement about a
  binary, including one built elsewhere, that is
  [`forge cap inspect`](#auditing-a-compiled-binary), which reads what the
  compiler actually emitted rather than what the source claims.
- **Anything about non-March dependencies.** A package that vendors a shared
  library is described by its March declarations only.

### Threat model

| Threat | Covered? |
|---|---|
| Dependency update silently widens **declared** authority | **Yes**: this is the case it exists for |
| A new transitive dependency arrives with capabilities | **Yes**: reported as an addition |
| A dependency uses a `Cap(X)` value it did not declare | **Yes**: compile error, at build time |
| A dependency calls a capability builtin it did not declare | **Partly**: compiler warning at build time, but it compiles, and the declared set stays understated |
| Baseline edited to hide a change | Partly: the edit is in your diff, reviewed like any other |
| Effects through `extern` C, `dlopen`, or raw syscalls | **No**: reported as `IO.Foreign`, which constrains no behaviour |
| A dependency that misuses a capability it validly possesses | **No**: out of scope for any capability system |

For the row that is only partly covered, `forge cap inspect` on the built binary
is the stronger check: it reads capability markers the compiler emitted and
capability-bearing runtime symbols that persisted through dead-stripping, so a direct
builtin call shows up there whether or not it was declared.

---

## Auditing a compiled binary

`forge audit` reads source declarations. To ask what a *built artifact* possesses,
including the effect of dead-stripping, and evidence that does not depend on
trusting the source tree, use `forge cap inspect`:

```
$ forge cap inspect ./build/myapp
$ forge cap inspect ./build/myapp --deny IO.Network
$ forge cap inspect ./build/myapp --allow-only IO.Console,IO.FileRead
```

It cross-checks capability markers the compiler emitted, capability-bearing
runtime symbols remaining after dead-strip, and an embedded manifest when present. The
gate is fail-closed: `--deny` and `--allow-only` fail on a binary with coverage
that is not full, and foreign code requires an explicit `--allow-foreign`.

It also reports **which module** performs each capability's IO, not just that
the binary performs it:

```
Capabilities — ./build/myapp
  IO.Console              [march_print]
  IO.FileRead             [march_file_read]

Attributed to
  IO.Console            MyApp
  IO.FileRead           Conduit.Store
```

That is the difference between "this binary reads files" and "this binary reads
files *because of this dependency*". Attribution is computed before inlining:
by codegen time a small dependency function has been folded into its caller, and
attributing there would credit the dependency's IO to your application. A
capability reached only through an indirect call is reported as *unattributed*
rather than omitted.

Add `--strict` to re-check the capability upper limit on a binary you did not build:

```
$ forge cap inspect --strict ./build/myapp
forge cap inspect: module `HostileDep` uses `IO.FileRead` but does not declare `needs IO.FileRead`
```

Binaries carry each module's declared `needs` alongside its measured use, so the
two can be compared without the source. It fails closed on a binary that includes
no attribution, rather than reporting a clean upper limit for one with an upper
limit that cannot be read.

Use both. `forge audit` tells you which dependency changed and does so before
anything is built; `forge cap inspect` tells you what the artifact you are about
to ship actually includes, and which module in it is responsible.

### Reading is not enforcing

Both commands on this page *read*: they report authority, they do not restrain
it. The one place a capability declaration is *enforced* at build time is the
capability upper limit, which fails the build when any module's emitted code uses
a capability it did not declare, including a dependency that never opted in.
It is on by default; `--no-cap-strict` turns it off.
See [capability upper limits]({{ site.baseurl }}/docs/capabilities/#cap-strict).

The rows above marked "constrains no behaviour" (`IO.Foreign`, raw syscalls, an
undeclared builtin call) are a limit of *reading a declaration or a symbol
table*, not a limit of what March can enforce. To turn the declared set into an
actual OS-level confinement, one that bounds even `extern` C and raw syscalls
because it confines the whole process, see [OS-level
enforcement]({{ site.baseurl }}/docs/capability-enforcement/#os-level-enforcement-sandboxing-the-compiled-binary):
`forge cap run` (a sandbox forge installs around the binary) and `--cap-sandbox`
(a deny-default profile the binary installs on itself at startup).

---

## See also

- [Capabilities]({{ site.baseurl }}/docs/capabilities/): the language feature
  these tools report on
- [Capability Enforcement]({{ site.baseurl }}/docs/capability-enforcement/):
  [OS-level enforcement]({{ site.baseurl }}/docs/capability-enforcement/#os-level-enforcement-sandboxing-the-compiled-binary)
  (`forge cap run`, `--cap-sandbox`) that turns a declared set into a real sandbox,
  and node-local hot-deploy admission control
- [Safety by Construction]({{ site.baseurl }}/docs/safety-by-construction/):
  how capabilities sit alongside the other safety axes
- [FFI]({{ site.baseurl }}/docs/ffi/): the `extern` boundary, and why analysis
  stops there
