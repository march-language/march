# March Standard Library Design

The standard library ships with the compiler and is auto-available to all March programs. Design principles:

- **Immutable by default** — all collection operations return new values
- **Result over panic** — operations that can fail return `Result`; panics are for programmer errors
- **Capability-tracked IO** — side effects require capability tokens, not effect annotations
- **Consistent naming** — `map`, `flat_map`, `filter`, `fold_left` everywhere
- **Partial function convention** — `head` panics, `head_opt` returns `Option`

---

## 1. Typeclasses

The foundational interfaces that the rest of the stdlib is built on.

```march
interface Eq(a) do
  fn eq(x : a, y : a) : Bool
  fn neq(x : a, y : a) : Bool do not(eq(x, y)) end
end

interface Ord(a) : Eq(a) do
  fn compare(x : a, y : a) : Ordering
  fn lt(x : a, y : a) : Bool do compare(x, y) == Less end
  fn lte(x : a, y : a) : Bool do compare(x, y) != Greater end
  fn gt(x : a, y : a) : Bool do compare(x, y) == Greater end
  fn gte(x : a, y : a) : Bool do compare(x, y) != Less end
end

type Ordering = Less | Equal | Greater

interface Show(a) do
  fn show(x : a) : String
end

interface Hash(a) : Eq(a) do
  fn hash(x : a) : Int
end

interface Num(a) do
  fn add(x : a, y : a) : a
  fn sub(x : a, y : a) : a
  fn mul(x : a, y : a) : a
  fn neg(x : a) : a
  fn from_int(n : Int) : a
end

interface Fractional(a) : Num(a) do
  fn div(x : a, y : a) : a
end

interface Default(a) do
  fn default() : a
end

interface Mappable(f) do
  fn map(container : f(a), func : a -> b) : f(b)
end

interface Iterable(c) do
  type Elem
  fn iter(collection : c) : Iterator(Elem)
end

interface Interpolatable(a) do
  fn format(value : a) : String
end

interface Textual(a) do
  fn length(s : a) : Int
  fn slice(s : a, start : Int, len : Int) : a
  fn concat(a : a, b : a) : a
  fn to_string(s : a) : String
end
```

`Eq` and `Ord` are compiler-derivable for ADTs (structural equality, lexicographic ordering). `Show` is compiler-derivable for all types (debug representation). `Hash` is derivable for types composed entirely of hashable parts.

---

## 2. Core Types

The primitive type modules. Each owns its type and provides all operations on it.

```march
mod Core.Int do
  impl Eq(Int) do ... end
  impl Ord(Int) do ... end
  impl Num(Int) do ... end
  impl Show(Int) do ... end
  impl Hash(Int) do ... end
  impl Default(Int) do fn default() do 0 end end
  impl Interpolatable(Int) do ... end

  fn abs(n : Int) : Int
  fn pow(base : Int, exp : Int) : Int
  fn mod(a : Int, b : Int) : Int
  fn div_euclid(a : Int, b : Int) : Int
  fn mod_euclid(a : Int, b : Int) : Int
  fn to_float(n : Int) : Float
  fn to_string(n : Int) : String
  fn from_string(s : String) : Option(Int)
  fn max_value : Int
  fn min_value : Int
end

mod Core.Float do
  impl Eq(Float) do ... end
  impl Ord(Float) do ... end
  impl Num(Float) do ... end
  impl Fractional(Float) do ... end
  impl Show(Float) do ... end
  impl Default(Float) do fn default() do 0.0 end end
  impl Interpolatable(Float) do ... end

  fn abs(x : Float) : Float
  fn floor(x : Float) : Int
  fn ceil(x : Float) : Int
  fn round(x : Float) : Int
  fn truncate(x : Float) : Int
  fn to_string(x : Float) : String
  fn from_string(s : String) : Option(Float)
  fn is_nan(x : Float) : Bool
  fn is_infinite(x : Float) : Bool
  fn infinity : Float
  fn neg_infinity : Float
  fn nan : Float
  fn epsilon : Float
end

mod Core.Bool do
  impl Eq(Bool) do ... end
  impl Ord(Bool) do ... end
  impl Show(Bool) do ... end
  impl Default(Bool) do fn default() do false end end

  fn to_string(b : Bool) : String
  fn from_string(s : String) : Option(Bool)
end

mod Core.Char do
  impl Eq(Char) do ... end
  impl Ord(Char) do ... end
  impl Show(Char) do ... end

  fn is_alpha(c : Char) : Bool
  fn is_digit(c : Char) : Bool
  fn is_alphanumeric(c : Char) : Bool
  fn is_whitespace(c : Char) : Bool
  fn is_uppercase(c : Char) : Bool
  fn is_lowercase(c : Char) : Bool
  fn to_uppercase(c : Char) : Char
  fn to_lowercase(c : Char) : Char
  fn to_int(c : Char) : Int
  fn from_int(n : Int) : Option(Char)
end

mod Core.String do
  impl Eq(String) do ... end
  impl Ord(String) do ... end
  impl Show(String) do ... end
  impl Hash(String) do ... end
  impl Default(String) do fn default() do "" end end
  impl Textual(String) do ... end
  impl Interpolatable(String) do ... end

  fn length(s : String) : Int
  fn byte_length(s : String) : Int
  fn is_empty(s : String) : Bool
  fn concat(a : String, b : String) : String
  fn slice(s : String, start : Int, len : Int) : String
  fn contains(s : String, sub : String) : Bool
  fn starts_with(s : String, prefix : String) : Bool
  fn ends_with(s : String, suffix : String) : Bool
  fn index_of(s : String, sub : String) : Option(Int)
  fn replace(s : String, old : String, new : String) : String
  fn replace_all(s : String, old : String, new : String) : String
  fn split(s : String, sep : String) : List(String)
  fn join(parts : List(String), sep : String) : String
  fn trim(s : String) : String
  fn trim_start(s : String) : String
  fn trim_end(s : String) : String
  fn to_uppercase(s : String) : String
  fn to_lowercase(s : String) : String
  fn chars(s : String) : List(Char)
  fn from_chars(cs : List(Char)) : String
  fn repeat(s : String, n : Int) : String
  fn reverse(s : String) : String
  fn pad_left(s : String, width : Int, fill : Char) : String
  fn pad_right(s : String, width : Int, fill : Char) : String
end

mod Core.Unit do
  impl Eq(Unit) do ... end
  impl Show(Unit) do ... end
  impl Default(Unit) do fn default() do () end end
end

mod Core.Atom do
  impl Eq(Atom) do ... end
  impl Show(Atom) do ... end
  impl Hash(Atom) do ... end

  fn to_string(a : Atom) : String
end
```

---

## 3. Option & Result

```march
mod Core.Option do
  -- type Option(a) = Some(a) | None  (built-in)

  impl Eq(a) for Option(a) when Eq(a) do ... end
  impl Ord(a) for Option(a) when Ord(a) do ... end
  impl Show(a) for Option(a) when Show(a) do ... end
  impl Default(Option(a)) do fn default() do None end end
  impl Mappable(Option) do ... end

  -- Extracting
  fn unwrap(opt : Option(a)) : a
  fn unwrap_or(opt : Option(a), default : a) : a
  fn unwrap_or_else(opt : Option(a), f : () -> a) : a
  fn expect(opt : Option(a), msg : String) : a

  -- Testing
  fn is_some(opt : Option(a)) : Bool
  fn is_none(opt : Option(a)) : Bool

  -- Transforming
  fn map(opt : Option(a), f : a -> b) : Option(b)
  fn flat_map(opt : Option(a), f : a -> Option(b)) : Option(b)
  fn filter(opt : Option(a), pred : a -> Bool) : Option(a)
  fn or_else(opt : Option(a), f : () -> Option(a)) : Option(a)
  fn zip(a : Option(a), b : Option(b)) : Option((a, b))

  -- Converting
  fn to_result(opt : Option(a), err : e) : Result(a, e)
  fn to_list(opt : Option(a)) : List(a)
end

mod Core.Result do
  -- type Result(a, e) = Ok(a) | Err(e)  (built-in)

  impl Eq(a) for Result(a, e) when Eq(a), Eq(e) do ... end
  impl Show(a) for Result(a, e) when Show(a), Show(e) do ... end
  impl Mappable(Result) do ... end

  -- Extracting
  fn unwrap(res : Result(a, e)) : a
  fn unwrap_err(res : Result(a, e)) : e
  fn unwrap_or(res : Result(a, e), default : a) : a
  fn expect(res : Result(a, e), msg : String) : a

  -- Testing
  fn is_ok(res : Result(a, e)) : Bool
  fn is_err(res : Result(a, e)) : Bool

  -- Transforming
  fn map(res : Result(a, e), f : a -> b) : Result(b, e)
  fn map_err(res : Result(a, e), f : e -> f) : Result(a, f)
  fn flat_map(res : Result(a, e), f : a -> Result(b, e)) : Result(b, e)
  fn or_else(res : Result(a, e), f : e -> Result(a, f)) : Result(a, f)

  -- Collecting
  fn collect(results : List(Result(a, e))) : Result(List(a), e)

  -- Converting
  fn to_option(res : Result(a, e)) : Option(a)
end
```

---

## 4. Collections

### 4.1 List

```march
mod Collections.List do
  -- type List(a) = Cons(a, List(a)) | Nil  (built-in)

  impl Eq(a) for List(a) when Eq(a) do ... end
  impl Ord(a) for List(a) when Ord(a) do ... end
  impl Show(a) for List(a) when Show(a) do ... end
  impl Default(List(a)) do fn default() do Nil end end
  impl Mappable(List) do ... end
  impl Iterable(List(a)) do type Elem = a end

  -- Construction
  fn empty() : List(a)
  fn singleton(x : a) : List(a)
  fn repeat(x : a, n : Int) : List(a)
  fn range(start : Int, stop : Int) : List(Int)
  fn range_step(start : Int, stop : Int, step : Int) : List(Int)

  -- Access
  fn head(xs : List(a)) : a
  fn tail(xs : List(a)) : List(a)
  fn head_opt(xs : List(a)) : Option(a)
  fn tail_opt(xs : List(a)) : Option(List(a))
  fn last(xs : List(a)) : a
  fn nth(xs : List(a), n : Int) : a
  fn nth_opt(xs : List(a), n : Int) : Option(a)

  -- Measurement
  fn length(xs : List(a)) : Int
  fn is_empty(xs : List(a)) : Bool

  -- Transforming
  fn map(xs : List(a), f : a -> b) : List(b)
  fn flat_map(xs : List(a), f : a -> List(b)) : List(b)
  fn filter(xs : List(a), pred : a -> Bool) : List(a)
  fn filter_map(xs : List(a), f : a -> Option(b)) : List(b)
  fn fold_left(acc : b, xs : List(a), f : (b, a) -> b) : b
  fn fold_right(xs : List(a), acc : b, f : (a, b) -> b) : b
  fn scan_left(acc : b, xs : List(a), f : (b, a) -> b) : List(b)
  fn reverse(xs : List(a)) : List(a)
  fn append(xs : List(a), ys : List(a)) : List(a)
  fn concat(xss : List(List(a))) : List(a)
  fn intersperse(xs : List(a), sep : a) : List(a)

  -- Searching
  fn find(xs : List(a), pred : a -> Bool) : Option(a)
  fn find_index(xs : List(a), pred : a -> Bool) : Option(Int)
  fn contains(xs : List(a), x : a) : Bool when Eq(a)
  fn any(xs : List(a), pred : a -> Bool) : Bool
  fn all(xs : List(a), pred : a -> Bool) : Bool

  -- Sorting
  fn sort(xs : List(a)) : List(a) when Ord(a)
  fn sort_by(xs : List(a), f : (a, a) -> Ordering) : List(a)

  -- Splitting
  fn take(xs : List(a), n : Int) : List(a)
  fn drop(xs : List(a), n : Int) : List(a)
  fn take_while(xs : List(a), pred : a -> Bool) : List(a)
  fn drop_while(xs : List(a), pred : a -> Bool) : List(a)
  fn split_at(xs : List(a), n : Int) : (List(a), List(a))
  fn partition(xs : List(a), pred : a -> Bool) : (List(a), List(a))
  fn chunks(xs : List(a), size : Int) : List(List(a))

  -- Combining
  fn zip(xs : List(a), ys : List(b)) : List((a, b))
  fn zip_with(xs : List(a), ys : List(b), f : (a, b) -> c) : List(c)
  fn unzip(pairs : List((a, b))) : (List(a), List(b))
  fn enumerate(xs : List(a)) : List((Int, a))

  -- Reducing
  fn sum(xs : List(a)) : a when Num(a)
  fn product(xs : List(a)) : a when Num(a)
  fn minimum(xs : List(a)) : a when Ord(a)
  fn maximum(xs : List(a)) : a when Ord(a)

  -- Deduplication
  fn dedup(xs : List(a)) : List(a) when Eq(a)
  fn unique(xs : List(a)) : List(a) when Eq(a), Hash(a)
end
```

### 4.2 Array

Fixed-size, contiguous, O(1) indexed access. Interacts with linear types for zero-copy mutation.

```march
mod Collections.Array do
  impl Eq(a) for Array(a) when Eq(a) do ... end
  impl Show(a) for Array(a) when Show(a) do ... end
  impl Mappable(Array) do ... end
  impl Iterable(Array(a)) do type Elem = a end

  -- Construction
  fn create(size : Int, value : a) : Array(a)
  fn from_list(xs : List(a)) : Array(a)
  fn init(size : Int, f : Int -> a) : Array(a)

  -- Access
  fn get(arr : Array(a), idx : Int) : a
  fn get_opt(arr : Array(a), idx : Int) : Option(a)
  fn set(arr : Array(a), idx : Int, val : a) : Array(a)
  fn length(arr : Array(a)) : Int

  -- Linear mutation (zero-copy when uniquely owned)
  fn create_linear(size : Int, value : a) : linear Array(a)
  fn set!(arr : linear Array(a), idx : Int, val : a) : linear Array(a)
  fn freeze(arr : linear Array(a)) : Array(a)

  -- Transforming
  fn map(arr : Array(a), f : a -> b) : Array(b)
  fn fold_left(acc : b, arr : Array(a), f : (b, a) -> b) : b
  fn to_list(arr : Array(a)) : List(a)
  fn slice(arr : Array(a), start : Int, len : Int) : Array(a)
  fn sort(arr : Array(a)) : Array(a) when Ord(a)
end
```

### 4.3 Map

Immutable key-value map (hash array mapped trie internally).

```march
mod Collections.Map do
  impl Eq(v) for Map(k, v) when Eq(k), Eq(v) do ... end
  impl Show(k, v) for Map(k, v) when Show(k), Show(v) do ... end
  impl Default(Map(k, v)) do fn default() do empty() end end

  -- Construction
  fn empty() : Map(k, v)
  fn singleton(key : k, value : v) : Map(k, v) when Eq(k), Hash(k)
  fn from_list(pairs : List((k, v))) : Map(k, v) when Eq(k), Hash(k)

  -- Access
  fn get(m : Map(k, v), key : k) : Option(v) when Eq(k), Hash(k)
  fn get_or(m : Map(k, v), key : k, default : v) : v when Eq(k), Hash(k)
  fn contains_key(m : Map(k, v), key : k) : Bool when Eq(k), Hash(k)

  -- Modification
  fn insert(m : Map(k, v), key : k, value : v) : Map(k, v) when Eq(k), Hash(k)
  fn remove(m : Map(k, v), key : k) : Map(k, v) when Eq(k), Hash(k)
  fn update(m : Map(k, v), key : k, f : Option(v) -> Option(v)) : Map(k, v)
      when Eq(k), Hash(k)

  -- Measurement
  fn size(m : Map(k, v)) : Int
  fn is_empty(m : Map(k, v)) : Bool

  -- Transforming
  fn map_values(m : Map(k, v), f : v -> w) : Map(k, w)
  fn filter(m : Map(k, v), pred : (k, v) -> Bool) : Map(k, v)
  fn fold(acc : b, m : Map(k, v), f : (b, k, v) -> b) : b

  -- Combining
  fn merge(a : Map(k, v), b : Map(k, v)) : Map(k, v) when Eq(k), Hash(k)
  fn merge_with(a : Map(k, v), b : Map(k, v), f : (v, v) -> v) : Map(k, v)
      when Eq(k), Hash(k)

  -- Converting
  fn keys(m : Map(k, v)) : List(k)
  fn values(m : Map(k, v)) : List(v)
  fn to_list(m : Map(k, v)) : List((k, v))
end
```

### 4.4 Set

Immutable set (backed by Map internally).

```march
mod Collections.Set do
  impl Eq(a) for Set(a) when Eq(a) do ... end
  impl Show(a) for Set(a) when Show(a) do ... end
  impl Default(Set(a)) do fn default() do empty() end end

  -- Construction
  fn empty() : Set(a)
  fn singleton(x : a) : Set(a) when Eq(a), Hash(a)
  fn from_list(xs : List(a)) : Set(a) when Eq(a), Hash(a)

  -- Access
  fn contains(s : Set(a), x : a) : Bool when Eq(a), Hash(a)
  fn size(s : Set(a)) : Int
  fn is_empty(s : Set(a)) : Bool

  -- Modification
  fn insert(s : Set(a), x : a) : Set(a) when Eq(a), Hash(a)
  fn remove(s : Set(a), x : a) : Set(a) when Eq(a), Hash(a)

  -- Set operations
  fn union(a : Set(a), b : Set(a)) : Set(a) when Eq(a), Hash(a)
  fn intersection(a : Set(a), b : Set(a)) : Set(a) when Eq(a), Hash(a)
  fn difference(a : Set(a), b : Set(a)) : Set(a) when Eq(a), Hash(a)
  fn is_subset(a : Set(a), b : Set(a)) : Bool when Eq(a), Hash(a)
  fn is_disjoint(a : Set(a), b : Set(a)) : Bool when Eq(a), Hash(a)

  -- Transforming
  fn map(s : Set(a), f : a -> b) : Set(b) when Eq(b), Hash(b)
  fn filter(s : Set(a), pred : a -> Bool) : Set(a)
  fn fold(acc : b, s : Set(a), f : (b, a) -> b) : b
  fn to_list(s : Set(a)) : List(a)
end
```

### 4.5 Vector

Length-indexed, fixed-size. Requires type-level naturals.

```march
mod Collections.Vector do
  impl Eq(a) for Vector(n, a) when Eq(a) do ... end
  impl Show(a) for Vector(n, a) when Show(a) do ... end
  impl Mappable(Vector(n)) do ... end

  -- Construction
  fn create(value : a) : Vector(n, a)
  fn from_list(xs : List(a)) : Option(Vector(n, a))
  fn init(f : Int -> a) : Vector(n, a)

  -- Access
  fn get(v : Vector(n, a), idx : Int) : a
  fn set(v : Vector(n, a), idx : Int, val : a) : Vector(n, a)
  fn length(v : Vector(n, a)) : Int

  -- Math (numeric elements)
  fn dot(a : Vector(n, Float), b : Vector(n, Float)) : Float
  fn sum(v : Vector(n, a)) : a when Num(a)
  fn scale(v : Vector(n, a), s : a) : Vector(n, a) when Num(a)

  -- Combining (compile-time length checking)
  fn concat(a : Vector(n, a), b : Vector(m, a)) : Vector(n + m, a)
  fn head(v : Vector(n + 1, a)) : a
  fn tail(v : Vector(n + 1, a)) : Vector(n, a)
  fn zip_with(a : Vector(n, a), b : Vector(n, b), f : (a, b) -> c) : Vector(n, c)

  -- Converting
  fn to_list(v : Vector(n, a)) : List(a)
  fn to_array(v : Vector(n, a)) : Array(a)
end
```

### 4.6 NDArray

Multi-dimensional array with compile-time shape checking.

```march
mod Collections.NDArray do
  type alias Matrix(m, n, a) = NDArray([m, n], a)

  -- Construction
  fn zeros(shape : shape) : NDArray(shape, Float)
  fn ones(shape : shape) : NDArray(shape, Float)
  fn fill(shape : shape, value : a) : NDArray(shape, a)

  -- Access
  fn get(arr : NDArray(shape, a), indices : List(Int)) : a
  fn set(arr : NDArray(shape, a), indices : List(Int), val : a) : NDArray(shape, a)
  fn shape(arr : NDArray(shape, a)) : List(Int)

  -- Matrix operations (2D specializations)
  fn matmul(a : Matrix(m, n, Float), b : Matrix(n, p, Float)) : Matrix(m, p, Float)
  fn transpose(m : Matrix(r, c, a)) : Matrix(c, r, a)

  -- Reshaping (element count must match at compile time)
  fn reshape(arr : NDArray(s1, a)) : NDArray(s2, a) where Product(s1) = Product(s2)
  fn flatten(arr : NDArray(shape, a)) : Array(a)

  -- Element-wise
  fn map(arr : NDArray(shape, a), f : a -> b) : NDArray(shape, b)
  fn zip_with(a : NDArray(shape, a), b : NDArray(shape, b), f : (a, b) -> c)
      : NDArray(shape, c)
end
```

---

## 5. IO & Capabilities

March has **no algebraic effects**. Side effects are tracked via capability types. An IO capability is created at program entry and threaded explicitly through functions that perform IO.

```march
mod IO do
  -- Console (requires Cap(IO))
  fn print(cap : Cap(IO), s : String) : Unit
  fn println(cap : Cap(IO), s : String) : Unit
  fn eprint(cap : Cap(IO), s : String) : Unit
  fn eprintln(cap : Cap(IO), s : String) : Unit
  fn read_line(cap : Cap(IO)) : String
  fn read_line_opt(cap : Cap(IO)) : Option(String)

  -- Formatting (pure — no capability needed)
  fn inspect(x : a) : String when Show(a)
  fn debug(cap : Cap(IO), x : a) : Unit when Show(a)
end

mod IO.File do
  fn read(cap : Cap(IO), path : String) : Result(String, IOError)
  fn read_bytes(cap : Cap(IO), path : String) : Result(List(Byte), IOError)
  fn write(cap : Cap(IO), path : String, content : String) : Result(Unit, IOError)
  fn write_bytes(cap : Cap(IO), path : String, bytes : List(Byte)) : Result(Unit, IOError)
  fn append(cap : Cap(IO), path : String, content : String) : Result(Unit, IOError)
  fn exists(cap : Cap(IO), path : String) : Bool
  fn delete(cap : Cap(IO), path : String) : Result(Unit, IOError)
  fn rename(cap : Cap(IO), old : String, new : String) : Result(Unit, IOError)
  fn list_dir(cap : Cap(IO), path : String) : Result(List(String), IOError)
  fn is_file(cap : Cap(IO), path : String) : Bool
  fn is_dir(cap : Cap(IO), path : String) : Bool
  fn mkdir(cap : Cap(IO), path : String) : Result(Unit, IOError)
  fn mkdir_p(cap : Cap(IO), path : String) : Result(Unit, IOError)
end

mod IO.Process do
  fn args(cap : Cap(IO)) : List(String)
  fn env(cap : Cap(IO), key : String) : Option(String)
  fn exit(cap : Cap(IO), code : Int) : a
  fn cwd(cap : Cap(IO)) : String
end

type IOError = IOError(String)
```

The `Cap(IO)` token is unforgeable and non-linear — you can pass it around and use it repeatedly, but you cannot conjure one from nothing. The `main` function receives it from the runtime:

```march
fn main(io : Cap(IO)) do
  IO.println(io, "Hello, world!")
end
```

This means:
- Pure functions cannot perform IO (no cap = no IO)
- IO capability can be subdivided (e.g., pass only `Cap(FileRead)` to a function that should only read files)
- Tests can substitute mock capabilities

---

## 6. Actors & Concurrency

Concurrency in March is the actor model — share-nothing message passing with typed, capability-secure references.

```march
mod Concurrent do
  -- Spawning actors (returns stable identity + epoch-0 capability)
  fn spawn(cap : Cap(IO), actor_def : ActorDef(s, m)) : (ActorId(m), Cap(Pid(m)))

  -- Messaging (requires cap for the target actor)
  fn send(cap : Cap(Pid(m)), msg : m) : Unit where Sendable(m)
  fn ask(cap : Cap(Pid(m)), msg : m) : Future(r) where Sendable(m)

  -- Futures
  fn await(future : Future(a)) : a
  fn map(future : Future(a), f : a -> b) : Future(b)
  fn map2(a : Future(a), b : Future(b), f : (a, b) -> c) : Future(c)
end

mod Concurrent.Task do
  -- Structured parallel concurrency (lighter than actors, no mailbox, no state)
  fn spawn(cap : Cap(IO), f : () -> a) : Task(a) where Sendable(a)
  fn await(task : Task(a)) : a
  fn await_all(tasks : List(Task(a))) : List(a)

  -- Convenience
  fn parallel(cap : Cap(IO), tasks : List(() -> a)) : List(a) where Sendable(a)
  fn race(cap : Cap(IO), tasks : List(() -> a)) : a where Sendable(a)
end

mod Concurrent.Stream do
  -- Async sequences (logs, metrics, events, pub/sub)
  fn subscribe(stream : Stream(a), handler : a -> Unit) : Subscription
  fn unsubscribe(sub : Subscription) : Unit
  fn map(stream : Stream(a), f : a -> b) : Stream(b)
  fn filter(stream : Stream(a), pred : a -> Bool) : Stream(a)
  fn take(stream : Stream(a), n : Int) : Stream(a)
  fn merge(a : Stream(a), b : Stream(a)) : Stream(a)
  fn to_list(stream : Stream(a)) : Future(List(a))
end
```

Tasks are scoped — they must complete before the enclosing scope exits. No leaked goroutines.

`Sendable(a)` is compiler-derived for types composed entirely of sendable parts. The compiler refuses to derive it for closures, mutable references, linear pointers, and capabilities (caps are node-local).

---

## 7. Math

```march
mod Math do
  -- Constants
  fn pi : Float
  fn e : Float
  fn tau : Float

  -- Basic
  fn abs(x : Float) : Float
  fn min(a : a, b : a) : a when Ord(a)
  fn max(a : a, b : a) : a when Ord(a)
  fn clamp(x : a, low : a, high : a) : a when Ord(a)

  -- Powers & roots
  fn sqrt(x : Float) : Float
  fn cbrt(x : Float) : Float
  fn pow(base : Float, exp : Float) : Float
  fn exp(x : Float) : Float
  fn exp2(x : Float) : Float

  -- Logarithms
  fn log(x : Float) : Float
  fn log2(x : Float) : Float
  fn log10(x : Float) : Float

  -- Trigonometry
  fn sin(x : Float) : Float
  fn cos(x : Float) : Float
  fn tan(x : Float) : Float
  fn asin(x : Float) : Float
  fn acos(x : Float) : Float
  fn atan(x : Float) : Float
  fn atan2(y : Float, x : Float) : Float

  -- Hyperbolic
  fn sinh(x : Float) : Float
  fn cosh(x : Float) : Float
  fn tanh(x : Float) : Float

  -- Rounding (returns Float, not Int — use Core.Float for Int versions)
  fn floor(x : Float) : Float
  fn ceil(x : Float) : Float
  fn round(x : Float) : Float
  fn truncate(x : Float) : Float

  -- Interpolation
  fn lerp(a : Float, b : Float, t : Float) : Float
end

mod Math.Random do
  -- Pseudo-random number generation. Requires Cap(IO) for system entropy,
  -- or can be run purely with an explicit seed.

  fn int(cap : Cap(IO), low : Int, high : Int) : Int
  fn float(cap : Cap(IO)) : Float
  fn float_range(cap : Cap(IO), low : Float, high : Float) : Float
  fn bool(cap : Cap(IO)) : Bool
  fn choice(cap : Cap(IO), xs : List(a)) : a
  fn choice_opt(cap : Cap(IO), xs : List(a)) : Option(a)
  fn shuffle(cap : Cap(IO), xs : List(a)) : List(a)
  fn sample(cap : Cap(IO), xs : List(a), n : Int) : List(a)

  -- Pure deterministic RNG (no capability needed)
  type Rng  -- opaque, immutable PRNG state

  fn from_seed(seed : Int) : Rng
  fn next_int(rng : Rng, low : Int, high : Int) : (Int, Rng)
  fn next_float(rng : Rng) : (Float, Rng)
  fn next_bool(rng : Rng) : (Bool, Rng)
end
```

---

## 8. Regex

```march
mod String.Regex do
  -- type Regex — opaque, compiled pattern

  type Match = Match(
    text : String,
    start : Int,
    end : Int,
    groups : List(Option(String))
  )

  fn compile(pattern : String) : Result(Regex, String)
  fn is_match(re : Regex, s : String) : Bool
  fn find(re : Regex, s : String) : Option(Match)
  fn find_all(re : Regex, s : String) : List(Match)
  fn replace(re : Regex, s : String, replacement : String) : String
  fn replace_all(re : Regex, s : String, replacement : String) : String
  fn replace_with(re : Regex, s : String, f : Match -> String) : String
  fn split(re : Regex, s : String) : List(String)

  -- Convenience (compile + match in one step, panics on bad pattern)
  fn matches(pattern : String, s : String) : Bool
end
```

---

## 9. Time

```march
mod Time do
  -- Instant: monotonic clock (for measuring durations)
  -- DateTime: wall clock (for display/storage)
  -- Duration: a span of time

  type Duration = Duration(nanoseconds : Int)

  -- Duration construction
  fn nanoseconds(n : Int) : Duration
  fn microseconds(n : Int) : Duration
  fn milliseconds(n : Int) : Duration
  fn seconds(n : Int) : Duration
  fn minutes(n : Int) : Duration
  fn hours(n : Int) : Duration

  impl Eq(Duration) do ... end
  impl Ord(Duration) do ... end
  impl Show(Duration) do ... end
  impl Num(Duration) do ... end

  -- Duration access
  fn to_seconds(d : Duration) : Float
  fn to_millis(d : Duration) : Int
  fn to_nanos(d : Duration) : Int

  -- Monotonic clock
  fn now(cap : Cap(IO)) : Instant
  fn elapsed(cap : Cap(IO), start : Instant) : Duration
  fn since(start : Instant, end : Instant) : Duration

  -- Wall clock
  fn utc_now(cap : Cap(IO)) : DateTime
  fn local_now(cap : Cap(IO)) : DateTime

  -- DateTime access
  fn year(dt : DateTime) : Int
  fn month(dt : DateTime) : Int
  fn day(dt : DateTime) : Int
  fn hour(dt : DateTime) : Int
  fn minute(dt : DateTime) : Int
  fn second(dt : DateTime) : Int
  fn weekday(dt : DateTime) : Weekday

  type Weekday = Monday | Tuesday | Wednesday | Thursday
               | Friday | Saturday | Sunday

  -- DateTime arithmetic
  fn add(dt : DateTime, d : Duration) : DateTime
  fn sub(dt : DateTime, d : Duration) : DateTime
  fn diff(a : DateTime, b : DateTime) : Duration

  -- Formatting & parsing
  fn format(dt : DateTime, fmt : String) : String
  fn parse(s : String, fmt : String) : Result(DateTime, String)

  -- Unix timestamps
  fn to_unix(dt : DateTime) : Int
  fn to_unix_millis(dt : DateTime) : Int
  fn from_unix(secs : Int) : DateTime
  fn from_unix_millis(ms : Int) : DateTime

  impl Eq(DateTime) do ... end
  impl Ord(DateTime) do ... end
  impl Show(DateTime) do ... end

  -- Convenience
  fn sleep(cap : Cap(IO), d : Duration) : Unit
  fn measure(cap : Cap(IO), f : () -> a) : (a, Duration)
end
```

---

## 10. Iterators

Lazy, pull-based sequences. Transformation is lazy (no work until consumed); consumption forces evaluation.

```march
mod Iterator do
  -- type Iterator(a) — opaque, internally () -> Option(a)

  -- Construction
  fn from_list(xs : List(a)) : Iterator(a)
  fn from_array(arr : Array(a)) : Iterator(a)
  fn empty() : Iterator(a)
  fn once(x : a) : Iterator(a)
  fn repeat(x : a) : Iterator(a)
  fn iterate(start : a, f : a -> a) : Iterator(a)
  fn unfold(state : s, f : s -> Option((a, s))) : Iterator(a)
  fn count_from(start : Int) : Iterator(Int)
  fn count_from_step(start : Int, step : Int) : Iterator(Int)

  -- Transforming (lazy)
  fn map(iter : Iterator(a), f : a -> b) : Iterator(b)
  fn flat_map(iter : Iterator(a), f : a -> Iterator(b)) : Iterator(b)
  fn filter(iter : Iterator(a), pred : a -> Bool) : Iterator(a)
  fn filter_map(iter : Iterator(a), f : a -> Option(b)) : Iterator(b)
  fn take(iter : Iterator(a), n : Int) : Iterator(a)
  fn take_while(iter : Iterator(a), pred : a -> Bool) : Iterator(a)
  fn drop(iter : Iterator(a), n : Int) : Iterator(a)
  fn drop_while(iter : Iterator(a), pred : a -> Bool) : Iterator(a)
  fn zip(a : Iterator(a), b : Iterator(b)) : Iterator((a, b))
  fn zip_with(a : Iterator(a), b : Iterator(b), f : (a, b) -> c) : Iterator(c)
  fn enumerate(iter : Iterator(a)) : Iterator((Int, a))
  fn chain(a : Iterator(a), b : Iterator(a)) : Iterator(a)
  fn intersperse(iter : Iterator(a), sep : a) : Iterator(a)
  fn scan(acc : b, iter : Iterator(a), f : (b, a) -> b) : Iterator(b)
  fn chunks(iter : Iterator(a), size : Int) : Iterator(List(a))
  fn dedup(iter : Iterator(a)) : Iterator(a) when Eq(a)

  -- Consuming (forces evaluation)
  fn to_list(iter : Iterator(a)) : List(a)
  fn to_array(iter : Iterator(a)) : Array(a)
  fn fold(acc : b, iter : Iterator(a), f : (b, a) -> b) : b
  fn for_each(iter : Iterator(a), f : a -> Unit) : Unit
  fn count(iter : Iterator(a)) : Int
  fn sum(iter : Iterator(a)) : a when Num(a)
  fn product(iter : Iterator(a)) : a when Num(a)
  fn any(iter : Iterator(a), pred : a -> Bool) : Bool
  fn all(iter : Iterator(a), pred : a -> Bool) : Bool
  fn find(iter : Iterator(a), pred : a -> Bool) : Option(a)
  fn min(iter : Iterator(a)) : Option(a) when Ord(a)
  fn max(iter : Iterator(a)) : Option(a) when Ord(a)
  fn nth(iter : Iterator(a), n : Int) : Option(a)
  fn collect_result(iter : Iterator(Result(a, e))) : Result(List(a), e)

  -- Generic construction via Iterable
  fn from(x : c) : Iterator(a) when Iterable(c, Elem = a)
end
```

---

## 11. Prelude

Everything auto-imported into every module with no `use` statement.

### Types

```march
Int, Float, Bool, Char, String, Unit, Atom
Option, Some, None
Result, Ok, Err
List, Cons, Nil
Ordering, Less, Equal, Greater
```

### Typeclasses

```march
Eq, Ord, Show, Hash, Num, Mappable, Iterable
```

### Functions

```march
-- IO (convenience — these take Cap(IO) as first arg)
fn print(cap : Cap(IO), s : String) : Unit
fn println(cap : Cap(IO), s : String) : Unit
fn inspect(x : a) : String when Show(a)
fn debug(cap : Cap(IO), x : a) : Unit when Show(a)

-- Diverging
fn panic(msg : String) : a
fn todo(msg : String) : a
fn unreachable() : a

-- Option/Result helpers
fn unwrap(opt : Option(a)) : a
fn unwrap_or(opt : Option(a), default : a) : a
fn map(container : f(a), func : a -> b) : f(b) when Mappable(f)

-- List basics
fn head(xs : List(a)) : a
fn tail(xs : List(a)) : List(a)
fn length(xs : List(a)) : Int
fn reverse(xs : List(a)) : List(a)
fn fold_left(acc : b, xs : List(a), f : (b, a) -> b) : b
fn filter(xs : List(a), pred : a -> Bool) : List(a)

-- Combinators
fn identity(x : a) : a
fn compose(f : b -> c, g : a -> b) : a -> c
fn flip(f : (a, b) -> c) : (b, a) -> c
fn const(x : a) : b -> a
```

### Operators

```march
-- Desugared by compiler:
==  !=        -- Eq
<  <=  >  >=  -- Ord
+  -  *  /    -- Num
++            -- String.concat or List.append
|>            -- pipe
>>            -- function composition
```

---

## 12. Error Conventions

Three tiers of failure, used consistently throughout the stdlib:

### 1. `Result(a, e)` — the default

Any operation that can reasonably fail returns `Result`. File IO, parsing, network, regex compilation. The caller decides how to handle it.

### 2. `panic(msg)` — programmer errors

For violated invariants and impossible states. `head([])`, `unwrap(None)`, array out of bounds. These are bugs, not expected failures. Panics unwind the stack and are not catchable with try/catch — they propagate to the actor boundary, where the supervisor decides what to do (restart, escalate, log).

### 3. `todo(msg)` — incomplete code

Special panic for stubs. Typechecks as any type so you can sketch out a program top-down. Prints source location. Never valid in production.

### Naming convention for partial functions

- `fn head(xs) : a` — panics on empty (short name, common path)
- `fn head_opt(xs) : Option(a)` — returns None on empty (`_opt` suffix)

This applies throughout: `nth` / `nth_opt`, `get` / `get_opt`, `unwrap` / `unwrap_or`.

### Actor-boundary error recovery

Panics propagate to the actor boundary. The supervision tree handles recovery:

```march
-- Supervisor catches actor panics and restarts
actor Supervisor do
  on ChildFailed(id, reason) do
    restart(id)
  end
end
```

This means library code can panic on true invariant violations, and actor boundaries provide natural recovery points — consistent with the Erlang "let it crash" philosophy.

---

## 13. Implementation Split: OCaml/C Runtime vs March Source

The stdlib is designed to be implemented primarily in March itself, bottoming out at a thin layer of OCaml/C runtime intrinsics. The codegen pipeline (TIR → LLVM → native) already supports closures, ADTs, pattern matching, and generic functions — enough to self-host the pure logic.

### Must be OCaml/C runtime intrinsics (~40 primitives)

These bottom out at machine instructions, LLVM ops, or syscalls:

| Category | Primitives | Why |
|----------|-----------|-----|
| **Arithmetic** | `Int.add`, `Int.sub`, `Int.mul`, `Int.div`, `Int.mod`, `Float.*` ops | LLVM native arithmetic instructions |
| **Comparison** | Primitive `eq`, `lt` for Int, Float, Bool, Char | Machine compare instructions |
| **String primitives** | `alloc`, `concat`, `eq`, `slice`, `length`, `byte_length` | Raw memory ops on string representation |
| **Conversions** | `int_to_string`, `string_to_int`, `float_to_string`, `int_to_float`, `char_to_int` | Already in `march_runtime.c` |
| **Array primitives** | `create`, `get`, `set`, `length` | Raw indexed memory access |
| **Memory** | `alloc`, `free`, `incrc`, `decrc` | Reference counting runtime (already exists) |
| **IO — console** | `print`, `read_line` | Syscalls (`write(2)`, `read(2)`) |
| **IO — filesystem** | `open`, `read`, `write`, `stat`, `unlink`, `readdir`, `mkdir` | POSIX syscalls |
| **IO — process** | `args`, `env`, `exit`, `cwd` | Syscalls / libc |
| **Time** | `clock_gettime` (monotonic + wall), `nanosleep` | Syscalls |
| **Regex engine** | `compile`, `exec`, `free` | Wraps a C regex library (PCRE2 or similar) |
| **Actor runtime** | `spawn`, `send`, `mailbox_recv`, scheduler loop | C runtime for green threads + message queues |
| **Math — transcendental** | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log`, `sqrt`, `pow` | `libm` C functions |
| **Random — entropy** | `getrandom` / `/dev/urandom` | Syscall for seeding |
| **Hash** | Primitive hash for Int, String, Atom | SipHash or similar in C |

### Implemented in March (~300 functions)

Everything that's pure logic over the primitives above. This is the vast majority of the stdlib by function count:

**Core types (high-level ops):**
- `Int.abs`, `Int.pow`, `Int.div_euclid`, `Int.mod_euclid`
- `Float.is_nan`, `Float.is_infinite`, `Float.floor`/`ceil`/`round` (call intrinsic, wrap result)
- `Bool.to_string`, `Char.is_alpha`, `Char.is_digit`, `Char.to_uppercase`, etc.
- `String.split`, `String.join`, `String.trim`, `String.replace`, `String.starts_with`, `String.pad_left`, etc. (built on `slice` + `concat` + `length` primitives)

**Option & Result — all of it:**
- `map`, `flat_map`, `unwrap_or`, `filter`, `zip`, `to_result`, `collect`, etc.

**List — all of it:**
- `map`, `filter`, `fold_left`, `fold_right`, `reverse`, `sort`, `zip`, `take`, `drop`, `partition`, `find`, `any`, `all`, `sum`, `unique`, etc.

**Map & Set — all of it:**
- HAMT (hash array mapped trie) implementation is pure data structure code
- `insert`, `get`, `remove`, `merge`, `fold`, `filter`, `keys`, `values`, etc.

**Array (high-level ops):**
- `map`, `fold_left`, `to_list`, `slice`, `sort`, `from_list`, `init` (built on `create`/`get`/`set` primitives)

**Vector & NDArray — all of it:**
- `dot`, `scale`, `zip_with`, `reshape`, `matmul`, `transpose` (built on Array primitives)

**Iterator — all of it:**
- Entirely closure-based: `map`, `filter`, `take`, `chain`, `enumerate`, `fold`, `to_list`, etc.

**Math (pure):**
- `min`, `max`, `clamp`, `lerp` (transcendentals are C intrinsics)

**Time (pure logic):**
- `Duration` constructors and arithmetic (just Int wrappers)
- `DateTime` field accessors (`year`, `month`, `day`, etc.)
- `format` and `parse` (string manipulation over a struct)

**Regex (wrappers):**
- `find_all`, `replace_with`, `split` (March logic over C `compile`/`exec`)

**Concurrency (wrappers):**
- `Task.parallel`, `Task.race`, `Stream.map`, `Stream.filter` (March logic over runtime `spawn`/`send`)

**All typeclass impls for compound types:**
- Eq, Ord, Show for Option, Result, List, Map, Set, tuples, etc.

**Prelude combinators:**
- `identity`, `compose`, `flip`, `const`

### The ratio

Roughly **~40 C/OCaml primitives** and **~300 March functions**. The stdlib is ~90% March, ~10% intrinsic — consistent with how Rust, Haskell, and OCaml structure their own standard libraries.

### Migration path

Functions start as OCaml builtins in the tree-walking interpreter. As the codegen matures, they migrate to March source one module at a time. The spec is implementation-language-agnostic — nothing in the API signatures changes when a function moves from OCaml to March.
