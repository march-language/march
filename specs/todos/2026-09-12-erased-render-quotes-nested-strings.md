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

## Attempt 2026-09-17 — got most of the way, backed out

Tried and reverted. The mode threading itself works; the entry-point inventory
in "Why it is not a one-line fix" above is **incomplete**, which is what sank
it. What was built:

- `repr` threaded through `ctor_render` / `ctor_render_field`
  (`CTOR_REPR_BARE` / `CTOR_REPR_QUOTED`), with the `'s'` arm and the generic
  default arm's `is_str` branch honouring it.
- The typed entry split in two, because `to_string` and `~H` share
  `Llvm_ctor_desc.emit_to_string`: `march_value_to_string_typed` kept its
  quoting for `~H`, and a new `march_value_to_string_typed_show` added for
  `to_string`.
- `ctor_render_dyn` (the `march_render_dyn_hook`) set to BARE, and a new
  `ctor_render_repr` plus `march_value_to_string_repr` added for the untyped
  `~H` path in `stringify_for_escape`'s `None` arm.

**Result: the acceptance case passes** — a compiled erased
`to_string(["a","b"])` prints `[a, b]`, matching the interpreter — **but
`h_sigil_adt_interp` still loses its quoting on the two `poly_*` legs**
(`poly_tag1`, `poly_tag2`, the TVar-hole cases at lines 121-124). Those emit
`march_value_to_string_repr`, so they DO reach the new quoted entry, and their
header ids resolve (they render `B(...)` by name, not `#<tag:N>`), yet the
nested string still comes out bare. Not explained. The next attempt should
start by instrumenting `ctor_render_repr`'s return on exactly that leg rather
than re-deriving the threading.

Two more things the original writeup did not list, both of which the next
attempt needs:

1. **`stringify_for_escape`'s `None` arm** (`lib/tir/llvm_emit_html.ml`) calls
   the plain `march_value_to_string`, so flipping the dyn hook to BARE silently
   takes the untyped `~H` path with it. `march_html_auto_escape_dyn` is NOT the
   only untyped `~H` route.
2. **`ctor_put_generic`** (`runtime/march_extras.c`) falls back to
   `march_value_to_string` for any cell the table cannot walk, so a QUOTED
   render loses its convention at that boundary no matter how the entry points
   are split. A correct fix has to carry the mode across that fallback too.

The suite was not run against the reverted-out version; the only evidence above
is the two fixtures. Nothing landed.
