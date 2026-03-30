# Depot + Bastion Integration Plan

**Status**: Design | **Version**: 0.4 | **Author**: Claude

---

## Overview

This document is the full design and implementation plan for the Phoenix/Ecto-style Depot integration into Bastion. It covers every layer: schemas, changesets (Gate), the Repo API, query builder, migrations, contexts, testing sandbox, and generators.

### Design principles

1. **Everything is a plain function call.** No macro-like DSL blocks, no `schema "table" do ... end`, no `create table "users" do ... end` magic.
2. **Data structures over builder chains.** Pass a map describing what you want, not a pipe chain of 15 `add` calls. March maps preserve insertion order (they're assoc lists), so column order is deterministic.
3. **No hidden state.** Schema values are plain data returned by `schema/0`. Repos get their pool from config. Queries are composable values.

### What already exists

| Component | Status | Location |
|-----------|--------|----------|
| `Depot.Gate` | ✅ Done | `stdlib/depot_gate.march`, 79 tests |
| `Bastion.Depot.with_pool/2` | ✅ Done | `stdlib/bastion.march` |
| Migration file format (raw SQL) | ✅ Draft spec | `specs/bastion/depot-integration.md` |
| Changeset/Gate design | ✅ Draft spec | `specs/depot/changesets.md` |

### What this plan adds

1. **`Depot.Schema`** — typed schema definitions as maps
2. **`Depot.Gate` v2** — map-based `cast/3` operating on structs/maps with diff tracking (evolving the existing string-pair Gate)
3. **`Depot.Repo`** — repository API (`all`, `get`, `get!`, `get_by`, `one`, `insert`, `update`, `delete`, `transaction`, `preload`)
4. **`Depot.Query`** — composable pipe-friendly query builder (`where`, `select`, `join`, `order_by`, `limit`, `group_by`, `having`, `fragment`)
5. **`Depot.Migration`** — migration functions taking column maps
6. **`Depot.Test`** — sandbox mode for concurrent test isolation
7. **Forge generators** — `forge depot.migrate`, `forge depot.rollback`, `forge depot.gen.migration`, `forge bastion.gen.schema`, `forge bastion.gen.context`, `forge bastion.gen.html`, `forge bastion.gen.json`

---

## 1. Depot.Schema

A schema is a plain March value produced by calling `Depot.Schema.define/2` with a table name and a map describing fields and associations. No builder functions, no special syntax — one function call, one data structure.

### 1.1 Defining a schema

```march
mod MyApp.User do
  import Depot.Gate

  fn schema() ->
    Depot.Schema.define("users", %{
      fields: %{
        name:          String,
        email:         String,
        age:           (Int, %{default: 0}),
        role:          (String, %{default: "user"}),
        password_hash: String,
        confirmed_at:  (UtcDatetime, %{nullable: true}),
        metadata:      (Map, %{default: %{}}),
        password:      (String, %{virtual: true}),
        inserted_at:   UtcDatetime,
        updated_at:    UtcDatetime
      },
      belongs_to: %{
        org: MyApp.Org
      },
      has_many: %{
        posts: MyApp.Post
      },
      has_one: %{
        profile: MyApp.Profile
      },
      many_to_many: %{
        tags: (MyApp.Tag, %{join_through: "users_tags"})
      }
    })
end
```

The second argument to `define/2` is a map with these keys:

| Key | Value shape | Required |
|-----|------------|----------|
| `fields` | `%{name: Type}` or `%{name: (Type, %{opts})}` | yes |
| `belongs_to` | `%{name: SchemaMod}` or `%{name: (SchemaMod, %{opts})}` | no |
| `has_many` | `%{name: SchemaMod}` or `%{name: (SchemaMod, %{opts})}` | no |
| `has_one` | `%{name: SchemaMod}` or `%{name: (SchemaMod, %{opts})}` | no |
| `many_to_many` | `%{name: (SchemaMod, %{join_through: "table"})}` | no |
| `primary_key` | Atom (default `:id`) | no |

For fields: bare `Type` means no options. `(Type, %{opts})` for defaults, nullable, virtual.

A simpler schema with no associations:

```march
mod MyApp.Post do
  fn schema() ->
    Depot.Schema.define("posts", %{
      fields: %{
        title:     String,
        body:      String,
        published: (Bool, %{default: false}),
        user_id:   UUID,
        inserted_at: UtcDatetime,
        updated_at:  UtcDatetime
      },
      belongs_to: %{user: MyApp.User}
    })
end
```

### 1.2 Field types

| Field type | Postgres type |
|-----------|---------------|
| `String` | `TEXT` |
| `Int` | `BIGINT` |
| `Float` | `FLOAT8` |
| `Bool` | `BOOLEAN` |
| `UUID` | `UUID` |
| `UtcDatetime` | `TIMESTAMPTZ` |
| `Date` | `DATE` |
| `Time` | `TIME` |
| `Map` | `JSONB` |
| `List` | `JSONB` |
| `Binary` | `BYTEA` |

### 1.3 Field options

| Option | Type | Meaning |
|--------|------|---------|
| `default` | Any | Default value for blank structs and INSERT |
| `nullable` | Bool | Whether the field can be None (default false) |
| `virtual` | Bool | Field exists in struct but not in DB table |

### 1.4 Association options

| Association | Options |
|------------|---------|
| `belongs_to` | `foreign_key` (default `:{name}_id`), `references` (default `:id`) |
| `has_many` | `foreign_key`, `through` (e.g. `[:line_items, :product]`) |
| `has_one` | `foreign_key` |
| `many_to_many` | `join_through` (required — the join table name) |

### 1.5 Schema inspection API

```march
mod Depot.Schema do
  fn define(table: String, spec: Map) -> Schema

  fn table(schema: Schema) -> String
  fn fields(schema: Schema) -> Map
  fn primary_key(schema: Schema) -> Atom
  fn association(schema: Schema, name: Atom) -> Option(AssocMeta)
  fn virtual?(schema: Schema, field: Atom) -> Bool
  fn blank(schema: Schema) -> Map
end
```

`Depot.Schema.blank/1` returns a map with all field defaults applied:

```march
let blank = Depot.Schema.blank(MyApp.User.schema())
-- blank.name      => ""     (String default)
-- blank.role      => "user"
-- blank.age       => 0
-- blank.id        => None   (primary key, not yet persisted)
```

---

## 2. Depot.Gate (v2 — map-based)

The existing `Depot.Gate` operates on `List((String, String))` — flat string-pair lists. This section describes the v2 evolution: Gate operates on **maps and structs**, just like Ecto changesets operate on structs and maps.

### 2.1 Core concept: base + params = changes

A Gate tracks the **diff** between a base struct/map and incoming params:

- **base** — the existing data (a blank schema struct for inserts, a DB record for updates)
- **params** — the incoming user input (from a form, JSON body, etc.)
- **changes** — only the fields that actually differ from base
- **errors** — validation errors grouped by field: `%{field: [messages]}`

`cast/3` only records a change when the param value **differs** from the base value. This means `Depot.Repo.update` can generate `SET` clauses for only the fields that actually changed.

### 2.2 Gate type (v2)

```march
type Gate = Gate(
  Map,               -- base: the struct/map being operated on
  Map,               -- changes: fields that differ from base
  Map,               -- errors: %{field: [messages]}
  Bool,              -- valid?
  List(DbConstraint) -- DB constraint hints
)
```

### 2.3 `cast/3`

```march
fn cast(base, params, fields) do
  -- Only allow listed fields through from params
  let allowed = Map.filter(params, fn (k, _) -> List.member(fields, k))
  -- Only keep values that actually differ from base
  let changes = Map.filter(allowed, fn (k, v) ->
    case Map.get(base, k) do
      Some(existing) -> existing != v
      None           -> true
    end
  )
  Gate(base, changes, %{}, true, Nil)
end
```

### 2.4 Insert flow (base is a blank struct)

```march
-- params come from a form submission
let params = %{name: "Alice", email: "alice@test.com", password: "secret123"}

-- base is the blank schema struct with defaults
let blank = Depot.Schema.blank(MyApp.User.schema())
-- => %{name: "", email: "", role: "user", password_hash: "", ...}

let gate = cast(blank, params, ["name", "email", "password", "role"])
-- gate.base    => %{name: "", email: "", role: "user", ...}
-- gate.changes => %{name: "Alice", email: "alice@test.com", password: "secret123"}
-- "role" was in the allow list but not in params, so no change — keeps default "user"

let gate = gate
  |> validate_required(["name", "email", "password"])
  |> validate_length("password", [LenMin(12)])
-- gate.errors => %{password: ["should be at least 12 character(s)"]}
-- gate.valid  => false
```

### 2.5 Update flow (base is an existing DB record)

```march
let user = MyApp.Repo.get!(MyApp.User.schema(), id)
-- user => %{id: "abc", name: "Alice", email: "alice@test.com", role: "user", ...}

let gate = cast(user, %{name: "Alicia", role: "user"}, ["name", "role"])
-- gate.base    => %{id: "abc", name: "Alice", role: "user", ...}
-- gate.changes => %{name: "Alicia"}
-- "role" was "user" in both base and params, so it's NOT a change
-- Repo.update will only SET name='Alicia', not touch role
```

### 2.6 Full schema module with Gate functions

```march
mod MyApp.User do
  import Depot.Gate

  fn schema() ->
    Depot.Schema.define("users", %{
      fields: %{
        name:          String,
        email:         String,
        password_hash: String,
        role:          (String, %{default: "user"}),
        confirmed_at:  (UtcDatetime, %{nullable: true}),
        password:      (String, %{virtual: true}),
        inserted_at:   UtcDatetime,
        updated_at:    UtcDatetime
      }
    })

  fn registration_gate(params) ->
    cast(Depot.Schema.blank(schema()), params, ["name", "email", "password", "role"])
    |> validate_required(["name", "email", "password"])
    |> validate_length("name", [LenMin(2), LenMax(100)])
    |> validate_format("email", "@")
    |> validate_length("password", [LenMin(12)])
    |> hash_password()
    |> unique_constraint("email", [ConstraintName("users_email_index"),
                                   ConstraintMessage("has already been taken")])

  fn update_gate(user, params) ->
    cast(user, params, ["name", "role"])
    |> validate_required(["name"])
    |> validate_length("name", [LenMin(2), LenMax(100)])
    |> validate_inclusion("role", ["user", "admin", "moderator"])

  pfn hash_password(gate) ->
    case get_change(gate, "password") do
      Some(pw) ->
        gate
        |> put_change("password_hash", Crypto.bcrypt_hash(pw))
        |> delete_change("password")
      None -> gate
    end
end
```

### 2.7 Gate v2 API

```march
mod Depot.Gate do
  -- Construction
  fn cast(base: Map, params: Map, fields: List(String)) -> Gate

  -- Field access
  fn get_field(gate: Gate, field: String) -> Option(Any)
  -- checks changes first, then base

  fn get_change(gate: Gate, field: String) -> Option(Any)
  -- only looks in changes

  fn put_change(gate: Gate, field: String, value: Any) -> Gate
  fn delete_change(gate: Gate, field: String) -> Gate

  -- Error access
  fn add_error(gate: Gate, field: String, message: String) -> Gate
  fn errors(gate: Gate) -> Map
  -- => %{email: ["too short"], name: ["is required"]}
  fn get_errors(gate: Gate, field: String) -> List(String)
  -- => ["too short"] or []
  fn is_valid(gate: Gate) -> Bool

  -- Validators (unchanged from v1, but operate on map-based Gate)
  fn validate_required(gate: Gate, fields: List(String)) -> Gate
  fn validate_length(gate: Gate, field: String, opts: List(LengthOpt)) -> Gate
  fn validate_format(gate: Gate, field: String, pattern: String) -> Gate
  fn validate_inclusion(gate: Gate, field: String, values: List(Any)) -> Gate
  fn validate_exclusion(gate: Gate, field: String, values: List(Any)) -> Gate
  fn validate_number(gate: Gate, field: String, opts: List(NumberOpt)) -> Gate
  fn validate_acceptance(gate: Gate, field: String) -> Gate
  fn validate_confirmation(gate: Gate, field: String) -> Gate
  fn validate_change(gate: Gate, field: String, validator: fn(Any) -> Option(String)) -> Gate

  -- DB constraint hints
  fn unique_constraint(gate: Gate, field: String, opts: List(ConstraintOpt)) -> Gate
  fn foreign_key_constraint(gate: Gate, field: String, opts: List(ConstraintOpt)) -> Gate
  fn no_assoc_constraint(gate: Gate, field: String, opts: List(ConstraintOpt)) -> Gate
  fn check_constraint(gate: Gate, field: String, opts: List(ConstraintOpt)) -> Gate
  fn apply_constraint_error(gate: Gate, db_error: Error) -> Gate

  -- Association support
  fn cast_assoc(gate: Gate, assoc: String, gate_fn: fn(Map) -> Gate) -> Gate
  fn put_assoc(gate: Gate, assoc: String, structs: List(Map)) -> Gate
end
```

### 2.8 How Repo uses the Gate

`Depot.Repo.insert` reads `gate.base` merged with `gate.changes` to build the INSERT. `Depot.Repo.update` uses the primary key from `gate.base` and only SETs the fields in `gate.changes`:

```march
-- Insert: merges base + changes into a full row
-- UPDATE users SET name='Alice', email='alice@test.com', password_hash='...',
--   role='user', inserted_at=now(), updated_at=now()
-- WHERE id = gen_random_uuid() RETURNING *

-- Update: only touches changed fields
-- UPDATE users SET name='Alicia' WHERE id='abc' RETURNING *
```

If a DB constraint is violated, `Repo.insert`/`Repo.update` maps the Postgres error back into the gate's error map using the constraint hints registered via `unique_constraint`, `foreign_key_constraint`, etc.

### 2.9 Migration path from v1

The current `cast/2` (string-pair list, no base) remains available for standalone validation without a schema. The new `cast/3` (base map, params map, field list) is the schema-aware version. Existing 79 Gate tests continue to pass unchanged. New tests cover the map-based API.

---

## 3. Depot.Repo

The Repo is the interface between application code and the database. A single `MyApp.Repo` module is defined per application. It gets its pool from config at startup — callers never pass a pool around. The `Bastion.Depot.with_pool` middleware attaches the pool to `conn` before it reaches a controller, and the Repo reads from config, so there's no manual pool threading anywhere.

### 3.1 Defining your Repo

```march
-- lib/my_app/repo.march
mod MyApp.Repo do
  pfn pool() ->
    Depot.Pool.get("my_app")

  fn all(query) ->
    Depot.Repo.all(pool(), query)

  fn get(schema, id) ->
    Depot.Repo.get(pool(), schema, id)

  fn get!(schema, id) ->
    Depot.Repo.get!(pool(), schema, id)

  fn get_by(schema, clauses) ->
    Depot.Repo.get_by(pool(), schema, clauses)

  fn one(query) ->
    Depot.Repo.one(pool(), query)

  fn insert(gate) ->
    Depot.Repo.insert(pool(), gate)

  fn update(gate) ->
    Depot.Repo.update(pool(), gate)

  fn delete(struct) ->
    Depot.Repo.delete(pool(), struct)

  fn transaction(fun) ->
    Depot.Repo.transaction(pool(), fun)

  fn preload(struct_or_list, assocs) ->
    Depot.Repo.preload(pool(), struct_or_list, assocs)

  fn update_all(query, updates) ->
    Depot.Repo.update_all(pool(), query, updates)

  fn delete_all(query) ->
    Depot.Repo.delete_all(pool(), query)
end
```

The pool is private — callers just use `MyApp.Repo.all(...)`, `MyApp.Repo.insert(...)`, etc. No pool argument anywhere in application code.

### 3.2 Read API

```march
-- All users
let users = MyApp.Repo.all(MyApp.User.schema())

-- By primary key
let user = MyApp.Repo.get(MyApp.User.schema(), "abc-123")

-- By field
let user = MyApp.Repo.get_by(MyApp.User.schema(), %{email: "alice@example.com"})

-- Composed query
let admins =
  MyApp.User.schema()
  |> Depot.Query.where(fn u -> u.role == "admin")
  |> Depot.Query.order_by(:name)
  |> MyApp.Repo.all()
```

### 3.3 Write API

```march
fn create_user(params) do
  let gate = MyApp.User.registration_gate(params)
  case Depot.Gate.is_valid(gate) do
    true ->
      case MyApp.Repo.insert(gate) do
        Ok(user)            -> Ok(user)
        Err(gate_with_errs) -> Err(gate_with_errs)
      end
    false ->
      Err(gate)
  end
end

-- Bulk update
MyApp.User.schema()
|> Depot.Query.where(fn u -> u.role == "guest")
|> MyApp.Repo.update_all(%{role: "member"})
```

### 3.4 Transactions

Inside a transaction, the callback receives a transaction-scoped Repo module so that all operations within the transaction use the same connection:

```march
fn transfer_funds(from_id, to_id, amount) do
  MyApp.Repo.transaction(fn repo ->
    let from = repo.get!(MyApp.Account.schema(), from_id)
    let to   = repo.get!(MyApp.Account.schema(), to_id)

    if from.balance < amount do
      Err("insufficient funds")
    else
      let debit_gate  = MyApp.Account.update_gate(from, %{balance: from.balance - amount})
      let credit_gate = MyApp.Account.update_gate(to,   %{balance: to.balance   + amount})

      case (repo.update(debit_gate), repo.update(credit_gate)) do
        (Ok(a), Ok(b)) -> Ok((a, b))
        _              -> Err("transfer failed")
      end
    end
  end)
end
```

### 3.5 Preloading associations

```march
let user  = MyApp.Repo.get!(MyApp.User.schema(), id)
let user  = MyApp.Repo.preload(user, [:posts, :profile])
-- user.posts   => List(Post)
-- user.profile => Option(Profile)

-- Works on lists (one query per assoc, not N+1)
let users = MyApp.Repo.all(MyApp.User.schema())
let users = MyApp.Repo.preload(users, [:posts])
```

---

## 4. Depot.Query

The query builder produces composable `Query` values that are lazy — no database call happens until you pass the query to a Repo function. Queries start from a `Schema` value and grow through a pipeline of `Depot.Query.*` calls.

### 4.1 Starting a query

```march
-- Implicit: piping a Schema into any query function wraps it in a Query
MyApp.User.schema()
|> Depot.Query.where(fn u -> u.role == "admin")

-- Explicit
let q = Depot.Query.from(MyApp.User.schema())
```

### 4.2 `where`

```march
fn where(query: Query, predicate: fn(t) -> Bool) -> Query
```

```march
MyApp.User.schema()
|> Depot.Query.where(fn u -> u.role == "admin")
|> Depot.Query.where(fn u -> u.age >= 18)
-- Multiple where calls are AND-combined
```

### 4.3 `select`

```march
fn select(query: Query, projection: fn(t) -> p) -> Query
```

```march
MyApp.User.schema()
|> Depot.Query.select(fn u -> %{id: u.id, email: u.email})
```

When `select` is omitted, the full schema struct is returned.

### 4.4 `order_by`

```march
fn order_by(query: Query, field: Atom) -> Query
fn order_by(query: Query, field: Atom, direction: :asc | :desc) -> Query
```

```march
MyApp.User.schema()
|> Depot.Query.order_by(:name)
|> Depot.Query.order_by(:inserted_at, :desc)
```

### 4.5 `limit` and `offset`

```march
fn limit(query: Query, n: Int) -> Query
fn offset(query: Query, n: Int) -> Query
```

```march
MyApp.User.schema()
|> Depot.Query.limit(20)
|> Depot.Query.offset(40)
```

### 4.6 `join`

```march
fn join(query: Query, kind: :inner | :left | :right, schema: Schema, on: fn(t, j) -> Bool) -> Query
```

```march
MyApp.User.schema()
|> Depot.Query.join(:inner, MyApp.Post.schema(), fn (u, p) -> p.user_id == u.id)
|> Depot.Query.where(fn (u, p) -> p.published == true)
|> Depot.Query.select(fn (u, p) -> %{name: u.name, title: p.title})
```

### 4.7 `group_by` and `having`

```march
fn group_by(query: Query, field: Atom) -> Query
fn having(query: Query, predicate: fn(t) -> Bool) -> Query
```

```march
MyApp.Post.schema()
|> Depot.Query.group_by(:user_id)
|> Depot.Query.having(fn p -> Depot.Query.count(p.id) > 5)
|> Depot.Query.select(fn p -> (p.user_id, Depot.Query.count(p.id)))
|> MyApp.Repo.all()
```

### 4.8 `fragment` — raw SQL escape hatch

```march
fn fragment(sql: String, args: List(Any)) -> FragmentExpr
```

```march
MyApp.User.schema()
|> Depot.Query.where(fn u ->
    Depot.Query.fragment("lower(?) = ?", [u.email, "alice@example.com"]))
```

`?` placeholders are always parameterized — never string-interpolated into SQL.

### 4.9 Subqueries

```march
let active_ids =
  MyApp.User.schema()
  |> Depot.Query.where(fn u -> u.confirmed_at != None)
  |> Depot.Query.select(fn u -> u.id)

MyApp.Post.schema()
|> Depot.Query.where(fn p -> p.user_id |> Depot.Query.in_subquery(active_ids))
|> MyApp.Repo.all()
```

### 4.10 Query composition

Queries are plain values and compose freely:

```march
pfn base_query() ->
  MyApp.User.schema()
  |> Depot.Query.where(fn u -> u.deleted_at == None)

fn active_admins() ->
  base_query()
  |> Depot.Query.where(fn u -> u.role == "admin")
  |> Depot.Query.order_by(:name)

fn paginate(query, page, per_page) ->
  query
  |> Depot.Query.limit(per_page)
  |> Depot.Query.offset((page - 1) * per_page)
```

---

## 5. Depot.Migration

Migrations are plain March files. `up/0` and `down/0` are regular functions that call migration helpers. Column definitions are maps — one map describes the whole table, not one function call per column. Migrations always `import Depot.Migration` so you write `create_table(...)` not `Depot.Migration.create_table(...)`.

### 5.1 `create_table`

```march
-- priv/depot/migrations/20260401000001_create_users.march
mod Migrations.CreateUsers do
  import Depot.Migration

  fn up() do
    create_table("users", %{
      id:            (UUID,        %{primary_key: true, default: :gen_random_uuid}),
      name:          (String,      %{null: false}),
      email:         (String,      %{null: false}),
      password_hash: (String,      %{null: false}),
      role:          (String,      %{null: false, default: "user"}),
      confirmed_at:  (UtcDatetime, %{null: true}),
      metadata:      (Map,         %{null: false, default: "{}"}),
      inserted_at:   (UtcDatetime, %{null: false}),
      updated_at:    (UtcDatetime, %{null: false})
    })

    create_index("users", [:email], %{unique: true})
    create_index("users", [:role])
  end

  fn down() do
    drop_table("users")
  end
end
```

Each entry in the column map is `name: (Type, %{opts})`. The map preserves insertion order, so columns appear in the DDL in the order written.

### 5.2 `alter_table`

```march
mod Migrations.AddAvatarUrlToUsers do
  import Depot.Migration

  fn up() do
    alter_table("users", %{
      add:    %{avatar_url: (String, %{null: true})},
      modify: %{role: (String, %{null: false, default: "member"})},
      remove: [:legacy_flag]
    })

    create_index("users", [:avatar_url])
  end

  fn down() do
    drop_index("users_avatar_url_index")

    alter_table("users", %{
      modify: %{role: (String, %{null: false, default: "user"})},
      remove: [:avatar_url]
    })
  end
end
```

The `alter_table/2` map has three optional keys: `add` (column map), `modify` (column map), and `remove` (list of atoms).

### 5.3 Foreign key references

```march
mod Migrations.CreatePosts do
  import Depot.Migration

  fn up() do
    let user_ref = references("users", %{on_delete: :delete_all})

    create_table("posts", %{
      id:        (UUID,   %{primary_key: true, default: :gen_random_uuid}),
      user_id:   (UUID,   %{null: false, references: user_ref}),
      title:     (String, %{null: false}),
      body:      (String, %{null: false}),
      published: (Bool,   %{null: false, default: false}),
      inserted_at: (UtcDatetime, %{null: false}),
      updated_at:  (UtcDatetime, %{null: false})
    })

    create_index("posts", [:user_id])
  end

  fn down() do
    drop_table("posts")
  end
end
```

### 5.4 `Depot.Migration` API

```march
mod Depot.Migration do
  -- Table operations
  fn create_table(name: String, columns: Map) -> ()
  fn create_table(name: String, columns: Map, opts: Map) -> ()
  -- opts: %{if_not_exists: true}

  fn alter_table(name: String, changes: Map) -> ()
  -- changes: %{add: column_map, modify: column_map, remove: [atoms]}

  fn drop_table(name: String) -> ()
  fn drop_table(name: String, opts: Map) -> ()
  -- opts: %{if_exists: true}

  fn rename_table(from: String, to: String) -> ()
  fn rename_column(table: String, from: Atom, to: Atom) -> ()

  -- Index operations
  fn create_index(table: String, columns: List(Atom)) -> ()
  fn create_index(table: String, columns: List(Atom), opts: Map) -> ()
  -- opts: %{unique, name, where (partial), using (:btree | :hash | :gin | :gist)}

  fn drop_index(name: String) -> ()
  fn drop_index(name: String, opts: Map) -> ()

  -- Reference builder
  fn references(table: String, opts: Map) -> RefDef
  -- opts: %{on_delete, on_update, column}
  -- on_delete/on_update: :nothing | :delete_all | :nilify_all | :restrict

  -- Constraints
  fn add_constraint(table: String, name: String, check: String) -> ()
  fn drop_constraint(table: String, name: String) -> ()

  -- Raw SQL
  fn execute(sql: String) -> ()
end
```

### 5.5 Schema versions table

The runner maintains a `schema_migrations` table:

```sql
CREATE TABLE schema_migrations (
  version     BIGINT PRIMARY KEY,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Each migration file's timestamp prefix is the version. `forge depot.migrate` applies all pending migrations in ascending order. `forge depot.rollback` calls `down/0` on the most recently applied migration.

### 5.6 Forge commands

```bash
# Apply all pending migrations
forge depot.migrate

# Rollback the last N migrations (default 1)
forge depot.rollback
forge depot.rollback --step 3

# Show migration status
forge depot.migrations

# Rollback all, then migrate (dev reset)
forge depot.reset

# Generate a timestamped stub
forge depot.gen.migration add_avatar_url_to_users
# Creates: priv/depot/migrations/20260401120000_add_avatar_url_to_users.march
```

Generated stub:

```march
mod Migrations.AddAvatarUrlToUsers do
  fn up() do
    -- TODO
  end

  fn down() do
    -- TODO
  end
end
```

---

## 6. Contexts

Contexts are plain March modules that wrap Repo calls and expose a clean domain API to controllers. No base module, no magic — just functions.

Convention:
- **One context per domain** (`MyApp.Accounts`, `MyApp.Blog`, `MyApp.Orders`)
- **Controllers call context functions, never Repo directly**
- **Context functions take no pool** — Repo gets it from config

### 6.1 Example context: Accounts

```march
mod MyApp.Accounts do
  fn list_users() ->
    MyApp.Repo.all(MyApp.User.schema())

  fn get_user(id) ->
    MyApp.Repo.get(MyApp.User.schema(), id)

  fn get_user!(id) ->
    MyApp.Repo.get!(MyApp.User.schema(), id)

  fn get_user_by_email(email) ->
    MyApp.Repo.get_by(MyApp.User.schema(), %{email: email})

  fn list_admins() ->
    MyApp.User.schema()
    |> Depot.Query.where(fn u -> u.role == "admin")
    |> Depot.Query.order_by(:name)
    |> MyApp.Repo.all()

  fn create_user(params) do
    let gate = MyApp.User.registration_gate(params)
    case Depot.Gate.is_valid(gate) do
      true  -> MyApp.Repo.insert(gate)
      false -> Err(gate)
    end
  end

  fn update_user(user, params) do
    let gate = MyApp.User.update_gate(user, params)
    case Depot.Gate.is_valid(gate) do
      true  -> MyApp.Repo.update(gate)
      false -> Err(gate)
    end
  end

  fn delete_user(user) ->
    MyApp.Repo.delete(user)

  fn authenticate(email, password) do
    case get_user_by_email(email) do
      Some(user) ->
        if Crypto.bcrypt_verify(password, user.password_hash) do
          Ok(user)
        else
          Err(:invalid_credentials)
        end
      None ->
        Crypto.constant_time_dummy_verify()
        Err(:invalid_credentials)
    end
  end
end
```

### 6.2 Controller calling a context

No pool management — the Repo gets its pool from config, the middleware already set it up before the request reached the controller.

```march
mod MyApp.UserController do
  fn index(conn) do
    let users = MyApp.Accounts.list_users()
    Controller.render(conn, "index.html", %{users: users})
  end

  fn show(conn, %{id: id}) do
    case MyApp.Accounts.get_user(id) do
      Some(user) -> Controller.render(conn, "show.html", %{user: user})
      None       -> FallbackController.call(conn, 404)
    end
  end

  fn new(conn) do
    let gate = Depot.Gate.cast(
      Depot.Schema.blank(MyApp.User.schema()), %{}, [])
    Controller.render(conn, "new.html", %{gate: gate})
  end

  fn create(conn) do
    let params = conn |> parse_params()

    case MyApp.Accounts.create_user(params) do
      Ok(user) ->
        conn
        |> put_flash(:info, "Account created!")
        |> redirect(to: MyApp.Routes.user_path(user.id))
      Err(gate) ->
        Controller.render(conn, "new.html", %{gate: gate})
    end
  end

  fn edit(conn, %{id: id}) do
    let user = MyApp.Accounts.get_user!(id)
    let gate = Depot.Gate.cast(user, %{}, [])
    Controller.render(conn, "edit.html", %{user: user, gate: gate})
  end

  fn update(conn, %{id: id}) do
    let params = conn |> parse_params()
    let user   = MyApp.Accounts.get_user!(id)

    case MyApp.Accounts.update_user(user, params) do
      Ok(updated) ->
        conn
        |> put_flash(:info, "Updated.")
        |> redirect(to: MyApp.Routes.user_path(updated.id))
      Err(gate) ->
        Controller.render(conn, "edit.html", %{user: user, gate: gate})
    end
  end

  fn delete(conn, %{id: id}) do
    let user = MyApp.Accounts.get_user!(id)
    MyApp.Accounts.delete_user(user)
    conn
    |> put_flash(:info, "Deleted.")
    |> redirect(to: MyApp.Routes.users_path())
  end
end
```

---

## 7. Testing with Depot.Test

### 7.1 Sandbox mode

Each test runs inside a DB transaction that is rolled back when the test finishes. Configure once in `test_helper.march`:

```march
Depot.Test.start_sandbox()
```

### 7.2 Depot.Test API

```march
mod Depot.Test do
  fn start_sandbox() -> ()
  fn checkout() -> ()
  fn checkin() -> ()
end
```

The sandbox wraps the Repo's configured pool — no pool argument needed anywhere.

### 7.3 Writing tests

```march
mod MyApp.AccountsTest do
  import Bastion.Test

  @setup fn () -> Depot.Test.checkout() end

  fn test "list_users returns all users"() do
    TestFactory.insert_user(%{name: "Alice", email: "alice@test.com"})
    TestFactory.insert_user(%{name: "Bob",   email: "bob@test.com"})

    let users = MyApp.Accounts.list_users()
    assert List.length(users) == 2
  end

  fn test "create_user with valid params"() do
    let result = MyApp.Accounts.create_user(%{
      name:     "Alice",
      email:    "alice@test.com",
      password: "supersecret123"
    })

    assert Result.is_ok(result)
    let user = Result.unwrap(result)
    assert user.name == "Alice"
    assert user.password_hash != "supersecret123"
  end

  fn test "create_user with duplicate email returns gate error"() do
    TestFactory.insert_user(%{name: "Alice", email: "alice@test.com"})

    let result = MyApp.Accounts.create_user(%{
      name:     "Alice2",
      email:    "alice@test.com",
      password: "supersecret123"
    })

    assert Result.is_err(result)
    let gate = Result.unwrap_err(result)
    assert Depot.Gate.get_errors(gate, "email") == ["has already been taken"]
  end
end
```

### 7.4 Factory helpers

```march
mod MyApp.TestFactory do
  fn insert_user(attrs) do
    let defaults = %{
      name:     "Test User",
      email:    "user_#{Crypto.random_hex(4)}@test.com",
      password: "testpassword123"
    }
    let params = Map.merge(defaults, attrs)
    let gate   = MyApp.User.registration_gate(params)
    case MyApp.Repo.insert(gate) do
      Ok(user) -> user
      Err(g)   -> panic("TestFactory.insert_user failed: #{inspect(Depot.Gate.errors(g))}")
    end
  end
end
```

### 7.5 Concurrent test isolation

Each test process gets its own sandbox connection inside its own transaction — full isolation.

```march
@async true
fn test "concurrent user creation"() do
  Depot.Test.checkout()
  TestFactory.insert_user(%{email: "concurrent@test.com"})
  let user = MyApp.Accounts.get_user_by_email("concurrent@test.com")
  assert user != None
end
```

---

## 8. Generators

### 8.1 `forge depot.gen.migration`

```bash
forge depot.gen.migration create_users
```

Generates `priv/depot/migrations/<timestamp>_<name>.march` with stub `up/down`.

### 8.2 `forge bastion.gen.schema`

```bash
forge bastion.gen.schema User users name:string email:string age:integer role:string
```

Generates:
- `lib/my_app/user.march` — schema + gate functions
- `priv/depot/migrations/<timestamp>_create_users.march`

Generated schema:

```march
mod MyApp.User do
  import Depot.Gate

  fn schema() ->
    Depot.Schema.define("users", %{
      fields: %{
        name:        String,
        email:       String,
        age:         Int,
        role:        String,
        inserted_at: UtcDatetime,
        updated_at:  UtcDatetime
      }
    })

  fn gate(params) ->
    cast(Depot.Schema.blank(schema()), params, ["name", "email", "age", "role"])
    |> validate_required(["name", "email"])

  fn update_gate(user, params) ->
    cast(user, params, ["name", "age", "role"])
    |> validate_required(["name"])
end
```

Generated migration:

```march
mod Migrations.CreateUsers do
  import Depot.Migration

  fn up() do
    create_table("users", %{
      id:          (UUID,        %{primary_key: true, default: :gen_random_uuid}),
      name:        (String,      %{null: false}),
      email:       (String,      %{null: false}),
      age:         (Int,         %{null: true}),
      role:        (String,      %{null: true}),
      inserted_at: (UtcDatetime, %{null: false}),
      updated_at:  (UtcDatetime, %{null: false})
    })
  end

  fn down() do
    drop_table("users")
  end
end
```

### 8.3 `forge bastion.gen.context`

```bash
forge bastion.gen.context Accounts User users name:string email:string
```

Generates:
- `lib/my_app/accounts.march` — context module
- `lib/my_app/user.march` — schema + gate
- `priv/depot/migrations/<timestamp>_create_users.march`
- `test/my_app/accounts_test.march` — test stubs

Generated context:

```march
mod MyApp.Accounts do
  fn list_users() ->
    MyApp.Repo.all(MyApp.User.schema())

  fn get_user(id) ->
    MyApp.Repo.get(MyApp.User.schema(), id)

  fn get_user!(id) ->
    MyApp.Repo.get!(MyApp.User.schema(), id)

  fn create_user(params) do
    let gate = MyApp.User.gate(params)
    case Depot.Gate.is_valid(gate) do
      true  -> MyApp.Repo.insert(gate)
      false -> Err(gate)
    end
  end

  fn update_user(user, params) do
    let gate = MyApp.User.update_gate(user, params)
    case Depot.Gate.is_valid(gate) do
      true  -> MyApp.Repo.update(gate)
      false -> Err(gate)
    end
  end

  fn delete_user(user) ->
    MyApp.Repo.delete(user)
end
```

### 8.4 `forge bastion.gen.html`

```bash
forge bastion.gen.html Accounts User users name:string email:string
```

Generates everything from `gen.context` plus:
- `lib/my_app/controllers/user_controller.march`
- `lib/my_app/templates/user/{index,show,new,edit,_form}.march`
- Route snippet for `lib/my_app/router.march`

Generated `_form.march`:

```march
mod MyApp.Templates.User.Form do
  fn render(conn, gate) do
    ~H"""
    <div class="field">
      <label for="name">Name</label>
      <input id="name" name="name"
             value={Depot.Gate.get_field(@gate, "name") |> Option.unwrap_or("")} />
      <.error_tag gate={@gate} field="name" />
    </div>

    <div class="field">
      <label for="email">Email</label>
      <input id="email" name="email" type="email"
             value={Depot.Gate.get_field(@gate, "email") |> Option.unwrap_or("")} />
      <.error_tag gate={@gate} field="email" />
    </div>

    <button type="submit">Save</button>
    """
  end
end
```

### 8.5 `forge bastion.gen.json`

```bash
forge bastion.gen.json Accounts User users name:string email:string
```

Generates everything from `gen.context` plus:
- `lib/my_app/controllers/user_json_controller.march`
- `lib/my_app/views/user_view.march`
- Route snippet for the JSON API

Generated JSON controller:

```march
mod MyApp.UserJsonController do
  fn index(conn) do
    let users = MyApp.Accounts.list_users()
    Controller.json(conn, %{data: List.map(users, fn u -> MyApp.UserView.render(u))})
  end

  fn show(conn, %{id: id}) do
    case MyApp.Accounts.get_user(id) do
      Some(user) ->
        Controller.json(conn, %{data: MyApp.UserView.render(user)})
      None ->
        conn |> put_status(404)
        |> Controller.json(%{error: "not found"})
    end
  end

  fn create(conn) do
    let params = conn |> parse_json_params()

    case MyApp.Accounts.create_user(params) do
      Ok(user) ->
        conn |> put_status(201)
        |> Controller.json(%{data: MyApp.UserView.render(user)})
      Err(gate) ->
        conn |> put_status(422)
        |> Controller.json(%{errors: Depot.Gate.errors(gate)})
    end
  end

  fn update(conn, %{id: id}) do
    let params = conn |> parse_json_params()
    let user   = MyApp.Accounts.get_user!(id)

    case MyApp.Accounts.update_user(user, params) do
      Ok(updated) ->
        Controller.json(conn, %{data: MyApp.UserView.render(updated)})
      Err(gate) ->
        conn |> put_status(422)
        |> Controller.json(%{errors: Depot.Gate.errors(gate)})
    end
  end

  fn delete(conn, %{id: id}) do
    let user = MyApp.Accounts.get_user!(id)
    MyApp.Accounts.delete_user(user)
    conn |> put_status(204) |> Controller.json(%{})
  end
end
```

---

## 9. End-to-End Developer Experience

### Step 1 — Create the app

```bash
forge bastion new myapp
cd myapp
```

`config/dev.march`:

```march
mod Config.Dev do
  fn load() do
    Config.put("depot", "url",
      Env.get("DATABASE_URL") |> Option.unwrap_or("postgres://localhost/myapp_dev"))
    Config.put("depot", "pool_size", "10")
    Config.put("depot", "pool_name", "my_app")
  end
end
```

### Step 2 — Generate a resource

```bash
forge bastion.gen.html Accounts User users name:string email:string role:string
```

### Step 3 — Run the migration

```bash
forge depot.migrate
# [info] Running 20260401120000_create_users ... OK
```

### Step 4 — Start the server

```bash
forge bastion server
# [info] Running MyApp.Endpoint on http://localhost:4000
```

### Step 5 — Test

```bash
forge test
# Running 1 test
# test creating a user persists to the DB ... OK (12ms)
# 1 test, 0 failures
```

---

## 10. Pool configuration and startup

```march
mod MyApp.Application do
  fn start() do
    Depot.Pool.start("my_app", %{
      url:  Config.get("depot", "url") |> Option.unwrap_or("postgres://localhost/myapp_dev"),
      size: Config.get_int("depot", "pool_size") |> Option.unwrap_or(10)
    })
    MyApp.Endpoint.start()
  end
end
```

```march
-- In the endpoint pipeline
fn call(conn) do
  conn
  |> parse_body()
  |> load_session()
  |> Bastion.Depot.with_pool(Depot.Pool.get("my_app"))
  |> MyApp.Router.route()
end
```

---

## 11. Implementation Order

| Phase | Deliverable | Key file(s) |
|-------|------------|-------------|
| 1 | `Depot.Schema.define/2`, `blank/1`, inspection API | `stdlib/depot_schema.march` |
| 2 | `Depot.Gate` v2 — map-based `cast/3` with diff tracking, evolve existing Gate | `stdlib/depot_gate.march` |
| 3 | `Depot.Repo` read API — `all`, `get`, `get!`, `get_by`, `one`, `count`, `exists?` | `stdlib/depot_repo.march` |
| 4 | `Depot.Repo` write API — `insert`, `update`, `delete`, `update_all`, `delete_all`, `insert_or_update` | add to `depot_repo.march` |
| 5 | `Depot.Repo.transaction` + `preload` | add to `depot_repo.march` |
| 6 | `Depot.Query` — `from`, `where`, `select`, `order_by`, `limit`, `offset` | `stdlib/depot_query.march` |
| 7 | `Depot.Query` — `join`, `group_by`, `having`, `fragment`, `in_subquery` | add to `depot_query.march` |
| 8 | `Depot.Migration` — `create_table`, `alter_table`, `drop_table`, `create_index`, `drop_index`, `references`, `add_constraint`, `execute` | `stdlib/depot_migration.march` |
| 9 | `forge depot.migrate` / `rollback` / `migrations` / `reset` | `forge/lib/cmd_depot.ml` |
| 10 | `forge depot.gen.migration` | add to `cmd_depot.ml` |
| 11 | `Depot.Test` sandbox — `start_sandbox`, `checkout`, `checkin` | `stdlib/depot_test.march` |
| 12 | `forge bastion.gen.schema` | `forge/lib/cmd_bastion_gen.ml` |
| 13 | `forge bastion.gen.context` | add to `cmd_bastion_gen.ml` |
| 14 | `forge bastion.gen.html` | add to `cmd_bastion_gen.ml` |
| 15 | `forge bastion.gen.json` | add to `cmd_bastion_gen.ml` |
