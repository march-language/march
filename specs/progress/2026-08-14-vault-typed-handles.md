`[P2]` # Vault typed table handles — `Vault(v)`, phantom in the element type

Closes item 3 of `specs/todos/2026-08-12-vault-toward-ets-semantics.md`
("typed table handles"), filed out of the named-registry design. Items 1 and 4
of that file shipped 2026-08-12; item 2 (write partitioning) stays open and
deliberately unmotivated — see the staleness note there.

## The hole

`vault_get`'s scheme was `∀t k v. t -> k -> Option(v)` — `t` (the handle) and
`v` (the element) were unrelated variables, so the element type was chosen
fresh at every call site. Storing an `Int` and reading it back as a `Pid`
typechecked, and the resulting fake Pid was dereferenced as an actor record on
the next `send`. Erlang does not have this problem because it is dynamically
typed end to end; March is not.

## What shipped

**A phantom element parameter on the handle.** `Vault(v)` is a new arity-1
entry in `builtin_types` (`lib/typecheck/typecheck.ml`), and the raw
`vault_*` builtins were retyped against it:

| builtin | before | after |
|---|---|---|
| `vault_new` | `String -> t` | `String -> Vault(v)` |
| `vault_whereis` | `String -> Option(t)` | `String -> Option(Vault(v))` |
| `vault_set` | `t -> k -> v -> Unit` | `Vault(v) -> k -> v -> Unit` |
| `vault_get` | `t -> k -> Option(v)` | `Vault(v) -> k -> Option(v)` |
| `vault_update` | `t -> k -> f -> Unit` | `Vault(v) -> k -> ((v) -> v) -> Unit` |
| `vault_incr` | `t -> k -> Int -> Int` | `Vault(Int) -> k -> Int -> Int` |
| `vault_push_capped` | `t -> k -> v -> Int -> Unit` | `Vault(List(e)) -> k -> e -> Int -> Unit` |
| `vault_keys` | `t -> List(k)` | `Vault(v) -> List(String)` |

`incr`/`push_capped` are pinned to the cell shape the C runtime actually
reads and writes (`march_vault_incr` an integer cell, `march_vault_push_capped`
a list cell) rather than left generic, and `keys` now returns the stringified
keys it really returns instead of the caller's key type — a second, quieter
erasure in the same module.

**No key parameter — decided against, with evidence.** The design note
sketched `Vault(k, v)`. Keys are stringified by `vault_key_cstr` before they
reach the table, so (a) a key-type mismatch is a silent MISS, never a value
read at the wrong type — there is no memory-safety hole for `k` to close —
and (b) `stdlib/config.march` deliberately keys ONE table with both 2-tuples
(`(ns, key)`) and 3-tuples (`(ns, section, key)`), which no single `k` can
describe. A key parameter would have cost a working stdlib module to buy
nothing.

**The parameter is only worth anything with a value restriction.** March
generalizes let-bound applications (there is no value restriction:
`let xs = List.reverse([])` is `∀a. List(a)` today). Without a restriction,
`let t = Vault.new("t")` would be `∀v. Vault(v)`, `Vault.set(t, "k", 42)`
would instantiate `v := Int` and `Vault.get(t, "k")` would instantiate
`v := Pid(_)` independently — the phantom parameter would be decoration.
`demote_vault_handle_vars` demotes every var occurring **under** a `Vault`
constructor to level 0 (reusing `demote_to_monomorphic`, the same mechanism
the `cap_narrow`/`mint_cap`/`from_json` value restrictions already use), at
the three generalization sites where a handle can be bound without saying what
it holds:

- block `let` with no annotation (`Ast.ELet`),
- top-level `let` with no annotation (`Ast.DLet`),
- a `fn`/local `fn` with no return annotation.

It is scoped to `Vault`: a type that does not mention `Vault` anywhere changes
generalization behaviour by exactly zero variables.

**Writing the annotation is the opt-out.** `fn table() : Vault(v)` keeps a
handle factory polymorphic. That is what `Vault.new`/`open`/`whereis` and
`Config.global_table`/`Config.new_store` now use, and it makes element erasure
explicit and greppable instead of ambient.

## Honest limits — what this does NOT close

1. **`new`/`open`/`whereis` still choose `v`, they do not check it.**
   `Vault.set(Vault.open("t"), "k", 42)` and
   `Vault.get(Vault.open("t"), "k") : Option(Pid)` in two places still
   typecheck: each call mints a handle at whatever type its context wants. A
   name-keyed process-global table cannot do better without a type-indexed
   registry (a genuinely bigger feature). The mitigation is the one the
   docstrings now state: bind the handle once and pass it around.
2. **`ns_set`/`ns_get`/`ns_drop` are fully erased.** They take a namespace
   *string*, so there is no handle to carry `v`. Marked ELEMENT-ERASED in the
   docstrings, with a pointer to the handle API.
3. **`Config` is as erased as Vault used to be.** `Config.get(:ns, :key)`
   returns whatever the caller asks for. This is not a regression — it is
   where a heterogeneous store's erasure was all along — but it does mean the
   Int-read-as-Pid confusion is still reachable through `Config`, and closing
   *that* needs a tagged/dynamic value type, not a phantom parameter.

## Compatibility

- **Runtime: nothing changed.** No representation, layout, RC, or codegen
  change. `Vault(v)` lowers to `Tir.TCon("Vault", [_])`, which classifies
  `Boxed` and `needs_rc = true` — the same treatment the erased handle already
  got via `TPtr TUnit`, and the same treatment `Pid(a)` gets. TIR
  golden snapshots are unchanged.
- **The runtime-owned `$actor_registry` table is untouched.**
  `runtime/march_runtime.c` calls `march_vault_set`/`march_vault_get` directly
  in C; that path never passes through the typechecker, so it neither gains
  nor loses a check. March-level code that observes the raw registry table
  (`test/native/actor_registry_retire_vault.march`) goes through
  `Vault.whereis` + `Vault.keys`, and `keys`' new `List(String)` result is
  what that test already wanted.
- **Source compatibility:** one element type per table needs no change. A
  single bound handle holding several unrelated types now needs separate
  tables or the `: Vault(v)` annotation. In-tree, exactly one call site was
  affected — `Config.put_endpoint`, which bound `let tbl = global_table()` and
  then wrote an `Int` port and two `String`s into it; it now calls
  `global_table()` per write, which is the erased factory re-instantiating,
  and a comment says so.

## Verification

- Reject witness `specs/lang/types/reject/t178_vault_element_type_confusion.march`
  (store `Int`, read as `Pid`) — accepted before, rejected after with
  ``expected `Pid(…)` but got `Int` ``.
- Accept witness `specs/lang/types/accept/t177_vault_typed_handle.march` —
  every handle-taking op in the module used at one coherent element type,
  plus two further tables at other element types in the same scope.
- `dune build @types-check`, `scripts/run-tests.sh`, `run_snapshots.exe`.
