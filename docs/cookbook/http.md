---
layout: cookbook
title: "Cookbook: HTTP"
permalink: /docs/cookbook/http/
---

# HTTP

March has two HTTP modules: `HttpClient` for making requests and `HttpServer` for handling them.

---

## Making requests

Simple GET:

```march
match HttpClient.get("https://api.example.com/users") do
  Ok(resp)  -> println(resp.body)
  Err(msg)  -> println("error: " ++ msg)
end
```

POST with a JSON body:

```march
let body = Json.to_string(Json.Object([
  ("name", Json.String("Alice")),
  ("age",  Json.Number(30.0))
]))

match HttpClient.post("https://api.example.com/users", body) do
  Ok(resp) when resp.status == 201 -> println("created")
  Ok(resp) -> println("unexpected: " ++ int_to_string(resp.status))
  Err(e)   -> println("failed: " ++ e)
end
```

With a configured client (base URL, auth, retries):

```march
let client =
  HttpClient.new_client()
  |> HttpClient.add_request_step(HttpClient.step_base_url("https://api.example.com"))
  |> HttpClient.add_request_step(HttpClient.step_bearer_auth(token))
  |> HttpClient.with_retry(3)

match HttpClient.run(client, HttpClient.get("/users")) do
  Ok(resp) -> resp.body
  Err(msg) -> Err(msg)
end
```

---

## Handling requests

A minimal HTTP handler:

```march
fn handle(conn) do
  match HttpServer.method(conn) do
    :get  -> HttpServer.text(conn, 200, "Hello!")
    :post ->
      let body = HttpServer.req_body(conn)
      HttpServer.json(conn, 201, "{\"received\": true}")
    _     -> HttpServer.text(conn, 405, "Method Not Allowed")
  end
end
```

Path-based routing:

```march
fn route(conn) do
  match (HttpServer.method(conn), HttpServer.path(conn)) do
    (:get,  "/")        -> HttpServer.text(conn, 200, "home")
    (:get,  "/health")  -> HttpServer.text(conn, 200, "ok")
    (:post, "/echo")    ->
      HttpServer.text(conn, 200, HttpServer.req_body(conn))
    _                   -> HttpServer.text(conn, 404, "not found")
  end
end
```

---

## Complete example: a JSON echo server

```march
mod EchoServer do
  fn handle(conn) do
    match (HttpServer.method(conn), HttpServer.path(conn)) do
      (:post, "/echo") ->
        let body = HttpServer.req_body(conn)
        match Json.parse(body) do
          Ok(_)  -> HttpServer.json(conn, 200, body)
          Err(e) ->
            let msg = "{\"error\": \"" ++ e ++ "\"}"
            HttpServer.json(conn, 400, msg)
        end
      (:get, "/health") ->
        HttpServer.json(conn, 200, "{\"status\": \"ok\"}")
      _ ->
        HttpServer.text(conn, 404, "not found")
    end
  end

  fn main() do
    println("Listening on :8080")
    HttpServer.run_pipeline([handle], 8080)
  end
end
```
