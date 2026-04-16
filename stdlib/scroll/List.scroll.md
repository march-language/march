# List

List module: immutable singly-linked list operations.

List(a) = Cons(a, List(a)) Nil  (built-in constructors)

Design:
- Partial functions (head, tail, nth, last) panic on empty/out-of-bounds
- Safe variants use the _opt suffix and return Option
- fold_left is the primitive; fold_right recurses on the structure
- sort uses merge sort

## fn empty() : List(a)

Returns an empty list.

## Examples

```march
List.empty()  -- []
```

## fn singleton(x : a) : List(a)

Returns a list containing a single element.

## Examples

```march
List.singleton(42)   -- [42]
List.singleton("hi") -- ["hi"]
```

## fn repeat(x : a, n : Int) : List(a)

Returns a list with `x` repeated `n` times.

## Examples

```march
List.repeat(0, 3)    -- [0, 0, 0]
List.repeat("x", 4)  -- ["x", "x", "x", "x"]
```

## fn range(start : Int, stop : Int) : List(Int)

Returns [start, start+1, ..., stop-1]. Returns [] if start >= stop.

## Examples

```march
List.range(0, 5)   -- [0, 1, 2, 3, 4]
List.range(3, 7)   -- [3, 4, 5, 6]
List.range(5, 5)   -- []
```

## fn length(xs : List(a)) : Int

Returns the number of elements in the list.

## Examples

```march
List.length([1, 2, 3])  -- 3
List.length([])         -- 0
```

## fn append(xs : List(a), ys : List(a)) : List(a)

Concatenates two lists.

## Examples

```march
List.append([1, 2], [3, 4, 5])  -- [1, 2, 3, 4, 5]
List.append([], [1, 2])         -- [1, 2]
```

## fn map(xs : List(a), f : a -> b) : List(b)

Applies `f` to each element, returning a new list.

## Examples

```march
List.map([1, 2, 3], fn x -> x * 2)
-- [2, 4, 6]

List.map(["a", "b"], String.upper)
-- ["A", "B"]
```

## fn filter(xs : List(a), pred : a -> Bool) : List(a)

Returns only elements satisfying `pred`.

## Examples

```march
List.filter([1, 2, 3, 4, 5], fn x -> x > 2)
-- [3, 4, 5]

List.filter(["foo", "", "bar", ""], fn s -> !String.is_empty(s))
-- ["foo", "bar"]
```

## fn fold_left(acc : b, xs : List(a), f : b -> a -> b) : b

Left fold: reduces the list from left to right with an accumulator.

## Examples

```march
List.fold_left(0, [1, 2, 3, 4], fn acc -> fn x -> acc + x)
-- 10

List.fold_left([], [1, 2, 3], fn acc -> fn x -> Cons(x * 2, acc))
-- [6, 4, 2]  (note: reversed; use fold_right or reverse for ordered)
```

## fn sort_by(xs : List(a), cmp : a -> a -> Bool) : List(a)

Sorts by a comparator function. Uses merge sort (stable, O(n log n)).

## Examples

```march
List.sort_by([3, 1, 4, 1, 5], fn (a, b) -> a < b)
-- [1, 1, 3, 4, 5]

List.sort_by(["banana", "apple", "cherry"], fn (a, b) -> a < b)
-- ["apple", "banana", "cherry"]
```

## fn zip(xs : List(a), ys : List(b)) : List((a, b))

Pairs up elements from two lists. Stops at the shorter list.

## Examples

```march
List.zip([1, 2, 3], ["a", "b", "c"])
-- [(1, "a"), (2, "b"), (3, "c")]

List.zip([1, 2], ["a", "b", "c", "d"])
-- [(1, "a"), (2, "b")]
```

