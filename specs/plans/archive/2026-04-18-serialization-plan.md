# Serialization & Networking — XML, YAML, TOML, DNS, Sockets

**Status:** Planning
**Date:** 2026-04-18

## Motivation

March has JSON, CSV, Base64, and URI covered. The next tier of real-world
interop requires XML (enterprise APIs, RSS, SVG, HTML parsing), YAML
(infrastructure-as-code, CI configs), and TOML (the dominant config format for
modern tooling — Rust, Python pyproject.toml, Hugo, etc.). DNS lookup and raw
TCP/UDP sockets unblock any networked program that isn't pure HTTP.

The user-experience goal is that the most common case — embed structured data
directly in source — should be a sigil, not a parse call.

## 1. Multi-character sigil lexer extension

### Current state

The lexer accepts `'~' (['A'-'Z'] as c)` — a single uppercase letter. The AST
carries `ESigil of char * expr * span`. Desugaring calls `Sigil.<lower_c>(content)`.

### Required change

Extend to support lowercase multi-character sigil names (`~xml`, `~yaml`, `~toml`):

**Lexer (`lib/lexer/lexer.mll`)**
```ocaml
(* existing — keep *)
| '~' (['A'-'Z'] as c) { SIGIL_PREFIX (String.make 1 c) }

(* new — multi-char lowercase sigil names *)
| '~' (['a'-'z']+ as name) { SIGIL_PREFIX name }
```

Change `%token <char> SIGIL_PREFIX` → `%token <string> SIGIL_PREFIX` everywhere.

**AST (`lib/ast/ast.ml`)**
```ocaml
(* before *)
| ESigil of char * expr * span

(* after *)
| ESigil of string * expr * span
```

**Desugar (`lib/desugar/desugar.ml`)**
```ocaml
| ESigil (name, content, sp) ->
    let content' = desugar_expr content in
    if name = "H" then
      html_interp_to_iolist content' sp   (* ~H unchanged *)
    else
      let fn_name = "Sigil." ^ String.lowercase_ascii name in
      EApp (EVar { txt = fn_name; span = sp }, [content'], sp)
```

All other `ESigil` match arms need updating from `char` to `string` — they only
pattern-match on the tag and are otherwise shape-preserving, so this is
mechanical.

### Resulting sigil dispatch

| Sigil | Desugars to |
|-------|-------------|
| `~H"..."` | `IOList.from_strings([...])` (special-cased, unchanged) |
| `~R"..."` | `Sigil.r("...")` |
| `~J"..."` | `Sigil.j("...")` |
| `~xml"..."` | `Sigil.xml("...")` |
| `~yaml"..."` | `Sigil.yaml("...")` |
| `~toml"..."` | `Sigil.toml("...")` |

---

## 2. TOML module (`stdlib/toml.march`)

TOML is the highest-priority gap — it is the default config format for forge
itself, and any `forge.toml` tooling written in March needs it.

### Types

```march
type TomlValue =
    TStr(String)
  | TInt(Int)
  | TFloat(Float)
  | TBool(Bool)
  | TDatetime(String)   -- RFC 3339, kept as String until DateTime TZ lands
  | TArray(List(TomlValue))
  | TTable(List((String, TomlValue)))

type TomlError = TomlError(String, Int, Int)  -- message, line, col
```

### API

```march
mod Toml do
  fn parse(src : String) : Result(TomlValue, TomlError)
  fn parse_exn(src : String) : TomlValue          -- panics on error
  fn to_string(v : TomlValue) : String
  fn get(v : TomlValue, key : String) : Option(TomlValue)
  fn get_in(v : TomlValue, keys : List(String)) : Option(TomlValue)
  fn get_str(v : TomlValue, key : String) : Option(String)
  fn get_int(v : TomlValue, key : String) : Option(Int)
  fn get_bool(v : TomlValue, key : String) : Option(Bool)
  fn get_table(v : TomlValue, key : String) : Option(TomlValue)
  fn get_array(v : TomlValue, key : String) : Option(List(TomlValue))
end
```

### Sigil handler (`stdlib/sigil.march` addition)

```march
fn toml(content : String) : TomlValue
  Toml.parse_exn(content)
end
```

Usage:
```march
let cfg = ~toml"""
[server]
host = "localhost"
port = 8080

[db]
url = "postgres://..."
pool = 10
"""

let port = Toml.get_int(cfg, "server.port")  -- Some(8080)
```

### Implementation

Pure March parser — no FFI needed. TOML's grammar is simple enough (similar
complexity to JSON, which is already pure March). Implement in ~400 lines
following the same recursive-descent pattern as `json.march`.

---

## 3. YAML module (`stdlib/yaml.march`)

YAML is far more complex than TOML (indentation-sensitive, multiple syntaxes
for the same value, anchors/aliases). Pure March implementation is impractical
for full spec compliance. Use FFI to `libyaml` (C, widely available, small).

### Types

```march
-- YAML value tree (subset: scalars, sequences, mappings)
type YamlValue =
    YNull
  | YBool(Bool)
  | YInt(Int)
  | YFloat(Float)
  | YStr(String)
  | YSeq(List(YamlValue))
  | YMap(List((String, YamlValue)))   -- keys always stringified

type YamlError = YamlError(String, Int, Int)
```

### API

```march
mod Yaml do
  fn parse(src : String) : Result(YamlValue, YamlError)
  fn parse_exn(src : String) : YamlValue
  fn parse_all(src : String) : Result(List(YamlValue), YamlError)  -- multi-document
  fn to_string(v : YamlValue) : String
  fn to_string_pretty(v : YamlValue) : String
  fn get(v : YamlValue, key : String) : Option(YamlValue)
  fn get_in(v : YamlValue, keys : List(String)) : Option(YamlValue)
end
```

### Sigil handler

```march
fn yaml(content : String) : YamlValue
  Yaml.parse_exn(content)
end
```

Usage:
```march
let config = ~yaml"""
services:
  web:
    image: my-app:latest
    ports:
      - "8080:8080"
  db:
    image: postgres:16
"""
```

### Implementation

FFI wrapper around `libyaml`. The C shim (`runtime/march_yaml.c`) calls
`yaml_parser_*`, walks the event stream, and builds a March heap value via the
standard `march_alloc_*` runtime helpers. Link flag: `-lyaml`. Add to
`runtime/dune` as an optional C stubs library; if `libyaml` is absent, the
module is omitted and `Yaml` is not in scope (compile-time absence, not runtime
error).

---

## 4. XML module (`stdlib/xml.march`)

### Types

```march
type XmlNode =
    Element(String, List((String, String)), List(XmlNode))
  --          tag    attributes              children
  | Text(String)
  | CData(String)
  | Comment(String)
  | ProcessingInstruction(String, String)

type XmlDoc = XmlDoc(Option(String), XmlNode)  -- encoding, root

type XmlError = XmlError(String, Int, Int)
```

### API

```march
mod Xml do
  fn parse(src : String) : Result(XmlDoc, XmlError)
  fn parse_exn(src : String) : XmlDoc
  fn to_string(doc : XmlDoc) : String
  fn to_string_pretty(doc : XmlDoc) : String

  -- Navigation
  fn root(doc : XmlDoc) : XmlNode
  fn tag(node : XmlNode) : Option(String)
  fn text(node : XmlNode) : Option(String)
  fn attr(node : XmlNode, name : String) : Option(String)
  fn children(node : XmlNode) : List(XmlNode)
  fn elements(node : XmlNode) : List(XmlNode)  -- children that are Element nodes

  -- Simple path (slash-separated tag names, no XPath)
  fn find(node : XmlNode, path : String) : Option(XmlNode)
  fn find_all(node : XmlNode, path : String) : List(XmlNode)

  -- Construction
  fn elem(tag : String, attrs : List((String, String)), children : List(XmlNode)) : XmlNode
  fn text_node(s : String) : XmlNode
end
```

### Sigil handler

```march
fn xml(content : String) : XmlDoc
  Xml.parse_exn(content)
end
```

Usage:
```march
let doc = ~xml"""
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>March Blog</title>
  <entry>
    <title>Hello</title>
    <content>First post.</content>
  </entry>
</feed>
"""

let titles = Xml.find_all(Xml.root(doc), "entry/title")
```

### Implementation

FFI to `libexpat` (battle-tested, zero-allocation event-driven parser, standard
on macOS and most Linux). Same pattern as YAML: C shim builds the March value
tree. Link flag: `-lexpat`.

For a pure-March fallback: a non-validating subset parser (~300 lines) covering
the 95% case (no DTD, no namespaces in the path API). Ship the pure parser
first, mark it `-- namespace-unaware`, document the limitation.

---

## 5. DNS module (`stdlib/dns.march`)

### Types

```march
type DnsRecord =
    A(String)            -- IPv4
  | AAAA(String)         -- IPv6
  | CNAME(String)
  | MX(Int, String)      -- priority, exchange
  | TXT(List(String))
  | SRV(Int, Int, Int, String)  -- priority, weight, port, target

type DnsError =
    NotFound
  | Timeout
  | ServerError(String)
  | ParseError(String)
```

### API

```march
mod Dns do
  fn lookup_a(host : String) : Task(Result(List(String), DnsError))
  fn lookup_aaaa(host : String) : Task(Result(List(String), DnsError))
  fn lookup_cname(host : String) : Task(Result(String, DnsError))
  fn lookup_mx(host : String) : Task(Result(List(DnsRecord), DnsError))
  fn lookup_txt(host : String) : Task(Result(List(String), DnsError))
  fn lookup_srv(service : String, proto : String, domain : String)
      : Task(Result(List(DnsRecord), DnsError))
  fn resolve(host : String) : Task(Result(String, DnsError))  -- A → first IPv4
end
```

### Implementation

Wrap `getaddrinfo` / `res_query` via C shim
(`runtime/march_dns.c`). All calls are non-blocking — schedule via the existing
`march_io_submit` event loop primitive. No March runtime changes needed; this
fits the same pattern as the HTTP client's async I/O.

---

## 6. Raw sockets (`stdlib/socket.march`)

### Types

```march
type SocketAddr =
    Ipv4(String, Int)   -- "127.0.0.1", port
  | Ipv6(String, Int)
  | Unix(String)        -- path

type Proto = Tcp | Udp

type Socket   -- opaque handle

type SocketError =
    ConnectionRefused
  | Timeout
  | AddressInUse
  | PermissionDenied
  | Closed
  | Io(String)
```

### API

```march
mod Socket do
  -- TCP client
  fn connect(addr : SocketAddr) : Task(Result(Socket, SocketError))

  -- TCP server
  fn bind(addr : SocketAddr) : Task(Result(Socket, SocketError))
  fn listen(sock : Socket, backlog : Int) : Result(Unit, SocketError)
  fn accept(sock : Socket) : Task(Result(Socket, SocketError))

  -- UDP
  fn udp_bind(addr : SocketAddr) : Task(Result(Socket, SocketError))
  fn udp_send(sock : Socket, data : Bytes, addr : SocketAddr) : Task(Result(Int, SocketError))
  fn udp_recv(sock : Socket, buf_size : Int) : Task(Result((Bytes, SocketAddr), SocketError))

  -- Shared I/O
  fn read(sock : Socket, n : Int) : Task(Result(Bytes, SocketError))
  fn read_exact(sock : Socket, n : Int) : Task(Result(Bytes, SocketError))
  fn write(sock : Socket, data : Bytes) : Task(Result(Int, SocketError))
  fn write_all(sock : Socket, data : Bytes) : Task(Result(Unit, SocketError))
  fn close(sock : Socket) : Task(Unit)

  -- Options
  fn set_nodelay(sock : Socket, v : Bool) : Result(Unit, SocketError)
  fn set_timeout(sock : Socket, ms : Int) : Result(Unit, SocketError)
end
```

### Implementation

Thin C shim over POSIX `socket(2)` / `connect(2)` / `accept(2)` / `read(2)` /
`write(2)`, integrated with the event loop via `epoll`/`kqueue` (same path as
`http_transport`). The `Socket` handle wraps a file descriptor.

---

## Implementation order

1. **Multi-char sigil lexer** (compiler change — prerequisite for `~xml`, `~yaml`, `~toml`)
2. **TOML** (pure March, no FFI, unblocks forge.toml tooling)
3. **XML** (pure non-validating parser first; libexpat later)
4. **YAML** (libyaml FFI)
5. **Raw sockets** (fits event loop; prerequisite for custom protocols)
6. **DNS** (after sockets; shares C integration pattern)

Each item is a separate PR. The sigil extension should land first since it is a
compiler change that affects multiple modules.

## Out of scope

- Full XPath / XSLT — path API (`find`/`find_all`) covers 95% of use cases
- YAML 1.1 anchors/aliases in the March API (libyaml resolves them transparently)
- DNS over HTTPS (use `http_client` directly)
- TLS over raw sockets (use `tls.march`)
