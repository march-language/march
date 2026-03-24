# Depot — March Database Library

**Library name:** `depot`
**Status:** Design proposal
**Date:** 2026-03-24
**Inspired by:** Postgrex (Elixir), Ecto (Elixir), Diesel (Rust)

---

## Table of Contents

1. [Why No FFI](#1-why-no-ffi)
2. [Architecture Overview](#2-architecture-overview)
3. [Package Layout](#3-package-layout)
4. [PostgreSQL Wire Protocol](#4-postgresql-wire-protocol)
5. [Type System Mapping](#5-type-system-mapping)
6. [Schema Declaration](#6-schema-declaration)
7. [Query Builder ADT](#7-query-builder-adt)
8. [Connection Pool (Actor-based)](#8-connection-pool-actor-based)
9. [Auto-Migration Engine](#9-auto-migration-engine)
10. [API Design & March Code Examples](#10-api-design--march-code-examples)
11. [Implementation Phases](#11-implementation-phases)
12. [Test Plan](#12-test-plan)
13. [Benchmark Plan](#13-benchmark-plan)
14. [Open Design Questions](#14-open-design-questions)

---

## 1. Why No FFI

The original plan assumed Depot would need FFI to call `libsqlite3.so`. This was wrong.

**Postgrex** (Elixir's PostgreSQL driver) is entirely pure Elixir — no NIFs, no C bindings. It
speaks PostgreSQL's documented binary wire protocol over a TCP socket. March already has all the
TCP primitives needed, proven by `stdlib/http_transport.march`:

```
tcp_connect(host, port)         → Result(fd, String)
tcp_send_all(fd, data)          → Result(Unit, String)
tcp_recv_all(fd, max, timeout)  → Result(String, String)
tcp_close(fd)                   → Unit
```

Depot uses these same primitives to implement the PostgreSQL wire protocol directly. No FFI, no
C bindings, no linking to any external library.

### What About SQLite?

SQLite is an *embedded* C library — it has no wire protocol and does not listen on any port. You
cannot connect to it over TCP. Two options for the future:

- **`depot_sqlite` package** — a separate `forge` package that wraps SQLite via FFI once FFI
  evaluation dispatch (dlsym) is complete. Same Depot query builder ADT, different backend
  adapter. The query compiler would emit SQLite-dialect SQL.
- **`postlite` proxy** — for local development/testing, run
  [postlite](https://github.com/benbjohnson/postlite) which proxies the PostgreSQL wire protocol
  to an in-process SQLite database. Zero code changes to Depot; requires an external binary.

**Primary target for Depot v1:** PostgreSQL 14+, and any server that speaks the PostgreSQL wire
protocol: CockroachDB, YugabyteDB, Neon, PlanetScale (Postgres mode), Supabase, etc.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      User Application                        │
│  Depot.Repo.all(from(users) |> where_(eq("age", PInt(18)))) │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                   Depot.Repo                                 │
│  all / get / get! / insert / update / delete / transaction  │
└──────┬──────────────────────────────┬───────────────────────┘
       │                              │
┌──────▼──────────┐        ┌──────────▼──────────────────────┐
│  Query Compiler │        │    Connection Pool (Actor)       │
│  ADT → SQL      │        │    checkout / checkin / health   │
└──────┬──────────┘        └──────────┬──────────────────────┘
       │                              │
┌──────▼──────────────────────────────▼──────────────────────┐
│                  Wire Protocol Layer                         │
│  Message encoding/decoding, handshake, auth, simple query,  │
│  extended query (prepared statements)                        │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│              TCP Socket Builtins (already in eval.ml)        │
│  tcp_connect / tcp_send_all / tcp_recv_all / tcp_close       │
└─────────────────────────────────────────────────────────────┘
```

The layering is strict — each layer only knows about the layer directly below it. Query
compilation is pure (no IO); wire protocol is IO-only (no query knowledge). This makes each layer
independently testable.

---

## 3. Package Layout

Depot lives in its own repository, completely separate from the March compiler repo:

```bash
# Outside the march/ directory — its own repo
cd ~/code
forge depot new --lib
cd depot
git init && git remote add origin git@github.com:your-org/depot.git
```

```
~/code/depot/
├── forge.toml                   -- package manifest
├── src/
│   ├── depot.march              -- re-exports public API
│   ├── wire/
│   │   ├── message.march        -- Backend/Frontend message ADT
│   │   ├── encode.march         -- Binary encoding (big-endian)
│   │   ├── decode.march         -- Binary decoding + frame parser
│   │   └── auth.march           -- MD5 + SCRAM-SHA-256 auth
│   ├── conn/
│   │   ├── conn.march           -- Single connection FSM
│   │   └── pool.march           -- Actor-based connection pool
│   ├── schema/
│   │   ├── types.march          -- March type ↔ PostgreSQL OID mapping
│   │   └── introspect.march     -- Query pg_catalog for live schema state
│   ├── query/
│   │   ├── ast.march            -- Query ADT (from/where/select/join/...)
│   │   ├── build.march          -- Builder functions + pipe helpers
│   │   └── compile.march        -- Query ADT → parameterized SQL + params
│   ├── repo.march               -- Public Repo API
│   ├── migration.march          -- Auto-migration engine
│   └── changeset.march          -- Validation and casting
└── test/
    ├── wire_test.march
    ├── query_test.march
    ├── migration_test.march
    └── integration_test.march
```

### `forge.toml`

```toml
[package]
name    = "depot"
version = "0.1.0"
march   = ">=0.5.0"   # references the published March compiler, not a local path

[deps]
# no external deps — pure March on TCP builtins
```

The march compiler repo and the depot repo are entirely independent. Depot consumes March as a
toolchain version (`march = ">=0.5.0"`), the same way a Rust crate specifies `edition = "2021"`
without depending on the rustc source tree. The two repos never reference each other via local
paths.

---

## 4. PostgreSQL Wire Protocol

PostgreSQL wire protocol version 3.0 is documented at
`https://www.postgresql.org/docs/current/protocol.html`. It is a binary, length-prefixed,
message-oriented protocol — conceptually similar to how March's HTTP transport works, but with
its own message types and binary encoding.

### 4.1 Message Format

All messages except `StartupMessage`:
```
byte    type        -- single character message type ('Q', 'T', 'D', etc.)
int32   length      -- total length including this field, excluding type byte
byte[]  payload
```

`StartupMessage` (first message, no type byte):
```
int32   length      -- total length including this field
int32   protocol    -- 196608 = 3.0 (0x00030000)
byte[]  key=value\0 pairs, terminated by \0\0
```

### 4.2 Message ADT

```march
-- depot/src/wire/message.march

mod Wire.Message do

-- Frontend messages (client → server)
pub type FrontendMessage =
    Startup(Map(String, String))          -- user, database, application_name
  | Query(String)                         -- simple query protocol
  | Parse(String, String, List(Int))      -- name, query, param_oids
  | Bind(String, String, List(Param))     -- portal, stmt, params
  | Execute(String, Int)                  -- portal, max_rows (0 = all)
  | Describe(DescribeTarget)
  | Close(CloseTarget)
  | Sync
  | Flush
  | Terminate
  | PasswordMessage(String)               -- MD5 or cleartext password
  | SASLInitialResponse(String, Bytes)    -- mechanism, data
  | SASLResponse(Bytes)

pub type DescribeTarget = DescribeStatement(String) | DescribePortal(String)
pub type CloseTarget    = CloseStatement(String)    | ClosePortal(String)

pub type Param =
    ParamNull
  | ParamText(String)
  | ParamBinary(Bytes)

-- Backend messages (server → client)
pub type BackendMessage =
    AuthOk
  | AuthMD5(Bytes)                        -- 4-byte salt
  | AuthSASL(List(String))                -- mechanism list
  | AuthSASLContinue(Bytes)
  | AuthSASLFinal(Bytes)
  | BackendKeyData(Int, Int)              -- pid, secret
  | ParameterStatus(String, String)       -- name, value
  | ReadyForQuery(TransactionStatus)
  | RowDescription(List(FieldDesc))
  | DataRow(List(Option(Bytes)))          -- None = SQL NULL
  | CommandComplete(String)               -- tag e.g. "SELECT 42"
  | EmptyQueryResponse
  | ErrorResponse(ErrorFields)
  | NoticeResponse(ErrorFields)
  | ParseComplete
  | BindComplete
  | CloseComplete
  | NoData
  | PortalSuspended

pub type TransactionStatus = Idle | InTransaction | InFailedTransaction

pub type FieldDesc = FieldDesc(
  String,   -- column name
  Int,      -- table OID (0 = not a table column)
  Int,      -- attribute number
  Int,      -- type OID
  Int,      -- type size (-1 = variable)
  Int,      -- type modifier
  Int       -- format (0 = text, 1 = binary)
)

pub type ErrorFields = {
  severity : String,
  code     : String,     -- SQLSTATE e.g. "23505"
  message  : String,
  detail   : Option(String),
  hint     : Option(String),
  position : Option(Int)
}

end
```

### 4.3 Binary Encoding

The `Bytes` stdlib module (`stdlib/bytes.march`) provides the byte-list foundation. Depot adds
big-endian integer encoding (the only piece missing from stdlib):

```march
-- depot/src/wire/encode.march

mod Wire.Encode do

pub fn i32_be(n : Int) : Bytes do
  Bytes.from_list([
    (n / 16777216) % 256,
    (n / 65536)    % 256,
    (n / 256)      % 256,
     n             % 256
  ])
end

pub fn i16_be(n : Int) : Bytes do
  Bytes.from_list([(n / 256) % 256, n % 256])
end

pub fn cstring(s : String) : Bytes do
  Bytes.concat(Bytes.from_string(s), Bytes.from_list([0]))
end

pub fn length_prefix(payload : Bytes) : Bytes do
  -- length includes itself (4 bytes) but NOT the type byte
  Bytes.concat(i32_be(Bytes.length(payload) + 4), payload)
end

pub fn frame(type_byte : Int, payload : Bytes) : Bytes do
  Bytes.concat(Bytes.from_list([type_byte]), length_prefix(payload))
end

pub fn encode(msg : Wire.Message.FrontendMessage) : Bytes do
  match msg do
  | Startup(params) ->
    let pairs = Map.fold(params, Bytes.empty(), fn acc k v ->
      Bytes.concat(acc, Bytes.concat(cstring(k), cstring(v)))
    )
    let payload = Bytes.concat(i32_be(196608), Bytes.concat(pairs, Bytes.from_list([0])))
    length_prefix(payload)
  | Query(sql) ->
    frame(81, cstring(sql))                 -- 'Q' = 81
  | Parse(name, sql, oids) ->
    let oid_bytes = List.fold(oids, Bytes.empty(), fn acc oid ->
      Bytes.concat(acc, i32_be(oid)))
    let payload = Bytes.concat(
      Bytes.concat(cstring(name), cstring(sql)),
      Bytes.concat(i16_be(List.length(oids)), oid_bytes))
    frame(80, payload)                      -- 'P' = 80
  | Bind(portal, stmt, params) ->
    encode_bind(portal, stmt, params)
  | Execute(portal, max_rows) ->
    frame(69, Bytes.concat(cstring(portal), i32_be(max_rows)))  -- 'E' = 69
  | Sync      -> frame(83, Bytes.empty())   -- 'S' = 83
  | Flush     -> frame(72, Bytes.empty())   -- 'H' = 72
  | Terminate -> frame(88, Bytes.empty())   -- 'X' = 88
  | PasswordMessage(pw) ->
    frame(112, cstring(pw))                 -- 'p' = 112
  | Describe(DescribeStatement(name)) ->
    frame(68, Bytes.concat(Bytes.from_list([83]), cstring(name)))  -- 'D'+'S'
  | Describe(DescribePortal(name)) ->
    frame(68, Bytes.concat(Bytes.from_list([80]), cstring(name)))  -- 'D'+'P'
  | _ -> panic("encode: unimplemented message type")
  end
end

fn encode_bind(portal, stmt, params) do
  let n = List.length(params)
  let param_bytes = List.fold(params, Bytes.empty(), fn acc p ->
    match p do
    | ParamNull    -> Bytes.concat(acc, i32_be(-1))
    | ParamText(s) ->
      let b = Bytes.from_string(s)
      Bytes.concat(acc, Bytes.concat(i32_be(Bytes.length(b)), b))
    | ParamBinary(b) ->
      Bytes.concat(acc, Bytes.concat(i32_be(Bytes.length(b)), b))
    end
  )
  -- one format code (0 = text) covering all params; one result format code (0 = text)
  let payload = Bytes.concat(
    Bytes.concat(cstring(portal), cstring(stmt)),
    Bytes.concat(i16_be(1), Bytes.concat(i16_be(0),
      Bytes.concat(i16_be(n), Bytes.concat(param_bytes,
        Bytes.concat(i16_be(1), i16_be(0)))))))
  frame(66, payload)                        -- 'B' = 66
end

end
```

### 4.4 Message Decoder

```march
-- depot/src/wire/decode.march

mod Wire.Decode do

-- Read one complete backend message from a Bytes buffer.
-- Returns Ok((message, remaining)) or Err(reason).
pub fn read_one(buf : Bytes) : Result((Wire.Message.BackendMessage, Bytes), String) do
  if Bytes.length(buf) < 5 then Err("incomplete: need at least 5 bytes")
  else
    let type_byte = Bytes.get(buf, 0)
    let msg_len   = decode_i32_be(buf, 1)   -- includes itself
    let total     = msg_len + 1              -- +1 for type byte
    if Bytes.length(buf) < total then Err("incomplete: need ${total} bytes")
    else
      let payload = Bytes.slice(buf, 5, msg_len - 4)
      let rest    = Bytes.slice(buf, total, Bytes.length(buf) - total)
      match decode_message(type_byte, payload) do
      | Err(e)    -> Err(e)
      | Ok(msg)   -> Ok((msg, rest))
      end
end

pub fn decode_i32_be(buf, offset) do
  Bytes.get(buf, offset)     * 16777216 +
  Bytes.get(buf, offset + 1) * 65536    +
  Bytes.get(buf, offset + 2) * 256      +
  Bytes.get(buf, offset + 3)
end

pub fn decode_i16_be(buf, offset) do
  Bytes.get(buf, offset) * 256 + Bytes.get(buf, offset + 1)
end

fn decode_message(type_byte, payload) do
  match type_byte do
  | 82  -> decode_auth(payload)             -- 'R'
  | 75  -> decode_backend_key(payload)      -- 'K'
  | 83  -> decode_param_status(payload)     -- 'S'
  | 90  -> decode_ready(payload)            -- 'Z'
  | 84  -> decode_row_desc(payload)         -- 'T'
  | 68  -> decode_data_row(payload)         -- 'D'
  | 67  -> decode_command_complete(payload) -- 'C'
  | 69  -> decode_error(payload)            -- 'E'
  | 78  -> decode_notice(payload)           -- 'N'
  | 49  -> Ok(ParseComplete)               -- '1'
  | 50  -> Ok(BindComplete)                -- '2'
  | 51  -> Ok(CloseComplete)               -- '3'
  | 110 -> Ok(NoData)                      -- 'n'
  | 73  -> Ok(EmptyQueryResponse)          -- 'I'
  | 115 -> Ok(PortalSuspended)             -- 's'
  | _   -> Err("unknown backend message type: ${type_byte}")
  end
end

fn decode_auth(payload) do
  let auth_type = decode_i32_be(payload, 0)
  match auth_type do
  | 0  -> Ok(AuthOk)
  | 5  -> Ok(AuthMD5(Bytes.slice(payload, 4, 4)))
  | 10 ->
    -- SASL: list of mechanism names, each null-terminated, ending with \0\0
    Ok(AuthSASL(parse_cstring_list(payload, 4)))
  | 11 -> Ok(AuthSASLContinue(Bytes.slice(payload, 4, Bytes.length(payload) - 4)))
  | 12 -> Ok(AuthSASLFinal(Bytes.slice(payload, 4, Bytes.length(payload) - 4)))
  | _  -> Err("unknown auth type: ${auth_type}")
  end
end

fn decode_row_desc(payload) do
  let n_fields = decode_i16_be(payload, 0)
  let fields   = parse_fields(payload, 2, n_fields, Nil)
  Ok(RowDescription(List.reverse(fields)))
end

fn parse_fields(payload, offset, remaining, acc) do
  if remaining == 0 then acc
  else
    let (name, after_name) = read_cstring(payload, offset)
    let table_oid  = decode_i32_be(payload, after_name)
    let attr_num   = decode_i16_be(payload, after_name + 4)
    let type_oid   = decode_i32_be(payload, after_name + 6)
    let type_size  = decode_i16_be(payload, after_name + 10)
    let type_mod   = decode_i32_be(payload, after_name + 12)
    let fmt        = decode_i16_be(payload, after_name + 16)
    let field = FieldDesc(name, table_oid, attr_num, type_oid, type_size, type_mod, fmt)
    parse_fields(payload, after_name + 18, remaining - 1, Cons(field, acc))
end

fn decode_data_row(payload) do
  let n_cols = decode_i16_be(payload, 0)
  let cols   = parse_columns(payload, 2, n_cols, Nil)
  Ok(DataRow(List.reverse(cols)))
end

fn parse_columns(payload, offset, remaining, acc) do
  if remaining == 0 then acc
  else
    let col_len = decode_i32_be(payload, offset)
    if col_len == -1 then
      -- -1 means NULL
      parse_columns(payload, offset + 4, remaining - 1, Cons(None, acc))
    else
      let value = Bytes.slice(payload, offset + 4, col_len)
      parse_columns(payload, offset + 4 + col_len, remaining - 1, Cons(Some(value), acc))
end

-- Read a null-terminated string from buf at offset.
-- Returns (string, offset_after_null).
fn read_cstring(buf, offset) do
  fn go(i, chars) do
    let b = Bytes.get(buf, i)
    if b == 0 then (string_from_chars(List.reverse(chars)), i + 1)
    else go(i + 1, Cons(byte_to_char(b), chars))
  end
  go(offset, Nil)
end

fn decode_error(payload) do
  let fields = parse_error_fields(payload, 0, {
    severity = "ERROR", code = "00000", message = "unknown",
    detail = None, hint = None, position = None
  })
  Ok(ErrorResponse(fields))
end

fn parse_error_fields(payload, offset, acc) do
  if offset >= Bytes.length(payload) then acc
  else
    let field_type = Bytes.get(payload, offset)
    if field_type == 0 then acc
    else
      let (value, next) = read_cstring(payload, offset + 1)
      let acc = match field_type do
        | 86  -> { acc | severity = value }   -- 'V'
        | 67  -> { acc | code     = value }   -- 'C'
        | 77  -> { acc | message  = value }   -- 'M'
        | 68  -> { acc | detail   = Some(value) } -- 'D'
        | 72  -> { acc | hint     = Some(value) } -- 'H'
        | _   -> acc
        end
      parse_error_fields(payload, next, acc)
end

end
```

### 4.5 Connection FSM

```march
-- depot/src/conn/conn.march

mod Conn do

pub type ConnOpts = {
  host     : String,
  port     : Int,
  user     : String,
  password : String,
  database : String
}

pub type Conn = {
  fd     : Int,
  params : Map(String, String),  -- server ParameterStatus values
  pid    : Int,                  -- backend PID (for cancellation)
  secret : Int
}

pub type ConnError =
    TcpError(String)
  | AuthError(String)
  | ProtocolError(String)

-- Open and authenticate a connection.
pub fn connect(opts : ConnOpts) : Result(Conn, ConnError) do
  match tcp_connect(opts.host, opts.port) do
  | Err(msg) -> Err(TcpError(msg))
  | Ok(fd)   -> startup(fd, opts)
  end
end

fn startup(fd, opts) do
  let msg = Wire.Message.Startup(Map.from_list([
    ("user",             opts.user),
    ("database",         opts.database),
    ("application_name", "depot")
  ]))
  match send(fd, msg) do
  | Err(e) -> Err(e)
  | Ok(_)  -> auth_loop(fd, opts, Map.empty(), 0, 0)
  end
end

fn auth_loop(fd, opts, params, pid, secret) do
  match recv(fd) do
  | Err(e) -> Err(e)
  | Ok(AuthOk) ->
    auth_loop(fd, opts, params, pid, secret)
  | Ok(AuthMD5(salt)) ->
    let pw = md5_response(opts.user, opts.password, salt)
    match send(fd, Wire.Message.PasswordMessage(pw)) do
    | Err(e) -> Err(e)
    | Ok(_)  -> auth_loop(fd, opts, params, pid, secret)
    end
  | Ok(BackendKeyData(p, s)) ->
    auth_loop(fd, opts, params, p, s)
  | Ok(ParameterStatus(k, v)) ->
    auth_loop(fd, opts, Map.set(params, k, v), pid, secret)
  | Ok(ReadyForQuery(_)) ->
    Ok({ fd = fd, params = params, pid = pid, secret = secret })
  | Ok(ErrorResponse(fields)) ->
    Err(AuthError(fields.message))
  | Ok(_) ->
    Err(ProtocolError("unexpected message during startup"))
  end
end

-- MD5 auth: "md5" ++ hex(md5(hex(md5(password ++ user)) ++ salt))
fn md5_response(user, password, salt) do
  let inner = Bytes.to_hex(md5(Bytes.from_string(password ++ user)))
  let outer = md5(Bytes.concat(Bytes.from_string(inner), salt))
  "md5" ++ Bytes.to_hex(outer)
end

-- Simple query (no parameters — for DDL, introspection queries).
pub fn simple_query(conn : Conn, sql : String)
    : Result(List(Map(String, String)), ConnError) do
  match send(conn.fd, Wire.Message.Query(sql)) do
  | Err(e) -> Err(e)
  | Ok(_)  -> collect_rows(conn.fd, Nil, Nil)
  end
end

-- Extended query (parameterized — for safe user-supplied values).
pub fn exec(conn : Conn, sql : String, params : List(Wire.Message.Param))
    : Result(List(Map(String, String)), ConnError) do
  -- Unnamed statement + unnamed portal = one-shot prepared statement
  let parse   = Wire.Message.Parse("", sql, Nil)
  let bind    = Wire.Message.Bind("", "", params)
  let desc    = Wire.Message.Describe(DescribePortal(""))
  let execute = Wire.Message.Execute("", 0)
  let sync    = Wire.Message.Sync
  let msg_bytes = List.fold(
    [parse, bind, desc, execute, sync],
    Bytes.empty(),
    fn acc m -> Bytes.concat(acc, Wire.Encode.encode(m))
  )
  match tcp_send_all(conn.fd, Bytes.to_string(msg_bytes)) do
  | Err(e) -> Err(TcpError(e))
  | Ok(_)  -> collect_extended_rows(conn.fd, Nil, Nil)
  end
end

pub fn close(conn : Conn) : Unit do
  send(conn.fd, Wire.Message.Terminate)
  tcp_close(conn.fd)
end

fn send(fd, msg) do
  let bytes = Wire.Encode.encode(msg)
  match tcp_send_all(fd, Bytes.to_string(bytes)) do
  | Err(e) -> Err(TcpError(e))
  | Ok(_)  -> Ok(())
  end
end

fn recv(fd) do
  -- Read type byte + length (5 bytes), then payload
  match tcp_recv_exact(fd, 5) do
  | Err(e) -> Err(TcpError(e))
  | Ok(header_str) ->
    let hdr = Bytes.from_string(header_str)
    let msg_len = Wire.Decode.decode_i32_be(hdr, 1)
    match tcp_recv_exact(fd, msg_len - 4) do
    | Err(e) -> Err(TcpError(e))
    | Ok(payload_str) ->
      Wire.Decode.decode_message(
        Bytes.get(hdr, 0),
        Bytes.from_string(payload_str))
      |> Result.map_err(fn e -> ProtocolError(e))
    end
  end
end

fn collect_rows(fd, col_names, acc) do
  match recv(fd) do
  | Err(e) -> Err(e)
  | Ok(RowDescription(fields)) ->
    let names = List.map(fields, fn FieldDesc(name, _, _, _, _, _, _) -> name)
    collect_rows(fd, names, acc)
  | Ok(DataRow(cols)) ->
    let row = List.zip(col_names, List.map(cols, fn c ->
      match c do
      | None    -> ""
      | Some(b) -> Bytes.to_string(b)
      end
    ))
    collect_rows(fd, col_names, Cons(Map.from_list(row), acc))
  | Ok(CommandComplete(_)) -> collect_rows(fd, col_names, acc)
  | Ok(ReadyForQuery(_))   -> Ok(List.reverse(acc))
  | Ok(ErrorResponse(f))  -> Err(ProtocolError(f.message))
  | Ok(_) -> collect_rows(fd, col_names, acc)
  end
end

fn collect_extended_rows(fd, col_names, acc) do
  match recv(fd) do
  | Err(e) -> Err(e)
  | Ok(ParseComplete)      -> collect_extended_rows(fd, col_names, acc)
  | Ok(BindComplete)       -> collect_extended_rows(fd, col_names, acc)
  | Ok(RowDescription(fields)) ->
    let names = List.map(fields, fn FieldDesc(name, _, _, _, _, _, _) -> name)
    collect_extended_rows(fd, names, acc)
  | Ok(DataRow(cols)) ->
    let row = List.zip(col_names, List.map(cols, fn c ->
      match c do
      | None    -> ""
      | Some(b) -> Bytes.to_string(b)
      end
    ))
    collect_extended_rows(fd, col_names, Cons(Map.from_list(row), acc))
  | Ok(CommandComplete(_)) -> collect_extended_rows(fd, col_names, acc)
  | Ok(ReadyForQuery(_))   -> Ok(List.reverse(acc))
  | Ok(ErrorResponse(f))  -> Err(ProtocolError(f.message))
  | Ok(NoData)             -> collect_extended_rows(fd, col_names, acc)
  | Ok(_) -> collect_extended_rows(fd, col_names, acc)
  end
end

end
```

---

## 5. Type System Mapping

### 5.1 March Types → PostgreSQL OIDs

| March Type     | PostgreSQL Type | OID  | Notes                          |
|---------------|----------------|------|--------------------------------|
| `Bool`        | `boolean`       | 16   |                                |
| `Int`         | `int8`          | 20   | 64-bit signed                  |
| `Float`       | `float8`        | 701  | IEEE 754 double                |
| `String`      | `text`          | 25   |                                |
| `Decimal`     | `numeric`       | 1700 | exact arithmetic, no rounding  |
| `Bytes`       | `bytea`         | 17   |                                |
| `DateTime`    | `timestamptz`   | 1184 | always UTC                     |
| `Date`        | `date`          | 1082 |                                |
| `Time`        | `time`          | 1083 |                                |
| `Option(a)`   | nullable column | —    | NULL when None                 |
| `List(a)`     | `a[]`           | var  | PostgreSQL arrays              |
| `Json.JsonValue` | `jsonb`      | 3802 |                                |
| `UUID`        | `uuid`          | 2950 | planned stdlib type            |

Custom `type Foo = A | B | C` variants in March map to PostgreSQL `ENUM` types. The migration
engine creates/extends the enum type before altering the table.

### 5.2 Field Constraint Annotations

```march
-- Annotations on schema field registrations
@[primary_key]              -- PRIMARY KEY (implies NOT NULL)
@[unique]                   -- UNIQUE constraint
@[index]                    -- CREATE INDEX (non-unique)
@[default("now()")]         -- DEFAULT expression (raw SQL string)
@[references(User)]         -- FOREIGN KEY REFERENCES users(id)
@[check("age >= 0")]        -- CHECK constraint (raw SQL)
@[not_null]                 -- NOT NULL (already implied by non-Option types)
```

---

## 6. Schema Declaration

No macros. No DSL. A schema is a plain March record type plus a `Depot.Schema.table` registration
that names the table and declares constraints. The type system is the schema.

```march
-- In your application code

type User = {
  id         : Int,
  name       : String,
  email      : String,
  age        : Int,
  role       : Role,
  active     : Bool,
  created_at : DateTime
}

type Role = Admin | Member | Guest   -- maps to a PostgreSQL ENUM

type Post = {
  id         : Int,
  user_id    : Int,
  title      : String,
  body       : String,
  published  : Bool,
  created_at : DateTime
}

-- Schema registrations (at module top-level, evaluated at startup)
let users = Depot.Schema.table("users", [
  ("id",         "Int"),
  ("name",       "String"),
  ("email",      "String"),
  ("age",        "Int"),
  ("role",       "Role"),
  ("active",     "Bool"),
  ("created_at", "DateTime")
], {
  primary_key = "id",
  unique      = [["email"]],
  index       = [["name"], ["role"]],
  timestamps  = true            -- adds inserted_at / updated_at automatically
})

let posts = Depot.Schema.table("posts", [
  ("id",         "Int"),
  ("user_id",    "Int"),
  ("title",      "String"),
  ("body",       "String"),
  ("published",  "Bool"),
  ("created_at", "DateTime")
], {
  primary_key = "id",
  references  = [("user_id", "users", "id")],
  timestamps  = true
})
```

### Schema Type

```march
-- depot/src/schema/types.march

mod Depot.Schema do

pub type ColumnDef = {
  name        : String,
  march_type  : String,         -- "Int", "String", "Bool", etc.
  pg_type     : String,         -- "int8", "text", "boolean", etc.
  nullable    : Bool,
  primary_key : Bool,
  unique      : Bool,
  has_default : Bool,
  default_sql : Option(String)
}

pub type Schema = {
  table_name  : String,
  columns     : List(ColumnDef),
  primary_key : String,
  indexes     : List(IndexDef),
  unique_keys : List(List(String))
}

pub type IndexDef = {
  name    : String,
  columns : List(String),
  unique  : Bool
}

pub type SchemaOpts = {
  primary_key : String,
  unique      : List(List(String)),
  index       : List(List(String)),
  references  : List((String, String, String)),  -- (col, table, foreign_col)
  timestamps  : Bool
}

pub fn table(name : String, fields : List((String, String)), opts : SchemaOpts)
    : Schema do
  let col_defs = List.map(fields, fn (col_name, march_type) ->
    {
      name        = col_name,
      march_type  = march_type,
      pg_type     = march_type_to_pg(march_type),
      nullable    = march_type_is_option(march_type),
      primary_key = col_name == opts.primary_key,
      unique      = List.any(opts.unique, fn u -> u == [col_name]),
      has_default = col_name == opts.primary_key,  -- PK gets GENERATED ALWAYS AS IDENTITY
      default_sql = None
    }
  )
  {
    table_name  = name,
    columns     = col_defs,
    primary_key = opts.primary_key,
    indexes     = build_indexes(name, opts.index, false) ++
                  build_indexes(name, opts.unique, true),
    unique_keys = opts.unique
  }
end

fn march_type_to_pg(t) do
  match t do
  | "Int"      -> "int8"
  | "Float"    -> "float8"
  | "String"   -> "text"
  | "Bool"     -> "boolean"
  | "Bytes"    -> "bytea"
  | "Decimal"  -> "numeric"
  | "DateTime" -> "timestamptz"
  | "Date"     -> "date"
  | "Time"     -> "time"
  | other      -> String.to_lower(other)   -- User-defined enum: use type name lowercased
  end
end

fn march_type_is_option(t) do
  String.starts_with(t, "Option(")
end

fn build_indexes(table_name, cols_list, unique) do
  List.map(cols_list, fn cols ->
    let col_str = String.join("_", cols)
    let suffix  = if unique then "key" else "idx"
    { name = "${table_name}_${col_str}_${suffix}", columns = cols, unique = unique }
  )
end

end
```

**Schema derivation (future):** A `forge codegen depot` step will read the type declaration and
emit the `Depot.Schema.table(...)` call automatically. Until then, users write the field list
explicitly — verbose but readable and requires no compiler changes.

---

## 7. Query Builder ADT

The query builder is a pure data structure — no IO, no connection. It accumulates operations and
is compiled to a parameterized SQL string at execution time by `Query.Compile`.

### 7.1 Query ADT

```march
-- depot/src/query/ast.march

mod Depot.Query do

pub type Query = {
  schema   : Depot.Schema.Schema,
  select_  : SelectClause,
  where_   : List(Predicate),
  order_   : List(OrderClause),
  limit_   : Option(Int),
  offset_  : Option(Int),
  joins_   : List(JoinClause),
  group_by : List(String),
  having_  : List(Predicate),
  lock_    : Option(LockMode)
}

pub type SelectClause =
    SelectAll
  | SelectColumns(List(String))
  | SelectExprs(List((String, String)))  -- (sql_expr, alias)

pub type Predicate =
    Eq(String, Param)
  | NotEq(String, Param)
  | Lt(String, Param)
  | Lte(String, Param)
  | Gt(String, Param)
  | Gte(String, Param)
  | Like(String, String)
  | ILike(String, String)
  | In(String, List(Param))
  | IsNull(String)
  | IsNotNull(String)
  | And(Predicate, Predicate)
  | Or(Predicate, Predicate)
  | Not(Predicate)
  | Raw(String, List(Param))         -- escape hatch: raw SQL fragment

pub type Param =
    PInt(Int)
  | PFloat(Float)
  | PString(String)
  | PBool(Bool)
  | PDecimal(Decimal)
  | PBytes(Bytes)
  | PNull

pub type OrderClause =
    Asc(String)
  | Desc(String)
  | AscNullsLast(String)
  | DescNullsFirst(String)

pub type JoinClause = {
  kind  : JoinKind,
  table : String,
  alias : String,
  on    : Predicate
}

pub type JoinKind = InnerJoin | LeftJoin | RightJoin | FullJoin

pub type LockMode = ForUpdate | ForShare | ForUpdateSkipLocked

pub type CompiledQuery = {
  sql    : String,
  params : List(Param)
}

end
```

### 7.2 Builder Functions

```march
-- depot/src/query/build.march

mod Depot.Query.Build do

pub fn from(schema : Depot.Schema.Schema) : Depot.Query.Query do
  {
    schema   = schema,
    select_  = SelectAll,
    where_   = Nil,
    order_   = Nil,
    limit_   = None,
    offset_  = None,
    joins_   = Nil,
    group_by = Nil,
    having_  = Nil,
    lock_    = None
  }
end

pub fn where_(q, pred)     do { q | where_  = Cons(pred, q.where_) } end
pub fn select_(q, cols)    do { q | select_ = SelectColumns(cols) } end
pub fn order_by(q, clause) do { q | order_  = List.append(q.order_, [clause]) } end
pub fn limit(q, n)         do { q | limit_  = Some(n) } end
pub fn offset(q, n)        do { q | offset_ = Some(n) } end
pub fn group_by(q, cols)   do { q | group_by = cols } end
pub fn lock(q, mode)       do { q | lock_   = Some(mode) } end

pub fn join(q, other, on_pred) do
  add_join(q, { kind = InnerJoin, table = other.table_name, alias = other.table_name, on = on_pred })
end

pub fn left_join(q, other, on_pred) do
  add_join(q, { kind = LeftJoin, table = other.table_name, alias = other.table_name, on = on_pred })
end

fn add_join(q, clause) do
  { q | joins_ = List.append(q.joins_, [clause]) }
end

-- Predicate constructors
pub fn eq(col, val)    do Depot.Query.Eq(col, val)    end
pub fn neq(col, val)   do Depot.Query.NotEq(col, val) end
pub fn lt(col, val)    do Depot.Query.Lt(col, val)    end
pub fn lte(col, val)   do Depot.Query.Lte(col, val)   end
pub fn gt(col, val)    do Depot.Query.Gt(col, val)    end
pub fn gte(col, val)   do Depot.Query.Gte(col, val)   end
pub fn like(col, pat)  do Depot.Query.Like(col, pat)  end
pub fn ilike(col, pat) do Depot.Query.ILike(col, pat) end
pub fn is_null(col)    do Depot.Query.IsNull(col)     end
pub fn is_not_null(col)do Depot.Query.IsNotNull(col)  end
pub fn in_(col, vals)  do Depot.Query.In(col, vals)   end
pub fn and_(p, r)      do Depot.Query.And(p, r)       end
pub fn or_(p, r)       do Depot.Query.Or(p, r)        end
pub fn not_(p)         do Depot.Query.Not(p)          end
pub fn raw(sql, ps)    do Depot.Query.Raw(sql, ps)    end

end
```

### 7.3 SQL Compiler

```march
-- depot/src/query/compile.march

mod Depot.Query.Compile do

type CompileState = { counter : Int, params : List(Depot.Query.Param) }

pub fn compile(q : Depot.Query.Query) : Depot.Query.CompiledQuery do
  let s0 = { counter = 0, params = Nil }

  let (select_sql, s1) = compile_select(q.select_, q.schema.table_name)
  let (join_sql,   s2) = compile_joins(q.joins_, s1)
  let (where_sql,  s3) = compile_wheres(q.where_, s2)
  let group_sql        = compile_group(q.group_by)
  let (having_sql, s4) = compile_wheres(q.having_, s3)
  let (order_sql,  _ ) = compile_order(q.order_, s4)
  let limit_sql        = compile_limit(q.limit_)
  let offset_sql       = compile_offset(q.offset_)
  let lock_sql         = compile_lock(q.lock_)

  let having_clause = if having_sql == "" then "" else " HAVING ${having_sql}"

  let sql =
    "SELECT ${select_sql}"
    ++ " FROM ${q.schema.table_name}"
    ++ join_sql
    ++ where_sql
    ++ group_sql
    ++ having_clause
    ++ order_sql
    ++ limit_sql
    ++ offset_sql
    ++ lock_sql

  { sql = sql, params = List.reverse(s4.params) }
end

fn next_placeholder(s) do
  let n = s.counter + 1
  ({ s | counter = n }, "$${n}")
end

fn compile_select(clause, _table) do
  match clause do
  | SelectAll           -> ("*", "")
  | SelectColumns(cols) -> (String.join(", ", cols), "")
  | SelectExprs(exprs)  ->
    let parts = List.map(exprs, fn (expr, alias) -> "${expr} AS ${alias}")
    (String.join(", ", parts), "")
  end
end

fn compile_joins(joins, s) do
  List.fold(joins, ("", s), fn (acc_sql, s) clause ->
    let kw = match clause.kind do
      | InnerJoin -> "INNER JOIN"
      | LeftJoin  -> "LEFT JOIN"
      | RightJoin -> "RIGHT JOIN"
      | FullJoin  -> "FULL JOIN"
      end
    let (on_sql, s) = compile_pred(clause.on, s)
    (acc_sql ++ " ${kw} ${clause.table} ON ${on_sql}", s)
  )
end

fn compile_wheres(preds, s) do
  match preds do
  | Nil -> ("", s)
  | _   ->
    let (parts, s) = List.fold(
      List.reverse(preds), (Nil, s), fn (parts, s) pred ->
        let (sql, s) = compile_pred(pred, s)
        (Cons(sql, parts), s)
    )
    (" WHERE " ++ String.join(" AND ", parts), s)
  end
end

fn compile_pred(pred, s) do
  match pred do
  | Eq(col, val) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(val, s.params) }, "${col} = ${ph}")
  | NotEq(col, val) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(val, s.params) }, "${col} <> ${ph}")
  | Lt(col, val) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(val, s.params) }, "${col} < ${ph}")
  | Lte(col, val) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(val, s.params) }, "${col} <= ${ph}")
  | Gt(col, val) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(val, s.params) }, "${col} > ${ph}")
  | Gte(col, val) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(val, s.params) }, "${col} >= ${ph}")
  | Like(col, pat) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(PString(pat), s.params) }, "${col} LIKE ${ph}")
  | ILike(col, pat) ->
    let (s, ph) = next_placeholder(s)
    ({ s | params = Cons(PString(pat), s.params) }, "${col} ILIKE ${ph}")
  | IsNull(col)    -> (s, "${col} IS NULL")
  | IsNotNull(col) -> (s, "${col} IS NOT NULL")
  | In(col, vals) ->
    let (s, phs) = List.fold(vals, (s, Nil), fn (s, phs) val ->
      let (s, ph) = next_placeholder(s)
      ({ s | params = Cons(val, s.params) }, Cons(ph, phs))
    )
    (s, "${col} IN (${String.join(", ", List.reverse(phs))})")
  | And(p, r) ->
    let (s, ps) = compile_pred(p, s)
    let (s, rs) = compile_pred(r, s)
    (s, "(${ps} AND ${rs})")
  | Or(p, r) ->
    let (s, ps) = compile_pred(p, s)
    let (s, rs) = compile_pred(r, s)
    (s, "(${ps} OR ${rs})")
  | Not(p) ->
    let (s, ps) = compile_pred(p, s)
    (s, "NOT (${ps})")
  | Raw(sql, params) ->
    let s = { s | params = List.append(List.reverse(params), s.params) }
    (s, sql)
  end
end

fn compile_order(clauses, s) do
  match clauses do
  | Nil -> ("", s)
  | _   ->
    let parts = List.map(clauses, fn c ->
      match c do
      | Asc(col)           -> "${col} ASC"
      | Desc(col)          -> "${col} DESC"
      | AscNullsLast(col)  -> "${col} ASC NULLS LAST"
      | DescNullsFirst(col)-> "${col} DESC NULLS FIRST"
      end
    )
    (" ORDER BY " ++ String.join(", ", parts), s)
  end
end

fn compile_group(cols) do
  match cols do
  | Nil -> ""
  | _   -> " GROUP BY " ++ String.join(", ", cols)
  end
end

fn compile_limit(opt) do
  match opt do | None -> "" | Some(n) -> " LIMIT ${n}" end
end

fn compile_offset(opt) do
  match opt do | None -> "" | Some(n) -> " OFFSET ${n}" end
end

fn compile_lock(opt) do
  match opt do
  | None                   -> ""
  | Some(ForUpdate)        -> " FOR UPDATE"
  | Some(ForShare)         -> " FOR SHARE"
  | Some(ForUpdateSkipLocked) -> " FOR UPDATE SKIP LOCKED"
  end
end

fn param_to_wire(p) do
  match p do
  | PNull       -> Wire.Message.ParamNull
  | PInt(n)     -> Wire.Message.ParamText(int_to_string(n))
  | PFloat(f)   -> Wire.Message.ParamText(float_to_string(f))
  | PString(s)  -> Wire.Message.ParamText(s)
  | PBool(b)    -> Wire.Message.ParamText(if b then "t" else "f")
  | PDecimal(d) -> Wire.Message.ParamText(Decimal.to_string(d))
  | PBytes(b)   -> Wire.Message.ParamBinary(b)
  end
end

pub fn wire_params(compiled : Depot.Query.CompiledQuery)
    : List(Wire.Message.Param) do
  List.map(compiled.params, fn p -> param_to_wire(p))
end

end
```

---

## 8. Connection Pool (Actor-based)

```march
-- depot/src/conn/pool.march

mod Depot.Pool do

pub type PoolOpts = {
  host          : String,
  port          : Int,
  user          : String,
  password      : String,
  database      : String,
  pool_size     : Int,     -- default 10
  queue_timeout : Int      -- ms; default 5000
}

pub type PoolMsg =
    Checkout(Int)           -- timeout_ms
  | Checkin(Conn.Conn)
  | Healthcheck
  | Shutdown

pub type PoolReply =
    CheckedOut(Conn.Conn)
  | PoolExhausted
  | PoolDown(String)

type PoolState = {
  available   : List(Conn.Conn),
  checked_out : Int,
  max_size    : Int,
  opts        : PoolOpts
}

actor Pool do
  -- Initial state is injected via the Init message in the real implementation.
  -- Shown here with a placeholder.
  state = { available = Nil, checked_out = 0, max_size = 10, opts = ?default_opts }

  on Call(ref, Checkout(_timeout_ms)) ->
    match state.available do
    | Cons(conn, rest) ->
      Actor.reply(ref, CheckedOut(conn))
      { state | available = rest, checked_out = state.checked_out + 1 }
    | Nil ->
      if state.checked_out >= state.max_size then do
        Actor.reply(ref, PoolExhausted)
        state
      end else do
        match Conn.connect({
          host     = state.opts.host,
          port     = state.opts.port,
          user     = state.opts.user,
          password = state.opts.password,
          database = state.opts.database
        }) do
        | Err(e) ->
          Actor.reply(ref, PoolDown(to_string(e)))
          state
        | Ok(conn) ->
          Actor.reply(ref, CheckedOut(conn))
          { state | checked_out = state.checked_out + 1 }
        end
      end
    end

  on Checkin(conn) ->
    { state |
      available   = Cons(conn, state.available),
      checked_out = state.checked_out - 1
    }

  on Healthcheck ->
    -- Ping idle connections; drop dead ones; create replacements
    let live = List.filter(state.available, fn c -> ping(c))
    { state | available = live }

  on Shutdown ->
    List.each(state.available, fn c -> Conn.close(c))
    { state | available = Nil, checked_out = 0 }
end

fn ping(conn) do
  -- Send empty sync, expect ReadyForQuery
  match Conn.simple_query(conn, "") do
  | Ok(_) -> true
  | Err(_) -> false
  end
end

-- Run f with a checked-out connection. Always checks connection back in.
pub fn with_conn(pool : Pid(Pool), timeout_ms : Int, f)
    : Result(a, Depot.Error) do
  match Actor.call(pool, Checkout(timeout_ms), timeout_ms) do
  | Err(e)              -> Err(Depot.PoolError(e))
  | Ok(PoolExhausted)   -> Err(Depot.PoolExhausted)
  | Ok(PoolDown(msg))   -> Err(Depot.ConnError(msg))
  | Ok(CheckedOut(conn)) ->
    let result = f(conn)
    Actor.cast(pool, Checkin(conn))
    result
  end
end

end
```

---

## 9. Auto-Migration Engine

The migration engine diffs declared `Schema` values against the live PostgreSQL catalog and emits
DDL to bring the database in sync.

### 9.1 Introspection (via `pg_catalog`)

```march
-- depot/src/schema/introspect.march

mod Depot.Schema.Introspect do

pub type LiveColumn = {
  name        : String,
  pg_type     : String,
  nullable    : Bool,
  has_default : Bool
}

pub type LiveTable = {
  name    : String,
  columns : List(LiveColumn)
}

pub fn inspect_table(conn : Conn.Conn, table_name : String)
    : Result(Option(LiveTable), String) do
  let sql = "
    SELECT
      a.attname                            AS name,
      format_type(a.atttypid, a.atttypmod) AS pg_type,
      NOT a.attnotnull                     AS nullable,
      a.atthasdef                          AS has_default
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class     c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = $1
      AND n.nspname = 'public'
      AND a.attnum > 0
      AND NOT a.attisdropped
    ORDER BY a.attnum
  "
  match Conn.exec(conn, sql, [Wire.Message.ParamText(table_name)]) do
  | Err(e)  -> Err(to_string(e))
  | Ok(Nil) -> Ok(None)
  | Ok(rows) ->
    let cols = List.map(rows, fn row -> {
      name        = Map.get(row, "name")        |> Option.unwrap(""),
      pg_type     = Map.get(row, "pg_type")     |> Option.unwrap(""),
      nullable    = Map.get(row, "nullable")    |> Option.unwrap("f") == "t",
      has_default = Map.get(row, "has_default") |> Option.unwrap("f") == "t"
    })
    Ok(Some({ name = table_name, columns = cols }))
  end
end

end
```

### 9.2 Diff + Apply

```march
-- depot/src/migration.march

mod Depot.Migration do

pub type MigrationStep =
    CreateTable(Depot.Schema.Schema)
  | AddColumn(String, Depot.Schema.ColumnDef)
  | DropColumn(String, String)                   -- never auto-run; warn only
  | AlterColumnType(String, String, String)      -- table, col, new_pg_type
  | SetNotNull(String, String)
  | DropNotNull(String, String)
  | CreateIndex(String, Depot.Schema.IndexDef)
  | DropIndex(String)
  | CreateEnum(String, List(String))

pub fn diff(schema : Depot.Schema.Schema,
            live   : Option(Depot.Schema.Introspect.LiveTable))
    : List(MigrationStep) do
  match live do
  | None -> [CreateTable(schema)]
  | Some(live_table) ->
    find_missing_columns(schema, live_table)
    ++ find_type_changes(schema, live_table)
    ++ find_missing_indexes(schema, live_table)
  end
end

fn find_missing_columns(schema, live) do
  List.filter_map(schema.columns, fn col ->
    let exists = List.any(live.columns, fn lc -> lc.name == col.name)
    if exists then None else Some(AddColumn(schema.table_name, col))
  )
end

fn find_type_changes(schema, live) do
  List.filter_map(schema.columns, fn col ->
    match List.find(live.columns, fn lc -> lc.name == col.name) do
    | None -> None
    | Some(lc) ->
      if lc.pg_type != col.pg_type then
        Some(AlterColumnType(schema.table_name, col.name, col.pg_type))
      else None
    end
  )
end

fn find_missing_indexes(schema, _live) do
  -- simplified: always emit CREATE INDEX IF NOT EXISTS
  List.filter_map(schema.indexes, fn idx ->
    if idx.unique then None   -- unique constraints handled in CREATE TABLE
    else Some(CreateIndex(schema.table_name, idx))
  )
end

pub fn to_sql(step : MigrationStep) : String do
  match step do
  | CreateTable(schema) ->
    let col_defs = List.map(schema.columns, fn col ->
      let null_c = if col.nullable then "" else " NOT NULL"
      let pk_c   = if col.primary_key then " GENERATED ALWAYS AS IDENTITY PRIMARY KEY" else ""
      let uniq_c = if col.unique && !col.primary_key then " UNIQUE" else ""
      "${col.name} ${col.pg_type}${null_c}${pk_c}${uniq_c}"
    )
    "CREATE TABLE IF NOT EXISTS ${schema.table_name} (\n  "
    ++ String.join(",\n  ", col_defs)
    ++ "\n)"
  | AddColumn(table, col) ->
    let null_c = if col.nullable then "" else " NOT NULL"
    "ALTER TABLE ${table} ADD COLUMN IF NOT EXISTS ${col.name} ${col.pg_type}${null_c}"
  | AlterColumnType(table, col, new_type) ->
    "ALTER TABLE ${table} ALTER COLUMN ${col} TYPE ${new_type} USING ${col}::${new_type}"
  | CreateIndex(table, idx) ->
    let uniq = if idx.unique then "UNIQUE " else ""
    let cols  = String.join(", ", idx.columns)
    "CREATE ${uniq}INDEX IF NOT EXISTS ${idx.name} ON ${table} (${cols})"
  | CreateEnum(name, vals) ->
    let quoted = List.map(vals, fn v -> "'${v}'")
    "CREATE TYPE IF NOT EXISTS ${name} AS ENUM (${String.join(", ", quoted)})"
  | DropColumn(table, col) ->
    -- Never auto-run. Used only in dry-run output to show what would need manual intervention.
    "-- MANUAL: ALTER TABLE ${table} DROP COLUMN ${col}"
  | _ -> ""
  end
end

-- Compute and print all steps without executing (dry-run).
pub fn plan(pool, schemas : List(Depot.Schema.Schema))
    : Result(List(String), Depot.Error) do
  Depot.Pool.with_conn(pool, 5000, fn conn ->
    List.fold_result(schemas, Nil, fn acc schema ->
      match Depot.Schema.Introspect.inspect_table(conn, schema.table_name) do
      | Err(e)   -> Err(Depot.QueryError(e))
      | Ok(live) ->
        let steps = diff(schema, live)
        let sqls  = List.filter_map(steps, fn s ->
          let sql = to_sql(s)
          if sql == "" then None else Some(sql)
        )
        Ok(List.append(acc, sqls))
      end
    )
  )
end

-- Run all migration steps inside a transaction.
pub fn run(pool, schemas : List(Depot.Schema.Schema))
    : Result(Unit, Depot.Error) do
  Depot.Repo.transaction(pool, fn conn ->
    List.fold_result(schemas, (), fn _ schema ->
      match Depot.Schema.Introspect.inspect_table(conn, schema.table_name) do
      | Err(e)   -> Err(Depot.QueryError(e))
      | Ok(live) ->
        let steps = diff(schema, live)
        List.fold_result(steps, (), fn _ step ->
          let sql = to_sql(step)
          if sql == "" || String.starts_with(sql, "--") then Ok(())
          else Depot.Repo.execute_conn(conn, sql, Nil)
        )
      end
    )
  )
end

end
```

**Safety rules:**
- `ADD COLUMN` — always safe, auto-applied.
- `DROP COLUMN` — **never auto-applied**. Printed as a `-- MANUAL:` comment in `plan`, ignored in `run`.
- `ALTER COLUMN TYPE` — applied but logs a warning. Requires a `USING` cast.
- Re-running migration is idempotent (`IF NOT EXISTS` everywhere).

---

## 10. API Design & March Code Examples

### 10.1 Starting the Repo

```march
import Depot

fn main() do
  let pool = spawn(Depot.Pool, {
    host          = "localhost",
    port          = 5432,
    user          = "myapp",
    password      = "secret",
    database      = "myapp_dev",
    pool_size     = 10,
    queue_timeout = 5000
  })

  match Depot.Migration.run(pool, [users, posts]) do
  | Err(e) -> println("Migration failed: ${to_string(e)}")
  | Ok(_)  -> println("Migrations OK — ready")
  end
end
```

### 10.2 Query Building with Pipes

```march
-- Simple select with filtering, ordering, pagination
let q =
  Depot.Query.Build.from(users)
  |> where_(eq("active", PBool(true)))
  |> where_(gt("age", PInt(18)))
  |> order_by(Desc("created_at"))
  |> limit(50)
  |> offset(100)

match Depot.Repo.all(pool, q) do
| Err(e)   -> println("Error: ${to_string(e)}")
| Ok(rows) -> List.each(rows, fn row -> println(Map.get(row, "name")))
end

-- Grouped aggregation
let stats_q =
  Depot.Query.Build.from(users)
  |> where_(eq("active", PBool(true)))
  |> select_(["role", "count(*) AS n", "avg(age) AS avg_age"])
  |> group_by(["role"])
  |> order_by(Desc("n"))

match Depot.Repo.all(pool, stats_q) do
| Ok(rows) -> List.each(rows, fn r ->
    println("${r["role"]}: ${r["n"]} users, avg age ${r["avg_age"]}")
  )
| Err(e) -> println(to_string(e))
end
```

### 10.3 Get by Primary Key

```march
-- Returns Ok(Some(row)) | Ok(None) | Err(...)
match Depot.Repo.get(pool, users, 42) do
| Err(e)        -> handle_error(e)
| Ok(None)      -> { status = 404, body = "not found" }
| Ok(Some(row)) -> { status = 200, body = encode_user(row) }
end

-- Panics if not found (use when you're certain the row exists)
let user = Depot.Repo.get!(pool, users, 42)
```

### 10.4 Insert / Update / Delete

```march
-- Insert — returns the inserted row with server-assigned id
match Depot.Repo.insert(pool, users, Map.from_list([
  ("name",   "Alice"),
  ("email",  "alice@example.com"),
  ("age",    "30"),
  ("role",   "member"),
  ("active", "t")
])) do
| Err(Depot.UniqueViolation(constraint)) ->
  { status = 409, body = "duplicate: ${constraint}" }
| Err(e) ->
  { status = 500, body = to_string(e) }
| Ok(row) ->
  { status = 201, body = "created user ${row["id"]}" }
end

-- Update by primary key (partial)
match Depot.Repo.update(pool, users, 42, Map.from_list([("active", "f")])) do
| Err(Depot.NotFound) -> { status = 404, body = "not found" }
| Err(e)              -> { status = 500, body = to_string(e) }
| Ok(row)             -> { status = 200, body = encode_user(row) }
end

-- Delete by primary key
match Depot.Repo.delete(pool, users, 42) do
| Err(Depot.NotFound) -> { status = 404, body = "not found" }
| Err(e)              -> { status = 500, body = to_string(e) }
| Ok(_)               -> { status = 204, body = "" }
end

-- Delete by query (returns row count)
let q = Depot.Query.Build.from(users) |> where_(eq("active", PBool(false)))
match Depot.Repo.delete_all(pool, q) do
| Err(e) -> println("Error: ${to_string(e)}")
| Ok(n)  -> println("Deleted ${n} inactive users")
end
```

### 10.5 Typed Errors

```march
pub type Depot.Error =
    ConnError(String)
  | QueryError(String)
  | NotFound
  | UniqueViolation(String)      -- SQLSTATE 23505
  | ForeignKeyViolation(String)  -- SQLSTATE 23503
  | CheckViolation(String)       -- SQLSTATE 23514
  | PoolExhausted
  | PoolError(String)
  | Timeout
  | ParseError(String)           -- row → March type conversion

match Depot.Repo.get(pool, users, id) do
| Err(ConnError(msg))          -> reconnect_and_retry(msg)
| Err(PoolExhausted)           -> { status = 503, body = "try again later" }
| Err(e)                       -> { status = 500, body = to_string(e) }
| Ok(None)                     -> { status = 404, body = "not found" }
| Ok(Some(row))                -> { status = 200, body = encode_user(row) }
end
```

### 10.6 Joins

```march
-- Inner join: posts with their authors
let q =
  Depot.Query.Build.from(posts)
  |> join(users, eq("posts.user_id", PString("users.id")))
  |> where_(eq("posts.published", PBool(true)))
  |> select_(["posts.id", "posts.title", "users.name AS author"])
  |> order_by(Desc("posts.created_at"))
  |> limit(20)

match Depot.Repo.all(pool, q) do
| Ok(rows) ->
  List.each(rows, fn r ->
    println("${r["title"]} by ${r["author"]}")
  )
| Err(e) -> println(to_string(e))
end

-- Left join: users and their post count (users with no posts → count 0)
let q =
  Depot.Query.Build.from(users)
  |> left_join(posts, eq("users.id", PString("posts.user_id")))
  |> select_(["users.name", "count(posts.id) AS post_count"])
  |> group_by(["users.id", "users.name"])
  |> order_by(Desc("post_count"))
```

### 10.7 Transactions

```march
-- Everything in the callback shares one connection.
-- Returning Err triggers ROLLBACK. Returning Ok triggers COMMIT.
match Depot.Repo.transaction(pool, fn conn ->
  match Depot.Repo.insert_conn(conn, users, user_data) do
  | Err(e) -> Err(e)
  | Ok(user) ->
    let post_data = Map.set(template_post, "user_id", user["id"])
    Depot.Repo.insert_conn(conn, posts, post_data)
  end
) do
| Err(e)    -> println("Transaction rolled back: ${to_string(e)}")
| Ok(post)  -> println("Created user and post ${post["id"]}")
end
```

### 10.8 Raw SQL Escape Hatch

```march
-- When the query builder can't express what you need
match Depot.Repo.query(pool,
  "SELECT date_trunc('month', created_at) AS month, count(*) FROM users GROUP BY 1 ORDER BY 1",
  Nil) do
| Ok(rows) -> List.each(rows, fn r -> println("${r["month"]}: ${r["count"]}"))
| Err(e)   -> println(to_string(e))
end
```

### 10.9 Auto-Migration

```march
-- Dry run: see what would change without applying
match Depot.Migration.plan(pool, [users, posts]) do
| Err(e)   -> println("Plan failed: ${to_string(e)}")
| Ok(sqls) ->
  println("Would run ${List.length(sqls)} migration steps:")
  List.each(sqls, fn sql -> println("  " ++ sql))
end

-- Apply: run all safe migrations in a transaction
match Depot.Migration.run(pool, [users, posts]) do
| Err(e) -> println("Migration failed: ${to_string(e)}")
| Ok(_)  -> println("All migrations applied")
end
```

### 10.10 Changesets

```march
-- Validate and cast before writing to the database
let cs =
  Depot.Changeset.new(params)
  |> Depot.Changeset.validate_required(["name", "email", "age"])
  |> Depot.Changeset.validate_format("email", Regex.compile("[^@]+@[^@]+\\.[^@]+"))
  |> Depot.Changeset.validate_length("name", 2, 100)
  |> Depot.Changeset.validate_number("age", 0, 150)
  |> Depot.Changeset.validate_inclusion("role", ["admin", "member", "guest"])

match Depot.Changeset.apply(cs) do
| Err(errors) ->
  let msg = List.map(errors, fn (field, err) -> "${field}: ${err}")
            |> String.join(", ")
  { status = 422, body = "Validation failed: ${msg}" }
| Ok(data) ->
  match Depot.Repo.insert(pool, users, data) do
  | Err(UniqueViolation(_)) -> { status = 409, body = "email already taken" }
  | Err(e)                  -> { status = 500, body = to_string(e) }
  | Ok(row)                 -> { status = 201, body = encode_user(row) }
  end
end
```

---

## 11. Implementation Phases

### Phase 0 — Prerequisites: Bytes + `tcp_recv_exact`
**Goal:** Two small additions to the March runtime/stdlib needed before any wire protocol work.

**Deliverables:**
1. `Bytes.encode_i32_be(n) : Bytes` and `Bytes.decode_i32_be(b, offset) : Int`
2. `Bytes.encode_i16_be(n) : Bytes` and `Bytes.decode_i16_be(b, offset) : Int`
3. New eval builtin: `tcp_recv_exact(fd, n)` — reads exactly n bytes, looping on partial reads

**Dependencies:** None. Pure stdlib extension + 10 lines in `eval.ml`.
**Effort:** 0.5 days
**Tests:**
- Round-trip `i32_be` for 0, 1, 256, max_int32, negative
- `tcp_recv_exact` returns exactly n bytes even when TCP splits the data

---

### Phase 1 — Wire Protocol: Encoding
**Goal:** Pure March binary encoding of all Frontend messages.

**Deliverables:**
- `depot/src/wire/message.march` — full `FrontendMessage` + `BackendMessage` ADT
- `depot/src/wire/encode.march` — `encode(FrontendMessage) : Bytes`

**Dependencies:** Phase 0
**Effort:** 1.5 days
**Tests:**
- Byte-exact comparison against bytes captured from `psql` using Wireshark
- `Startup` message: correct length prefix, protocol version, key-value pairs
- `Query("SELECT 1")`: 'Q' byte, 4-byte length, "SELECT 1\0"
- `Terminate`: exactly 5 bytes `[88, 0, 0, 0, 4]`
- `Bind` with 2 params: correct format codes, param lengths

---

### Phase 2 — Wire Protocol: Decoding
**Goal:** Parse raw bytes into `BackendMessage` values.

**Deliverables:**
- `depot/src/wire/decode.march` — `read_one(Bytes) : Result((BackendMessage, Bytes), String)`
- Decoders for all 16 backend message types

**Dependencies:** Phase 1
**Effort:** 2 days
**Tests:**
- Decode byte sequences recorded from real PostgreSQL connections
- `RowDescription` with 3 fields: correct names and OIDs
- `DataRow` with one NULL column (len = -1 → `None`)
- `ErrorResponse`: all 6 fields extracted correctly
- Partial buffer (fewer bytes than promised by length field) → `Err("incomplete")`
- Unknown type byte → `Err("unknown backend message type: ...")`

---

### Phase 3 — Connection Handshake
**Goal:** Full TCP connection to a live PostgreSQL server.

**Deliverables:**
- `depot/src/conn/conn.march` — `connect`, `simple_query`, `exec`, `close`
- MD5 authentication (requires `md5` builtin — verify it exists in eval.ml)
- SCRAM-SHA-256 path (requires `sha256` + `hmac_sha256` builtins — may need adding)

**Dependencies:** Phases 0–2, live PostgreSQL for integration tests
**Effort:** 3 days
**Tests (integration):**
- Connect to local PostgreSQL with correct credentials → `Ok(Conn{...})`
- Connect with wrong password → `Err(AuthError(...))`
- `simple_query("SELECT 1")` → `Ok([{"?column?" => "1"}])`
- `simple_query("SELECT NULL")` → `Ok([{"" => ""}])` (or empty string — check PG behavior)
- `exec("SELECT $1::int", [ParamText("42")])` → `Ok([{"?column?" => "42"}])`
- Port refused → `Err(TcpError(...))`

---

### Phase 4 — Schema Registration
**Goal:** Represent March type declarations as runtime Schema values.

**Deliverables:**
- `depot/src/schema/types.march` — full `ColumnDef`, `Schema`, `SchemaOpts` types
- `Depot.Schema.table(...)` builder
- `depot/src/schema/introspect.march` — `inspect_table`
- March type string → PostgreSQL type string mapping

**Dependencies:** Phase 3 (introspect uses `Conn.exec`)
**Effort:** 2 days
**Tests:**
- `table("users", [...], {...})` produces correct `Schema` value
- `inspect_table(conn, "nonexistent")` → `Ok(None)`
- `inspect_table(conn, "users")` after creating it → `Ok(Some({...}))`
- Type mapping covers all 13 built-in types

---

### Phase 5 — Query Builder (Pure)
**Goal:** IO-free query construction and SQL compilation.

**Deliverables:**
- `depot/src/query/ast.march`
- `depot/src/query/build.march`
- `depot/src/query/compile.march`

**Dependencies:** Phase 4
**Effort:** 3 days
**Tests (all pure — no DB):**
- `from(users)` → `"SELECT * FROM users"`, `params = []`
- `where_(eq("age", PInt(18)))` → `"... WHERE age = $1"`, `params = [PInt(18)]`
- Two `where_` calls → `AND`-combined
- `order_by(Desc("name")) |> limit(10) |> offset(20)` → correct suffix
- `in_("role", [PString("a"), PString("b")])` → `"role IN ($1, $2)"`
- `and_(eq(...), or_(lt(...), gt(...)))` → correct parenthesization
- `join(posts, ...)` → `"INNER JOIN posts ON ..."`
- `left_join` → `"LEFT JOIN ..."`
- `Raw(sql, params)` passes through unchanged, params numbered correctly

---

### Phase 6 — Repo + Connection Pool
**Goal:** Actor-based pool; public Repo API.

**Deliverables:**
- `depot/src/conn/pool.march` — `Pool` actor
- `depot/src/repo.march` — `all`, `get`, `get!`, `query`, `execute`, `execute_conn`
- Extended query protocol in `Conn.exec` (Parse/Bind/Execute/Sync)

**Dependencies:** Phases 3–5
**Effort:** 3 days
**Tests:**
- `Repo.all(pool, from(users))` returns list of row maps
- `Repo.get(pool, users, 999)` → `Ok(None)` (not found)
- `Repo.get(pool, users, 1)` → `Ok(Some({...}))` (found)
- Pool at capacity → `Err(PoolExhausted)` after timeout
- 10 concurrent actor calls → all succeed, no deadlock
- Connection dropped mid-request → pool creates replacement on next checkout

---

### Phase 7 — Auto-Migration
**Goal:** Diff schemas against the live database and apply DDL.

**Deliverables:**
- `depot/src/migration.march` — `diff`, `to_sql`, `plan`, `run`
- `plan` dry-run mode
- Safety guard: `DropColumn` never auto-applied

**Dependencies:** Phases 4–6
**Effort:** 3 days
**Tests:**
- Empty DB + `run([users])` → `CREATE TABLE IF NOT EXISTS users (...)`
- Existing table missing one column → `ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`
- Type change detected → `ALTER COLUMN ... TYPE ...`
- `plan` returns SQL strings without executing
- `run` wraps all steps in a transaction; step failure → rollback

---

### Phase 8 — Insert / Update / Delete
**Goal:** Full CRUD with typed `Depot.Error` variants.

**Deliverables:**
- `Repo.insert`, `Repo.update`, `Repo.delete`, `Repo.delete_all`
- `Repo.insert_conn`, `Repo.update_conn`, `Repo.delete_conn` (connection-scoped)
- PostgreSQL SQLSTATE → `Depot.Error` mapping

**Dependencies:** Phase 6
**Effort:** 2 days
**Tests:**
- Insert valid row → `Ok(row_with_id)`
- Duplicate unique field → `Err(UniqueViolation(constraint_name))`
- Update missing row → `Err(NotFound)`
- Foreign key violation → `Err(ForeignKeyViolation(...))`
- `delete_all` matching 3 rows → `Ok(3)`

---

### Phase 9 — Transactions
**Goal:** `BEGIN`/`COMMIT`/`ROLLBACK` with automatic rollback on error return.

**Deliverables:**
- `Repo.transaction(pool, fn conn -> ...)`
- Nested transaction support via savepoints

**Dependencies:** Phases 6–8
**Effort:** 2 days
**Tests:**
- Callback returning `Ok` → `COMMIT`, data visible
- Callback returning `Err` → `ROLLBACK`, data not visible
- Concurrent transactions on same row → second blocks until first commits
- Nested transaction: inner `Err` → savepoint rollback, outer continues

---

### Phase 10 — Joins + Preloading
**Goal:** Typed join queries and N+1 prevention via batch preloading.

**Deliverables:**
- `compile.march` handles all four join kinds
- `Repo.preload(pool, rows, schema, assoc_schema)` — batched association loading

**Dependencies:** Phase 7
**Effort:** 3 days
**Tests:**
- Inner join posts + users → rows contain fields from both tables
- Left join: unmatched right side → `None`-valued fields
- `preload(user_rows, posts)` → single `WHERE user_id IN (...)` query, not N queries

---

### Phase 11 — Changesets
**Goal:** Validation and casting layer.

**Deliverables:**
- `depot/src/changeset.march` — `Changeset`, all validators, `apply`

**Dependencies:** Phase 8
**Effort:** 2 days
**Tests:**
- Missing required field → `Err([("email", "can't be blank")])`
- Bad format → `Err([("email", "has invalid format")])`
- Multiple errors accumulate (no short-circuit)
- All valid → `Ok(data)`, which can be passed directly to `Repo.insert`

---

## 12. Test Plan

### Unit Tests (no PostgreSQL required)

| Module | What's tested |
|--------|---------------|
| `wire/encode` | Byte-exact output for every FrontendMessage variant |
| `wire/decode` | Decode captured PostgreSQL bytes for every BackendMessage |
| `query/compile` | SQL string + param list for every Query combination |
| `schema/types` | March type → PG type for all 13 mapped types |
| `migration` | `diff` produces correct steps for all 6 change kinds |
| `changeset` | All 5 validators, error accumulation, valid passthrough |

### Integration Tests (requires PostgreSQL)

Run against a local PostgreSQL instance in CI via Docker:

```bash
docker run -d \
  -e POSTGRES_USER=depot_test \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=depot_test \
  -p 5432:5432 \
  postgres:16-alpine
```

| Test | Description |
|------|-------------|
| `connect_ok` | Connect + disconnect cleanly |
| `auth_fail` | Wrong password → `AuthError` |
| `migrate_create` | Empty DB → all tables created |
| `migrate_idempotent` | Run twice → no error, no duplicate DDL |
| `migrate_add_column` | Add field to type → `ALTER TABLE ADD COLUMN` |
| `insert_get` | Insert user, get by id, values match |
| `insert_unique_fail` | Duplicate email → `UniqueViolation` |
| `update` | Update field, re-fetch, verify new value |
| `delete` | Delete by id, verify `NotFound` on re-fetch |
| `delete_all` | Delete by query, verify count returned |
| `query_where` | Filter with `eq` + `gt` |
| `query_order` | `ORDER BY created_at DESC` |
| `query_limit_offset` | Page 2 of 10 results |
| `query_join` | Inner join users + posts |
| `query_left_join` | Left join with no match |
| `transaction_commit` | Insert in txn, commit, visible outside |
| `transaction_rollback` | Insert in txn, return Err, not visible |
| `pool_concurrency` | 20 actors querying concurrently |
| `pool_exhaustion` | pool_size=2, 5 concurrent → some get `PoolExhausted` |
| `changeset_valid` | Valid data → insert succeeds |
| `changeset_invalid` | Bad data → errors, no insert attempted |
| `raw_query` | `Repo.query` with raw SQL |
| `null_roundtrip` | Insert `None` field, get back `None` |
| `empty_result` | Query matching no rows → `Ok([])` |

### Edge Cases

- Empty `IN` list → return `Ok([])` without hitting the database (SQL `IN ()` is invalid)
- `get!` on missing row → panics with clear message including table name and id
- Very large string (1MB) round-trips correctly
- Connection lost mid-query → `Err(ConnError(...))`, pool creates a fresh connection
- Integer boundary: March `Int` and PostgreSQL `int8` are both int64 — no overflow
- Two processes running `Migration.run` simultaneously → second run is idempotent, no crash
- Query with no `where_` clauses → no `WHERE` in SQL, returns all rows

---

## 13. Benchmark Plan

All benchmarks use a fresh PostgreSQL 16 instance on the same machine as the March process.
Pool size is fixed at 1 for latency benchmarks (to isolate query overhead from pooling); size 10
for concurrency benchmarks.

### Benchmarks

| Name | Description | Target |
|------|-------------|--------|
| `connect_close` | Open + authenticate + close | < 5ms |
| `single_insert` | Insert one row via `Repo.insert` | < 3ms |
| `bulk_insert_1k` | 1,000 rows, one transaction | < 100ms |
| `bulk_insert_10k` | 10,000 rows, one transaction | < 1s |
| `bulk_insert_100k` | 100,000 rows via COPY protocol | < 10s |
| `select_by_pk` | `Repo.get` (indexed) | < 2ms |
| `select_where` | `Repo.all` with one `WHERE` on indexed col | < 3ms |
| `select_where_unindexed` | `Repo.all` with seq scan | baseline |
| `groupby_agg` | `SELECT role, count(*), avg(age) GROUP BY role` | < 10ms |
| `join_two_tables` | Inner join users + posts, 100 rows | < 5ms |
| `transaction_1k` | 1,000 single-row inserts in one transaction | < 200ms |
| `pool_10_concurrent` | 10 actors in parallel, pool_size=10 | < 50ms total |
| `query_compile_only` | Compile a 5-clause query to SQL (pure, no IO) | < 10μs |

### Comparisons

Each benchmark is run against these baselines on identical hardware:

| Baseline | Notes |
|----------|-------|
| **Depot (March)** | This library |
| **Postgrex raw** | Elixir — closest protocol-level comparison |
| **Ecto + Postgrex** | Elixir — query builder overhead on top |
| **asyncpg** | Python — fastest async Python PG driver |
| **psycopg2** | Python — synchronous baseline |
| **Diesel** | Rust — compiled query builder |
| **psql -c "..."** | CLI round-trip floor |

### Expected Positioning

Depot should be within 15% of Postgrex (same wire protocol, comparable implementation). The
primary overhead vs. raw psql is the actor pool checkout (~1 actor call round-trip). Depot should
be 3–5× faster than asyncpg due to March's lighter runtime and absence of a GIL.

---

## 14. Open Design Questions

### Q1: Row Deserialization

Currently `Repo.all` returns `List(Map(String, String))` — text values for every column. Users
must manually convert types (`int_of_string(row["age"])`). Options:

- **Option A (current):** Return raw `Map(String, String)`. Simple, no codegen.
- **Option B:** `forge codegen depot` derives a `from_row` function from the type declaration.
  `Repo.all` returns `List(User)` when called with a typed schema.
- **Option C:** A `Repo.decode(row, decoder)` helper where `decoder` is a user-supplied function.
  More flexible than A, less magic than B.

**Recommendation:** Ship Option A in Phase 6; add Option B when `forge codegen` exists.

### Q2: SCRAM-SHA-256 Authentication

PostgreSQL 14+ defaults to SCRAM-SHA-256, deprecating MD5. SCRAM requires:
- SHA-256 (check if `sha256` builtin exists in eval.ml)
- HMAC-SHA-256 (likely needs adding)
- PBKDF2 with configurable iterations (slow in pure March — consider a builtin)

**Decision needed:** Implement pure-March SHA-256 (possible but slow for PBKDF2 iterations), or
add `sha256`/`hmac_sha256`/`pbkdf2` as OCaml builtins?

**Pragmatic answer:** For a dev database with MD5 auth enabled, Phase 3 is unblocked. SCRAM can
be Phase 3.5. Add `sha256` as a builtin — it's one OCaml line and unblocks HTTPS too.

### Q3: `tcp_recv_exact` Builtin

Phase 0 adds `tcp_recv_exact(fd, n)` to eval.ml. This reads exactly `n` bytes, blocking until
all arrive. The current `tcp_recv_all` reads up to a max, which is insufficient for the wire
protocol frame parser. This is a ~10-line change to `eval.ml` but needs a decision on the
builtin name and error semantics.

### Q4: COPY Protocol for Bulk Insert

PostgreSQL's binary `COPY` protocol is 10–100× faster than repeated `INSERT` for large loads.
`bulk_insert_100k` won't hit the 10s target without it. Plan: add `Repo.insert_all(pool, schema,
rows)` in Phase 8 using `COPY FROM STDIN`. Adds ~200 lines of wire protocol code.

### Q5: Prepared Statement Cache

The extended query protocol (Parse/Bind/Execute) re-parses on every call when using unnamed
statements. A per-connection `Map(String, String)` of `sql → statement_name` avoids re-parsing
repeated queries at the cost of statement name management and cache invalidation.

Worth implementing in Phase 6 for the common case of repeated queries in the pool.

### Q6: Connection String DSN Support

Current API uses `PoolOpts` record. Adding DSN parsing:

```march
Depot.Pool.connect("postgres://user:pass@localhost:5432/mydb?pool_size=10")
```

HTTP URL parsing already exists in `stdlib/http.march`. Small addition, good developer UX.

### Q7: TLS / SSL Support

PostgreSQL TLS handshake: the client sends an `SSLRequest` message (a startup message with magic
code 80877103) before the normal startup. The server replies with 'S' (proceed) or 'N' (no TLS).
This requires TLS socket primitives not in March's current TCP builtins.

**Plan for v1:** Document that Depot v1 requires a TLS-terminating proxy (pgbouncer, Cloudflare
Tunnel, stunnel) for encrypted connections. Add TLS in v2 when TLS builtins exist.

### Q8: SQLite Backend (`depot_sqlite`)

When FFI eval dispatch is implemented (see `specs/plans/data-ecosystem-plan.md` Feature 1),
create a separate `forge depot_sqlite new --lib` package that:
- Wraps `libsqlite3` via FFI
- Provides the same `Depot.Schema`/`Depot.Query.Build`/`Depot.Migration` API
- Compiles queries to SQLite-dialect SQL (no `ilike`, different type names, etc.)
- Uses a single connection (no pool — SQLite is single-writer)

Until then, developers wanting SQLite can use `postlite` as a PostgreSQL-protocol proxy.

### Q9: File-Based Migrations

Auto-migration is great for development but production teams typically want:
- A migration history table (`depot_migrations`)
- Named, versioned `.sql` files checked into source control
- Explicit rollback steps

These are additive. Implement auto-migration (Phase 7) first; add a `Depot.Migrate.Files`
module when teams request it.

### Q10: `forge codegen depot`

The most ergonomically painful part of Depot v1 is manually writing the field list in
`Schema.table(...)`. A codegen command that reads `.march` source files and emits schema
registrations automatically would make Depot feel like Ecto.

Implementation path: teach `forge` to parse `.march` files (it already does this for
dependency resolution), extract `type Foo = { ... }` record declarations with a `@[depot.table]`
annotation, and emit a `foo_schema.march` file with the `Schema.table(...)` call.
