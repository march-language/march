# An erased render quotes nested strings; the interpreter does not

**Filed:** 2026-09-12. **Fixed:** 2026-09-24. The original write-up and the
backed-out 2026-09-17 attempt follow the resolution below, unchanged.

## Resolution (2026-09-24)

### What caused the `poly_tag1`/`poly_tag2` symptom

The poly legs never reached the 2026-09-17 attempt's `march_value_to_string_repr`.
A TVar `~H"<p>${x}</p>"` hole lowers to **`html_escape_ctx` with escaper 0**, not
to `html_auto_escape`. In the emitted IR of the fixture, each poly lambda
(`$lam…$apply`) calls `march_ctor_table_ensure` and then
`march_html_escape_ctx_dyn(i64 0, ptr %x)`. `march_html_escape_ctx_dyn` called
the plain `march_value_to_string`, and that goes through the dyn hook. The
attempt had set the hook to BARE for every type, so `B("<script>")` rendered
bare. The `march_value_to_string` calls that the attempt did switch to repr
(`vts_str…` in `@march_main`) belong to the statically typed `some`/`none`/
`record`/`tuple` holes, not to the poly legs. It is easy to read them as the
poly calls in the IR.

Instrumented to confirm. With a `TRACE` fprintf in `march_html_escape_ctx_dyn`
and `march_html_auto_escape_dyn`, a compiled copy of the fixture printed
`TRACE escape_ctx_dyn(esc=0)` once before each of `poly_tag1` and `poly_tag2`.
`auto_escape_dyn` never fired. With only `march_html_escape_ctx_dyn` flipped
back to the show convention, the new golden's `html_erased_list` and
`html_erased_ok` lines went bare. So this third untyped `~H` route is enough to
break the repr convention. The entry-point inventory had missed it.

### Fix

The convention is an explicit argument, not a thread-local and not a global:

- `march_value_to_string_mode(v, repr)` (runtime/march_runtime.c) is the generic
  renderer. `march_value_to_string` is `mode(v, 0)`, the **show** convention.
  The new `march_value_to_string_repr` is `mode(v, 1)`. The dyn hook is now
  `(v, repr)`, so the convention survives the generic renderer's hand-back to
  the table.
- `ctor_render` / `ctor_render_field` take `repr`. A nested String is quoted
  iff `repr`. **Show switches to repr below any type other than
  List/Option/Result** (`ctor_type_shows_elements`). This is exactly the
  interpreter's `show_dispatch`: those three have prelude `Show` impls that
  `show` each element, and every other constructor or record falls back to
  the repr-form `value_to_string`, which quotes all the way down. So erased
  `to_string` gives `[a, b]` and `Ok(x)`, but `B("x")`, `P(1, ["a"])` and
  `[B("x"), A]`, all matching the interpreter. A single global BARE, as the
  2026-09-17 attempt used, would have printed `B(x)`.
- `ctor_put_generic` and the generic-slot fallback call
  `march_value_to_string_mode(v, repr)`, which carries the mode across the
  boundary the todo flagged.

### Entry points

| Entry point | Reached from | Convention | Why |
|---|---|---|---|
| `march_value_to_string` | erased `to_string` (`llvm_emit.ml`, the `_` arm), `Show$String.show` | show | the interpreter's `to_string` is `show_dispatch` |
| `march_value_to_string_typed` | typed `to_string` (`Llvm_ctor_desc.emit_to_string`) and `stringify_for_escape`'s `Some` arm | repr | `~H` needs repr (`h_sigil_adt_interp`'s `list=`/`ok=`). For `to_string` it is also Show's answer, because a static List/Option/Result is routed to its prelude Show impl before this builtin. The static type here always lacks a Show impl, so Show falls back to repr (pinned by `typed_list_of_adt` and `typed_adt_holding_list`). |
| `stringify_for_escape` `None` arm (`llvm_emit_html.ml`) | typed `~H` holes the table cannot name (tuple, anonymous record, niche Option, qualified names) | repr (`march_value_to_string_repr`); plain on WASM (`shape_meta` off, no ctor table there) | `~H` is `value_to_string` |
| `march_html_escape_ctx_dyn` | TVar `~H` hole (escaper 0 and every context escaper) | repr | **the poly_tag route** |
| `march_html_auto_escape_dyn` | TVar `html_auto_escape` | repr | `~H` |
| `march_html_auto_escape`'s stamped-non-IOList recovery | mis-dispatched cell | repr | `~H` |
| `ctor_render_dyn` (the hook) | `march_value_to_string_mode` | as passed | none of its own |
| `ctor_put_generic`, generic-slot fallback | inside `ctor_render` | inherits | carries the mode across the generic renderer |

### Evidence

- New golden `test/native/erased_render_show` (dune rule `native_erased_render_show`,
  `.expected` = the interpreter's output). It is **red on `origin/main`**: the
  fix files were swapped back to `origin/main` and the rule was rebuilt. It
  differs on 6 lines (`erased_list=["a", "b"]`, `erased_c_built_list`,
  `erased_list_list`, `erased_ok=Ok("x")`, `erased_results`,
  `erased_empty_str=[""]`), and is **green** with the fix.
- `native_h_sigil_adt_interp` is unchanged, including `poly_tag1`/`poly_tag2`.
  `native_erased_type_id`, `native_to_string_ctor_names`,
  `native_qualified_type_name_render`, `native_compare_builtins` and
  `native_from_json_dispatch` are green.
- run_codegen groups `~H sigil codegen`, `llvm_builtins_preamble_golden`
  (updated for the new `declare`), `type_id`, `llvm_emit correctness`, `repr`,
  `iolist stdlib`, `repl_jit_regression`, `repl_jit_cross_line`,
  `llvm_ir_validity_gate`, `erased_record_update_codegen` and
  `string_literal_codegen` pass: 89 tests, exit 0.

### Residuals (pre-existing, not this item)

- A single-field constructor over a type variable (`type Wrap = W(a)`) renders
  as its bare payload when compiled (`W("x")` gives `x`), typed and erased,
  where the interpreter prints `W("x")`. This is a representation issue (the
  wrapper cell is elided), not the string convention.
- An erased value of a user type that has its own `impl Show` still renders
  through the table (repr). The runtime cannot see user impls.

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
