# Depot: Form Objects and Changeset Validation

**Status**: Draft | **Version**: 0.1 | **Part of**: Depot Design Spec

---

## Overview

A changeset is a typed validation pipeline that accumulates errors without short-circuiting. You describe the shape of valid data as a series of `cast`, `validate`, and `constraint` steps. At the end you have either a validated struct ready to persist, or a structured error map ready to display in a form.

March's type system enforces that you cannot use an unvalidated changeset as a persistence argument — the types distinguish `Changeset(pending)` from `Changeset(valid, t)`.

---

## Core Types

```march
# A changeset in progress — validation not yet complete
type Changeset(pending) = %{
  data: Map(Atom, Any),
  changes: Map(Atom, Any),
  errors: Map(Atom, List(String)),
  valid: Bool
}

# A valid changeset — safe to persist
type Changeset(valid, t) = %{
  data: t,
  changes: Map(Atom, Any),
  errors: Map(Atom, List(String)),
  valid: true
}

# Union used in function signatures
type AnyChangeset(t) = Changeset(pending) | Changeset(valid, t)
```

`Depot.insert/update` only accept `Changeset(valid, t)`, not `Changeset(pending)`. Calling them with an unvalidated changeset is a compile-time type error.

---

## Defining a Schema

```march
mod MyApp.User do
  import Depot.Changeset

  type User = %{
    id: Option(String),
    name: String,
    email: String,
    age: Int,
    role: String,
    password: Option(String),
    password_hash: Option(String)
  }

  # The required field list and types are known at compile time
  fn changeset(params: Map(String, Any)) -> AnyChangeset(User) do
    %User{}
    |> cast(params, fields: [:name, :email, :age, :role])
    |> validate_required([:name, :email])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:email, ~r/@/)
    |> validate_inclusion(:role, ["user", "admin", "moderator"])
    |> validate_number(:age, min: 13, max: 150)
  end

  # Registration changeset adds password fields
  fn registration_changeset(params: Map(String, Any)) -> AnyChangeset(User) do
    %User{}
    |> cast(params, fields: [:name, :email, :age, :role, :password])
    |> validate_required([:name, :email, :password])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: 12)
    |> hash_password()
  end

  pfn hash_password(cs: AnyChangeset(User)) -> AnyChangeset(User) do
    case Depot.Changeset.get_change(cs, :password) do
      Some(pw) ->
        cs
        |> Depot.Changeset.put_change(:password_hash, Crypto.bcrypt_hash(pw))
        |> Depot.Changeset.delete_change(:password)
      None -> cs
    end
  end
end
```

---

## Cast

`cast/3` allows listed fields through from the raw params map, coercing types where possible. Fields not in the allow list are silently dropped. Type coercions: `"42"` → `Int`, `"true"` → `Bool`, ISO 8601 strings → `DateTime`, etc.

```march
mod Depot.Changeset do
  fn cast(
    struct_or_changeset: t | AnyChangeset(t),
    params: Map(String, Any),
    fields: List(Atom)
  ) -> AnyChangeset(t)
end
```

---

## Validators

All validators return the changeset unchanged if the field is absent (use `validate_required` to enforce presence separately):

```march
mod Depot.Changeset do
  fn validate_required(cs, fields: List(Atom)) -> AnyChangeset(t)

  fn validate_length(cs, field: Atom, opts: LengthOpts) -> AnyChangeset(t)
  # opts: %{min: Int, max: Int, exact: Int, message: String}

  fn validate_format(cs, field: Atom, regex: Regex) -> AnyChangeset(t)
  # default message: "has invalid format"

  fn validate_inclusion(cs, field: Atom, values: List(Any)) -> AnyChangeset(t)
  # default message: "is not a valid value"

  fn validate_exclusion(cs, field: Atom, values: List(Any)) -> AnyChangeset(t)

  fn validate_number(cs, field: Atom, opts: NumberOpts) -> AnyChangeset(t)
  # opts: %{min, max, greater_than, less_than, equal_to, message}

  fn validate_acceptance(cs, field: Atom) -> AnyChangeset(t)
  # validates checkbox-style acceptance fields (must be true)

  fn validate_confirmation(cs, field: Atom) -> AnyChangeset(t)
  # validates matching `:field` and `:field_confirmation`

  fn validate_change(cs, field: Atom, validator: fn(Any) -> Option(String)) -> AnyChangeset(t)
  # custom validator: return Some("error message") or None
end
```

---

## Database Constraints

Constraints are checked against the database during `Depot.insert`/`Depot.update`. They are not validated in application code — they are mapped from database error codes back into the changeset's error map:

```march
mod Depot.Changeset do
  fn unique_constraint(cs, field: Atom, opts: ConstraintOpts) -> AnyChangeset(t)
  # opts: %{name: String, message: String}
  # name: the Postgres constraint name (e.g. "users_email_index")

  fn foreign_key_constraint(cs, field: Atom, opts: ConstraintOpts) -> AnyChangeset(t)
  fn no_assoc_constraint(cs, field: Atom, opts: ConstraintOpts) -> AnyChangeset(t)
  fn check_constraint(cs, field: Atom, opts: ConstraintOpts) -> AnyChangeset(t)
end

# Usage
fn changeset(params) do
  %User{}
  |> cast(params, fields: [:name, :email])
  |> validate_required([:name, :email])
  |> validate_format(:email, ~r/@/)
  |> unique_constraint(:email, name: "users_email_index",
      message: "has already been taken")
end
```

When Postgres raises a unique violation on `users_email_index`, `Depot.insert` maps it back to `%{email: ["has already been taken"]}` on the returned changeset rather than raising an exception.

---

## Persistence

```march
mod Depot do
  # Insert using a valid changeset
  fn insert(pool: Pool, cs: Changeset(valid, t)) -> Result(t, Changeset(pending))

  # Update using a valid changeset (changeset must be built from an existing struct)
  fn update(pool: Pool, cs: Changeset(valid, t)) -> Result(t, Changeset(pending))

  # Delete
  fn delete(pool: Pool, struct: t) -> Result(t, Error)
end
```

`Depot.insert` returns `Error(changeset)` only when a database constraint is violated. Application-level validation errors prevent a `Changeset(valid, t)` from ever being constructed — the types enforce this.

---

## Applying Changesets in Handlers

```march
fn create(conn) do
  params = conn |> parse_params()

  case MyApp.User.registration_changeset(params) do
    cs when Depot.Changeset.valid?(cs) ->
      case Depot.insert(conn.assigns.db, cs) do
        Ok(user) ->
          conn
          |> put_flash(:info, "Welcome, #{user.name}!")
          |> redirect(to: MyApp.Routes.dashboard_path())

        Error(cs_with_constraint_errors) ->
          conn |> render("new.html", changeset: cs_with_constraint_errors)
      end

    cs ->
      # Application validation failed — render form with errors
      conn |> render("new.html", changeset: cs)
  end
end
```

---

## Rendering Errors in Templates

```march
~H"""
<form method="post" action={MyApp.Routes.users_path()}>
  <div class="field">
    <label for="name">Name</label>
    <input id="name" name="name" value={Depot.Changeset.get_field(@changeset, :name)} />
    <.error_tag changeset={@changeset} field={:name} />
  </div>

  <div class="field">
    <label for="email">Email</label>
    <input id="email" name="email" value={Depot.Changeset.get_field(@changeset, :email)} />
    <.error_tag changeset={@changeset} field={:email} />
  </div>

  <button type="submit">Register</button>
</form>
"""
```

The `<.error_tag>` component is a Bastion built-in partial that renders the first error message for a field, or nothing if there are no errors:

```march
mod Bastion.Components do
  fn error_tag(changeset: AnyChangeset(t), field: Atom) -> Html.Safe do
    case Depot.Changeset.get_errors(changeset, field) do
      [] -> Html.raw("")
      [first | _] -> ~H"<span class=\"field-error\">#{first}</span>"
    end
  end
end
```

---

## Changeset API Reference

```march
mod Depot.Changeset do
  fn valid?(cs: AnyChangeset(t)) -> Bool
  fn errors(cs: AnyChangeset(t)) -> Map(Atom, List(String))
  fn get_errors(cs: AnyChangeset(t), field: Atom) -> List(String)
  fn get_field(cs: AnyChangeset(t), field: Atom) -> Option(Any)
  fn get_change(cs: AnyChangeset(t), field: Atom) -> Option(Any)
  fn put_change(cs: AnyChangeset(t), field: Atom, value: Any) -> AnyChangeset(t)
  fn delete_change(cs: AnyChangeset(t), field: Atom) -> AnyChangeset(t)
  fn add_error(cs: AnyChangeset(t), field: Atom, message: String) -> AnyChangeset(t)
end
```

---

## Open Questions

- Should `cast` be compile-time verified against the struct's field types, or is runtime coercion sufficient? Compile-time checking would catch `cast(params, fields: [:nonexistent_field])` as a type error.
- How should nested/embedded schemas work? E.g., a `User` with an embedded `Address` struct that also needs cast + validation.
- Should there be a `Depot.Changeset.Schema` declaration form to make the field list and types explicit, analogous to Ecto's `schema` macro?
