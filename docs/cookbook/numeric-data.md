---
layout: cookbook
title: "Cookbook: Numeric Data"
permalink: /docs/cookbook/numeric-data/
scrollmd: true
---

# Numeric Data

How to process large numeric arrays fast: the `NativeArray` auto-vectorized
path for everyday numeric loops, the `Simd` module for guaranteed vector
codegen, and how to tell which one you need. Uses the `NativeArray` and
`Simd` modules.

> Each snippet below is one module. Put your own `main` (or a `test` block)
> *inside* the module to run it; a file has a single top-level `mod`.

---

## From a List to a NativeArray

`List` and `Array` are the right default for everyday code, but a numeric
hot loop over a large collection wants `NativeArray` instead: a flat,
contiguous array that `march --compile` can auto-vectorize into real SIMD
instructions. Build one with `from_list_*`, and convert back with `to_list_*`
if you need a `List` again:

```march
mod NumFast do
  needs IO.Console

  fn main(_cap_console : Cap(IO.Console)) do
    let xs = [1.0, 2.0, 3.0, 4.0]
    let arr = NativeArray.from_list_float(xs)
    let doubled = NativeArray.map_float(arr, fn x -> x *. 2.0)
    let total = NativeArray.sum_float(doubled)
    println(float_to_string(total))   -- 20.
  end
end
```

`sum_float`/`map_float`/`map2_float` auto-vectorize under a compiled build;
see [SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/#what-vectorizes) for
exactly which shapes qualify (short, single-use, concrete-`Float` callbacks).
This is a fast path you opt into for numeric hot loops, not the default
representation for numeric data; reach for `List`/`Array` everywhere else.

---

## Narrow widths: 50% of the bytes, double the lanes

Beyond `Int`/`Float` (i64/f64), `NativeArray` also supports narrower element
widths, **f32**, **i32**, and **u8**, with the same shape of API (`make_*`,
`map_*`, `sum_*`, `map2_*`) plus conversions to/from the wider types. Halving
the element width doubles how many lanes fit in one SIMD vector, which is
where the extra speed comes from:

```march
mod NumFast do
  needs IO.Console

  fn main(_cap_console : Cap(IO.Console)) do
    -- Narrow to f32 for half the bytes / double the SIMD lanes.
    let arr64 = NativeArray.from_list_float([1.0, 2.0, 3.0, 4.0])
    let arr32 = NativeArray.float_to_f32_arr(arr64)
    let doubled = NativeArray.map_f32(arr32, fn x -> x *. 2.0)
    let total = NativeArray.sum_f32(doubled)
    println(float_to_string(total))              -- 20.

    -- Convert back if you need f64 precision again.
    let widened = NativeArray.f32_to_float_arr(doubled)
    println(int_to_string(NativeArray.length_float(widened)))  -- 4
  end
end
```

**Boundary rule:** integer stores truncate mod 2^w two's-complement, float
stores round to nearest-even binary32, loads widen exactly (`u8`
zero-extends, `i32` sign-extends); none of this traps, in any case. See [SIMD &
Native Arrays → Narrow element widths]({{ site.baseurl
}}/docs/simd/#narrow-element-widths) for the full boundary contract and the
f32-vs-f64 speedup numbers (~2.0-2.4x at N=5M).

---

## Aggregating a CSV column the fast-path way

The [Files cookbook]({{ site.baseurl }}/docs/cookbook/files/#aggregating-a-column)
sums a CSV column with `List.fold_left` over `List(List(String))`: simple
and fine for small-to-medium files. For a large column, convert the parsed
cells to a `NativeArray` first and let `sum_int`/`sum_float` do the
reduction instead of a hand-written fold:

```march
mod SalesFast do
  needs IO.Console

  pfn cell_to_int(cell : String) : Int do
    match string_to_int(cell) do
      Some(n) -> n
      None    -> 0     -- skip blanks / non-numeric cells
    end
  end

  -- Sum an integer column, located by its header name, via NativeArray.
  fn sum_column(rows : List(List(String)), header : List(String), column : String) : Result(Int, String) do
    match List.find_index(header, fn h -> h == column) do
      None    -> Err("no column named " ++ column)
      Some(i) ->
        let cells = List.map(rows, fn row -> cell_to_int(List.nth(row, i)))
        let arr = NativeArray.from_list_int(cells)
        Ok(NativeArray.sum_int(arr))
    end
  end

  fn main(_cap_console : Cap(IO.Console)) do
    let header = ["name", "qty"]
    let rows = [["a", "3"], ["b", "4"], ["c", "5"]]
    match sum_column(rows, header, "qty") do
      Ok(n)  -> println(int_to_string(n))   -- 12
      Err(e) -> println(e)
    end
  end
end
```

Same shape as `Sales.sum_column` in the Files cookbook (parse cells, locate
the column by header, fold), just with the reduction given to
`NativeArray.sum_int` instead of a hand-written `List.fold_left`. Worth the
extra `from_list_int` conversion once the row count gets large enough that
the reduction itself, not the CSV parse, dominates.

---

## When `NativeArray` isn't enough: the `Simd` module

`NativeArray`'s `map`/`map2`/`sum` compile to SIMD *when the optimizer
chooses to*: a short, single-use, concretely-typed callback qualifies, but
it's still an optimizer decision, not a language guarantee. The `Simd`
module is the opposite trade: five 128-bit vector types
(`F32x4`/`F64x2`/`I32x4`/`I64x2`/`U8x16`) you construct and operate on
directly, so the vector lowering is **guaranteed**. Reach for it when you
need something `NativeArray`'s builtin ops don't express: cross-lane
structure (masks, `select`), a fused multiply-add, or byte-level scanning.

### Dot product: a register-resident accumulator loop

```march
mod DotKernel do
  needs IO.Console

  pfn dot_loop(a, b, i : Int, limit : Int, acc) do
    if i >= limit do acc
    else
      let va = Simd.load_f32x4(a, i)
      let vb = Simd.load_f32x4(b, i)
      dot_loop(a, b, i + 4, limit, Simd.fma_f32x4(va, vb, acc))
    end
  end

  pfn dot_tail(a, b, i : Int, n : Int, acc : Float) : Float do
    if i >= n do acc
    else dot_tail(a, b, i + 1, n, acc +. NativeArray.get_f32(a, i) *. NativeArray.get_f32(b, i))
    end
  end

  doc "Dot product via an F32x4 FMA accumulator: index loop by 4, scalar tail for the remainder."
  fn dot_simd(a, b) : Float do
    let n = NativeArray.length_f32(a)
    let lanes = 4
    let limit = n - (n % lanes)
    let acc = dot_loop(a, b, 0, limit, Simd.splat_f32x4(0.0))
    let vector_sum = Simd.sum_f32x4(acc)
    dot_tail(a, b, limit, n, vector_sum)
  end

  fn main(_cap_console : Cap(IO.Console)) do
    let a = NativeArray.make_f32(9, 1.0)
    let b = NativeArray.make_f32(9, 2.0)
    println(float_to_string(dot_simd(a, b)))   -- 18.
  end
end
```

`dot_loop` is a self-tail-recursive top-level function threading the
`F32x4` accumulator as its own parameter: the shape the compiler keeps
register-resident across iterations with zero allocation (see [SIMD & Native
Arrays → The register-residency contract]({{ site.baseurl
}}/docs/simd/#the-register-residency-contract)). The scalar `dot_tail` at
the end handles any remainder that doesn't fill a full 4-lane group.

**Don't reach for this by default.** For exactly this shape (multiply two
arrays elementwise, then reduce), composing `NativeArray.map2_f32` +
`sum_f32` currently *beats* a hand-written `Simd` accumulator loop doing the
same computation (2.55 ms vs. 10.0 ms at N=5M, ~3.9x). The gap isn't a SIMD
cost; it's general per-iteration overhead every hand-written `NativeArray`
index loop pays (a preemption check, a stack save/restore, RC bookkeeping),
not specific to vectors; see [SIMD Benchmarks → Simd module
kernels]({{ site.baseurl }}/docs/simd-benchmarks/#simd-module-kernels) for
the full breakdown. Use the pattern above when you need `fma` fused into one
instruction, or cross-lane structure `map2`/`sum` can't express, not as a
default replacement for `map2` + `sum`.

### Byte scanning: where `Simd` is a clear win

Unlike the dot-product case, byte-level scanning is where `Simd` wins
completely: no `NativeArray` op does 16-lane-at-a-time comparison:

```march
mod ScanKernel do
  needs IO.Console

  doc "Index of the first byte equal to [needle] in [hay], or -1. 16-lane U8x16 stride, scalar tail."
  fn scan_simd(hay, needle : Int) : Int do
    let n = NativeArray.length_u8(hay)
    let lanes = 16
    let limit = n - (n % lanes)
    let target = Simd.splat_u8x16(needle)
    fn go(i) do
      if i >= limit do -1
      else
        let v = Simd.load_u8x16(hay, i)
        let hit = Simd.first_set_u8x16(Simd.eq_u8x16(v, target))
        if hit >= 0 do i + hit
        else go(i + lanes)
        end
      end
    end
    let vector_hit = go(0)
    if vector_hit >= 0 do vector_hit
    else
      fn tail(i) do
        if i >= n do -1
        else if NativeArray.get_u8(hay, i) == needle do i
        else tail(i + 1)
        end
        end
      end
      tail(limit)
    end
  end

  fn main(_cap_console : Cap(IO.Console)) do
    let hay0 = NativeArray.make_u8(40, 65)
    let hay = NativeArray.set_u8(hay0, 33, 10)
    println(int_to_string(scan_simd(hay, 10)))   -- 33
  end
end
```

`Simd.eq_u8x16` produces a per-lane mask (all-ones where the byte matches,
zero otherwise); `first_set_u8x16` reads that mask's lanes and returns the
index of the first match, or `-1` if none of the 16 bytes in this stride
matched, in which case the loop advances by a full 16-byte stride and tries
again. This is the classic memchr-shaped SIMD workload: measured **~11.5x
faster** than the equivalent byte-at-a-time scalar loop over 16MB of data.
See [SIMD Benchmarks → Simd module kernels]({{ site.baseurl
}}/docs/simd-benchmarks/#simd-module-kernels) for the numbers.

---

## See also

- [SIMD & Native Arrays]({{ site.baseurl }}/docs/simd/): the full guide, what vectorizes, how to trigger it, the unvarnished performance story, known limitations.
- [SIMD Benchmarks]({{ site.baseurl }}/docs/simd-benchmarks/): the numbers behind every claim on this page.
- [Parallel Data]({{ site.baseurl }}/docs/cookbook/parallel-data/): combining vectorization within a chunk with parallelism across chunks.
- [Standard Library → NativeArray]({{ site.baseurl }}/docs/stdlib/NativeArray.html) · [Standard Library → Simd]({{ site.baseurl }}/docs/stdlib/Simd.html): full API references.
