# Boxed ADT cells carry a runtime type id

**Filed:** 2026-08-05 (as `specs/todos/2026-08-05-boxed-adt-type-id.md`)
**Landed:** 2026-09-11
**Plan:** `specs/plans/boxed-adt-type-id-plan.md` (survey, design, and the
constraints the design had to respect)

## What was wrong

A boxed constructor cell's header is `{ rc:i64; tag:i32; pad:i32 }`. `tag` is
the constructor index, numbered per type from 0, so `IOList.Str("x")` and a
user `B("x")` were byte-identical. The 2026-09-08 constructor-name table
(`lib/tir/llvm_ctor_desc.ml`, `march_ctor_table_ensure`) fixed every renderer
that has a STATIC type. What remained was the genuinely erased slot, where
mono cannot specialise:

- a value reaching `to_string` or a `~H` hole through a closure stored in a
  container (`Bx(Cons(fn x -> ~H"<p>${x}</p>", Nil))`) printed `#<tag:N>`,
  and a real `IOList` there was stringified instead of flattened (pinned as
  `poly_iolist` in `test/native/h_sigil_adt_interp`);
- a generic `Cons(a, ...)` field instantiated at a user ADT inside a
  described type (`H(Int, List(Shape))`) rendered its elements through the
  untyped renderer (`H(0, [#<tag:0>, #<tag:1>])`).

## What landed

**The stamp.** Every boxed constructor header store also writes a TYPE id into
the pad word (offset 12): `-(1 + (fnv1a32(type_name) & 0x3FFFFFFF))`, where
`type_name` is the `type_defs` name (`IOList.IOList`, `Http.Method`, or a bare
`Shape` for the entry module) — the same string the descriptor's `T` line
carries. `Llvm_toplevel.build_ctor_info` computes it once per constructor into
`ctor_entry.ce_type_id`; allocation sites never derive it from the constructor
string they hold, because `Llvm_data.ctor_entry` resolves that string by
suffix (`IOList.Segments` → the `IOList.IOList.Segments` entry) and the
prefix names the wrong thing. That mistake was made and caught during
implementation: the first cut hashed the site's prefix and IOList cells went
unstamped.

- `Llvm_data.emit_heap_alloc` stores the id only when nonzero (calloc already
  zeroed it). `Llvm_data.emit_store_tag` — the RESTAMP every FBIP reuse,
  alloc-hole and stack-cell path goes through — always writes the pad word,
  because reuse is matched by arity and the cell may have belonged to another
  type. The unboxed-aggregate box in `Llvm_ctx.coerce` stamps too.
- **The one cell that must KEEP its pad word is the actor struct**, which
  carries a record shape id there. Its state write-back reuses the one
  long-lived actor object in place on every handler call, so an unconditional
  pad write erased the shape and `get_actor_field` answered `None` for the
  rest of the process. That arm uses `emit_store_tag_keep_pad` (tag only);
  re-stamping the shape instead also worked but put a
  `march_record_set_shape` call in every handler's hot path, and the id is
  already correct because an actor struct is only ever reused as itself.
  `native/timer_send_after` and `native/actor_dispatch_rc_window` both caught
  this — deterministically, three runs out of three, with the base compiler
  green on the same fixtures. Neither is in `scripts/run-tests.sh`: they are
  dune-rule goldens, so `dune build @test/runtest` is the gate that sees them.
- Two adjacent `i32` stores rather than one packed `i64`, so the emitter
  stays endian-agnostic; at `--opt 2` LLVM folds them into ONE
  `store <2 x i32> <i32 tag, i32 id>` (verified on the emitted `.ll` through
  `opt -O2`), so the stamp costs no instruction.
- Negative by construction, so it is disjoint from the pad word's existing
  users, which the todo had under-counted: record shape ids (`> 0`, tag-0
  cells), the closure flag `MARCH_CLO_ARG0_BORROWED`, and the SIMD lane kind.
  `rec_shape_of` already rejects `id <= 0`. The two runtime sites that compare
  the whole 64-bit tag+pad word against `MARCH_MIGRATE_TAG` cannot collide
  with a stamped cell (ordinary tags are bounded by
  `MARCH_ORDINARY_CTOR_TAG_LIMIT`).

**The runtime.** `march_type_id_of_name` (the C half of the hash) and an
id → row-table index map filled as descriptors register
(`march_ctor_table_ensure`). A collision — two DIFFERENT names on one id in
one process — marks the id AMBIGUOUS and readers treat it as unknown; the
one outcome this mechanism must never produce is a wrong constructor name.
Two identical names (the REPL registers one descriptor per fragment) keep
the first index. The plan's compile-time duplicate check in
`Llvm_ctor_desc.assign_ids` was NOT added: the runtime rule is what makes a
collision harmless, and a compiler warning would only make it visible.

- `march_render_dyn_hook`: `march_value_to_string`'s `#<tag:N>` fallback asks
  the table to render by header id first. Installed when the first descriptor
  registers, so the WASM runtime and binaries with no erased render site never
  pay for it.
- `ctor_render`'s generic `'p'` slot resolves the header id before classifying
  by tag — that is what closes the nested-generic-field residual. Where a
  static id and the cell's own id disagree, the cell wins (it is ground truth
  for what was allocated). The row-mismatch fallbacks suppress the hook so a
  cell whose id resolved but whose tag did not match cannot loop.
- `march_html_auto_escape_dyn` / `march_html_escape_ctx_dyn`: the `~H`
  decision for an erased hole, made by identity — flatten iff the header says
  IOList (verbatim in HTML context, context-escaped elsewhere), otherwise
  render by name and escape. An unstamped cell (id 0) is escaped, never
  flattened on a tag guess. The static `march_html_auto_escape` guard, which
  could only reject tags `> 2`, now also declines a cell whose id says it is
  not an IOList — by rendering it by name and escaping it, the same outcome
  the erased path produces, rather than by widening that site's `abort` into
  a crash a running program could hit.

**The emitter dispatch.** The `TVar` arms of `emit_html_auto_escape`,
`emit_html_escape_ctx_static` and `emit_html_escape_ctx_dynamic`
(`lib/tir/llvm_emit_html.ml`) call the `_dyn` entry points; the generic
`to_string` arm and `stringify_for_escape` register the descriptor
(`Llvm_ctor_desc.emit_ensure_if_erased`) before handing the runtime an erased
value, since nothing on the runtime side can find the descriptor by itself.
All gated on `shape_meta` like `id_for`, because the runtime half lives in
`march_extras.c`, which the WASM runtime does not build.

## Proof

- `test/native/h_sigil_adt_interp.expected`: the three `poly_*` lines flipped
  to the interpreter's rendering. Proven RED (each printed `#<tag:N>`) on the
  pre-change compiler before any code changed; GREEN after.
- New `test/native/erased_type_id` (nested generic field, erased `to_string`,
  erased list, erased `~H` on an ADT / an IOList / a String): the same
  RED→GREEN, with the String line green throughout (the security baseline
  the dispatch exists to protect).
- `test_codegen` `type_id` group: pins the hash vectors on the OCaml side and
  that a constructor allocation emits the offset-12 store.
- **IR shape, 196 programs** (`test/native/*.march`, both compilers, private
  `HOME`, SSA numbering canonically renumbered so the stamp's renumbering
  cascade does not mask anything): **192 are byte-identical once the stamp's
  two lines are removed.** The four that are not are all accounted for:
  `h_sigil_adt_interp` differs in exactly six lines, the three erased `~H`
  holes moving from `value_to_string` + `html_escape_ctx` to
  `ctor_table_ensure` + `html_escape_ctx_dyn`; the other three newly emit the
  constructor descriptor (below).
- **Benchmarks, compiled `--opt 2`, A/B against a compiler built at the base
  commit, 11 interleaved runs a side, first discarded, medians:**
  `binary_trees` 0.220s both sides, `tree_transform` 0.650s both sides — no
  measurable delta, which is what the store fold predicts.
- `scripts/run-tests.sh`: green apart from two bookkeeping goldens that this
  change is supposed to move — the `llvm_builtins_preamble` byte-identical
  blob (two new `declare` lines) and `test/refine_audit/corpus.baseline` (the
  two lines the new fixture adds, and nothing else).

## What it costs

- **No instructions.** Two adjacent constant `i32` stores fold to one
  `store <2 x i32>`, and the benchmarks show no delta.
- **~17KB of rodata in a binary that newly needs the descriptor.** The
  constructor descriptor was previously emitted only where a STATIC render
  site referenced it; an erased render site now forces it too, because that
  string is how the runtime learns the names. Measured on
  `test/native/actor_call_canonical`: 97,608 → 114,824 bytes. Three of the
  196 corpus programs newly carry it (six in total do). This is the cost
  `Llvm_ctor_desc.id_for`'s doc comment warned about when the constant was
  *unreferenced*; here it is load-bearing, so the trade is different, but the
  size is real and a binary with no erased render site still pays nothing.
- The erased `~H` path no longer leaks its intermediate string: it used to
  build one with `march_value_to_string` and hand it to
  `march_html_auto_escape`, which never released it; the `_dyn` entry points
  own and release their own temporary. Ownership at the TIR level is
  unchanged — the builtin names are the same, only the emitted C symbol
  differs — so Perceus's decisions are untouched.

## What this does NOT close (corrected from the todo)

The todo claimed a header id would close residuals 1, 2, 3 and 5. It closes
1 and 5. **Niche `Option` (2) and newtype (3) have no cell to stamp** — a
niche `Some(x)` IS `x`, a newtype IS its payload — so stamping the payload's
cell with the payload's id just makes the renderer print the payload's
constructor, the same wrong answer `describable` refuses. Anonymous records
and tuples (4) still have no name to hash. Cells the C runtime builds itself
(`make_cons`, `make_some_i64`, `make_ok`, HTTP header pairs; ~100 sites)
carry id 0 and fall back to today's rendering; stamping them is a separate
follow-up. A `Trusted*`/`Safe` wrapper reaching an erased hole is rendered
as `Safe("...")` and escaped (the safe direction), not unwrapped.
