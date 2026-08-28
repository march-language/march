---
layout: cookbook
title: "Cookbook: Config"
permalink: /docs/cookbook/config/
scrollmd: true
---

# Parse a config file

Read a TOML file, pull out typed values with sensible defaults, and let
environment variables override them. Uses `File`, `Toml`, and `Env`.

---

## Read and parse

`Toml.parse` returns `Result(TomlValue, TomlError)`. The `get_*` accessors each
return an `Option`, so a missing key becomes a default rather than a crash:

```march
mod AppConfig do

  -- Avoid naming the type `Config` — the stdlib already has a `Config` module,
  -- and March's type namespace is global, so the two would collide.
  type Settings = Settings(String, Int)

  pfn default_port(tv) : Int do
    match Toml.get_int(tv, "port") do
      Some(p) -> p
      None    -> 8080
    end
  end

  fn load(path : String) : Result(Settings, String) do
    match File.read(path) do
      Err(_)   -> Err("cannot read " ++ path)
      Ok(text) ->
        match Toml.parse(text) do
          Err(_) -> Err("invalid TOML in " ++ path)
          Ok(tv) ->
            let host =
              match Toml.get_str(tv, "host") do
                Some(h) -> h
                None    -> "localhost"
              end
            -- Env var wins over the file; the file value is the fallback.
            let port = Env.get_int("PORT", default_port(tv))
            Ok(Settings(host, port))
        end
    end
  end

end
```

For a config like:

```toml
host = "0.0.0.0"
port = 9000
```

`load` returns `Ok(Settings("0.0.0.0", 9000))`, or `Ok(Settings("0.0.0.0", 3000))`
if `PORT=3000` is set in the environment.

---

## Accessors and nesting

`Toml.get_str` / `get_int` / `get_float` / `get_bool` read top-level keys.
For nested tables, `Toml.get_in(tv, ["database", "host"])` walks a key path and
returns `Option(TomlValue)`. There's also `get_table` and `get_array` for
sub-tables and lists.

```toml
[database]
host = "db.internal"
port = 5432
```

<!-- scroll:skip -->
```march
let db_host =
  match Toml.get_in(tv, ["database", "host"]) do
    Some(TomlValue.TStr(h)) -> h
    _                       -> "localhost"
  end
```

---

## Environment overrides

The `Env` module reads process environment variables, each with a default so
unset variables don't fail:

- `Env.get(name, default) : String`
- `Env.get_int(name, default) : Int`
- `Env.get_bool(name, default) : Bool`
- `Env.require(name) : String`: panics if unset (use for must-have secrets)

The pattern above, `Env.get_int("PORT", default_port(tv))`, gives the standard
precedence: **environment overrides file, file overrides hard-coded default.**

> Prefer YAML? `Yaml.parse` mirrors this API (`Yaml.get`, `Yaml.get_str`, …), so
> the same structure works for `.yaml` config.

---

## Try it

`Toml.parse` works on any string, so you can try the accessors without a file:

```march
match Toml.parse("host = \"prod.example.com\"\nport = 443") do
  Ok(tv) -> Toml.get_str(tv, "host")
  Err(_) -> None
end
```

This returns `Some("prod.example.com")`.

---

## See also

- [Standard Library → Toml / Env]({{ site.baseurl }}/docs/stdlib/): full accessor lists.
- [Capabilities]({{ site.baseurl }}/docs/capabilities/): gate config-file reads behind `needs IO.FileRead`.
