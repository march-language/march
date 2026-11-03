`[P3]` - [x] **Compiled: an entry module named `List` or `String` does not compile.** Fixed 2026-10-12.

Filed 2026-10-12 by the interpreter-vs-compiled differential sweep (group V).
`specs/lang/types/accept/t126_entry_module_shadows_list_length.march` and
`t127_entry_module_shadows_string_byte_size.march` ran interpreted (exit 0)
but `--compile` stopped with:

```
march: error: `List.head_opt` is called here returning
`TCon(Option,[TRecord{ref:TCon(MonitorRef,[]),…}])`, but its body could not be
specialized -- the callee's return type is still `TCon(Option,[TVar(a)])`.
```

(t127: the same for `String.last_index_of`.) Minimal shape:

```march
mod List do
  fn go(ys : List(Int)) : Int do List.length(ys) end
  fn main() : Int do go([1]) end
end
```

## Root cause

Not mono's or defun's name tables. `bin/main.ml`'s `compile` puts the entry
module's own name in `extern_mod_names`, so it strips any stdlib module of that
name before lowering. That rule came from 02d212d40: a project file
`lib/crypto.march` (`mod Crypto`) used as the entry has to REPLACE the stdlib's
Crypto, or sibling modules resolve `Crypto.foo` against the stdlib copy. An
entry `List` or `String` cannot replace the stdlib's, though. Actor, Map, Json
and the prelude call `List.head_opt`, `String.last_index_of` and the like, which
the entry does not define. With the stdlib module stripped, those calls bound
only to the lazy shapes-only load, whose bodies never reach lowering. Mono then
refused the niche/boxed `Option` disagreement. The interpreter fills such a
hole lazily, so it ran.

## The fix

The entry still shadows a same-named stdlib module, but only when it can stand
in for it: every `M.f` that the rest of the stdlib calls (qualified free
variables of all other stdlib decls, prelude included) must be an `f` the entry
defines. Otherwise the stdlib module is kept beside the entry, and the two stay
distinct. The entry's declarations are flat (unqualified), and desugar's
`strip_entry_self_qual` already sends the entry's own `List.f` calls to its own
`f`. Every other `List.f`, including the stdlib's own internal calls, names the
stdlib member.

Behaviour change: an entry `mod Crypto` (or any stdlib module name) that does
not define every member the rest of the stdlib uses no longer hides the stdlib
copy from sibling `MARCH_LIB_PATH` modules. Before, that combination left the
stdlib with calls into nothing, and it was masked only because stdlib-span
diagnostics are filtered and the dead callers were usually unreachable. The
multi-file `run_check_cmd` path (`seen_mod_names`) only strips stdlib DMods
shadowed by a loaded DMod. This change does not touch it.

## Tests

`test/native/entry_module_named_list.march` and
`entry_module_named_string.march` (+ `.expected`, rules in `test/dune`, refine
audit baseline regenerated). Each entry defines its own `length` / `byte_size`
and `shout`, calls them qualified and bare, and calls stdlib members of the same
module and of modules that use it internally (`Stats.count` → stdlib
`List.length`, Map, Json, `String.join`, `List.head_opt`). The compiled output
equals the interpreter's. With the old `bin/main.ml` both stop with "body could
not be specialized". t126 and t127 now compile and exit 0.
