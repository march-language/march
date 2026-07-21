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
let client = HttpClient.new_client()
match HttpClient.get(client, "https://api.example.com/users") do
  Ok(resp) -> println(Http.response_body(resp))
  Err(_)   -> println("error: request failed")
end
```

POST with a JSON body:

```march
let body = Json.to_string(Json.Object([
  ("name", Json.Str("Alice")),
  ("age",  Json.Number(30.0))
]))

let client = HttpClient.new_client()
match HttpClient.post(client, "https://api.example.com/users", body) do
  Ok(resp) when Http.response_status_code(resp) == 201 -> println("created")
  Ok(resp) -> println("unexpected: " ++ int_to_string(Http.response_status_code(resp)))
  Err(_)   -> println("failed")
end
```

With a configured client (base URL, auth, retries):

```march
let client =
  HttpClient.new_client()
  |> HttpClient.add_request_step("base_url", HttpClient.step_base_url("https://api.example.com"))
  |> HttpClient.add_request_step("auth", HttpClient.step_bearer_auth(token))
  |> HttpClient.with_retry(3, 100)

let req = Request(Get, SchemeHttp, "", None, "/users", None, Nil, "")
match HttpClient.run(client, req) do
  Ok(resp) -> Ok(Http.response_body(resp))
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
    HttpServer.new(8080)
    |> HttpServer.plug(handle)
    |> HttpServer.listen()
  end
end
```
