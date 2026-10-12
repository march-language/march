`[P3]` - [ ] **Compiled: an entry module named `List` or `String` does not compile.**

Filed 2026-10-12 by the interpreter-vs-compiled differential sweep (group V).
`specs/lang/types/accept/t126_entry_module_shadows_list_length.march` and
`t127_entry_module_shadows_string_byte_size.march` run interpreted (exit 0)
but `--compile` stops with:

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

An entry module whose name equals a stdlib module's merges or collides with
that module's functions in mono (the stdlib `List.head_opt` called from
`Actor`/monitor code can no longer be found as the stdlib body). Needs a
decision: reject an entry module named like a stdlib module with a clear
diagnostic, or keep the two apart in lowering (they are distinct in the
typechecker, which is what those two fixtures pin).
