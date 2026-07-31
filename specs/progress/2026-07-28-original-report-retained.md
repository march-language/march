- ⏳ **(original report, retained)**  A closure that captures a free variable is allocated and never released, even when it never escapes. Minimal repro, compiled `--opt 2`:
  ```march
  fn go(i : Int, acc : Int, k : Int) : Int do
    if i <= 0 do acc
    else
      let f = fn x -> x * k
      go(i - 1, acc + f(i), k)
    end
  end
  ```
  At 4,000,000 iterations this reports `obj_allocs 4000000` under `MARCH_STRING_STATS=1` and peaks at **131.6 MB** RSS (measured 2026-07-28; `march_string_stats obj_allocs 4000000`, `maximum resident set size 131563520`, `24000006000000` for `go(4000000, 0, 3)`), against **2.9 MB / 0 allocs** for the identical loop with the capture inlined (`fn x -> x * 2`, which the optimizer eliminates entirely — `march_string_stats obj_allocs 0`, `maximum resident set size 3031040`). RSS grows linearly with the iteration count on a flat (tail-recursive) stack, so this is a leak, not churn. **Distinct from the capture-free case fixed by static closures:** a capturing closure's contents differ per instance, so it cannot be a module-lifetime static object — this needs a genuine ownership fix in `lib/tir/perceus.ml`/`lib/tir/borrow.ml`, not a codegen change. Note the same shape leaks whether the closure is called directly or passed to a higher-order function, so the call boundary is not the discriminator. Interpreted execution is unaffected (OCaml GC).
