# Bound the memory used by freestanding WASM string joins

The browser runtime implements `String.join` over a bump allocator. Joining
large arrays during JSON serialization accumulated a new copy of the full
prefix at each step and exhausted linear memory.

The runtime now measures the joined byte length before allocating and copies
each string and separator once. A wasm32 probe under a 16 MiB limit traps
on the previous runtime and succeeds with this change. It exercises 3,200
items, empty and singleton lists, empty separators and items, UTF-8, and
embedded NUL bytes.
