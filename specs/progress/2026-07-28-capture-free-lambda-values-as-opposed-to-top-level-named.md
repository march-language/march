- ⏳ **Capture-free LAMBDA values (as opposed to top-level named functions) still allocate one closure per materialization (compiled) — OPEN, found 2026-07-28 in final whole-branch review of the static-closure work.** `static_closure_ok`/`intern_static_closure` only fire for a top-level `fn`-declared function materialized as a value; an anonymous lambda expression that captures nothing, passed as a value at its own creation site, is neither a top-level named function (the case this branch fixes) nor a capturing closure (the other open item above) — it falls between the two. Minimal repro, compiled `--opt 2`:
  ```march
  mod Main do
    fn apply_it(f : Int -> Int, n : Int) : Int do f(n) end

    fn go(i : Int, acc : Int) : Int do
      if i <= 0 do
        acc
      else
        go(i - 1, acc + apply_it(fn x -> x * 2, i))
      end
    end

    fn main() : () do
      println(go(4000000, 0))
    end
  end
  ```
  Measured 2026-07-28 (`MARCH_STRING_STATS=1`, `--opt 2`, 4,000,000 iterations): `march_string_stats obj_allocs 4000000`, peak RSS **131.5 MB** (`maximum resident set size 131547136`) — the same shape and magnitude as the pre-fix top-level-function-value leak (125.4 MB) and the still-open capturing-closure leak (131.6 MB) above. **Distinct from both existing entries:** it is not a top-level function reference (so `intern_static_closure` never sees it — no `fn_name` lookup applies to an anonymous lambda AST node) and it is capture-free (so, unlike the capturing-closure case, it is a legitimate candidate for the same static-global treatment this branch gave named functions — no ownership/perceus work should be needed, just extending the eligibility check to cover defunctionalized capture-free lambdas). Needs its own fix in `lib/tir/llvm_emit.ml`'s closure-materialization path (or `defun.ml`, if capture-free-ness needs to be visible before the lambda is defunctionalized into a synthetic top-level function).
