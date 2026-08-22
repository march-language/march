# `Vault.set`/`Vault.get` with a non-String key SIGSEGVs/SIGBUS when compiled natively

Filed while validating downstream packages (bastion, depot, forgepm, conduit, sigil,
scroll, march_doc, marathon) against `origin/main` ahead of the 0.3.0 release. Found
via forgepm's own compiled test suite crashing (SIGBUS, exit 138) partway through
`forge test` — no assertion failure printed, the process just dies.

## Symptom

`stdlib/vault.march`'s module doc is explicit that Vault accepts non-String keys:

> Keys can be any plain value: Int, String, Bool, Atom, Tuple, or Ctor. Function
> values, Pids, and Tasks cannot be used as keys. Keys are STRINGIFIED on the way
> in, which is why the handle is not parameterised by a key type.

That promise holds under the **interpreter** but not the **native compiled**
backend: any non-String key (confirmed with `Int`) segfaults/SIGBUSes.

Minimal repro:

```march
mod Main do
  needs IO

  fn main(cap: Cap(IO)) do
    let t = Vault.new("t")
    Vault.set(t, 5, "hello")
    println(Vault.get(t, 5))
  end
end
```

```
$ march /tmp/repro.march                          # interpreted: correct
Some(hello)

$ march --compile --opt 2 /tmp/repro.march -o /tmp/repro && /tmp/repro
[SIGSEGV, exit 139]
```

## Root cause

`runtime/march_extras.c`'s `vault_key_cstr` (used by every `march_vault_*`
builtin — new/set/get/drop/update/size/set_ttl/whereis/ns_set/ns_get, see the
~10 call sites in that file) assumes its argument is always a `march_string *`:

```c
/* Convert a March string value to a C string key.
 * The key is always a march_string* — cast directly to read its content. */
static char *vault_key_cstr(void *key) {
    march_string *ms = (march_string *)key;
    char *buf = malloc((size_t)ms->len + 1);
    memcpy(buf, ms->data, (size_t)ms->len);
    ...
```

When the March-level call site passes a non-String key (e.g. a tagged `Int`),
the erased UNIFORM-representation bits reach this function unchanged and get
dereferenced as a `march_string*` — the same class of bug as
`[[project_erased_i64_convention]]` (a raw scalar's bit pattern used as a
pointer). The function's own comment ("always a march_string*") directly
contradicts `stdlib/vault.march`'s documented contract that any plain value
works as a key. Either the stdlib's `Vault.set`/`get`/etc. wrapper functions
need to stringify non-String keys (via `to_string`) BEFORE calling into the
`vault_*` builtins, or `vault_key_cstr` itself needs to become kind-aware and
stringify Int/Bool/Atom/Tuple/Ctor keys correctly — right now neither happens
on the compiled path.

## Severity

High — `Vault(v)` typed handles are a headline 0.3.0 feature (the whole
ecosystem migration this session did was largely about adapting to typed
Vault tables per-element-type), and the stdlib doc's own examples encourage
non-String keys. This crashed a real downstream package's test suite
(forgepm) with no assertion output, just a silent process death — the kind of
failure a user would have real trouble diagnosing.

## Suggested fix

Audit `runtime/march_extras.c`'s vault builtins (`march_vault_set`,
`march_vault_get`, `march_vault_drop`, `march_vault_update`,
`march_vault_set_ttl`, `march_vault_ns_set`, `march_vault_ns_get`, etc.) and
either:
1. Have the compiler emit a `to_string`/stringify coercion at the call site
   for non-String key arguments before they reach the builtin, matching the
   documented "stringified on the way in" contract, or
2. Make `vault_key_cstr` kind-aware (mirrors the erased-Float bug filed
   alongside this one, `2026-08-20-record-put-get-float-niche-segfault.md`)
   and format Int/Bool/Atom/Tuple/Ctor keys into their string representation
   directly.

Also worth checking: `test/run_stdlib.exe`'s Vault test coverage — a
non-String-key round-trip test would have caught this before release.

---

## RESOLVED (2026-08-21)

**Both halves were fixed by PR #315** (`ca5c1398`), which landed the FIX but
left this file open in `specs/todos/`:

1. `vault_key_cstr` now classifies the uniform representation instead of
   casting straight to `march_string *` — tagged scalar → `"i:<decimal>"`
   (matching the interpreter's `vault_key_of_value`), `march_string` → its raw
   bytes unchanged (so `Vault.keys()` keeps returning genuine Strings for every
   existing `keys() -> get()` round-trip), boxed Float → `"f:<bits>"`, and a
   Tuple/Ctor key panics with an actionable message rather than folding onto a
   single bucket. Its own doc comment records the two inherent limits (Bool and
   Int are indistinguishable once tagged; a String spelled `"i:5"` collides
   with the Int key 5).
2. `lib/tir/llvm_emit.ml` gained the missing key-coercion arms for the READ
   builtins — `vault_get` / `vault_drop` / `vault_update` / `vault_incr` and
   the `ns_*` trio. Only the writers had been special-cased, so a read passed
   the key with its NATURAL llvm type while the write had stored it tagged, and
   the two stringified to different vault keys.

Re-verified on `origin/main` (`3fda8f46`) before this file was moved: the exact
repro at the top of this file compiles and prints `Some(hello)`, byte-identical
to the interpreter.

**What was still missing, and is added here: the regression fixture.** The
answer to this file's own last line was "nothing covered it". PR #315 shipped
no test, so nothing pinned the fix.
`test/native/vault_non_string_key.march` (+ `.expected`, wired into
`test/dune`) now round-trips ODD, EVEN and NEGATIVE Int keys plus String, Bool
and absent keys through `set`/`get`/`has`/`drop`/`put_new`/`incr`/`update`/
`size`. The three Int flavours are deliberate and the fixture says so in its
own header: the two halves of the bug hid on different values — an EVEN Int
survives a raw store untouched (the erased-i64 untag only shifts odd words),
while an ODD one round-trips *consistently wrong* and looks fine unless you
also print `Vault.keys()` — so a single-value test would have passed against
the broken compiler.

Non-vacuity, by file-copy swap of `runtime/march_extras.c`, `lib/tir/llvm_emit.ml`
and `lib/tir/lower.ml` back to **`c2f747f7`** — the commit BEFORE #315 — followed
by `dune build bin/main.exe` + `@warm-cache` (verified restaged):

```
----- vault_non_string_key -----
  run_exit=139
  RESULT: DIFFERS from golden  (non-vacuous)
1,14d0
< Some(odd)
  ... all 14 golden lines missing — SIGSEGV before the first println ...
```

Against `origin/main` (`3fda8f46`) it MATCHES the golden, which is the correct
result and the point: #315 already fixed the bug, so this fixture is a guard
against regression, not a proof of new work. (First attempt at this proof used
`0defdbfa` as "pre-#315" — that is #316, one commit LATER, and the fixture
passed there too. The parent-of-#315 commit is the right baseline.)
