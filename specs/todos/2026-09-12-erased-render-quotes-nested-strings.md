# An erased render quotes nested strings; the interpreter does not

**Filed:** 2026-09-12 — **pre-existing on `origin/main`**, not introduced by
the stamping work of the same day. Measured, not assumed (see below).

## The gap

```march
let cb = Bx(Cons(fn x -> to_string(x), Nil))     -- erased (TVar) slot
println(apply_first(cb, Cons("a", Cons("b", Nil))))
```

```
interpreted:  [a, b]
compiled:     ["a", "b"]
```

Measured both ways on 2026-09-12 with a worktree built at `origin/main`
(`62945f09`) and the same program compiled by each:

| | `origin/main` | after the file-error stamping |
|---|---|---|
| compiled-built `List(String)`, erased slot | `["a", "b"]` | `["a", "b"]` |

Identical, so the quoting is the pre-existing behaviour of the constructor
table's renderer, not a consequence of stamping more cells. Stamping makes it
reachable for C-BUILT lists too (`string_split`, `string_chars`), which is why
it is worth writing down now: the same divergence will simply show up in more
places.

## Why it happens

`ctor_render` (`runtime/march_extras.c`) deliberately mirrors
`March_eval.Eval_runtime.value_to_string` — the interpreter's Show-less,
repr-style fallback — which QUOTES a nested string. Its own comment says so,
and that choice is right for the `~H` path: `test/native/h_sigil_adt_interp`
pins `list=<p>["&lt;script&gt;…"]</p>` as the interpreter's own rendering
there.

But an erased `to_string` is not the repr path. The interpreter reaches it
through the `Show` instance, where `to_string` of a `String` is the string
itself, so it prints `[a, b]`. One renderer is serving two conventions.

## Why it is not a one-line fix

Flipping the quoting would fix the `to_string` path and BREAK the `~H` path,
whose golden pins the quoted form. `ctor_render` needs to know which
convention its caller wants — a repr/Show mode threaded from the entry point
(`march_value_to_string_typed`, `ctor_render_dyn`,
`march_html_auto_escape_dyn`) down through `ctor_render_field`'s `'p'` and
`'A'` arms — rather than a global change of heart.

## Acceptance

An erased `to_string` of a `List(String)` prints `[a, b]` compiled, matching
the interpreter, while `test/native/h_sigil_adt_interp` keeps its quoted
`~H` rendering unchanged.
