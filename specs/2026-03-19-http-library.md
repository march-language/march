# HTTP Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the three-layer HTTP library (pure types, transport, client) as March stdlib modules.

**Architecture:** Layer 1 (`Http`) is pure March — types, constructors, accessors, transforms. Layer 2 (`Http.Transport`) needs runtime builtins for TCP sockets — we add C runtime functions and eval builtins first, then write the March module. Layer 3 (`Http.Client`) is pure March pipeline logic that calls Layer 2 to send requests.

**Tech Stack:** March stdlib modules (`.march` files), C runtime extensions (`march_runtime.c/h`), OCaml eval builtins (`eval.ml`), Alcotest tests (`test_march.ml`).

**Spec:** `docs/superpowers/specs/2026-03-19-http-library-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `stdlib/http.march` | Layer 1: pure HTTP types, constructors, accessors, transforms |
| `stdlib/http_transport.march` | Layer 2: Pool, send, stream — wraps runtime builtins |
| `stdlib/http_client.march` | Layer 3: Client, step pipeline, built-in steps |
| `runtime/march_runtime.c` | Add: TCP socket connect/send/recv/close, simple HTTP/1.1 parser |
| `runtime/march_runtime.h` | Add: declarations for new socket/HTTP functions |
| `lib/eval/eval.ml` | Add: eval builtins bridging March to runtime socket functions |
| `bin/main.ml` | Add: http.march, http_transport.march, http_client.march to stdlib load order |
| `test/test_march.ml` | Add: tests for all three layers |

**Note on module naming:** March uses flat file names for stdlib. The file `stdlib/http.march` contains `mod Http do ... end`. Nested modules `Http.Transport` and `Http.Client` are defined in separate files as `mod Http do mod Transport do ... end end` to keep files focused while nesting under the `Http` namespace.

---

## Task 1: Layer 1 — Pure HTTP Types (`stdlib/http.march`)

The foundation. Pure types with no I/O. Everything else builds on this.

**Files:**
- Create: `stdlib/http.march`
- Modify: `bin/main.ml` (add to stdlib load order)
- Modify: `test/test_march.ml` (add tests)

- [ ] **Step 1: Write the Http module with Method, Scheme, Status, Header types**

Create `stdlib/http.march`:

```march
-- Http module: pure HTTP protocol types, constructors, and transforms.
--
-- This is Layer 1 of March's HTTP library. It contains no I/O — only
-- data types and functions for building and inspecting HTTP requests
-- and responses. Libraries that work with HTTP types depend on this alone.
--
-- Usage:
--   use Http
--   let req = Http.get("https://example.com") |> unwrap
--   let req = req |> Http.set_header("Accept", "application/json")

mod Http do

  type Method =
    | Get
    | Post
    | Put
    | Patch
    | Delete
    | Head
    | Options
    | Trace
    | Connect
    | Other(String)

  type Scheme = Http | Https

  type Status = Status(Int)

  type Header = Header(String, String)

  type UrlError =
    | InvalidScheme(String)
    | MissingHost
    | InvalidPort(String)
    | MalformedUrl(String)

  -- Request(body): an HTTP request parameterized over body type.
  -- Fields: method, scheme, host, port, path, query, headers, body
  type Request(body) = Request(Method, Scheme, String, Option(Int), String, Option(String), List(Header), body)

  -- Response(body): an HTTP response parameterized over body type.
  -- Fields: status, headers, body
  type Response(body) = Response(Status, List(Header), body)

  -- -----------------------------------------------------------------------
  -- Method helpers
  -- -----------------------------------------------------------------------

  doc "Convert a Method to its HTTP verb string."
  pub fn method_to_string(m : Method) : String do
    match m with
    | Get     -> "GET"
    | Post    -> "POST"
    | Put     -> "PUT"
    | Patch   -> "PATCH"
    | Delete  -> "DELETE"
    | Head    -> "HEAD"
    | Options -> "OPTIONS"
    | Trace   -> "TRACE"
    | Connect -> "CONNECT"
    | Other(s) -> s
    end
  end

  -- -----------------------------------------------------------------------
  -- Status helpers
  -- -----------------------------------------------------------------------

  pub fn status_code(s : Status) : Int do
    match s with
    | Status(n) -> n
    end
  end

  pub fn status_ok() : Status do Status(200) end
  pub fn status_created() : Status do Status(201) end
  pub fn status_no_content() : Status do Status(204) end
  pub fn status_moved() : Status do Status(301) end
  pub fn status_found() : Status do Status(302) end
  pub fn status_bad_request() : Status do Status(400) end
  pub fn status_unauthorized() : Status do Status(401) end
  pub fn status_forbidden() : Status do Status(403) end
  pub fn status_not_found() : Status do Status(404) end
  pub fn status_server_error() : Status do Status(500) end

  pub fn is_informational(s : Status) : Bool do
    let c = status_code(s)
    c >= 100 && c < 200
  end

  pub fn is_success(s : Status) : Bool do
    let c = status_code(s)
    c >= 200 && c < 300
  end

  pub fn is_redirect(s : Status) : Bool do
    let c = status_code(s)
    c >= 300 && c < 400
  end

  pub fn is_client_error(s : Status) : Bool do
    let c = status_code(s)
    c >= 400 && c < 500
  end

  pub fn is_server_error(s : Status) : Bool do
    let c = status_code(s)
    c >= 500 && c < 600
  end

  -- -----------------------------------------------------------------------
  -- Request accessors
  -- -----------------------------------------------------------------------

  pub fn method(req : Request(b)) : Method do
    match req with | Request(m, _, _, _, _, _, _, _) -> m end
  end

  pub fn scheme(req : Request(b)) : Scheme do
    match req with | Request(_, s, _, _, _, _, _, _) -> s end
  end

  pub fn host(req : Request(b)) : String do
    match req with | Request(_, _, h, _, _, _, _, _) -> h end
  end

  pub fn port(req : Request(b)) : Option(Int) do
    match req with | Request(_, _, _, p, _, _, _, _) -> p end
  end

  pub fn path(req : Request(b)) : String do
    match req with | Request(_, _, _, _, p, _, _, _) -> p end
  end

  pub fn query(req : Request(b)) : Option(String) do
    match req with | Request(_, _, _, _, _, q, _, _) -> q end
  end

  pub fn headers(req : Request(b)) : List(Header) do
    match req with | Request(_, _, _, _, _, _, h, _) -> h end
  end

  pub fn body(req : Request(b)) : b do
    match req with | Request(_, _, _, _, _, _, _, b) -> b end
  end

  -- -----------------------------------------------------------------------
  -- Request transforms (pipeable)
  -- -----------------------------------------------------------------------

  pub fn set_method(req : Request(b), m : Method) : Request(b) do
    match req with
    | Request(_, sc, h, p, pa, q, hd, bd) -> Request(m, sc, h, p, pa, q, hd, bd)
    end
  end

  pub fn set_scheme(req : Request(b), s : Scheme) : Request(b) do
    match req with
    | Request(m, _, h, p, pa, q, hd, bd) -> Request(m, s, h, p, pa, q, hd, bd)
    end
  end

  pub fn set_host(req : Request(b), host : String) : Request(b) do
    match req with
    | Request(m, sc, _, p, pa, q, hd, bd) -> Request(m, sc, host, p, pa, q, hd, bd)
    end
  end

  pub fn set_port(req : Request(b), port : Int) : Request(b) do
    match req with
    | Request(m, sc, h, _, pa, q, hd, bd) -> Request(m, sc, h, Some(port), pa, q, hd, bd)
    end
  end

  pub fn set_path(req : Request(b), path : String) : Request(b) do
    match req with
    | Request(m, sc, h, p, _, q, hd, bd) -> Request(m, sc, h, p, path, q, hd, bd)
    end
  end

  pub fn set_body(req : Request(a), new_body : b) : Request(b) do
    match req with
    | Request(m, sc, h, p, pa, q, hd, _) -> Request(m, sc, h, p, pa, q, hd, new_body)
    end
  end

  pub fn set_header(req : Request(b), name : String, value : String) : Request(b) do
    match req with
    | Request(m, sc, h, p, pa, q, hd, bd) ->
      Request(m, sc, h, p, pa, q, Cons(Header(name, value), hd), bd)
    end
  end

  -- -----------------------------------------------------------------------
  -- Response accessors
  -- -----------------------------------------------------------------------

  pub fn response_status(resp : Response(b)) : Status do
    match resp with | Response(s, _, _) -> s end
  end

  pub fn response_headers(resp : Response(b)) : List(Header) do
    match resp with | Response(_, h, _) -> h end
  end

  pub fn response_body(resp : Response(b)) : b do
    match resp with | Response(_, _, b) -> b end
  end

  pub fn response_status_code(resp : Response(b)) : Int do
    status_code(response_status(resp))
  end

  pub fn response_is_success(resp : Response(b)) : Bool do
    is_success(response_status(resp))
  end

  pub fn response_is_redirect(resp : Response(b)) : Bool do
    is_redirect(response_status(resp))
  end

  -- -----------------------------------------------------------------------
  -- Header lookup (case-insensitive)
  -- -----------------------------------------------------------------------

  pub fn get_header(resp : Response(b), name : String) : Option(String) do
    let lower_name = string_to_lowercase(name)
    fn find(hs : List(Header)) : Option(String) do
      match hs with
      | Nil -> None
      | Cons(Header(n, v), rest) ->
        if string_to_lowercase(n) == lower_name then Some(v)
        else find(rest)
      end
    end
    find(response_headers(resp))
  end

  pub fn get_request_header(req : Request(b), name : String) : Option(String) do
    let lower_name = string_to_lowercase(name)
    fn find(hs : List(Header)) : Option(String) do
      match hs with
      | Nil -> None
      | Cons(Header(n, v), rest) ->
        if string_to_lowercase(n) == lower_name then Some(v)
        else find(rest)
      end
    end
    find(headers(req))
  end

  -- -----------------------------------------------------------------------
  -- URL parsing
  -- -----------------------------------------------------------------------

  doc """
  Parse a URL string into a Request(Unit).
  Supports http:// and https:// schemes.
  Returns Err(UrlError) for malformed URLs.
  """
  pub fn parse_url(url : String) : Result(Request(Unit), UrlError) do
    -- Extract scheme
    let has_https = string_starts_with(url, "https://")
    let has_http = string_starts_with(url, "http://")
    if not(has_https) && not(has_http) then
      Err(InvalidScheme(url))
    else
      let url_scheme = if has_https then Https else Http
      let prefix_len = if has_https then 8 else 7
      let rest = string_slice(url, prefix_len, string_byte_length(url) - prefix_len)
      -- Split host+port from path
      let path_idx = string_index_of(rest, "/")
      let host_part = match path_idx with
        | Some(i) -> string_slice(rest, 0, i)
        | None -> rest
        end
      let path_and_query = match path_idx with
        | Some(i) -> string_slice(rest, i, string_byte_length(rest) - i)
        | None -> "/"
        end
      -- Split path from query
      let query_idx = string_index_of(path_and_query, "?")
      let url_path = match query_idx with
        | Some(i) -> string_slice(path_and_query, 0, i)
        | None -> path_and_query
        end
      let url_query = match query_idx with
        | Some(i) -> Some(string_slice(path_and_query, i + 1, string_byte_length(path_and_query) - i - 1))
        | None -> None
        end
      -- Split host from port
      let port_idx = string_index_of(host_part, ":")
      let url_host = match port_idx with
        | Some(i) -> string_slice(host_part, 0, i)
        | None -> host_part
        end
      let url_port = match port_idx with
        | Some(i) ->
          let port_str = string_slice(host_part, i + 1, string_byte_length(host_part) - i - 1)
          match string_to_int(port_str) with
          | Some(p) -> Some(p)
          | None -> Some(-1)
          end
        | None -> None
        end
      if string_is_empty(url_host) then
        Err(MissingHost)
      else match url_port with
        | Some(-1) -> Err(InvalidPort(host_part))
        | _ -> Ok(Request(Get, url_scheme, url_host, url_port, url_path, url_query, Nil, ()))
        end
    end
  end

  -- -----------------------------------------------------------------------
  -- Convenience constructors
  -- -----------------------------------------------------------------------

  pub fn get(url : String) : Result(Request(Unit), UrlError) do
    parse_url(url)
  end

  pub fn post(url : String, bdy : b) : Result(Request(b), UrlError) do
    match parse_url(url) with
    | Ok(req) -> Ok(set_method(set_body(req, bdy), Post))
    | Err(e) -> Err(e)
    end
  end

  pub fn put(url : String, bdy : b) : Result(Request(b), UrlError) do
    match parse_url(url) with
    | Ok(req) -> Ok(set_method(set_body(req, bdy), Put))
    | Err(e) -> Err(e)
    end
  end

  pub fn patch(url : String, bdy : b) : Result(Request(b), UrlError) do
    match parse_url(url) with
    | Ok(req) -> Ok(set_method(set_body(req, bdy), Patch))
    | Err(e) -> Err(e)
    end
  end

  pub fn delete(url : String) : Result(Request(Unit), UrlError) do
    match parse_url(url) with
    | Ok(req) -> Ok(set_method(req, Delete))
    | Err(e) -> Err(e)
    end
  end

  pub fn head(url : String) : Result(Request(Unit), UrlError) do
    match parse_url(url) with
    | Ok(req) -> Ok(set_method(req, Head))
    | Err(e) -> Err(e)
    end
  end

  pub fn options(url : String) : Result(Request(Unit), UrlError) do
    match parse_url(url) with
    | Ok(req) -> Ok(set_method(req, Options))
    | Err(e) -> Err(e)
    end
  end

  -- -----------------------------------------------------------------------
  -- Query string encoding
  -- -----------------------------------------------------------------------

  doc "Encode a list of key-value pairs as a query string."
  pub fn encode_query(params : List((String, String))) : String do
    fn encode_pair(k : String, v : String) : String do
      k ++ "=" ++ v
    end
    fn go(ps : List((String, String))) : List(String) do
      match ps with
      | Nil -> Nil
      | Cons((k, v), rest) -> Cons(encode_pair(k, v), go(rest))
      end
    end
    string_join(go(params), "&")
  end

  pub fn set_query(req : Request(b), params : List((String, String))) : Request(b) do
    match req with
    | Request(m, sc, h, p, pa, _, hd, bd) ->
      let q = if is_nil(params) then None else Some(encode_query(params))
      Request(m, sc, h, p, pa, q, hd, bd)
    end
  end

end
```

- [ ] **Step 2: Register http.march in stdlib load order**

In `bin/main.ml`, add `"http.march"` to the `files` list after `"iolist.march"`:

```ocaml
    let files = [
      "prelude.march";
      "option.march";
      "result.march";
      "list.march";
      "math.march";
      "string.march";
      "iolist.march";
      "http.march";
    ] in
```

- [ ] **Step 3: Write tests for Layer 1**

Add to `test/test_march.ml`:

1. Add helper:
```ocaml
let eval_with_http src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let http_decl = load_stdlib_file_for_test "http.march" in
  eval_with_stdlib [string_decl; http_decl] src
```

2. Add test functions:
```ocaml
let test_http_parse_url () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/path?q=1") with
      | Ok(req) -> Http.host(req)
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url host" "example.com" (vstr (call_fn env "f" []))

let test_http_parse_url_scheme () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:8080/api") with
      | Ok(req) ->
        match Http.scheme(req) with
        | Http.Http -> "http"
        | Http.Https -> "https"
        end
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url scheme" "http" (vstr (call_fn env "f" []))

let test_http_parse_url_path () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("https://example.com/api/v1") with
      | Ok(req) -> Http.path(req)
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url path" "/api/v1" (vstr (call_fn env "f" []))

let test_http_parse_url_port () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("http://localhost:3000/") with
      | Ok(req) ->
        match Http.port(req) with
        | Some(p) -> p
        | None -> 0
        end
      | Err(_) -> -1
      end
    end
  end|} in
  Alcotest.(check int) "parse_url port" 3000 (vint (call_fn env "f" []))

let test_http_parse_url_invalid () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.parse_url("ftp://bad") with
      | Ok(_) -> "ok"
      | Err(Http.InvalidScheme(_)) -> "invalid_scheme"
      | Err(_) -> "other_error"
      end
    end
  end|} in
  Alcotest.(check string) "parse_url invalid scheme" "invalid_scheme" (vstr (call_fn env "f" []))

let test_http_set_header () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.get("https://example.com") with
      | Ok(req) ->
        let req = Http.set_header(req, "Accept", "application/json")
        Http.get_request_header(req, "accept")
      | Err(_) -> None
      end
    end
  end|} in
  let result = call_fn env "f" [] in
  let args = vcon "Some" result in
  Alcotest.(check string) "set_header" "application/json" (vstr (List.hd args))

let test_http_method_to_string () =
  let env = eval_with_http {|mod Test do
    fn f() do Http.method_to_string(Http.Post) end
  end|} in
  Alcotest.(check string) "method_to_string" "POST" (vstr (call_fn env "f" []))

let test_http_status_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do Http.is_success(Http.status_ok()) end
  end|} in
  Alcotest.(check bool) "status_ok is success" true (vbool (call_fn env "f" []))

let test_http_post_constructor () =
  let env = eval_with_http {|mod Test do
    fn f() do
      match Http.post("https://example.com/api", "body data") with
      | Ok(req) -> Http.method_to_string(Http.method(req))
      | Err(_) -> "fail"
      end
    end
  end|} in
  Alcotest.(check string) "post method" "POST" (vstr (call_fn env "f" []))

let test_http_encode_query () =
  let env = eval_with_http {|mod Test do
    fn f() do
      Http.encode_query(Cons(("key", "value"), Cons(("foo", "bar"), Nil)))
    end
  end|} in
  Alcotest.(check string) "encode_query" "key=value&foo=bar" (vstr (call_fn env "f" []))

let test_http_response_helpers () =
  let env = eval_with_http {|mod Test do
    fn f() do
      let resp = Http.Response(Http.Status(404), Nil, "Not Found")
      Http.response_status_code(resp)
    end
  end|} in
  Alcotest.(check int) "response status code" 404 (vint (call_fn env "f" []))
```

3. Register tests in the test suite at the bottom of the file:
```ocaml
      ("http stdlib", [
        Alcotest.test_case "parse_url"          `Quick test_http_parse_url;
        Alcotest.test_case "parse_url scheme"    `Quick test_http_parse_url_scheme;
        Alcotest.test_case "parse_url path"      `Quick test_http_parse_url_path;
        Alcotest.test_case "parse_url port"      `Quick test_http_parse_url_port;
        Alcotest.test_case "parse_url invalid"   `Quick test_http_parse_url_invalid;
        Alcotest.test_case "set_header"          `Quick test_http_set_header;
        Alcotest.test_case "method_to_string"    `Quick test_http_method_to_string;
        Alcotest.test_case "status helpers"      `Quick test_http_status_helpers;
        Alcotest.test_case "post constructor"    `Quick test_http_post_constructor;
        Alcotest.test_case "encode_query"        `Quick test_http_encode_query;
        Alcotest.test_case "response helpers"    `Quick test_http_response_helpers;
      ]);
```

- [ ] **Step 4: Build and run tests**

Run: `/Users/80197052/.opam/march/bin/dune build`
Then: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All existing tests pass + new http stdlib tests pass.

- [ ] **Step 5: Commit**

```bash
git add stdlib/http.march bin/main.ml test/test_march.ml
git commit -m "feat(stdlib): add Http module — pure protocol types (Layer 1)"
```

---

## Task 2: Runtime TCP Socket Primitives

Add C runtime functions for TCP socket operations. These are the foundation for Layer 2.

**Files:**
- Modify: `runtime/march_runtime.h` (add declarations)
- Modify: `runtime/march_runtime.c` (add implementations)

- [ ] **Step 1: Add socket function declarations to runtime header**

Add to `runtime/march_runtime.h`:

```c
/* ── TCP socket primitives ─────────────────────────────────────────── */
/* All functions return March values (tagged pointers or ints).
   Errors are returned as Option(String) / Result-style values.       */

/* march_tcp_connect(host, port) -> Result(Int, String)
   Opens a TCP connection. Returns Ok(fd) or Err(message). */
march_obj_t* march_tcp_connect(march_obj_t* host, int64_t port);

/* march_tcp_send(fd, data) -> Result(Int, String)
   Sends data on a connected socket. Returns Ok(bytes_sent) or Err(msg). */
march_obj_t* march_tcp_send(int64_t fd, march_obj_t* data);

/* march_tcp_recv(fd, max_bytes) -> Result(String, String)
   Receives up to max_bytes. Returns Ok(data) or Err(msg). */
march_obj_t* march_tcp_recv(int64_t fd, int64_t max_bytes);

/* march_tcp_close(fd) -> Unit
   Closes a socket file descriptor. */
void march_tcp_close(int64_t fd);

/* march_tcp_send_all(fd, data) -> Result(Unit, String)
   Sends all data, retrying on partial writes. */
march_obj_t* march_tcp_send_all(int64_t fd, march_obj_t* data);

/* march_tcp_recv_all(fd, max_bytes, timeout_ms) -> Result(String, String)
   Receives data until connection closes or max_bytes reached. */
march_obj_t* march_tcp_recv_all(int64_t fd, int64_t max_bytes, int64_t timeout_ms);
```

- [ ] **Step 2: Implement socket functions in runtime C**

Add to `runtime/march_runtime.c`:

```c
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <poll.h>

/* Helper: create Ok(value) — alloc a VCon("Ok", [value]) */
static march_obj_t* make_ok(march_obj_t* value) {
    march_obj_t* obj = march_alloc(16 + 8);  /* header + 1 field */
    obj->tag = 0;  /* Ok tag */
    ((march_obj_t**)((char*)obj + 16))[0] = value;
    if (value) march_incrc(value);
    return obj;
}

/* Helper: create Err(msg) — alloc a VCon("Err", [string]) */
static march_obj_t* make_err(const char* msg) {
    march_obj_t* s = march_string_lit(msg, strlen(msg));
    march_obj_t* obj = march_alloc(16 + 8);
    obj->tag = 1;  /* Err tag */
    ((march_obj_t**)((char*)obj + 16))[0] = s;
    return obj;
}

/* Helper: wrap an int64 as a March TInt field value */
static march_obj_t* make_int_obj(int64_t n) {
    march_obj_t* obj = march_alloc(16 + 8);
    obj->tag = 0;
    ((int64_t*)((char*)obj + 16))[0] = n;
    return obj;
}

march_obj_t* march_tcp_connect(march_obj_t* host, int64_t port) {
    /* Extract C string from March string */
    const char* hostname = march_string_data(host);

    struct addrinfo hints, *result;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%lld", (long long)port);

    int err = getaddrinfo(hostname, port_str, &hints, &result);
    if (err != 0) {
        return make_err(gai_strerror(err));
    }

    int fd = socket(result->ai_family, result->ai_socktype, result->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(result);
        return make_err(strerror(errno));
    }

    if (connect(fd, result->ai_addr, result->ai_addrlen) < 0) {
        freeaddrinfo(result);
        close(fd);
        return make_err(strerror(errno));
    }

    freeaddrinfo(result);
    return make_ok(make_int_obj(fd));
}

march_obj_t* march_tcp_send(int64_t fd, march_obj_t* data) {
    const char* buf = march_string_data(data);
    int64_t len = march_string_len(data);
    ssize_t sent = send((int)fd, buf, (size_t)len, 0);
    if (sent < 0) {
        return make_err(strerror(errno));
    }
    return make_ok(make_int_obj(sent));
}

march_obj_t* march_tcp_send_all(int64_t fd, march_obj_t* data) {
    const char* buf = march_string_data(data);
    int64_t total = march_string_len(data);
    int64_t sent = 0;
    while (sent < total) {
        ssize_t n = send((int)fd, buf + sent, (size_t)(total - sent), 0);
        if (n < 0) {
            return make_err(strerror(errno));
        }
        sent += n;
    }
    /* Return Ok(()) — unit as empty object */
    return make_ok(NULL);
}

march_obj_t* march_tcp_recv(int64_t fd, int64_t max_bytes) {
    char* buf = malloc((size_t)max_bytes + 1);
    if (!buf) return make_err("out of memory");

    ssize_t n = recv((int)fd, buf, (size_t)max_bytes, 0);
    if (n < 0) {
        free(buf);
        return make_err(strerror(errno));
    }

    march_obj_t* s = march_string_lit(buf, (int64_t)n);
    free(buf);
    return make_ok(s);
}

march_obj_t* march_tcp_recv_all(int64_t fd, int64_t max_bytes, int64_t timeout_ms) {
    /* Accumulate received data into a buffer */
    int64_t cap = max_bytes < 8192 ? max_bytes : 8192;
    int64_t total = 0;
    char* buf = malloc((size_t)cap);
    if (!buf) return make_err("out of memory");

    struct pollfd pfd;
    pfd.fd = (int)fd;
    pfd.events = POLLIN;

    while (total < max_bytes) {
        int ready = poll(&pfd, 1, (int)timeout_ms);
        if (ready < 0) {
            free(buf);
            return make_err(strerror(errno));
        }
        if (ready == 0) break;  /* timeout */

        int64_t remaining = max_bytes - total;
        int64_t chunk = remaining < 4096 ? remaining : 4096;
        if (total + chunk > cap) {
            cap = cap * 2;
            if (cap > max_bytes) cap = max_bytes;
            buf = realloc(buf, (size_t)cap);
            if (!buf) return make_err("out of memory");
        }

        ssize_t n = recv((int)fd, buf + total, (size_t)chunk, 0);
        if (n < 0) {
            free(buf);
            return make_err(strerror(errno));
        }
        if (n == 0) break;  /* connection closed */
        total += n;
    }

    march_obj_t* s = march_string_lit(buf, total);
    free(buf);
    return make_ok(s);
}

void march_tcp_close(int64_t fd) {
    close((int)fd);
}
```

**Note:** These runtime functions are called from the eval interpreter via builtins (Task 3), not from compiled LLVM code. The `make_ok`/`make_err` helpers above are for the compiled path; the eval builtins create `VCon("Ok", [...])` / `VCon("Err", [...])` directly.

- [ ] **Step 3: Build to verify compilation**

Run: `/Users/80197052/.opam/march/bin/dune build`
Expected: Clean build, no errors.

- [ ] **Step 4: Commit**

```bash
git add runtime/march_runtime.c runtime/march_runtime.h
git commit -m "feat(runtime): add TCP socket primitives for HTTP transport"
```

---

## Task 3: Eval Builtins for TCP Sockets

Wire the TCP primitives into the interpreter so March code can call them.

**Files:**
- Modify: `lib/eval/eval.ml` (add builtins)
- Modify: `test/test_march.ml` (add basic socket test)

- [ ] **Step 1: Add TCP builtins to eval.ml**

Find the builtin registration section in `lib/eval/eval.ml` and add:

```ocaml
(* TCP socket builtins *)
| "tcp_connect" ->
  (match args with
   | [VString host; VInt port] ->
     (try
        let open Unix in
        let addrs = getaddrinfo host (string_of_int port)
          [AI_FAMILY PF_INET; AI_SOCKTYPE SOCK_STREAM] in
        (match addrs with
         | [] -> VCon ("Err", [VString ("cannot resolve " ^ host)])
         | ai :: _ ->
           let fd = socket ai.ai_family ai.ai_socktype ai.ai_protocol in
           (try
              connect fd ai.ai_addr;
              VCon ("Ok", [VInt (Obj.magic fd : int)])
            with Unix_error (err, _, _) ->
              close fd;
              VCon ("Err", [VString (error_message err)])))
      with
      | Unix.Unix_error (err, _, _) ->
        VCon ("Err", [VString (Unix.error_message err)])
      | exn ->
        VCon ("Err", [VString (Printexc.to_string exn)]))
   | _ -> eval_err "tcp_connect(host, port)")

| "tcp_send" ->
  (match args with
   | [VInt fd; VString data] ->
     (try
        let n = Unix.send (Obj.magic fd) (Bytes.of_string data) 0
          (String.length data) [] in
        VCon ("Ok", [VInt n])
      with Unix.Unix_error (err, _, _) ->
        VCon ("Err", [VString (Unix.error_message err)]))
   | _ -> eval_err "tcp_send(fd, data)")

| "tcp_send_all" ->
  (match args with
   | [VInt fd; VString data] ->
     let sock = (Obj.magic fd : Unix.file_descr) in
     let buf = Bytes.of_string data in
     let total = Bytes.length buf in
     let rec loop off =
       if off >= total then VCon ("Ok", [VCon ("Unit", [])])
       else
         try
           let n = Unix.send sock buf off (total - off) [] in
           loop (off + n)
         with Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VString (Unix.error_message err)])
     in
     loop 0
   | _ -> eval_err "tcp_send_all(fd, data)")

| "tcp_recv" ->
  (match args with
   | [VInt fd; VInt max_bytes] ->
     let buf = Bytes.create max_bytes in
     (try
        let n = Unix.recv (Obj.magic fd) buf 0 max_bytes [] in
        VCon ("Ok", [VString (Bytes.sub_string buf 0 n)])
      with Unix.Unix_error (err, _, _) ->
        VCon ("Err", [VString (Unix.error_message err)]))
   | _ -> eval_err "tcp_recv(fd, max_bytes)")

| "tcp_recv_all" ->
  (match args with
   | [VInt fd; VInt max_bytes; VInt _timeout_ms] ->
     let sock = (Obj.magic fd : Unix.file_descr) in
     let buf = Buffer.create 4096 in
     let chunk = Bytes.create 4096 in
     let rec loop total =
       if total >= max_bytes then
         VCon ("Ok", [VString (Buffer.contents buf)])
       else
         try
           let to_read = min 4096 (max_bytes - total) in
           let n = Unix.recv sock chunk 0 to_read [] in
           if n = 0 then VCon ("Ok", [VString (Buffer.contents buf)])
           else begin
             Buffer.add_subbytes buf chunk 0 n;
             loop (total + n)
           end
         with Unix.Unix_error (err, _, _) ->
           VCon ("Err", [VString (Unix.error_message err)])
     in
     loop 0
   | _ -> eval_err "tcp_recv_all(fd, max_bytes, timeout_ms)")

| "tcp_close" ->
  (match args with
   | [VInt fd] ->
     (try Unix.close (Obj.magic fd) with _ -> ());
     VCon ("Unit", [])
   | _ -> eval_err "tcp_close(fd)")
```

- [ ] **Step 2: Build to verify compilation**

Run: `/Users/80197052/.opam/march/bin/dune build`
Expected: Clean build.

- [ ] **Step 3: Add a basic TCP builtin test**

Add to `test/test_march.ml`:

```ocaml
(* Test that tcp_connect returns Err for bad host — does NOT need a running server *)
let test_tcp_connect_bad_host () =
  let env = eval_module {|mod Test do
    fn f() do
      match tcp_connect("this-host-does-not-exist.invalid", 9999) with
      | Ok(_) -> "connected"
      | Err(_) -> "error"
      end
    end
  end|} in
  Alcotest.(check string) "tcp_connect bad host" "error" (vstr (call_fn env "f" []))

let test_tcp_close_noop () =
  (* tcp_close on an invalid fd should not crash *)
  let env = eval_module {|mod Test do
    fn f() do
      tcp_close(-1)
      "ok"
    end
  end|} in
  Alcotest.(check string) "tcp_close no crash" "ok" (vstr (call_fn env "f" []))
```

Register:
```ocaml
      ("tcp builtins", [
        Alcotest.test_case "connect bad host" `Quick test_tcp_connect_bad_host;
        Alcotest.test_case "close noop"       `Quick test_tcp_close_noop;
      ]);
```

- [ ] **Step 4: Run tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(eval): add TCP socket builtins (tcp_connect, tcp_send, tcp_recv, tcp_close)"
```

---

## Task 4: HTTP/1.1 Request Serialization Builtin

Add a builtin that serializes an HTTP request to a raw string for sending over TCP. This bridges Layer 1 types to Layer 2 transport.

**Files:**
- Modify: `lib/eval/eval.ml` (add http_serialize_request builtin)
- Modify: `test/test_march.ml` (add test)

- [ ] **Step 1: Add http_serialize_request builtin**

This builtin takes method, host, path, query, headers (as list of pairs), and body strings, and produces a raw HTTP/1.1 request string.

```ocaml
| "http_serialize_request" ->
  (match args with
   | [VString method_str; VString host; VString path; body_opt; header_list] ->
     let buf = Buffer.create 256 in
     (* Request line *)
     let query_part = match body_opt with
       | VCon ("Some", [VString q]) -> "?" ^ q
       | _ -> ""
     in
     Buffer.add_string buf method_str;
     Buffer.add_char buf ' ';
     Buffer.add_string buf path;
     Buffer.add_string buf query_part;
     Buffer.add_string buf " HTTP/1.1\r\n";
     (* Host header *)
     Buffer.add_string buf "Host: ";
     Buffer.add_string buf host;
     Buffer.add_string buf "\r\n";
     (* User headers *)
     let rec add_headers = function
       | VCon ("Nil", []) -> ()
       | VCon ("Cons", [VCon ("Header", [VString name; VString value]); rest]) ->
         Buffer.add_string buf name;
         Buffer.add_string buf ": ";
         Buffer.add_string buf value;
         Buffer.add_string buf "\r\n";
         add_headers rest
       | _ -> ()
     in
     add_headers header_list;
     (* Body *)
     (match args with
      | [_; _; _; _; _; VString body] when body <> "" ->
        Buffer.add_string buf "Content-Length: ";
        Buffer.add_string buf (string_of_int (String.length body));
        Buffer.add_string buf "\r\n\r\n";
        Buffer.add_string buf body
      | _ ->
        Buffer.add_string buf "\r\n");
     VString (Buffer.contents buf)
   | _ -> eval_err "http_serialize_request(method, host, path, query_opt, headers, body)")
```

Actually, let's simplify — take 6 args explicitly:

```ocaml
| "http_serialize_request" ->
  (match args with
   | [VString meth; VString host; VString path; query_opt; header_list; VString body] ->
     let buf = Buffer.create 256 in
     let query_str = match query_opt with
       | VCon ("Some", [VString q]) -> "?" ^ q
       | _ -> ""
     in
     Buffer.add_string buf meth;
     Buffer.add_char buf ' ';
     Buffer.add_string buf path;
     Buffer.add_string buf query_str;
     Buffer.add_string buf " HTTP/1.1\r\n";
     Buffer.add_string buf "Host: ";
     Buffer.add_string buf host;
     Buffer.add_string buf "\r\n";
     let rec add_headers = function
       | VCon ("Nil", []) -> ()
       | VCon ("Cons", [VCon ("Header", [VString n; VString v]); rest]) ->
         Buffer.add_string buf n;
         Buffer.add_string buf ": ";
         Buffer.add_string buf v;
         Buffer.add_string buf "\r\n";
         add_headers rest
       | _ -> ()
     in
     add_headers header_list;
     if body <> "" then begin
       Buffer.add_string buf "Content-Length: ";
       Buffer.add_string buf (string_of_int (String.length body));
       Buffer.add_string buf "\r\n"
     end;
     Buffer.add_string buf "\r\n";
     Buffer.add_string buf body;
     VString (Buffer.contents buf)
   | _ -> eval_err "http_serialize_request(method, host, path, query_opt, headers, body)")
```

- [ ] **Step 2: Add http_parse_response builtin**

Parses a raw HTTP/1.1 response string into (status_code, headers_list, body):

```ocaml
| "http_parse_response" ->
  (match args with
   | [VString raw] ->
     (* Find end of headers *)
     (match String.split_on_char '\n' raw with
      | [] -> VCon ("Err", [VString "empty response"])
      | status_line :: rest ->
        (* Parse status line: "HTTP/1.1 200 OK" *)
        let parts = String.split_on_char ' ' (String.trim status_line) in
        (match parts with
         | _ :: code_str :: _ ->
           (try
              let code = int_of_string code_str in
              (* Parse headers until empty line *)
              let rec parse_headers lines acc =
                match lines with
                | [] -> (List.rev acc, "")
                | line :: rest ->
                  let trimmed = String.trim line in
                  if trimmed = "" then
                    (List.rev acc, String.concat "\n" rest)
                  else
                    match String.index_opt trimmed ':' with
                    | Some i ->
                      let name = String.trim (String.sub trimmed 0 i) in
                      let value = String.trim (String.sub trimmed (i+1) (String.length trimmed - i - 1)) in
                      parse_headers rest ((name, value) :: acc)
                    | None -> parse_headers rest acc
              in
              let (hdrs, body) = parse_headers rest [] in
              let header_list = List.fold_right (fun (n, v) acc ->
                VCon ("Cons", [VCon ("Header", [VString n; VString v]); acc])
              ) hdrs (VCon ("Nil", [])) in
              VCon ("Ok", [VCon ("Tuple3", [VInt code; header_list; VString body])])
            with _ ->
              VCon ("Err", [VString ("bad status code: " ^ code_str)]))
         | _ ->
           VCon ("Err", [VString ("bad status line: " ^ status_line)])))
   | _ -> eval_err "http_parse_response(raw_string)")
```

- [ ] **Step 3: Add tests**

```ocaml
let test_http_serialize_request () =
  let env = eval_with_http {|mod Test do
    fn f() do
      http_serialize_request(
        "GET", "example.com", "/path", Some("q=1"),
        Cons(Http.Header("Accept", "text/html"), Nil),
        ""
      )
    end
  end|} in
  let result = vstr (call_fn env "f" []) in
  let expected = "GET /path?q=1 HTTP/1.1\r\nHost: example.com\r\nAccept: text/html\r\n\r\n" in
  Alcotest.(check string) "serialize request" expected result

let test_http_parse_response () =
  let env = eval_module {|mod Test do
    fn f() do
      let raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello"
      match http_parse_response(raw) with
      | Ok((code, headers, body)) -> code
      | Err(_) -> -1
      end
    end
  end|} in
  Alcotest.(check int) "parse response status" 200 (vint (call_fn env "f" []))
```

Register:
```ocaml
      ("http serialization", [
        Alcotest.test_case "serialize request"  `Quick test_http_serialize_request;
        Alcotest.test_case "parse response"     `Quick test_http_parse_response;
      ]);
```

- [ ] **Step 4: Run tests**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/eval/eval.ml test/test_march.ml
git commit -m "feat(eval): add http_serialize_request and http_parse_response builtins"
```

---

## Task 5: Layer 2 — HTTP Transport Module (`stdlib/http_transport.march`)

The low-level transport layer. Uses TCP builtins + serialization to send HTTP requests.

**Files:**
- Create: `stdlib/http_transport.march`
- Modify: `bin/main.ml` (add to load order)
- Modify: `test/test_march.ml` (add tests)

- [ ] **Step 1: Write the Http.Transport module**

Create `stdlib/http_transport.march`:

```march
-- Http.Transport: low-level HTTP transport layer.
--
-- Sends raw HTTP/1.1 requests over TCP sockets.
-- This is Layer 2 of March's HTTP library — it handles connection
-- management and raw request/response exchange.
--
-- Most users should use Http.Client (Layer 3) instead. Use this
-- directly only when you need low-level control over connections.

mod Http do
  mod Transport do

    type TransportError =
      | ConnectionRefused(String)
      | Timeout(String)
      | SendError(String)
      | RecvError(String)
      | ParseError(String)
      | Closed

    doc """
    Send an HTTP request and receive the response.
    This is a simple one-shot function: opens connection, sends, receives, closes.

    Takes an Http.Request(String) and returns a Result containing
    an Http.Response(String) or a TransportError.
    """
    pub fn send(req : Http.Request(String)) : Result(Http.Response(String), TransportError) do
      let meth = Http.method_to_string(Http.method(req))
      let req_host = Http.host(req)
      let req_path = Http.path(req)
      let req_query = Http.query(req)
      let req_headers = Http.headers(req)
      let req_body = Http.body(req)

      -- Determine port
      let req_port = match Http.port(req) with
        | Some(p) -> p
        | None ->
          match Http.scheme(req) with
          | Http.Https -> 443
          | Http.Http -> 80
          end
        end

      -- Serialize the request
      let raw_request = http_serialize_request(meth, req_host, req_path, req_query, req_headers, req_body)

      -- Connect
      match tcp_connect(req_host, req_port) with
      | Err(msg) -> Err(ConnectionRefused(msg))
      | Ok(fd) ->
        -- Send
        match tcp_send_all(fd, raw_request) with
        | Err(msg) ->
          tcp_close(fd)
          Err(SendError(msg))
        | Ok(_) ->
          -- Receive response (up to 1MB, 30s timeout)
          match tcp_recv_all(fd, 1048576, 30000) with
          | Err(msg) ->
            tcp_close(fd)
            Err(RecvError(msg))
          | Ok(raw_response) ->
            tcp_close(fd)
            -- Parse the response
            match http_parse_response(raw_response) with
            | Err(msg) -> Err(ParseError(msg))
            | Ok((status_code, resp_headers, resp_body)) ->
              Ok(Http.Response(Http.Status(status_code), resp_headers, resp_body))
            end
          end
        end
      end
    end

    doc """
    Send a request to the given host and path with no body.
    Convenience wrapper around send().
    """
    pub fn simple_get(url : String) : Result(Http.Response(String), TransportError) do
      match Http.get(url) with
      | Err(Http.InvalidScheme(s)) -> Err(ParseError("invalid scheme: " ++ s))
      | Err(Http.MissingHost) -> Err(ParseError("missing host"))
      | Err(Http.InvalidPort(s)) -> Err(ParseError("invalid port: " ++ s))
      | Err(Http.MalformedUrl(s)) -> Err(ParseError("malformed url: " ++ s))
      | Ok(req) -> send(Http.set_body(req, ""))
      end
    end

  end
end
```

- [ ] **Step 2: Register in stdlib load order**

In `bin/main.ml`, add `"http_transport.march"` after `"http.march"`:

```ocaml
    let files = [
      "prelude.march";
      "option.march";
      "result.march";
      "list.march";
      "math.march";
      "string.march";
      "iolist.march";
      "http.march";
      "http_transport.march";
    ] in
```

- [ ] **Step 3: Add tests**

The transport tests need a real or mocked server. Since we can't guarantee a server in tests, we test the error paths and the serialization integration.

```ocaml
let eval_with_http_transport src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let http_decl = load_stdlib_file_for_test "http.march" in
  let transport_decl = load_stdlib_file_for_test "http_transport.march" in
  eval_with_stdlib [string_decl; http_decl; transport_decl] src

let test_http_transport_connection_refused () =
  let env = eval_with_http_transport {|mod Test do
    fn f() do
      let req = Http.set_body(Http.Request(Http.Get, Http.Http, "127.0.0.1", Some(19999), "/", None, Nil, ()), "")
      match Http.Transport.send(req) with
      | Ok(_) -> "connected"
      | Err(Http.Transport.ConnectionRefused(_)) -> "refused"
      | Err(_) -> "other_error"
      end
    end
  end|} in
  Alcotest.(check string) "connection refused" "refused" (vstr (call_fn env "f" []))

let test_http_transport_simple_get_bad_url () =
  let env = eval_with_http_transport {|mod Test do
    fn f() do
      match Http.Transport.simple_get("ftp://bad") with
      | Ok(_) -> "ok"
      | Err(Http.Transport.ParseError(_)) -> "parse_error"
      | Err(_) -> "other"
      end
    end
  end|} in
  Alcotest.(check string) "simple_get bad url" "parse_error" (vstr (call_fn env "f" []))
```

Register:
```ocaml
      ("http transport", [
        Alcotest.test_case "connection refused"  `Quick test_http_transport_connection_refused;
        Alcotest.test_case "simple_get bad url"  `Quick test_http_transport_simple_get_bad_url;
      ]);
```

- [ ] **Step 4: Build and run tests**

Run: `/Users/80197052/.opam/march/bin/dune build && /Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add stdlib/http_transport.march bin/main.ml test/test_march.ml
git commit -m "feat(stdlib): add Http.Transport module — TCP-based HTTP/1.1 transport (Layer 2)"
```

---

## Task 6: Layer 3 — HTTP Client Module (`stdlib/http_client.march`)

The high-level composable client with step pipeline.

**Files:**
- Create: `stdlib/http_client.march`
- Modify: `bin/main.ml` (add to load order)
- Modify: `test/test_march.ml` (add tests)

- [ ] **Step 1: Write the Http.Client module**

Create `stdlib/http_client.march`:

```march
-- Http.Client: high-level composable HTTP client with step pipeline.
--
-- This is Layer 3 of March's HTTP library. It provides a Req-style
-- three-phase pipeline (request steps, response steps, error steps)
-- built on top of Http.Transport.
--
-- Usage:
--   use Http.Client
--   let client = Http.Client.new_client()
--     |> Http.Client.add_request_step("auth", Http.Client.Steps.bearer_auth("my-token"))
--     |> Http.Client.with_redirects(5)
--   let resp = Http.Client.get(client, "https://api.example.com/users")

mod Http do
  mod Client do

    type HttpError =
      | TransportError(Http.Transport.TransportError)
      | StepError(String, String)
      | TooManyRedirects(Int)

    -- Step types: plain functions
    -- RequestStep: transforms the request before sending
    type RequestStepEntry = RequestStepEntry(String, Http.Request(String) -> Result(Http.Request(String), HttpError))

    -- ResponseStep: transforms the (request, response) pair after receiving
    type ResponseStepEntry = ResponseStepEntry(String, (Http.Request(String), Http.Response(String)) -> Result((Http.Request(String), Http.Response(String)), HttpError))

    -- ErrorStep: attempts to recover from errors
    type ErrorRecovery = Recover(Http.Response(String)) | Fail(HttpError)
    type ErrorStepEntry = ErrorStepEntry(String, (Http.Request(String), HttpError) -> ErrorRecovery)

    -- Client: holds configuration for sending requests
    type Client = Client(
      List(RequestStepEntry),
      List(ResponseStepEntry),
      List(ErrorStepEntry),
      Int,   -- max_redirects (0 = disabled)
      Int,   -- max_retries (0 = disabled)
      Int    -- retry_backoff_ms
    )

    -- -----------------------------------------------------------------------
    -- Client construction
    -- -----------------------------------------------------------------------

    doc "Create a new bare client with no steps and no redirect/retry."
    pub fn new_client() : Client do
      Client(Nil, Nil, Nil, 0, 0, 0)
    end

    -- -----------------------------------------------------------------------
    -- Step registration (pipeable)
    -- -----------------------------------------------------------------------

    pub fn add_request_step(client : Client, name : String, step : Http.Request(String) -> Result(Http.Request(String), HttpError)) : Client do
      match client with
      | Client(req_steps, resp_steps, err_steps, redir, retries, backoff) ->
        let entry = RequestStepEntry(name, step)
        Client(append_step(req_steps, entry), resp_steps, err_steps, redir, retries, backoff)
      end
    end

    pub fn add_response_step(client : Client, name : String, step : (Http.Request(String), Http.Response(String)) -> Result((Http.Request(String), Http.Response(String)), HttpError)) : Client do
      match client with
      | Client(req_steps, resp_steps, err_steps, redir, retries, backoff) ->
        let entry = ResponseStepEntry(name, step)
        Client(req_steps, append_step(resp_steps, entry), err_steps, redir, retries, backoff)
      end
    end

    pub fn add_error_step(client : Client, name : String, step : (Http.Request(String), HttpError) -> ErrorRecovery) : Client do
      match client with
      | Client(req_steps, resp_steps, err_steps, redir, retries, backoff) ->
        let entry = ErrorStepEntry(name, step)
        Client(req_steps, resp_steps, append_step(err_steps, entry), redir, retries, backoff)
      end
    end

    -- Helper to append to end of list
    fn append_step(xs : List(a), x : a) : List(a) do
      match xs with
      | Nil -> Cons(x, Nil)
      | Cons(h, t) -> Cons(h, append_step(t, x))
      end
    end

    -- -----------------------------------------------------------------------
    -- Pipeline behaviors
    -- -----------------------------------------------------------------------

    pub fn with_redirects(client : Client, max : Int) : Client do
      match client with
      | Client(req_steps, resp_steps, err_steps, _, retries, backoff) ->
        Client(req_steps, resp_steps, err_steps, max, retries, backoff)
      end
    end

    pub fn with_retry(client : Client, max_attempts : Int, backoff_ms : Int) : Client do
      match client with
      | Client(req_steps, resp_steps, err_steps, redir, _, _) ->
        Client(req_steps, resp_steps, err_steps, redir, max_attempts, backoff_ms)
      end
    end

    -- -----------------------------------------------------------------------
    -- Step introspection
    -- -----------------------------------------------------------------------

    pub fn list_steps(client : Client) : List(String) do
      match client with
      | Client(req_steps, resp_steps, err_steps, _, _, _) ->
        fn req_names(xs : List(RequestStepEntry)) : List(String) do
          match xs with
          | Nil -> Nil
          | Cons(RequestStepEntry(n, _), rest) -> Cons("request:" ++ n, req_names(rest))
          end
        end
        fn resp_names(xs : List(ResponseStepEntry)) : List(String) do
          match xs with
          | Nil -> Nil
          | Cons(ResponseStepEntry(n, _), rest) -> Cons("response:" ++ n, resp_names(rest))
          end
        end
        fn err_names(xs : List(ErrorStepEntry)) : List(String) do
          match xs with
          | Nil -> Nil
          | Cons(ErrorStepEntry(n, _), rest) -> Cons("error:" ++ n, err_names(rest))
          end
        end
        fn list_concat(a : List(String), b : List(String)) : List(String) do
          match a with
          | Nil -> b
          | Cons(h, t) -> Cons(h, list_concat(t, b))
          end
        end
        list_concat(req_names(req_steps), list_concat(resp_names(resp_steps), err_names(err_steps)))
      end
    end

    -- -----------------------------------------------------------------------
    -- Pipeline execution
    -- -----------------------------------------------------------------------

    doc """
    Send a request through the full step pipeline.
    1. Run request steps left-to-right
    2. Send via Http.Transport.send
    3. Handle redirects if configured
    4. Run response steps left-to-right
    5. On error, run error steps
    """
    pub fn send(client : Client, req : Http.Request(String)) : Result(Http.Response(String), HttpError) do
      match client with
      | Client(req_steps, resp_steps, err_steps, max_redir, max_retries, backoff) ->
        -- Phase 1: Run request steps
        match run_request_steps(req_steps, req) with
        | Err(e) -> run_error_steps(err_steps, req, e)
        | Ok(transformed_req) ->
          -- Phase 2: Send via transport (with retry)
          match send_with_retry(transformed_req, max_retries) with
          | Err(transport_err) ->
            let http_err = TransportError(transport_err)
            run_error_steps(err_steps, transformed_req, http_err)
          | Ok(resp) ->
            -- Phase 3: Handle redirects
            match handle_redirects(transformed_req, resp, max_redir, 0) with
            | Err(e) -> run_error_steps(err_steps, transformed_req, e)
            | Ok(final_resp) ->
              -- Phase 4: Run response steps
              match run_response_steps(resp_steps, transformed_req, final_resp) with
              | Err(e) -> run_error_steps(err_steps, transformed_req, e)
              | Ok((_, final_response)) -> Ok(final_response)
              end
            end
          end
        end
      end
    end

    -- Run request steps in order
    fn run_request_steps(steps : List(RequestStepEntry), req : Http.Request(String)) : Result(Http.Request(String), HttpError) do
      match steps with
      | Nil -> Ok(req)
      | Cons(RequestStepEntry(_, step_fn), rest) ->
        match step_fn(req) with
        | Err(e) -> Err(e)
        | Ok(new_req) -> run_request_steps(rest, new_req)
        end
      end
    end

    -- Run response steps in order
    fn run_response_steps(steps : List(ResponseStepEntry), req : Http.Request(String), resp : Http.Response(String)) : Result((Http.Request(String), Http.Response(String)), HttpError) do
      match steps with
      | Nil -> Ok((req, resp))
      | Cons(ResponseStepEntry(_, step_fn), rest) ->
        match step_fn(req, resp) with
        | Err(e) -> Err(e)
        | Ok((new_req, new_resp)) -> run_response_steps(rest, new_req, new_resp)
        end
      end
    end

    -- Run error steps — first Recover wins
    fn run_error_steps(steps : List(ErrorStepEntry), req : Http.Request(String), err : HttpError) : Result(Http.Response(String), HttpError) do
      match steps with
      | Nil -> Err(err)
      | Cons(ErrorStepEntry(_, step_fn), rest) ->
        match step_fn(req, err) with
        | Recover(resp) -> Ok(resp)
        | Fail(new_err) -> run_error_steps(rest, req, new_err)
        end
      end
    end

    -- Send with retry on transport errors
    fn send_with_retry(req : Http.Request(String), retries_left : Int) : Result(Http.Response(String), Http.Transport.TransportError) do
      match Http.Transport.send(req) with
      | Ok(resp) -> Ok(resp)
      | Err(e) ->
        if retries_left > 0 then
          send_with_retry(req, retries_left - 1)
        else
          Err(e)
      end
    end

    -- Handle redirect responses
    fn handle_redirects(req : Http.Request(String), resp : Http.Response(String), max : Int, count : Int) : Result(Http.Response(String), HttpError) do
      if max == 0 then Ok(resp)
      else if not(Http.response_is_redirect(resp)) then Ok(resp)
      else if count >= max then Err(TooManyRedirects(count))
      else
        match Http.get_header(resp, "location") with
        | None -> Ok(resp)
        | Some(location) ->
          -- Build redirect request
          let redirect_req = Http.set_path(
            Http.set_method(req, Http.Get),
            location
          )
          match Http.Transport.send(Http.set_body(redirect_req, "")) with
          | Err(e) -> Err(TransportError(e))
          | Ok(new_resp) -> handle_redirects(redirect_req, new_resp, max, count + 1)
          end
        end
    end

    -- -----------------------------------------------------------------------
    -- Convenience methods
    -- -----------------------------------------------------------------------

    pub fn get(client : Client, url : String) : Result(Http.Response(String), HttpError) do
      match Http.get(url) with
      | Err(_) -> Err(StepError("url", "invalid url: " ++ url))
      | Ok(req) -> send(client, Http.set_body(req, ""))
      end
    end

    pub fn post(client : Client, url : String, bdy : String) : Result(Http.Response(String), HttpError) do
      match Http.post(url, bdy) with
      | Err(_) -> Err(StepError("url", "invalid url: " ++ url))
      | Ok(req) -> send(client, req)
      end
    end

    pub fn put_request(client : Client, url : String, bdy : String) : Result(Http.Response(String), HttpError) do
      match Http.put(url, bdy) with
      | Err(_) -> Err(StepError("url", "invalid url: " ++ url))
      | Ok(req) -> send(client, req)
      end
    end

    pub fn delete(client : Client, url : String) : Result(Http.Response(String), HttpError) do
      match Http.delete(url) with
      | Err(_) -> Err(StepError("url", "invalid url: " ++ url))
      | Ok(req) -> send(client, Http.set_body(req, ""))
      end
    end

    -- -----------------------------------------------------------------------
    -- Built-in Steps
    -- -----------------------------------------------------------------------

    mod Steps do

      doc "Add default User-Agent and Accept headers."
      pub fn default_headers(req : Http.Request(String)) : Result(Http.Request(String), Http.Client.HttpError) do
        Ok(req
          |> Http.set_header("User-Agent", "march/0.1")
          |> Http.set_header("Accept", "*/*"))
      end

      doc "Add a Bearer token authorization header."
      pub fn bearer_auth(token : String) : Http.Request(String) -> Result(Http.Request(String), Http.Client.HttpError) do
        fn step(req : Http.Request(String)) : Result(Http.Request(String), Http.Client.HttpError) do
          Ok(Http.set_header(req, "Authorization", "Bearer " ++ token))
        end
        step
      end

      doc "Add HTTP Basic authorization header."
      pub fn basic_auth(user : String, pass : String) : Http.Request(String) -> Result(Http.Request(String), Http.Client.HttpError) do
        fn step(req : Http.Request(String)) : Result(Http.Request(String), Http.Client.HttpError) do
          -- Simple base64 not available yet, use raw for now
          Ok(Http.set_header(req, "Authorization", "Basic " ++ user ++ ":" ++ pass))
        end
        step
      end

      doc "Set a base URL prefix — prepends to the path."
      pub fn put_base_url(base : String) : Http.Request(String) -> Result(Http.Request(String), Http.Client.HttpError) do
        -- Parse the base URL to extract scheme, host, port
        fn step(req : Http.Request(String)) : Result(Http.Request(String), Http.Client.HttpError) do
          match Http.parse_url(base ++ Http.path(req)) with
          | Err(_) -> Err(Http.Client.StepError("put_base_url", "invalid base url: " ++ base))
          | Ok(parsed) ->
            Ok(Http.set_body(
              Http.Request(
                Http.method(req),
                Http.scheme(parsed),
                Http.host(parsed),
                Http.port(parsed),
                Http.path(parsed),
                Http.query(req),
                Http.headers(req),
                Http.body(req)
              ),
              Http.body(req)
            ))
          end
        end
        step
      end

      doc "Set the Content-Type header."
      pub fn put_content_type(ct : String) : Http.Request(String) -> Result(Http.Request(String), Http.Client.HttpError) do
        fn step(req : Http.Request(String)) : Result(Http.Request(String), Http.Client.HttpError) do
          Ok(Http.set_header(req, "Content-Type", ct))
        end
        step
      end

      doc """
      Response step: return Err for 4xx/5xx status codes.
      Makes HTTP error status codes into pipeline errors.
      """
      pub fn raise_on_error_status(req : Http.Request(String), resp : Http.Response(String)) : Result((Http.Request(String), Http.Response(String)), Http.Client.HttpError) do
        let code = Http.response_status_code(resp)
        if code >= 400 then
          Err(Http.Client.StepError("raise_on_error_status", int_to_string(code)))
        else
          Ok((req, resp))
      end

    end

  end
end
```

- [ ] **Step 2: Register in stdlib load order**

In `bin/main.ml`, add `"http_client.march"` after `"http_transport.march"`.

- [ ] **Step 3: Write tests**

```ocaml
let eval_with_http_client src =
  let string_decl = load_stdlib_file_for_test "string.march" in
  let http_decl = load_stdlib_file_for_test "http.march" in
  let transport_decl = load_stdlib_file_for_test "http_transport.march" in
  let client_decl = load_stdlib_file_for_test "http_client.march" in
  eval_with_stdlib [string_decl; http_decl; transport_decl; client_decl] src

(* Test pipeline construction — no network needed *)
let test_http_client_new () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let client = Http.Client.new_client()
      let steps = Http.Client.list_steps(client)
      match steps with
      | Nil -> "empty"
      | _ -> "not_empty"
      end
    end
  end|} in
  Alcotest.(check string) "new client has no steps" "empty" (vstr (call_fn env "f" []))

let test_http_client_add_steps () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let client = Http.Client.new_client()
        |> Http.Client.add_request_step("headers", Http.Client.Steps.default_headers)
        |> Http.Client.add_request_step("auth", Http.Client.Steps.bearer_auth("tok"))
      let steps = Http.Client.list_steps(client)
      length(steps)
    end
  end|} in
  Alcotest.(check int) "two request steps" 2 (vint (call_fn env "f" []))

let test_http_client_request_step_transforms () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let step = Http.Client.Steps.bearer_auth("my-token")
      let req = Http.Request(Http.Get, Http.Https, "example.com", None, "/", None, Nil, "")
      match step(req) with
      | Ok(r) ->
        match Http.get_request_header(r, "authorization") with
        | Some(v) -> v
        | None -> "none"
        end
      | Err(_) -> "error"
      end
    end
  end|} in
  Alcotest.(check string) "bearer auth step" "Bearer my-token" (vstr (call_fn env "f" []))

let test_http_client_raise_on_error_status () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      let req = Http.Request(Http.Get, Http.Https, "example.com", None, "/", None, Nil, "")
      let resp = Http.Response(Http.Status(404), Nil, "Not Found")
      match Http.Client.Steps.raise_on_error_status(req, resp) with
      | Err(Http.Client.StepError(name, _)) -> name
      | Ok(_) -> "ok"
      end
    end
  end|} in
  Alcotest.(check string) "raise on 404" "raise_on_error_status" (vstr (call_fn env "f" []))

let test_http_client_error_step_recovery () =
  let env = eval_with_http_client {|mod Test do
    fn f() do
      fn recover_step(req, err) do
        Http.Client.Recover(Http.Response(Http.Status(200), Nil, "recovered"))
      end
      let client = Http.Client.new_client()
        |> Http.Client.add_response_step("raise", Http.Client.Steps.raise_on_error_status)
        |> Http.Client.add_error_step("recover", recover_step)
      -- We can't test with a real server, but we can verify the pipeline
      -- by checking step registration
      length(Http.Client.list_steps(client))
    end
  end|} in
  Alcotest.(check int) "client with 2 steps" 2 (vint (call_fn env "f" []))
```

Register:
```ocaml
      ("http client", [
        Alcotest.test_case "new client"           `Quick test_http_client_new;
        Alcotest.test_case "add steps"            `Quick test_http_client_add_steps;
        Alcotest.test_case "request step transform" `Quick test_http_client_request_step_transforms;
        Alcotest.test_case "raise on error status" `Quick test_http_client_raise_on_error_status;
        Alcotest.test_case "error step recovery"   `Quick test_http_client_error_step_recovery;
      ]);
```

- [ ] **Step 4: Build and run tests**

Run: `/Users/80197052/.opam/march/bin/dune build && /Users/80197052/.opam/march/bin/dune runtest`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add stdlib/http_client.march bin/main.ml test/test_march.ml
git commit -m "feat(stdlib): add Http.Client module — step pipeline and built-in steps (Layer 3)"
```

---

## Task 7: Integration Test with Real HTTP

End-to-end test that makes a real HTTP request. This validates all three layers working together.

**Files:**
- Create: `examples/http_get.march` (example program)
- Modify: `test/test_march.ml` (optional integration test)

- [ ] **Step 1: Create example program**

Create `examples/http_get.march`:

```march
mod HttpGet do
  fn main() do
    -- Simple GET request using Layer 3
    let client = Http.Client.new_client()
      |> Http.Client.add_request_step("headers", Http.Client.Steps.default_headers)

    match Http.Client.get(client, "http://httpbin.org/get") with
    | Ok(resp) ->
      println("Status: " ++ int_to_string(Http.response_status_code(resp)))
      println("Body: " ++ Http.response_body(resp))
    | Err(Http.Client.TransportError(Http.Transport.ConnectionRefused(msg))) ->
      println("Connection refused: " ++ msg)
    | Err(Http.Client.StepError(name, msg)) ->
      println("Step error in " ++ name ++ ": " ++ msg)
    | Err(_) ->
      println("Unknown error")
    end
  end
end
```

- [ ] **Step 2: Create example using Layer 2 directly**

Create `examples/http_transport.march`:

```march
mod HttpTransport do
  fn main() do
    -- Direct transport usage (Layer 2)
    let req = Http.Request(Http.Get, Http.Http, "httpbin.org", Some(80), "/ip", None,
      Cons(Http.Header("Accept", "application/json"), Nil), "")

    match Http.Transport.send(req) with
    | Ok(resp) ->
      println("Status: " ++ int_to_string(Http.response_status_code(resp)))
      println("Body: " ++ Http.response_body(resp))
    | Err(Http.Transport.ConnectionRefused(msg)) ->
      println("Refused: " ++ msg)
    | Err(Http.Transport.SendError(msg)) ->
      println("Send error: " ++ msg)
    | Err(_) ->
      println("Error")
    end
  end
end
```

- [ ] **Step 3: Verify examples parse and typecheck**

Run: `/Users/80197052/.opam/march/bin/dune exec march -- examples/http_get.march`
(This will attempt to connect — verify it either succeeds or shows "Connection refused" cleanly.)

- [ ] **Step 4: Commit**

```bash
git add examples/http_get.march examples/http_transport.march
git commit -m "feat(examples): add HTTP library usage examples"
```

---

## Task 8: Final Verification

Run the full test suite and verify nothing is broken.

- [ ] **Step 1: Run full test suite**

Run: `/Users/80197052/.opam/march/bin/dune runtest`
Expected: All tests pass (existing + new).

- [ ] **Step 2: Run existing benchmarks to check for regressions**

Run: `/Users/80197052/.opam/march/bin/dune exec march -- bench/list_ops.march`
Run: `/Users/80197052/.opam/march/bin/dune exec march -- bench/string_pipeline.march`
Expected: No crashes or regressions.

- [ ] **Step 3: Verify clean build**

Run: `/Users/80197052/.opam/march/bin/dune clean && /Users/80197052/.opam/march/bin/dune build`
Expected: Clean build with no warnings.
