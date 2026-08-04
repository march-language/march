# Path-scoped capabilities

**Date:** 2026-08-04
**Status:** design, approved for implementation

Let a module narrow a filesystem capability to a directory:

```march
mod Config do
  needs IO.FileRead("/etc/myapp")
  needs IO.FileWrite("/var/log/myapp")
end
```

Today `needs IO.FileRead` is all-or-nothing: a module that reads one config
file declares the same capability as one that reads `/etc/shadow`.

---

## 1. Where the check happens

Both, with each half doing only what it can prove:

| call site | compile time | runtime |
|---|---|---|
| `file_read("/etc/myapp/db.conf")` — literal, in scope | silent | enforced |
| `file_read("/etc/shadow")` — literal, out of scope | **error** | n/a (won't build) |
| `file_read(p)` — computed | silent | **enforced** |

The static half is deliberately narrow. `refine_check.ml:64` records a
deliberate decision to model `String` as an uninterpreted sort and to stay out
of Z3's string theory — "staying decidable and cheap is the whole point of the
scoping". A literal-versus-prefix comparison needs none of that: it is plain
string containment, decided in the compiler, no solver involved.

This also matches refinecheck's existing definite-failure stance: report only
what is definitely wrong, stay silent otherwise.

---

## 2. Representation: scopes ride alongside the cap string

Ten modules consume capabilities as bare strings (`Cap_lattice`,
`emit_c_table`, `typecheck`, `cap_infer`, `cmd_cap`, `cmd_deploy_hot`,
`cap_sandbox`, `cap_package`, `cap_binary`, and the generated C lattice table).
A scope is therefore a **separate optional field**, never encoded into the
string:

```ocaml
type scoped = { cap : string; scope : string option }  (* None = all paths *)
```

Encoding it in-band (`"IO.FileRead:/etc"`) would break every one of those
consumers silently — the C lattice table is code-genned from
`Cap_lattice.hierarchy`, and a scoped string would match no hierarchy entry.

**Subsumption** layers one rule on the existing one:

> `a ⊒ b` iff `cap_subsumes a.cap b.cap` **and**
> (`a.scope = None` ∨ `b.scope` is at-or-beneath `a.scope`)

Unscoped subsumes scoped, so every existing declaration keeps its current
meaning. `needs IO.FileRead` still means "any path".

---

## 3. Grammar

```march
needs IO.FileRead("/etc/myapp")                     -- scoped
needs IO.FileRead("/etc"), IO.FileRead("/usr/share")-- union of two scopes
needs IO.FileRead                                    -- unchanged: all paths
```

`cap_path` gains an optional `( STRING )` suffix. `DNeeds` carries
`(name list * string option) list`. Backward compatible by construction: no
existing source changes meaning.

Scopes are only meaningful on filesystem capabilities. A scope on any other
capability (`needs IO.Network("/etc")`) is a **compile error** rather than a
silently ignored annotation — an ignored scope reads as enforcement that isn't
there.

---

## 4. Which builtins take a path

Verified against `builtin_cap_table` and the signature table:

| kind | builtins | scope check |
|---|---|---|
| path at arg 0 | `file_read` `file_open` `file_exists` `file_stat` `dir_list` `dir_exists` `file_write` `file_append` `file_delete` `dir_mkdir` `dir_mkdir_p` `dir_rmdir` `dir_rm_rf` | arg 0 |
| **two paths** | `file_rename` `file_copy` (`TArrow(t_string, TArrow(t_string, …))`) | **both args** |
| handle, not path | `file_read_line` `file_read_chunk` `csv_next_row` (arg 0 is `t_int`) | none — the handle came from a checked `file_open` |
| non-path | `csv_open` (arg 0 is `t_atom`) | none |

The handle rule is what makes this sound without dataflow: a handle cannot be
obtained except through an opening builtin, which *is* checked.

`file_copy` needs read on its source and write on its destination; it is
declared `IO.FileSystem`, which subsumes both.

---

## 5. Path normalization

Before any comparison, both the declared scope and the literal are normalized:
collapse `//`, resolve `.` and `..` lexically, strip trailing `/`. Without this
`"/etc/ssl/../shadow"` defeats a `/etc/ssl` scope.

Lexical resolution only — no filesystem access at compile time, since the
build machine's filesystem is not the deployment machine's. Symlinks are
therefore **not** resolved statically; Landlock resolves at the inode level so
the runtime half is safe, and this limit is stated rather than implied away.

A scope must be absolute. A relative scope is a compile error: it would mean
something different depending on the working directory at run time.

---

## 6. Runtime enforcement

Both backends do prefix scoping natively, so this is a small change to
`forge/lib/cap_sandbox.ml`:

| | unscoped today | scoped |
|---|---|---|
| macOS SBPL | `(allow file-read* …)` | `(allow file-read* (subpath "/etc/myapp"))` |
| Linux bwrap | `--ro-bind / /` | `--ro-bind /etc/myapp /etc/myapp` only |

This is what makes `IO.FileRead` **enforceable on macOS**, which the current
design records as impossible. The blanket deny failed because dyld must read
`/usr/lib` before user code exists; a *scoped allow* sidesteps that entirely —
permit the loader's paths plus the declared scope, deny the rest.

---

## 7. Scoped markers in the binary

Scoped markers are sound only if the scope comes from **emitted code**, never
from the declaration. A scope copied out of `needs` is a claim; a binary can
still call `march_file_read` with a computed path.

Emission rule, at the same `mangle_extern` choke point the existing markers use:

| emitted | meaning |
|---|---|
| `__march_cap_scope_IO_FileRead_<path>` | a call site passes this literal |
| `__march_cap_scope_IO_FileRead_DYNAMIC` | ≥1 call site passes a computed path |

**The load-bearing rule: every uncertainty resolves to `DYNAMIC`.** Over-
reporting uncertainty is safe; under-reporting it is the false-assurance
failure this design family exists to avoid. A binary with literals and no
`DYNAMIC` marker is a strong statement — every filesystem access targets a path
you can see. With `DYNAMIC`, the scope list is explicitly incomplete.

Measured (2026-08-04): path-bearing symbol names and pinned data globals both
survive `-dead_strip`, so either channel works; symbol names are chosen for
consistency with the existing markers.

---

## 8. Analysis point

TIR, at the call atom, plus local constant propagation through `let`-bound
literals.

Measured: `file_read("/etc/passwd")` lowers to `ALit (LitString …)` and
`file_read(full)` to `AVar` — distinguishable at the call site. An
argv-derived path stays a stack load with no constant behind it, so `DYNAMIC`
is detectable.

The optimizer folds some concatenations into literals by emission time
(`"/etc/" ++ "hosts"` became one constant). Analyzing at TIR forgoes those.
That costs precision, not soundness — a forgone literal becomes `DYNAMIC`,
which is the safe direction.

---

## 9. Components

| component | file | responsibility |
|---|---|---|
| scope algebra | `lib/caps/cap_scope.ml` (new) | normalize, `within`, scoped subsumption |
| grammar | `lib/parser/parser.mly`, `lib/ast/ast.ml` | optional `(STRING)` on `cap_path` |
| declaration storage | `lib/typecheck/typecheck.ml` | carry scopes on `module_caps` |
| static check | `lib/typecheck/typecheck.ml` | literal-vs-scope at path builtins |
| markers | `lib/tir/llvm_toplevel.ml` | scoped + `DYNAMIC` emission |
| sandbox | `forge/lib/cap_sandbox.ml` | scoped SBPL / bwrap rules |
| reporting | `forge/lib/cmd_cap.ml` | show scopes in `query` / `inspect` |

`cap_scope.ml` is separate from `cap_lattice.ml` so the existing string API is
untouched and the new algebra is unit-testable without a compiler.

---

## 10. Phasing

**Phase 1 (this change):** scope algebra, grammar, declaration storage, static
literal check, reporting. Ships a usable, testable feature: definite violations
become compile errors.

**Phase 2:** scoped sandbox profiles (the enforcement payoff) and scoped
markers with `DYNAMIC`.

Phase 1 alone is honest — it catches definite violations and documents intent.
It must not be *described* as enforcement until Phase 2 lands.

---

## 11. Testing

| test | guards |
|---|---|
| literal in scope → silent | no false positives |
| literal out of scope → error | the feature's whole point |
| computed path → silent | no false positives on dynamic paths |
| `..` escape (`/etc/ssl/../shadow`) → error | normalization actually applied |
| relative scope → error | scope means one thing |
| scope on `IO.Network` → error | no silently ignored annotations |
| unscoped `needs IO.FileRead` → all paths allowed | backward compatibility |
| scoped subsumption both directions | `/etc` ⊒ `/etc/ssl`, and not the reverse |
| handle builtins unchecked | `file_read_line` after a checked open |
| two-path builtins check both args | `file_rename(ok, bad)` errors |
