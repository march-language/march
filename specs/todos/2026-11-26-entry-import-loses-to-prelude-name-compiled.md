`[P2]` Compiled: an entry module's bare call to a name it imports loses to a
prelude function of that name

Found while writing `test/native/lazy_lower_shadow` (lazy stdlib lowering,
`specs/progress/2026-11-26-lazy-stdlib-lowering.md`); not caused by it: the
compiler before that change does the same.

```march
-- lib/shadow_lib.march (on MARCH_LIB_PATH)
mod ShadowLib do
  fn reverse(xs : List(Int)) : List(Int) do xs end
end

-- entry.march
mod Main do
  needs IO.Console
  import ShadowLib
  fn main(_c : Cap(IO.Console)) do
    -- prints [1, 2, 3] interpreted, [3, 2, 1] compiled
    ...reverse([1, 2, 3])...
  end
end
```

The interpreter binds the entry's bare `reverse` to the import; the compiled
program calls the prelude's `reverse` (both with and without
`--disable-pass lazy-lower`).

Likely cause: `Lower.lower_module` sets `_current_module_fns` for Pass 2 to
every top-level `DFn` of the merged module, and the prelude's functions are
top-level `DFn`s there (unwrapped, bare names), so `Lower_state.resolve_use_alias`
treats `reverse` as one of the entry module's own functions and never consults
its imports. The fix is probably to count only the entry file's own top-level
fns (`span.file = !Lower_state._entry_file`), then check what else relied on
the prelude names being in that table.
