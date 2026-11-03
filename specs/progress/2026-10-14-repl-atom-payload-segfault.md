# REPL segfault on an atom inside a value; compiled `Option(Atom)` miscompile

Found 2026-10-14 while turning stdlib doc examples into checked transcripts
(`scripts/check-stdlib-doctests.py` feeds `march>` lines to `march repl`):
`UUID.parse("not-a-uuid")` killed the native REPL with SIGSEGV (exit 139).

## Symptoms

| input at `march repl`          | before              | after                |
|--------------------------------|---------------------|----------------------|
| `Err(:invalid)`, `Ok(:a)`      | exit 139            | `= Err(:invalid)` …  |
| `Some(:a)`                     | exit 139            | `= Some(:a)`         |
| `[:a, :b]`, `(:a, 1)`          | exit 139            | `= [:a, :b]` …       |
| `UUID.parse("not-a-uuid")`     | exit 139            | `= Err(:invalid)`    |
| `:a`                           | `= :a` (see below)  | `= :a`               |
| `[Some(1), None]`              | `= [Some(1), null]` | `= [Some(1), None]`  |

The interpreter was right throughout. `--compile` did not crash, but an
`Option(Atom)` built from a literal atom was wrong:

```march
fn pick(b : Bool) : Option(Atom) do if b do Some(:a) else None end end
match pick(true) do Some(x) -> x == :a ... end   -- false compiled, true interpreted
to_string(pick(true))                            -- Some(:<atom>) compiled
```

## Root causes

1. **REPL printer: no Atom case.** `Repl_jit.pp_word` (lib/jit/repl_jit.ml)
   had arms for Int/Bool/Unit/Float/TVar and sent every other type to
   `pp_heap_value`. An atom is an i64 FNV hash (`Llvm_ctx.atom_hash`), never a
   heap cell, so the printer read a "constructor tag" 8 bytes past the hash
   and faulted. A bare `:a` only printed because its fragment failed to emit
   and `repl.ml` silently fell back to the interpreter.

2. **Codegen: literal atom payload allocated boxed.** The `arg_tir_ty`
   matches in `Llvm_emit_alloc` (the niche alloc, niche reuse, and the repr
   audit) had no `LitAtom` arm, so a literal atom typed as `TUnit`.
   `niche_payload_ok TUnit` is false, so `Some(:a)` became a boxed heap cell,
   while every decode site (`Llvm_case`, `Show$Option`) reads `Option(Atom)` as
   a niche. The match bound the cell's address as the atom.

3. **`Kind.payload_needs_tag` said an atom is stored untagged.** Its TCon arm
   asks `repr_of`, which answers Boxed for `Atom` (no variant). But
   `Llvm_ctx.coerce` tags an i64 atom `(h<<1)|1` on its way into a ptr slot.
   So the niche decode used `tagged=false`, and the REPL printer (which reads
   the same `Kind.Niche.tagged`) got the tagged word.

## Fix

- `lib/tir/kind.ml` `payload_needs_tag`: `TCon ("Atom", []) -> true`.
- `lib/tir/llvm_emit_alloc.ml`: `LitAtom -> TCon ("Atom", [])` in the three
  `arg_tir_ty` matches.
- `lib/jit/repl_jit.ml`: `pp_word` and `pp_heap_value` get an Atom arm
  (untag with an ARITHMETIC shift; `atom_hash` keeps bit 63 equal to bit 62
  for this), and `run_expr` an Atom return arm. Names come from two tables:
  atom literals of every lowered fragment (`record_atom_lits`) and the
  runtime's namer registry, which the stdlib precompile fills.
  `march_atom_name_cstr` (runtime/march_runtime.c) is the new public, C-string
  entry to that registry, dlsym'd by `Repl_jit.create`. It returns a C string
  so the caller never has to decode an SSO immediate. An unknown hash prints
  `:<atom>`, as compiled code does.
- `pp_word` used to print `null` for a zero word before the niche decoder ran.
  It now lets `pp_heap_value` name a niche's nullary constructor (`None`).

## Tests

`test/test_jit.ml`:
- `repl_session` "atoms inside values print": ORC, clang and interpreter.
  The JIT cases exit 139 without the printer fix.
- `jit_file` "--compile Option(Atom) literal payload matches and prints":
  without the codegen fix it prints `matched=false` and `Some(:<atom>)`.

## Not fixed here

`march --jit` prints `:<atom>` for `to_string(:zz)` even for a bare atom in
`main`. The program's `Show$Atom` resolves to a precompiled table that lacks
the program's own atoms. This is separate from the niche bug and predates it.
