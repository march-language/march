# Bastion: Database Integration (Depot)

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Integration Model

Depot (the Postgres driver) remains a separate library. Bastion provides integration through:

1. A typed middleware plug that attaches the connection pool to the conn
2. Conventions for organizing queries in context modules
3. Forge generators that produce Depot migrations and query modules
4. The `--no-db` flag for projects that don't need a database

---

## Pool Middleware

```march
mod Bastion.Middleware.Depot do
  fn with_pool(conn: Conn(a), pool: Depot.Pool) -> Conn(a & WithDB) do
    conn |> assign(:db, pool)
  end
end

# In the endpoint pipeline
fn call(conn) do
  conn
  |> parse_body()
  |> load_session()
  |> Bastion.Middleware.Depot.with_pool(MyApp.Repo.pool())
  |> MyApp.Router.route()
end
```

---

## Context Modules (Query Organization)

Bastion follows the Phoenix convention of "context modules" — domain-scoped modules that encapsulate Depot queries:

```march
mod MyApp.Users do
  import Depot

  fn list_all(db: Depot.Pool) -> List(User) do
    Depot.query(db, "SELECT id, name, email, role FROM users ORDER BY name")
    |> Depot.decode(User)
  end

  fn get(db: Depot.Pool, id: String) -> Result(User, :not_found) do
    case Depot.query(db, "SELECT * FROM users WHERE id = $1", [id]) do
      [user] -> Ok(Depot.decode_row(user, User))
      [] -> Error(:not_found)
    end
  end

  fn create(db: Depot.Pool, params: UserParams) -> Result(User, ValidationError) do
    case validate(params) do
      Ok(valid) ->
        Depot.query(db,
          "INSERT INTO users (name, email, password_hash) VALUES ($1, $2, $3) RETURNING *",
          [valid.name, valid.email, hash_password(valid.password)]
        )
        |> Depot.decode(User)
        |> Ok()
      Error(errors) ->
        Error(errors)
    end
  end

  fn authenticate(email: String, password: String) -> Result(User, AuthError) do
    case get_by_email(email) do
      Ok(user) ->
        if verify_password(password, user.password_hash) do
          Ok(user)
        else
          Error(:invalid_credentials)
        end
      Error(:not_found) ->
        # Constant-time comparison to prevent timing attacks
        dummy_verify_password()
        Error(:invalid_credentials)
    end
  end
end
```

---

## Migrations

Depot migrations are plain March files with `up` and `down` functions:

```march
# priv/depot/migrations/20260326000001_create_users.march
mod Migrations.CreateUsers do
  import Depot.Migration

  fn up(db) do
    Depot.execute(db, """
      CREATE TABLE users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'user',
        inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    """)

    Depot.execute(db, "CREATE INDEX idx_users_email ON users (email)")
  end

  fn down(db) do
    Depot.execute(db, "DROP TABLE users")
  end
end
```

Run migrations with:

```bash
forge depot.migrate
```

---

## The `--no-db` Flag

```bash
# Full project with Depot
forge new my_app

# Project without database integration
forge new my_app --no-db
```

The `--no-db` flag omits Depot from dependencies, skips the pool middleware in the endpoint, and doesn't generate migration directories. The rest of Bastion works normally.

---

## Integration Testing with Depot

Tests that need a database use a sandboxed Depot connection that rolls back after each test:

```march
mod MyApp.UsersTest do
  import Bastion.Test
  import Bastion.Test.Depot

  # Each test runs in a transaction that's rolled back after the test
  @setup fn ->
    Bastion.Test.Depot.checkout(MyApp.Repo.pool())
  end

  fn test "create_user inserts a user"() do
    result = MyApp.Users.create(test_db(), %{
      name: "Alice",
      email: "alice@test.com",
      password: "secret123"
    })

    assert result |> Result.is_ok()
    user = Result.unwrap(result)
    assert user.name == "Alice"
    # password_hash is set, plain password is not stored
    assert user.password_hash != "secret123"
  end
end
```
