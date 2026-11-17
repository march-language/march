`[P3]` - [x] **Compiled: a payload atom's cell is never freed.**

Filed 2026-11-17, with the payload-atom representation
(`specs/progress/2026-11-17-compiled-payload-atom-match.md`).

`Atom` is not reference counted (`Kind`: `TCon ("Atom", [])` is an `i64`
immediate), and a payload atom (`:ok(7)`) is a heap cell under that type
(`Tir_names.atom_cell_ctor`). Perceus therefore never drops one: each
evaluation of `:ok(x)` that escapes its function leaks one cell of n + 2
slots, plus whatever its payload holds. A cell that does not escape is
stack-allocated by escape analysis and costs nothing.

A match arm takes its own reference to each payload field
(`Llvm_case`, the payload-atom binding). This is sound because the cell keeps
its references forever.

**What a fix needs.** Make `Atom` reference counted, with the drop and
increment guarded by bit 0: an odd value is a nullary atom and has no count.
That touches `Kind` (`needs_rc_of`, and `repr` stays `Imm`), `Rc_types`, the
EIncRC/EDecRC emitters, which skip non-ptr values today, and every runtime
site that receives an `Atom`. After that, a match arm's field increments
follow the ordinary owned/borrowed hand-off instead of always taking a
reference.

## Fixed 2026-11-17

`Atom` is now reference counted. It works like `String`: a `ptr`-typed value
that is either an immediate or a heap cell.

- **Representation** (`Kind`):
  - `llvm_ty` is `ptr` and `needs_rc`/`borrowable` are true; the layout is
    `Heap`.
  - In an erased slot an atom is stored raw (`payload_needs_tag` is false), so
    a container that holds a payload atom owns a real reference to it.
  - A nullary atom is its odd hash. Every RC entry point already skips an odd
    value (`IS_HEAP_PTR`), so `:none` costs nothing. The wasm runtime's RC is
    a no-op.
  - A parameter is a plain `ptr`, with no `dereferenceable`.
- **The cell owns its payload.** The runtime destructor for `MARCH_ATOM_TAG`
  releases every payload slot whenever the cell is freed, on every free path
  (`march_run_resource_dtor_slow`), as a typed array's does.
- **Match** (`Llvm_case`):
  - The switch reads the atom with a plain `ptrtoint`; labels are untagged.
  - When an arm consumes the scrutinee (Perceus starts its body with the
    scrutinee's release), each binder takes its own reference before that
    release runs. If the release frees the cell, the destructor drops the
    cell's references. This holds whether the cell was unique or shared.
  - A borrowed scrutinee's binders take nothing.
  - Perceus never encodes an atom scrutinee's release for FBIP reuse
    (`Perceus_core`), so a cell is never reused in place.
- **Atom values everywhere else**:
  - Literals are `inttoptr` constants.
  - `==` compares the bits inline and calls `march_atom_eq` only for two
    cells.
  - A record or ADT field of type `Atom` compares with `march_atom_eq`.
  - Shape kind `p`; constructor-descriptor kind `a`, which renders the name
    through the runtime's atom tables.
  - The generated `@march_atom_to_string` takes a `ptr`.
  - The four runtime builtins that return an atom (`file_close`, `csv_close`,
    `send_checked`, `revoke_cap`) are declared returning `ptr`.
  - `march_poly_eq` and `march_value_to_string` recognise an atom cell in an
    erased slot.
- **The REPL printer** (`Repl_jit.pp_atom`) reads atoms raw and renders a
  cell's payload by the kinds in its metadata word: strings, inline strings
  and nested cells.
- **Scalar assumptions removed**: `Borrow.is_scalar_field_ty`,
  `Alloc_contract.scalar_result` and `Dce`'s scalar-aggregate test no longer
  treat `Atom` as unable to hold heap data.

**Tests**: `test/test_codegen.ml` `payload_atom_codegen`, case "payload-atom
cells are released". It runs 2,000 iterations that build escaping payload
atoms:
- returned from a function;
- matched twice while still live;
- kept in a list;
- nested in another payload atom;
- held in a record field.

It requires `live_allocs()` to come back to where it started. Before the fix
it grew by 26,000 cells, 13 per iteration. Both payload-atom programs also run
clean under `MARCH_SANITIZE=1`.
