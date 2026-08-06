# `~H` misread non-IOList ADTs as IOLists — XSS + SIGSEGV

**Landed:** 2026-08-05
**Branch:** `fix/h-sigil-adt-misread` (off `main` @ `079ff744`)
**Severity:** High — unescaped output and a memory-unsafe read in compiled code

Task 0 of `specs/plans/2026-08-05-contextual-autoescaping.md`, split out and
landed ahead of the rest because it is independent of contextual escaping and
was live in the shipped compiler.

## The defect

`march_html_auto_escape` (`runtime/march_extras.c`) ended with:

```c
/* Constructor with tag >= 0: treat as IOList and flatten verbatim. */
```

and delegated to `mh_iolist_size` / `mh_iolist_copy`, which branch on the raw
heap tag: tag 1 reads field 0 as a `march_string*`, tag 2 walks field 0 as a
cons list. Constructor tags are numbered **per type** starting at 0, so every
ADT aliases `IOList = Empty | Str(String) | Segments(List(IOList))`.

The runtime cannot resolve this — `llvm_emit.ml:1543-1558` already said so in
prose while patching the single `Html.Safe` instance of it.

## Measured before/after (compiled; the interpreter was correct throughout)

| Interpolated into `~H"<p>${x}</p>"` | Before | After |
|---|---|---|
| `Point(1, 2)` — tag 0, 2 fields | `<p></p>` (empty) | `<p>#&lt;tag:0&gt;</p>` |
| `B("<script>")` — tag 1, String | `<p><script></p>` **raw, unescaped** | `<p>#&lt;tag:1&gt;</p>` |
| `C("xx", "yy")` — tag 2 | **SIGSEGV** (exit 139) | `<p>#&lt;tag:2&gt;</p>` |
| `Err("<b>")` | `<p><b></p>` **raw, unescaped** | `<p>#&lt;tag:1&gt;</p>` |
| `Ok("<script>")` | `<p></p>` (payload dropped) | `<p>#&lt;tag:0&gt;</p>` |
| `None` | `<p></p>` | `<p>nil</p>` |
| `Html.raw(...)` under a `Safe` name collision | `<p></p>` (markup dropped) | escaped, non-empty |
| `Cons("<script>alert(1)</script>", Nil)` — a plain `List(String)` | `<p><script>alert(1)</script></p>` **raw, unescaped** | `<p>#&lt;tag:1&gt;</p>` |
| record `{ name: "<script>", .. }` / tuple | `<p></p>` | `<p>#&lt;tag:0&gt;</p>` |
| `B("<script>")` via a stored closure (TVar) | `<p><script></p>` **raw, unescaped** | `<p>#&lt;tag:1&gt;</p>` |
| `C(..)` via a stored closure (TVar) | **SIGSEGV** | `<p>#&lt;tag:2&gt;</p>` |
| `Some("<script>")`, String, IOList, `Html.raw` | correct | unchanged |

**The widest case is a plain `List`.** `Cons` is tag 1 with the element in
field 0, aliasing `IOList.Str`, so interpolating any `List(String)` emitted its
**head element raw and unescaped**. That needs no custom ADT and no `Result` —
just a list in a template.

**`Option`/`Result` were NOT exempt.** The plan originally asserted they were
niche-optimised and therefore safe. That is true only of `Some(x)`; `None`,
`Ok` and `Err` are ordinary boxed constructors, and `Err` leaked its payload
raw and unescaped. Since `Result` is pervasive, this was by far the widest
instance of the bug — the plan has been corrected.

## The fix

`lib/tir/llvm_emit.ml` — decide from the argument's static TIR type instead of
letting the runtime guess from a heap tag. `String`, `Int`, `Float`, `Bool` and
`IOList` still take the runtime path, which genuinely handles them. Everything
else goes through `march_value_to_string` first and is escaped as a real String.

`TVar` — the unresolved case — also stringifies, and getting there took a
correction. The first version of this fix kept the runtime path for `TVar`, on
the stated assumption that mono concretises every ADT interpolation. **That is
false.** A value reaching the hole through a closure stored in a container is
not specialised:

```march
let b = Bx(Cons(fn x -> ~H"<p>${x}</p>", Nil))
apply_first(b, B("<script>"))
```

Measured with that first version still in place: `<p><script></p>` — raw and
unescaped — and the tag-2 case still segfaulted. The hole was entirely unfixed
for polymorphic sites.

`TVar` is genuinely undecidable: an IOList wants flattening, an ADT must not be
flattened, and nothing at runtime distinguishes them (`march_value_to_string`
renders a real IOList as `#<tag:2>`, so it cannot flatten one either). It now
resolves toward safety — stringify. The accepted cost is that a genuine IOList
partial reaching a polymorphic hole renders `#<tag:2>` instead of its markup:
visibly wrong for that (rare) pattern, but not a vulnerability. Pinned as
`poly_iolist`. The proper fix needs a runtime type id; filed as
`specs/todos/2026-08-05-boxed-adt-type-id.md`.

`runtime/march_extras.c` — the fallback arm now aborts with the observed tag
instead of guessing. Note its limit, which is documented at the site: IOList has
three constructors, so tags 0..2 stay ambiguous and only tag >= 3 is *provably*
not an IOList. The emitter is the real fix; this is defense in depth.

## Known follow-up

Compiled `march_value_to_string` has no constructor-name metadata, so ADTs
render `#<tag:N>` where the interpreter renders `Point(1, 2)`. That gap predates
this work and reproduces with `to_string` alone. Filed as
`specs/todos/2026-08-05-compiled-to-string-adt-ctor-names.md`;
`test/native/h_sigil_adt_interp.expected` pins the current output and is
annotated to be updated when ctor names land.

## Exposure sweep — forgepm

Clean, for both the app and the framework.

**bastion** (`lib/`, worktree copies excluded): 46 `~H`, 28 interpolations, 6
user multi-constructor ADTs — none reaches an interpolation.

**forgepm**: 153 `~H` sites and 257 interpolations. It declares exactly
one user multi-constructor ADT (`PublishResult`,
`lib/forgepm/client/registry.march:9`), which lives in the CLI publish client,
appears in no file containing `~H`, and is always destructured by `match` before
rendering. No interpolation references an `Option`/`Result`-typed binding,
function, or record field (the only such field is `Email.reply_to`, never
interpolated).

Caveat: this is source-level analysis, not a typechecked sweep — building
forgepm against this compiler fails with 68 pre-existing errors from bastion
version drift, unrelated to this change.

## Tests

- `test/native/h_sigil_adt_interp.march` — compile-and-run golden diff over
  tag-0/1/2 ADTs, `Option`, `Result`, String, IOList, `Html.raw`, and the
  polymorphic/`TVar` holes (`poly_tag1`, `poly_tag2`, `poly_iolist`). Fails on
  `main` with exit 139.
- `test/native/h_sigil_safe_collision.march` — separate file, because declaring
  a second `Safe` type makes every `Safe` in the program collide and would
  silently destroy the other test's coverage of the verbatim path. Asserts
  booleans rather than exact text, since the stringified form embeds a raw tag
  number that would make a golden diff brittle.

Backends checked: `html_auto_escape` is implemented only in
`runtime/march_extras.c` and emitted only from `lib/tir/llvm_emit.ml`, so the
JIT inherits the fix and there is no separate WASM or JS path to patch. The
interpreter (`lib/eval/eval.ml`) was always correct.

Full suite: 830 tests, 1 failure — `adversarial-regressions 40 MARCH_SANITIZE`,
an ASAN timeout. Environmental, not this change: a trivial
`clang -fsanitize=address` C program that only calls `printf` also hangs and is
SIGKILLed at 30s on this host, which is exactly the check that test's own
failure message asks for.
