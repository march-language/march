---
name: march-lang
description: March programming language reference — syntax, builtins, stdlib API, testing patterns, and common pitfalls. Use this skill whenever working on March source files (.march), writing or fixing March stdlib modules, writing March tests, modifying the March compiler (lexer/parser/AST/desugar/typecheck/eval), or debugging March compilation errors.
---

# March Language Reference

> **Purpose:** Eliminate the 30-turn exploration phase. Read this before writing a single line of March code.

---

## 1. WRONG vs RIGHT — Most Common Bugs

These are the patterns most frequently generated incorrectly. Memorize these.

### Conditionals: `then` does not exist

```march
-- WRONG: March has no `then` keyword
if x > 0 then x end

-- RIGHT
if x > 0 do x end

-- RIGHT with else
if x > 0 do
  x
else
  0
end
```

### Lambdas: only arrow form, never `do...end`

```march
-- WRONG: lambdas cannot use do...end blocks
let f = fn x do x + 1 end
List.map(xs, fn x do x * 2 end)

-- RIGHT
let f = fn x -> x + 1
List.map(xs, fn x -> x * 2)
```

### Zero-arg lambdas: must use `fn () ->`

```march
-- WRONG: `fn -> expr` is a parse error
let f = fn -> 42

-- WRONG: `fn _ ->` is a 1-arg lambda (calling with 0 args = "arity mismatch: expected 1, got 0")
let f = fn _ -> 42
f()   -- ERROR

-- RIGHT
let f = fn () -> 42
f()   -- OK
```

### Multi-line lambda bodies: use let chains after `->`

```march
-- WRONG: fn (x) do ... end is not valid syntax
let f = fn (x) do
  let y = x + 1
  y * 2
end

-- RIGHT: use let bindings after ->
let f = fn (x) ->
  let y = x + 1
  y * 2
```

### Visibility: no `pub` keyword, no `module` keyword

```march
-- WRONG
pub fn my_function(x : Int) : Int do x end
module Foo do ... end

-- RIGHT
fn my_function(x : Int) : Int do x end   -- public
pfn helper(x : Int) : Int do x end       -- private
mod Foo do ... end
```

### Type variants: no leading `|`

```march
-- WRONG
type Color = | Red | Green | Blue

-- RIGHT
type Color = Red | Green | Blue

-- RIGHT with payloads
type Shape = Circle(Float) | Rect(Float, Float) | Point
```

### HTTP method matching: returns Atom, not a Method type

```march
-- WRONG: no Method type; HttpServer.method() returns an Atom
match HttpServer.method(conn) do
  Get  -> ...
  Post -> ...
end

-- RIGHT: use atom literals
match HttpServer.method(conn) do
  :get  -> ...
  :post -> ...
  _     -> ...
end
```

### `do` is required after `if`, `match`, `mod`

```march
-- WRONG: missing do
if x > 0
  x
end

match xs
  Nil -> 0
  Cons(h, _) -> h
end

-- RIGHT
if x > 0 do x end

match xs do
  Nil        -> 0
  Cons(h, _) -> h
end
```

### Multi-head functions are supported

```march
-- OK: multi-head syntax (parser merges into single EMatch)
fn fib(0) do 0 end
fn fib(1) do 1 end
fn fib(n) do fib(n-1) + fib(n-2) end
```

---

## 2. March Syntax Quick Reference

### Modules

```march
mod ModuleName do
  -- declarations here
end
```

### Functions

```march
-- Public (visible outside module)
fn name(param1 : Type1, param2 : Type2) : ReturnType do
  body
end

-- Private (module-internal)
pfn name(param : Type) : ReturnType do
  body
end

-- Multi-head (pattern-matched)
fn fact(0) do 1 end
fn fact(n) do n * fact(n - 1) end
```

### Lambdas (always arrow form)

```march
fn x -> x + 1                  -- single param
fn (a, b) -> a + b             -- multiple params
fn () -> 42                    -- zero args (MUST use `()`)
fn _ -> 42                     -- one-arg wildcard (ignores arg)
fn (x, _) -> x                 -- tuple destructure
```

### Types

```march
-- Sum type (no leading |)
type Shape = Circle(Float) | Rect(Float, Float) | Point

-- Generic type
type Option(a) = None | Some(a)
type Result(a, e) = Ok(a) | Err(e)
type List(a) = Nil | Cons(a, List(a))

-- Private type
ptype Tree = Leaf(Int) | Node(Tree, Tree)
```

### Pattern Matching

```march
match expr do
  Pattern1          -> result1
  Pattern2(x)       -> result2
  Pattern3(a, b)    -> result3
  _                 -> default
end

-- Multi-expression arm (use let bindings)
match expr do
  Some(v) ->
    let y = v + 1
    let z = y * 2
    z
  None -> 0
end

-- Nested patterns
match pair do
  (Some(x), Some(y)) -> x + y
  (Some(x), None)    -> x
  (None,    _)       -> 0
end
```

### If / Else

```march
if condition do expr end

if condition do
  then_expr
else
  else_expr
end

-- Single-line
if x > 0 do x else 0 end
```

### Let Bindings (no `in`, newlines separate)

```march
let x = 1 + 2
let y = x * 3
y + 1    -- last expr in block is the result
```

### Pipe Operator

```march
x |> f           -- f(x)
x |> f(a)        -- f(x, a)   (x inserted as first arg)

-- Chain
value
|> transform1
|> transform2(arg)
|> transform3
```

### String Concatenation (no interpolation syntax)

```march
"Hello " ++ name ++ "!"
"Count: " ++ int_to_string(n)
```

### Doc Strings

```march
doc "Single-line documentation."
fn my_fn(x : Int) : Int do x end

doc """
Multi-line documentation.
"""
fn another_fn() : Unit do () end
```

### Atoms

```march
:get  :post  :put  :delete  :patch
:ok   :error :true :false
```

### Tuples

```march
let pair = (1, "hello")
let (a, b) = pair             -- destructure in let
fn f((x, y)) -> x + y        -- destructure in param
```

### Lists

```march
Nil                           -- empty list
Cons(1, Cons(2, Nil))         -- linked list (prefer List.range/stdlib)

match xs do
  Nil        -> ...
  Cons(h, t) -> ...
end
```

### Visibility summary

| Syntax | Visibility |
|--------|------------|
| `fn name(...)` | Public |
| `pfn name(...)` | Private |
| `type Foo = ...` | Public |
| `ptype Foo = ...` | Private |

---

## 3. Forge Commands

```bash
# Project creation
forge new my_app            # application
forge new my_lib --lib      # library
forge new my_tool --tool    # CLI tool

# Build & run
forge build                 # compile to .march/build/debug/<name>
forge build --release       # optimized binary
forge run                   # interpret directly (fast dev)
forge build --dump-phases   # emit IR to .march/phases/phases.json

# Testing
forge test                  # run all tests under test/
forge test --verbose
forge test --filter PATTERN
forge test --coverage

# Code quality
forge format                # format all .march files
forge format --check        # check only
forge format --stdin        # editor integration

# REPL
forge interactive           # launch REPL with project context
forge i                     # alias

# Dependencies
forge deps                  # install from forge.toml
forge deps update           # update all
forge deps update NAME      # update one
forge install PATH_OR_URL   # install as system CLI tool

# Search (Hoogle-style)
forge search map                               # name search (fuzzy)
forge search "" --type "String -> Int"         # type signature search
forge search "" --doc "concatenate"            # doc keyword search
forge search fold --type List --pretty         # combined, table output
forge search "" --json > out.json              # JSON output
forge search sort --rebuild                    # force index rebuild
forge search map --limit 5

# Bastion web framework
forge bastion new my_app         # scaffold Bastion web app
forge bastion server             # dev server (default port 4000)
forge bastion server --port 8080
forge bastion routes             # list all routes
forge bastion gen schema User users name:string email:string age:int

# Database migrations (Depot)
forge depot migrate              # apply pending migrations
forge depot rollback             # rollback last
forge depot rollback --step 3
forge depot migrations           # show migration status
forge depot reset                # rollback all, re-apply
forge depot gen migration create_users

# Asset pipeline
forge assets build               # bundle for dev
forge assets deploy              # bundle + minify for production
forge assets watch               # watch and rebuild

# Compiler inspection
forge phases                     # serve phase viewer at localhost:7777
forge phases --port 9000

# Cleaning
forge clean                      # remove .march/build/
forge clean --cas                # also remove cached dependencies
forge clean --all                # remove entire .march/

# Publishing
forge publish --dry-run
forge publish --old-source ./v1  # semver check
```

---

## 4. Forge Search (Hoogle-style)

Index cached at `.march/search-index.json`, built from stdlib.

### Query modes (AND semantics when combined)

```bash
# Name search: exact > substring > fuzzy Levenshtein
forge search filter             # finds "filter", "filter_map", etc.
forge search flt                # fuzzy: finds "filter", "flat_map"

# Type signature (all components must appear in signature)
forge search "" --type "String -> Int"
forge search "" --type "List(a), a -> Bool"

# Doc keyword (all keywords must appear in doc string)
forge search "" --doc "sort stable"

# Combined
forge search fold --type "List" --doc "accumulator"
```

### Direct compiler search (no forge)

```bash
dune exec march -- -search "String -> Int"
dune exec march -- -search "filter"
```

---

## 5. Stdlib Manifest

All 76 stdlib modules loaded by `bin/main.ml`:

### Auto-imported (Prelude)

Functions always in scope without `use`:
- `panic(msg: String) : a` — runtime error
- `todo(msg: String) : a` — unimplemented marker
- `unreachable() : a`
- `unwrap(opt: Option(a)) : a` — panics on None
- `unwrap_or(opt: Option(a), default: a) : a`
- `head(xs) / tail(xs) / is_nil(xs) / length(xs) / reverse(xs)`
- `fold_left(acc, xs, f) / filter(xs, pred) / map(xs, f)`
- `identity(x) / compose(f, g) / flip(f) / const(x, _)`
- `debug(x) / inspect(label, x)` — tap for debugging

### Data Structures

**Option** — `is_some`, `is_none`, `expect`, `unwrap`, `unwrap_or`, `unwrap_or_else`, `map`, `flat_map`, `filter`, `or_else`, `zip`, `to_result`, `to_list`

**Result** — `is_ok`, `is_err`, `expect`, `unwrap`, `unwrap_err`, `unwrap_or`, `map`, `map_err`, `flat_map`, `or_else`, `collect`, `to_option`

**List** — `empty`, `singleton`, `repeat`, `range`, `range_step`, `head`, `tail`, `head_opt`, `tail_opt`, `last`, `nth`, `nth_opt`, `length`, `is_empty`, `reverse`, `append`, `map`, `flat_map`, `filter`, `filter_map`, `fold_left`, `fold_right`, `scan_left`, `concat`, `intersperse`, `find`, `find_index`, `any`, `all`, `sort_by`, `take`, `drop`, `take_while`, `drop_while`, `split_at`, `partition`, `drop_last`, `chunks`, `zip`, `zip_with`, `unzip`, `enumerate`, `sum_int`, `product_int`, `minimum_int`, `maximum_int`, `member`, `dedup`

**Map** (AVL tree, needs comparator) — `get`, `insert`, `remove`, `keys`, `values`, `fold`, `from_list`, `filter`, `merge`, `merge_with`

**HAMT** (hash array mapped trie) — `get`, `insert`, `remove`, `fold`

**Set** — `new`, `contains`, `insert`, `remove`, `union`, `intersection`, `difference`, `from_list`, `to_list`, `fold`, `eq`

**OrderedMap** — `new`, `get`, `put`, `remove`, `keys`, `values`

**SortedSet** — `new`, `insert`, `remove`, `contains`, `to_list`

**Queue** — `new`, `enqueue`, `dequeue`, `peek`, `is_empty`, `length`, `pop_front`, `pop_back`

**Array** — `empty`, `length`, `is_empty`, `get`, `set`, `push`, `pop`, `map`, `fold_left`, `to_list`, `from_list`

**NativeArray** — `new`, `length`, `get`, `set`, `fill`

**Tuple** — `first`, `second`, `swap`, `map_first`, `map_second`

**Range** — `new`, `to_list`, `each`, `map`, `filter`

### Strings / Text

**String** — `byte_size`, `slice_bytes`, `contains`, `starts_with`, `ends_with`, `concat`, `replace`, `replace_all`, `split`, `split_first`, `join`, `trim`, `trim_start`, `trim_end`, `to_uppercase`, `to_lowercase`, `repeat`, `reverse`, `pad_left`, `pad_right`, `is_empty`, `grapheme_count`, `index_of`, `last_index_of`, `to_int`, `to_float`, `from_int`, `from_float`

**Char** — `code`, `from_code`, `is_ascii`, `is_alpha`, `is_digit`, `is_whitespace`, `is_uppercase`, `is_lowercase`, `to_uppercase`, `to_lowercase`

**IOList** — `empty`, `from_string`, `append`, `prepend`, `push`, `from_strings`, `to_string`, `byte_size`, `is_empty`, `hash`

**Regex** — `compile`, `matches`, `find`, `find_all`, `replace`, `replace_all`, `split`

**CSV** — `parse`, `parse_with_options`, `to_string`, `to_string_with_options`

**Bytes** — `length`, `is_empty`, `from_string`, `to_string`, `from_hex`, `to_hex`, `concat`, `slice`, `reverse`, `map`

### Math / Numbers

**Math** — `abs`, `floor`, `ceil`, `round`, `sqrt`, `pow`, `sin`, `cos`, `tan`, `log`, `log10`, `exp`, `max`, `min`, `lerp`, `pi`, `e`

**BigInt** — `zero`, `one`, `neg_one`, `from_int`, `to_string`, `neg`, `abs`, `add`, `sub`, `mul`, `div`, `mod`, `eq`, `compare`, `show`, `hash`

**Decimal** — `from_string`, `from_int`, `from_float`, `to_string`, `to_int`, `to_float`, `add`, `sub`, `mul`, `div`, `round`, `abs`, `neg`, `eq`, `compare`, `show`

**Stats** — `mean`, `median`, `stdev`, `percentile`, `variance`, `variance_pop`, `mode`, `covariance`, `correlation`, `linear_regression`

**Random** — `new`, `int`, `float`, `bool`, `choice`, `shuffle`, `sample`

**DateTime** — `now`, `from_timestamp`, `to_timestamp`, `diff_seconds`, `compare`, `day_of_week`, `format`, `parse`

**Duration** — `new`, `to_milliseconds`, `to_seconds`, `add`, `subtract`, `multiply`, `compare`, `format`

### Encoding / Crypto

**Base64** — `encode`, `decode`, `url_encode`, `url_decode`, `mime_encode`

**Crypto** — `sha256`, `sha512`, `hmac`, `hash_password`, `verify_password`, `random_bytes`, `random_hex`, `secure_compare`, `base64_encode`, `base64_decode`, `base64_url_encode`, `base64_url_decode`

**UUID** — `v4`, `parse`, `to_string`, `nil`, `v5`, `version`, `is_valid`

**URI** — `parse`, `to_string`, `encode`, `decode`, `encode_query`, `decode_query`, `merge`

**JSON** — `parse`, `to_string`, `get`, `get_in` (constructors: `String`, `Number`, `Bool`, `Null`, `Array`, `Object`)

### IO / Files

**File** — `read`, `read_lines`, `exists`, `stat`, `write`, `append`, `delete`, `copy`, `rename`, `with_lines`, `with_chunks`

**Dir** — `list`, `list_full`, `mkdir`, `mkdir_p`, `rmdir`, `rm_rf`, `exists`

**Path** — `join`, `normalize`, `dirname`, `basename`, `extension`, `absolute`, `relative`, `exists`

**Env** — `get`, `get_int`, `get_bool`, `get_all`, `set`, `require`, `require_int`

**Logger** — `debug`, `info`, `warn`, `error`, `log_with`

### Networking / HTTP

**Http** — `method_to_string`, `status_code`, `status_ok`…`status_server_error`, `is_informational`…`is_server_error`, request accessors (`method`/`scheme`/`host`/`port`/`path`/`query`/`headers`/`body`), setters (`set_method`…`set_path`)

**HttpTransport** — `connect`, `request_on`, `stream_request_on`, `request`, `simple_get`

**HttpClient** — `new_client`, `add_request_step`, `with_redirects`, `with_retry`, `run`, `get`, `post`, `put_request`, `delete`, `stream_get`; steps: `step_default_headers`, `step_bearer_auth`, `step_basic_auth`, `step_base_url`, `step_content_type`, `step_raise_on_error`

**HttpServer** — `method`, `path`, `path_info`, `query_string`, `req_headers`, `req_body`, `get_req_header`, `get_resp_header`, `get_assign`, `put_resp_header`, `assign`, `send_resp`, `halt`, `text`, `json`, `html`, `redirect`, `run_pipeline`, `new`, `plug`, `max_connections`, `idle_timeout`

**TLS** — `default_client_config`, `h2_client_config`, `server_config`, `client_ctx`, `server_ctx`, `connect`, `accept`, `read`, `write`, `close`, `ctx_free`, `negotiated_alpn`, `peer_cn`, `https_get`

**WebSocket** — `new`, `send`, `receive`, `close`, `is_open`

### Actors / Concurrency

**Process** — `spawn`, `exit`, `monitor`, `demonitor`, `self_pid`, `send`

**Actor** — `cast`, `call`, `reply`

**Task** — `async`, `await`, `await_ms`, `await_unwrap`, `await_many`, `await_many_ms`, `async_stream`, `async_stream_n`

**Channel** — `new`, `join`, `leave`, `push`, `broadcast`, `broadcast_from`, `serialize`, `parse`

**PubSub** — `new`, `subscribe_state`, `unsubscribe_state`, `broadcast`, `broadcast_from`, `topic_shard`, `topic_matches`, `broadcast_to`

**Presence** — `new`, `track_state`, `untrack_state`, `list_state`, `count_presences`, `is_present`, `connection_count`, `track`, `untrack`

**Flow** — `unfold`, `with_concurrency`

**Seq** — `fold`, `map`, `filter`, `take`, `drop`, `concat`, `zip_with`, `batch`, `fold_while`

### State / Storage

**Vault** (in-memory ETS-style store) — `new`, `set`, `get`, `drop`, `set_ttl`, `update`, `whereis`, `keys`

**Config** — `from_env`, `from_env_int`, `from_env_bool`, `env`, `validate`, `put_endpoint`, `new_store`, `secret_key_base`

### Functional Utilities

**Enum** — `map`, `flat_map`, `filter`, `fold`, `reduce`, `each`, `count`, `group_by`, `zip_with`, `sort_by`, `timsort_by`, `introsort_by`, `sort_small_by`

**Sort** — `by`, `mergesort_by`, `sort_small_by`, `insertion_sort_by`, `timsort_by`, `introsort_by`

**Iterable** — `fold`

### Web Framework (Bastion)

**Html** — `escape`, `raw`, `safe_to_string`, `list`, `join`, `escape_attr`, `tag`, `render_partial`, `render_collection`, `layout`, `content_hash`

**Sigil** — `h(content)` (safe HTML)

**Islands** — `wrap`, `wrap_with_dataflow`, `wrap_eager`, `client_only`, `wrap_with_css`, `bootstrap_script`, `preload_hint`, `empty_registry`, `register`, `registry_descriptors`, `find_island`

**CSRF** — `generate_token`, `token`, `ensure_token`, `tag`, `tag_string`, `validate`, `protect`, `skip`

**Session** — `new`, `load`, `save`, `save_with_opts`, `get`, `put`, `delete`, `clear`, `put_flash`, `get_flash`, `initialized`, `all`

**Bastion** — `etag`, `cached`, `fragment`, `invalidate`, `cache_control`, `no_cache`, `public_cache`, `path`, `serve`, `static_path`, `js_bundle_path`, `css_bundle_path`, `error_tag`

**BastionCookies** — `default_opts`, `put_signed`, `get_signed`, `put_encrypted`, `get_encrypted`, `delete`

**BastionCSP** — `assign_nonce`, `get_nonce`, `protect`, `protect_with_overrides`, `disable`, `report_only`

**BastionRoutes** — `register`, `all`, `path`, `static_path`, `path1`, `path2`

**BastionPubSub** — `subscribe`, `broadcast`, `broadcast_from`, `local_broadcast_sync`, `inbox`

**BastionTelemetry** — `attach`, `detach`, `execute`, `recent_events`, `start`, `record`, `counters`

**BastionDev** — `request_timer`, `finish_timer`, `server_timing`, `conn_inspector`, `live_reload_script`, `inject_live_reload`, `live_reload_handler`, `error_overlay`, `dashboard_handler`

**BastionHotDeploy** — `default_config`, `get_status`, `is_draining`, `start_drain`, `increment_in_flight`, `decrement_in_flight`, `health_status`, `drain_response`

**BastionIdempotency** — `get_key`, `lookup`, `mark_in_progress`, `complete_entry`, `replay_response`, `protect`

**BastionTestSandbox** — `checkout`, `release`, `vault_get`, `build_conn`, `build_conn_full`, `is_active`, `active_count`

### Database (Depot)

**Depot.Schema** — `field`, `references`, `timestamps`

**Depot.Repo** — `insert`, `update`, `delete`, `get`, `list`

**Depot.Query** — `where`, `select`, `order_by`, `limit`, `offset`

**Depot.Migration** — `up`, `down`

**Depot.Gate** — `build`, `allow`, `deny`

**Depot.Test** — `start_sandbox`, `checkout`, `checkin`, `stop_sandbox`, `sandboxed`, `active`

### Testing

**Test** — `fail`, `assert_true`, `assert_false`, `assert_eq_int`, `assert_eq_str`, `assert_eq_bool`, `assert_some`, `assert_none`, `assert_ok`, `assert_err`

### Data Science

**DataFrame** — `from_columns`, `from_rows`, `inner_join`, `left_join`, `right_join`, `outer_join`, `summarize`, `sample`, `train_test_split`, `col_add_float`, `col_mul_float`, `col_add_col`, `window`, `melt`, `pivot`

**Plot** — `line_plot`, `bar_chart`, `scatter_plot`, `histogram`

---

## 6. Idiomatic March Code Examples

### Tail-recursive accumulator pattern (canonical idiom)

```march
fn reverse(xs : List(a)) : List(a) do
  fn go(lst : List(a), acc : List(a)) : List(a) do
    match lst do
    Nil        -> acc
    Cons(h, t) -> go(t, Cons(h, acc))
    end
  end
  go(xs, Nil)
end

fn length(xs : List(a)) : Int do
  fn go(lst : List(a), acc : Int) : Int do
    match lst do
    Nil        -> acc
    Cons(_, t) -> go(t, acc + 1)
    end
  end
  go(xs, 0)
end
```

### Recursive Fibonacci (from `bench/fib.march`)

```march
mod Fib do
pfn fib(n : Int) : Int do
  if n < 2 do n
  else fib(n - 1) + fib(n - 2) end
end

pfn main() : Unit do
  println(int_to_string(fib(40)))
end
end
```

### Custom type with HOFs (from `bench/list_ops.march`)

```march
ptype IntList = INil | ICons(Int, IntList)

pfn imap(xs : IntList, f : Int -> Int) : IntList do
  pfn go(lst : IntList, acc : IntList) : IntList do
    match lst do
    INil        -> irev(acc, INil)
    ICons(h, t) -> go(t, ICons(f(h), acc))
    end
  end
  go(xs, INil)
end

pfn main() : Unit do
  let xs    = irange(1, 1000000)
  let ys    = imap(xs, fn x -> x * 2)
  let zs    = ifilter(ys, fn x -> x % 3 == 0)
  let total = ifold(zs, 0, fn (a, b) -> a + b)
  println(int_to_string(total))
end
```

### HTTP server with pipe + atom matching (from `examples/http_hello.march`)

```march
mod HttpHello do
fn router(conn) do
  match (HttpServer.method(conn), HttpServer.path_info(conn)) do
  (:get, Nil)                   -> conn |> HttpServer.text(200, "Hello!")
  (:post, Cons("users", Nil))   -> create_user(conn)
  _                             -> conn |> HttpServer.text(404, "Not Found")
  end
end

fn main() do
  HttpServer.new(8080)
  |> HttpServer.plug(router)
  |> HttpServer.listen()
end
end
```

### Binary tree with pattern matching (from `bench/binary_trees.march`)

```march
ptype Tree = Leaf | Node(Tree, Int, Tree)

pfn insert(t : Tree, v : Int) : Tree do
  match t do
  Leaf          -> Node(Leaf, v, Leaf)
  Node(l, x, r) ->
    if v < x do Node(insert(l, v), x, r)
    else if v > x do Node(l, x, insert(r, v))
    else t end
  end
end
```

### Parallel tasks (from `bench/parallel.march`)

```march
pfn par_sum(t : Tree, depth : Int, threshold : Int) : Int do
  match t do
  Leaf(n) -> n
  Node(l, r) ->
    if depth >= threshold do sum(l) + sum(r)
    else
      let tl = task_spawn(fn () -> par_sum(l, depth + 1, threshold))
      let tr = task_spawn(fn () -> par_sum(r, depth + 1, threshold))
      task_await_unwrap(tl) + task_await_unwrap(tr)
    end
  end
end
```

### Actor system (from `examples/actors.march`)

```march
actor Counter do
  state { value : Int }
  init { value = 0 }

  on Increment(n : Int) do
    { state with value = state.value + n }
  end

  on Reset() do
    { state with value = 0 }
  end
end

fn main() : Unit do
  let pid = spawn(Counter)
  send(pid, Increment(10))
  send(pid, Increment(5))
end
```

### Option chaining

```march
fn find_and_double(xs : List(Int), pred : Int -> Bool) : Option(Int) do
  xs
  |> List.find(pred)
  |> Option.map(fn x -> x * 2)
end
```

### Result collection

```march
fn parse_all(inputs : List(String)) : Result(List(Int), String) do
  inputs
  |> List.map(fn s -> String.to_int(s)
               |> Option.to_result("not a number: " ++ s))
  |> Result.collect
end
```

---

## 7. Builtins Reference

Directly callable without module qualification (built into the evaluator).

### Arithmetic operators

```
+   -.  *   *.  /   /.  %   ++  &&  ||  not
```

### Integer

| Builtin | Description |
|---------|-------------|
| `int_to_float(n)` | Convert Int to Float |
| `int_to_string(n)` | Convert Int to String |
| `int_abs(n)` | Absolute value |
| `int_pow(base, exp)` | Power |
| `int_div(a, b)` / `int_mod(a, b)` | Division / modulo |
| `int_div_euclid(a, b)` / `int_mod_euclid(a, b)` | Euclidean |
| `int_and(a, b)` / `int_or` / `int_xor` / `int_not` | Bitwise |
| `int_shl(n, k)` / `int_shr` | Bit shifts |
| `int_popcount(n)` | Count set bits |
| `int_max_value` / `int_min_value` | Bounds |

### Float

| Builtin | Description |
|---------|-------------|
| `float_to_int(f)` | Truncate to Int |
| `float_to_string(f)` | To String |
| `float_abs(f)` | Absolute value |
| `float_floor(f)` / `float_ceil` / `float_round` / `float_truncate` | Rounding |
| `float_is_nan(f)` / `float_is_infinite(f)` | Checks |
| `float_infinity` / `float_neg_infinity` / `float_nan` / `float_epsilon` | Constants |
| `float_from_string(s)` / `string_to_float(s)` | Parse |

### Math

| Builtin | Description |
|---------|-------------|
| `math_sqrt(x)` / `math_cbrt(x)` | Roots |
| `math_pow(x, y)` | Power |
| `math_exp(x)` / `math_exp2` | Exponential |
| `math_log(x)` / `math_log2` / `math_log10` | Logarithm |
| `math_sin(x)` / `math_cos` / `math_tan` | Trig |
| `math_asin` / `math_acos` / `math_atan` / `math_atan2(y,x)` | Inverse trig |
| `math_sinh` / `math_cosh` / `math_tanh` | Hyperbolic |

### String

| Builtin | Description |
|---------|-------------|
| `string_length(s)` | Character count |
| `string_byte_length(s)` | Byte count |
| `string_concat(a, b)` | Concatenate |
| `string_is_empty(s)` | Empty check |
| `string_slice(s, start, len)` | Byte-indexed slice |
| `string_contains(s, sub)` | Substring check |
| `string_starts_with(s, pre)` / `string_ends_with(s, suf)` | Prefix/suffix |
| `string_index_of(s, sub)` / `string_last_index_of` | Find |
| `string_replace(s, old, new)` / `string_replace_all` | Replace |
| `string_split(s, sep)` / `string_split_first` | Split |
| `string_join(xs, sep)` | Join list |
| `string_trim(s)` / `string_trim_start` / `string_trim_end` | Trim |
| `string_to_uppercase(s)` / `string_to_lowercase` | Case |
| `string_chars(s)` / `string_from_chars(cs)` | Char list conversion |
| `string_repeat(s, n)` / `string_reverse(s)` | Transform |
| `string_pad_left(s, w, fill)` / `string_pad_right` | Padding |
| `string_grapheme_count(s)` | Unicode graphemes |
| `string_to_int(s)` | Parse → Option(Int) |
| `bool_to_string(b)` | Bool to string |

### Char

| Builtin | Description |
|---------|-------------|
| `char_is_alpha(c)` / `char_is_digit` / `char_is_alphanumeric` | Category |
| `char_is_whitespace(c)` / `char_is_uppercase` / `char_is_lowercase` | Category |
| `char_to_uppercase(c)` / `char_to_lowercase` | Case |
| `char_to_int(c)` / `char_from_int(n)` | Code point |
| `byte_to_char(b)` | Byte to char |

### List (primitive)

| Builtin | Description |
|---------|-------------|
| `head(xs)` | First (panics if empty) |
| `tail(xs)` | Rest (panics if empty) |
| `is_nil(xs)` | Empty check |

### IO

| Builtin | Description |
|---------|-------------|
| `print(x)` / `println(x)` | Print |
| `print_int(n)` / `print_float(f)` | Typed print |
| `read_line()` | Read from stdin |
| `tap(x)` | Print and return |

### Map (hash map)

| Builtin | Description |
|---------|-------------|
| `record_get(m, key)` / `record_put(m, key, val)` | Get/set |
| `record_has_key(m, key)` | Key check |
| `record_keys(m)` / `record_values(m)` / `record_entries(m)` | Iteration |
| `record_from_list(pairs)` | Create from list |

### Actors / Process

| Builtin | Description |
|---------|-------------|
| `self` | Own PID |
| `spawn(actor)` | Spawn actor |
| `send(pid, msg)` | Send message |
| `receive` | Receive message |
| `kill(pid)` | Kill actor |
| `is_alive(pid)` | Liveness check |
| `monitor(pid)` / `demonitor(ref)` | Monitor |
| `link(pid)` | Link actors |
| `mailbox_size(pid)` | Mailbox size |
| `actor_cast(pid, msg)` | Async send |
| `actor_call(pid, msg, timeout)` | Sync send |
| `actor_reply(ref, result)` | Reply to call |

### Tasks

| Builtin | Description |
|---------|-------------|
| `task_spawn(f)` | Spawn task |
| `task_await(t)` | Await result |
| `task_await_unwrap(t)` | Await and unwrap |
| `task_yield()` | Yield scheduler |
| `task_spawn_steal(f)` | Work-stealing spawn |
| `task_spawn_link(f)` | Linked task spawn |

### Network / TLS

| Builtin | Description |
|---------|-------------|
| `tcp_connect(host, port)` | Connect |
| `tcp_send_all(fd, data)` / `tcp_recv_all(fd)` | Send/receive |
| `tcp_recv_exact(fd, n)` | Receive n bytes |
| `tcp_close(fd)` | Close |
| `tls_connect(fd, ctx, host)` | TLS connect |
| `tls_read(conn, n)` / `tls_write(conn, data)` | TLS IO |
| `tls_close(conn)` | TLS close |

### Crypto

| Builtin | Description |
|---------|-------------|
| `sha256(data)` / `sha512(data)` / `sha1(data)` | Hash |
| `hmac_sha256(key, data)` | HMAC-SHA256 |
| `pbkdf2_sha256(pass, salt, iter, len)` | PBKDF2 |
| `base64_encode(data)` / `base64_decode(s)` | Base64 |
| `random_bytes(n)` | Secure random bytes |
| `uuid_v4()` | Generate UUID v4 |
| `md5(data)` | MD5 hash |

### System

| Builtin | Description |
|---------|-------------|
| `unix_time()` | Current Unix timestamp |
| `sys_uptime_ms()` | Uptime in ms |
| `sys_heap_bytes()` | Heap memory usage |
| `sys_cpu_count()` | CPU count |
| `sys_actor_count()` | Live actor count |
| `process_env(name)` / `process_set_env(name, val)` | Env vars |
| `process_cwd()` | Working directory |
| `process_exit(code)` | Exit process |
| `process_argv()` | Command-line args |
| `process_spawn_sync(cmd, args)` | Spawn subprocess |

### Utility

| Builtin | Description |
|---------|-------------|
| `panic(msg)` | Runtime error |
| `todo(msg)` | Unimplemented marker |
| `unreachable()` | Assert unreachable |
| `eq(a, b)` | Structural equality |
| `compare(a, b)` | Comparison (-1/0/1) |
| `hash(x)` | Hash value |
| `show(x)` | Pretty print |
| `to_string(x)` | Coerce to string |
| `negate(n)` | Negate number |

---

## 8. Compiler Pipeline

### Interpreter path (used by `dune exec march`, `forge run`, tests)

```
Source (.march)
  → Lexer (lib/lexer/lexer.mll)           -- ocamllex tokenizer
  → Token Filter                           -- lookahead for do/end disambiguation
  → Parser (lib/parser/parser.mly)         -- menhir LR parser → AST
  → Desugar (lib/desugar/desugar.ml)       -- pipe desugar, multi-head fn → EMatch
  → Typecheck (lib/typecheck/typecheck.ml) -- bidirectional HM type inference
  → Eval (lib/eval/eval.ml)               -- tree-walking interpreter
```

Key desugar transformations:
- `x |> f` → `f(x)`, `x |> f(a)` → `f(x, a)`
- Multi-head `fn foo(0)…; fn foo(n)…` → single `fn foo` with `EMatch`
- Block `let` without `in` → nested let expressions

### Compiled path (used by `forge build`)

```
Source → Lexer → Parser → Desugar → Typecheck
  → TIR Lower (lib/tir/lower.ml)          -- typed intermediate representation
  → Mono (lib/tir/mono.ml)                -- monomorphization
  → Defun (lib/tir/defun.ml)              -- defunctionalization / closure conversion
  → Perceus (lib/tir/perceus.ml)          -- reference counting (FBIP)
  → Borrow (lib/tir/borrow.ml)            -- borrow analysis
  → Fusion (lib/tir/fusion.ml)            -- loop fusion / deforestation
  → LLVM Emit (lib/tir/llvm_emit.ml)      -- LLVM IR → native binary
```

Key files:
- `bin/main.ml` — entry point, stdlib loading, CLI flags (`-search`, `-compile`, etc.)
- `lib/ast/ast.ml` — AST types: `span`, `expr`, `pattern`, `decl`
- `lib/errors/errors.ml` — `Error`/`Warning`/`Hint` diagnostic type with span
- `lib/search/search.ml` — Hoogle-style search engine
- `lib/jit/` — REPL JIT compiler

---

## 9. Testing Patterns

### Test file structure (`test/test_march.ml`, ~19k lines, Alcotest)

```ocaml
(* Helper functions *)
let parse_module src =
  let lexbuf = Lexing.from_string src in
  March_parser.Parser.module_
    (March_parser.Token_filter.make March_lexer.Lexer.token) lexbuf

let parse_and_desugar src =
  March_desugar.Desugar.desugar_module (parse_module src)

let typecheck src =
  let m = parse_and_desugar src in
  let (errors, _) = March_typecheck.Typecheck.check_module m in
  errors

(* Check for type errors *)
let test_valid () =
  let ctx = typecheck {|mod T do fn f(x : Int) : Int do x end end|} in
  Alcotest.(check bool) "no errors" false (March_errors.Errors.has_errors ctx)

(* Eval and check result *)
let eval_module src =
  let m = parse_and_desugar src in
  ignore (March_typecheck.Typecheck.check_module m);
  March_eval.Eval.run_module m

let vint = function March_eval.Eval.VInt n -> n | _ -> failwith "not VInt"

let test_eval_fib () =
  let env = eval_module {|mod T do
    fn fib(0) do 0 end
    fn fib(1) do 1 end
    fn fib(n) do fib(n-1) + fib(n-2) end
    fn main() do fib(10) end
  end|} in
  let v = March_eval.Eval.call_fn env "main" [] in
  Alcotest.(check int) "fib(10)" 55 (vint v)
```

### How to add a test

1. Write `let test_my_feature () = ...` in `test/test_march.ml`
2. Add to the test list at the bottom:
   ```ocaml
   ("category", [
     Alcotest.test_case "my feature" `Quick test_my_feature;
   ])
   ```
3. Run `dune runtest`

Speed markers: `` `Quick `` (fast), `` `Slow `` (longer).

### Build commands

```bash
dune build        # build everything
dune runtest      # run all tests
# opam switch: march — dune/opam already in PATH, no eval $(opam env) needed
```

---

## 10. Project Layout

```
bin/main.ml                 compiler entry point
lib/ast/ast.ml              AST types
lib/lexer/lexer.mll         ocamllex lexer
lib/parser/parser.mly       menhir parser
lib/desugar/desugar.ml      pipe desugar
lib/typecheck/typecheck.ml  HM type inference
lib/eval/eval.ml            tree-walking interpreter
lib/tir/                    typed IR (lower/mono/defun/perceus/borrow/fusion/llvm_emit)
lib/jit/                    REPL JIT
lib/errors/errors.ml        diagnostics
lib/search/search.ml        Hoogle-style search
stdlib/                     87 March stdlib modules
runtime/                    C runtime (GC, scheduler, HTTP, TLS, WASM)
forge/                      build tool
lsp/                        LSP server
test/test_march.ml          alcotest suite (~19k lines)
specs/                      design specs, progress tracking
bench/                      benchmark .march programs (47 files)
examples/                   example .march programs (56 files)
```
