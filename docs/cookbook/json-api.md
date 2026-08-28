---
layout: cookbook
title: "Cookbook: JSON API"
permalink: /docs/cookbook/json-api/
scrollmd: true
---

# Call a JSON API and parse the response

Make an HTTP request, parse the JSON body, and pull typed fields out of it,
turning an untyped response into a value your program can trust. Uses
`HttpClient`, `Http`, and `Json`. (The [HTTP recipe]({{ site.baseurl }}/docs/cookbook/http/)
covers building requests and servers; this is the missing part: decoding a
response.)

---

## The shape of a JSON value

`Json.parse` returns `Result(JsonValue, String)`, where `JsonValue` is an ADT:

<!-- scroll:skip -->
```march
type JsonValue =
    Null
  | Bool(Bool)
  | Number(Float)
  | Str(String)
  | Array(List(JsonValue))
  | Object(List((String, JsonValue)))
```

You decode by pattern-matching this ADT; there's no reflection, so a malformed
or wrong-typed field is a branch you handle, not a crash.

---

## Fetch and decode

`HttpClient.get(client, url)` returns `Result(Response, _)`; `Http.response_body`
extracts the body string; `Json.get(jv, key)` returns `Option(JsonValue)` for a
field. Chaining the matches turns *two* failure sources (the request and the
parse) into one `Result`:

```march
mod Weather do

  type Report = Report(String, Float)   -- city name, temperature

  fn fetch(city : String) : Result(Report, String) do
    let client = HttpClient.new_client()
    match HttpClient.get(client, "https://example.com/weather?city=" ++ city) do
      Err(_)   -> Err("request failed")
      Ok(resp) ->
        match Json.parse(Http.response_body(resp)) do
          Err(e) -> Err("bad JSON: " ++ e)
          Ok(jv) ->
            -- pull two fields and check their shapes in one match
            match (Json.get(jv, "name"), Json.get(jv, "temp")) do
              (Some(JsonValue.Str(name)), Some(JsonValue.Number(t))) ->
                Ok(Report(name, t))
              _ ->
                Err("missing or wrong-typed fields")
            end
        end
    end
  end

end
```

Matching the **tuple** `(Json.get(…), Json.get(…))` checks both fields at once:
the success arm fires only when `name` is a string *and* `temp` is a number;
anything else falls through to the error arm. Constructors like `Str`/`Number`
exist in more than one type, so qualify them as `JsonValue.Str` / `JsonValue.Number`
to disambiguate.

---

## Nested fields

For values buried in nested objects, `Json.get_in(jv, ["main", "temp"])` walks a
key path; `Json.get_at(jv, i)` indexes into an array. Both return
`Option(JsonValue)`, so they compose with the same matching style:

<!-- scroll:skip -->
```march
match Json.get_in(jv, ["main", "temp"]) do
  Some(JsonValue.Number(t)) -> Ok(t)
  _                         -> Err("no main.temp")
end
```

---

## Try it

`Json.parse` works on any string, so you can exercise the accessors without a
network call:

```march
match Json.parse("{\"name\": \"Paris\", \"temp\": 14.5}") do
  Ok(jv) -> Json.get(jv, "name")
  Err(_) -> None
end
```

This returns `Some(JsonValue.Str("Paris"))`.

---

## See also

- [HTTP]({{ site.baseurl }}/docs/cookbook/http/): building requests, headers, and servers.
- [Pattern Matching]({{ site.baseurl }}/docs/pattern-matching/): exhaustiveness when decoding ADTs.
- [Standard Library → Json]({{ site.baseurl }}/docs/stdlib/): the full accessor list.
