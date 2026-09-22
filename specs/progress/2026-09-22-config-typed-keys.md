`[P2]` # Config typed keys — closes "Config needs a tagged value boundary"

Filed 2026-08-15 as `specs/todos/2026-08-15-config-erased-values.md`; the
original text is kept below, followed by the owner's decision and the fix.

# (filed) Config needs a tagged value boundary

`Vault(v)` now carries a phantom element type, so a bound Vault handle rejects
storing an `Int` and reading it as a `Pid`. `Config` deliberately opts out of
that rule: its process-global table is heterogeneous, and `Config.get` remains
polymorphic at every call site.

That leaves the old erased-value confusion reachable through the public Config
API. The following witness typechecks, then fails at runtime when `is_alive`
receives the stored `Int` as though it were a `Pid`:

```march
mod M do
  needs IO.Console
  needs IO.Mut

  fn main(_cap_console : Cap(IO.Console), _cap_mut : Cap(IO.Mut)) do
    Config.put(:config_erased_witness, :value, 42)
    match Config.get(:config_erased_witness, :value) do
      Some(p) -> println(bool_to_string(is_alive(p)))
      None    -> println("missing")
    end
  end
end
```

Observed on 2026-08-15:

- `--check` succeeds.
- Interpretation reaches `is_alive` and reports `is_alive: expected Pid`.

This is not fixed by adding another phantom parameter to Vault. Config needs a
tagged/dynamic value representation and checked extraction or an explicitly
typed Config API. Any future fix must preserve heterogeneous storage while
making an `Int`-as-`Pid` read fail before an actor builtin receives the value.

## Acceptance criteria

- The witness no longer reaches `is_alive` with an unchecked value.
- Heterogeneous Config storage continues to support existing Int/String/Bool
  use cases.
- The failure is explicit and recoverable rather than a runtime representation
  error or process crash.
- Both interpreter and compiled execution agree on the behavior.

## Decision (repo owner, 2026-09-22): typed keys

Of the two shapes offered above, the owner chose an **explicitly typed Config
API** over a tagged/dynamic value representation exposed to callers: typed keys,
the same idea as `Vault(v)`'s phantom element type. A key is minted as
`Config.key(:ns, :name, …) : Config.Key(v)`, and `Config.put(key, value : v)` /
`Config.get(key) : Option(v)` take the key instead of a bare `(ns, name)` pair,
so each key carries its value type while the underlying storage stays
heterogeneous.

Minting a key from a name has the same door as `Vault.new/open/whereis` (see
`specs/progress/2026-08-14-vault-typed-handles.md`, "Honest limits" item 1):
two mints of one `(ns, name)` can choose different `v`. How that door is closed
is recorded below.

## What shipped (2026-09-22)

**API.** `stdlib/config.march`:

| | |
|---|---|
| `Config.key(ns, name, codec : Codec(v)) : Key(v)` | 2-level path `:ns/:name` |
| `Config.key_in(ns, section, name, codec) : Key(v)` | 3-level path |
| `Config.put(key : Key(v), value : v) : Unit` | |
| `Config.get(key : Key(v)) : Option(v)` | `None` = unset **or** stored at another type |
| `Config.fetch(key : Key(v)) : Result(v, Config.Error)` | `KeyMissing(path)` / `KeyWrongType(path, expected, found)` |
| `get_with_default`, `require`, `validate`, `from_env`/`_int`/`_bool` | take a key instead of `ns, key` |
| `new_store(name) : Vault(Config.Value)`, `store_put`/`store_get`/`store_fetch` | same keys, isolated table |
| codecs `int() float() string() bool() atom() list(c)`, `codec(name, enc, dec)` | |
| `put_endpoint`, `endpoint_port/host`, `secret_key_base`, `env`, `is_*` | unchanged signatures; now via `endpoint_port_key()` etc. |

Removed (subsumed by `key_in` + the key-taking forms): the untyped 3-arg
`put`/2-arg `get`, `put_in`, `get_in`, `get_in_with_default`, `require_in`,
`validate_in`, `store_put_in`, `store_get_in`. No untyped compatibility shim
was kept: an untyped `put(ns, name, value : v)` cannot be implemented without
choosing `v` at the call site, which is the bug. CHANGELOG `### Changed`
carries the migration.

**How the minting door is closed: the codec is the key's type, as a value.**
The `Vault(v)` residual is that `Vault.open(name)` lets the caller *choose*
`v`. A typed `Config.key(ns, name)` with no other argument would have exactly
that door (two mints of one path at two types), and the owner's sketch left
the mechanism open. A "store a runtime type tag and compare it on `get`"
scheme needs the key to know its expected type AT RUNTIME, and March has no
runtime type information to ask for: compiled, an `Int` is an unboxed `i64`
and a `Pid` is a pointer, and no builtin reifies a type variable. So the key
carries the tag as a value: `Key(v) = Key(path, Codec(v))`, where
`Codec(v) = Codec(name, v -> Value, Value -> Option(v))` and `Value` is a
closed tagged sum (`CfgInt | CfgFloat | CfgString | CfgBool | CfgAtom |
CfgList`). The table is `Vault(Value)` — monomorphic, no `: Vault(v)` erased
opt-out any more. `put` encodes through the writing key's codec; `get`
decodes through the READING key's codec, which returns `None` for any other
tag. Consequences:

- **No way to mint `Key(v)` at an unchecked `v`.** `v` is fixed by the codec
  argument's type. A caller-built codec is fine: it must typecheck as
  `Value -> Option(v)`, and the only `v`s it can produce are ones it can build
  from a `Value` (a codec polymorphic in `v` can only ever decode `None`, by
  parametricity). There is no codec for `Pid`, and none can be written
  without an erased primitive — so the witness's route to `is_alive` is gone.
- **No value restriction is needed**, unlike `Vault(v)`: `let k =
  Config.key(:a, :b, Config.int())` is `Key(Int)` with no free variable to
  re-generalise.
- **Two mints of one path at different types** still typecheck (the
  typechecker cannot see that two paths are equal), and their disagreement is
  a recoverable read failure: `get` → `None`, `fetch` →
  `Err(KeyWrongType(":ns/:name", "String", "Int"))`.
- What stays open is Vault's own residual, not Config's: code that
  `Vault.open("__march_config__")` / `Vault.whereis` of a store's name can
  still mint a handle at another element type.

**Keys are strings now.** A path is stored as `":ns/:name"` /
`":ns/:section/:name"`. Found while reproducing: the old tuple keys
(`(ns, key)`) PANICKED on every compiled Config call (`Vault: unsupported key
kind (a constructor/tuple value)`), so interpreted and compiled did not even
fail the same way. Config now works compiled at all.

Also: `Config` now declares `needs IO.Mut` / `needs IO.Process` (it calls
`vault_new` and `process_env`); `--check stdlib/config.march` reported the
missing `needs` before this change too, hidden by the stdlib-diagnostic
filter.

## Verification

- **Witness red, before** (origin/main `70af5b0dc`): the todo's program
  `--check`s clean; interpreted it reaches `is_alive: expected Pid`; compiled
  it panics on the tuple key.
- **After:** the same program is rejected by `--check` (the untyped
  `Config.put(:ns, :name, 42)` no longer exists; the arity mismatch reads
  "This is not a function — it has type `()`"). Spelled with typed keys it is
  `specs/lang/types/reject/t285_config_typed_key_read_as_pid.march`:
  ``expected `Pid(s2)` but got `Int` ``. Accept twin `t286`.
- **Runtime half, both backends:** `test/native/config_typed_keys.march`
  writes through `key(..., int())` and reads the same path through
  `key(..., string())` (`None`, and `fetch` names both types), plus
  heterogeneous Int/String/Bool/Float/Atom/List storage, endpoint, validate
  and named stores; `test/dune` runs it interpreted AND compiled against one
  `.expected`.
- `test/stdlib/test_config.march` migrated (50 cases incl. wrong-type reads
  and a custom codec).
