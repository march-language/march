- ✅ **Static capture-free LAMBDA values — extended the static-closure mechanism above to anonymous lambdas, not just top-level named functions (2026-07-28, `lib/tir/llvm_emit.ml`'s `EAlloc` arm).** Previously `static_closure_ok`/`intern_static_closure` only fired for a top-level `fn`-declared function materialized as a value; an anonymous lambda expression that captures nothing, passed as a value at its own creation site (e.g. `apply_it(fn x -> x * 2, i)`), was neither a top-level named function nor a capturing closure — it fell between the two and kept allocating fresh every materialization, never freed. Minimal repro, compiled `--opt 2`:
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
  **Fixed** by recognizing this shape at LLVM emission with no `defun.ml` change needed — the discriminator is derivable purely at the emission site: `defun.ml` lifts every lambda to `EAlloc (TCon (clo_name, []), fn_ptr_atom :: fv_atoms)`, so a lambda that captures nothing leaves `fv_atoms = []`, i.e. the `EAlloc` carries **exactly one** argument (the lifted apply function's address, `Tir_names.is_clo_struct tcon_name` confirms it's a closure struct). That shape routes to the same `intern_static_closure` interning path a top-level function value uses. No `$clo_wrap` trampoline is generated for the lambda case (unlike the earlier bug where `clo_wrap_define` mattered) — the lifted apply function defunctionalization produces already has the `(clo_ptr, params…)` closure-call ABI, so field 0 can point straight at it. **Gated** the same way as the named-function case for REPL/JIT (`not ctx.repl`), but *more conservatively* for hot-reload: rather than resolving the defunctionalized closure's synthetic type name (`"$Clo_" ^ fn_name ^ "$" ^ uid`, not always unambiguously demangled — it may itself embed `$`) back to an owning module via `Hot_reload.is_reloadable`, static lambdas are disabled outright whenever `ctx.hr_config` is set at all. **Measured** (`MARCH_STRING_STATS=1`, `--opt 2`, 4,000,000 iterations of `apply_it(fn x -> x * 2, i)`): `obj_allocs` 4,000,000 → 0, peak RSS ~131.5 MB → ~2.99 MB. Compiled and interpreted output byte-identical before and after (no observable-behavior change, only the allocation strategy). No wall-clock speedup is claimed beyond the allocation/RSS elimination — this was not benchmarked for wall-clock. **Still does NOT cover capturing closures** — see the next open item; a capturing lambda's `EAlloc` always carries 2+ arguments (code pointer plus at least one captured free variable) and so never matches this single-argument shape, by design, since its contents differ per instance and cannot be a module-lifetime static object. Verified non-vacuous (disabling the new arm reproduces `LEAKED 20000`-shaped unbounded growth; restoring it gives bounded growth) via `test_lambda_static_closure_materialization_no_leak_compiled` (`test/test_codegen.ml`, "compiled capture-free lambda materialization does not leak per use") plus a native golden `test/native/static_lambda_no_leak.march` covering two distinct capture-free lambdas (4 distinct `$static_clo` globals confirmed, none shared) and a capture-free lambda alongside a capturing one in the same function, confirming the discriminator separates the two cases correctly at runtime.
