# `[P3]` An erased record released by a generic dec leaked its heap fields (FIXED)

Found while fixing `specs/progress/2026-10-12-erased-param-field-read-leak.md`.

A lambda whose parameter stays erased (`TVar`) because the container it is
stored in hides the element type now releases that parameter after reading a
field of it. The release is a plain `dec_rc` on a `TVar`, which the runtime
implements as `march_decrc`: it frees ONE cell and never its children, since
only the compiler knows a value's layout. When the lambda holds the last
reference (the caller handed over a record it no longer needs), the record's
heap fields (a String, a List) are never released.

Repro: `test/native/erased_param_field_read_leak_probe.march`'s `fresh` leg
with `rows(i)` (String names) instead of `scalar_rows(i)`: 3 objects per
iteration (the three name strings), against 6 before the fix.

The same shallow release applies to any erased value Perceus drops with a
plain `dec_rc` (the unused-parameter drop in `insert_dead_apply_param_drops`,
`Clo_flags`' trampoline release for generic named fns). Possible directions:
specialise such lambdas from the field set they read; or register a typed
drop per closure parameter type the way `march_clo_register_drops` registers
capture releases.

## Fixed 2026-10-12

The release site cannot be typed its way out of: the lambda's parameter is a
`TVar`, and the projections in its body name only the fields it reads. The
type is known only where the record is BUILT. So the record cell now carries
it, through its shape id, and the runtime runs the matching typed drop. This
is the same pattern as the closure capture releases (`march_clo_register_drops`).

- **Drop synthesis** (`lib/tir/drop.ml`, end of `run`): every record a
  function allocates (`ERecord`, or `EUpdate` on a structural record) gets its
  `__drop$R..` through `drop_fn_for` when it owns a heap field. The key comes
  from the field TYPES, exactly as the LLVM backend sees them
  (`Tir_names.atom_ty`, now also `Llvm_data.atom_tir_ty`).
- **Name contract** (`lib/tir/tir_names.ml`): `drop_type_key` (moved here from
  `Drop.mangle`) and `record_drop_fn_name fields`, so `Dce` and the LLVM
  backend can name the drop without depending on `Drop`.
- **Keep-alive** (`lib/tir/dce.ml`): a record allocation references its drop
  function, as a closure allocation references its `$clodrop$`.
- **Shape tag** (`lib/tir/llvm_data.ml`, `shape_desc_with_drop`): when the
  module defines the record's drop, its shape descriptor is
  `"name:k;..#__drop$R.."`. The suffix makes the shape id distinct per field
  types and not just per field kinds. Without it, `{ name : String }` and
  `{ name : List(Int) }` would share `"name:p;"`. The runtime's descriptor
  parser reads only the `name:k;` entries, so record introspection is
  unchanged. Shapes the runtime builds itself (`record_put`, `record_from_list`)
  carry no suffix and keep the old release.
- **Registration** (`lib/tir/llvm_toplevel.ml`): `march_clo_drops_register`,
  called from main's prologue (and the test runner's), also calls
  `march_record_register_drops` with (descriptor, id cache, drop) triples.
- **Release** (`lib/tir/llvm_emit.ml`, `llvm_emit_tcoarm.ml`): an `EDecRC` or
  `EAtomicDecRC` on a `TVar`-typed value (native targets) calls
  `march_decrc_erased_local` / `march_decrc_erased`. These run the
  registered drop for a record cell (tag 0, positive shape id) and otherwise
  fall back to `march_decrc_local` / `march_decrc`
  (`runtime/march_extras.c`). The drop is the typed one: it loads the
  fields, releases the cell with `march_decrc_freed`, and releases the fields
  only when that freed it, so a shared record keeps its children.

Not covered (still the old release): a record built only by the runtime; an
`EUpdate` on a NOMINAL record type whose drop no plain `ERecord` of the same
field types keeps alive; REPL fragments, which do not register. Each of these
is still a leak at worst, never a wrong layout: a drop is only attached to a
shape whose descriptor names it.

## Verification

- `test/native/erased_record_deep_release_probe.march`, 200 iterations each:
  rows with a String field 600 -> 0; String and List(String) fields 1800 -> 0;
  nominal records 600 -> 0; shared rows walked by four lambdas and then reread
  0 -> 0, same totals as the interpreter.
- `erased_param_field_read_leak_probe` unchanged.
- Linux arm64 ASAN error pass (`scripts/native-sanitize-sweep.sh`,
  `march-ci-ubuntu-step6b`) over the full native sweep with all three of
  the day's fixes, at 1 and 14 schedulers: no ASAN, UBSAN, RC-check or signal
  verdicts. 620 OK; the EXIT and DIFF rows are panics by design and
  post-processed goldens.
- `bench/list_ops`, `binary_trees` and `tree_transform`, `--compile --opt 2`,
  interleaved A/B against the base: CPU time unchanged within noise, and the
  output is byte-identical.
