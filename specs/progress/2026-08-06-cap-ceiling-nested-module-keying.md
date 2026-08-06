# `--cap-strict` false positive on modules nested two or more levels deep

Filed and fixed 2026-08-06, found while researching capabilities.

## Symptom

A module nested two levels deep that declares exactly the capability it uses
was reported as not declaring it:

```march
mod S1 do
  mod Innocent do
    mod DeeplyNested do
      needs IO.FileWrite
      fn exfil(data : String) : Bool do
        match file_write("/tmp/loot", data) do
          Ok(_) -> true
          Err(_) -> false
        end
      end
    end
  end
  fn main() do
    let _ = Innocent.DeeplyNested.exfil("secret")
    ()
  end
end
```

```
$ march --compile --cap-strict -o /tmp/bin nested.march
-- CAPABILITY CEILING --
module `Innocent.DeeplyNested` uses `IO.FileWrite` but does not declare `needs IO.FileWrite`
```

`--check` alone reported nothing — the ceiling only runs on the compile path.
A single level of nesting was clean, which is what localised the bug to depth
>= 2.

## Root cause — two mistakes in the same line

`lib/typecheck/typecheck.ml`, the `Ast.DMod` branch of `check_decl`, recorded

```ocaml
module_caps = (name.txt, inner_needs) :: env'.module_caps;
```

1. **Wrong key.** `name.txt` is the module's BARE name. The ceiling check in
   `bin/main.ml` joins `module_caps` against TIR attribution, whose owner is the
   fully-QUALIFIED path (`Innocent.DeeplyNested`, from `lower.ml`'s `mod_prefix`
   accumulation). `check_module_needs` is handed `~cap_qname_prefix` two lines
   earlier for exactly this reason; `module_caps` did not use it. At depth 1 the
   two spellings coincide — the entry module is unwrapped by desugar, so
   `cap_qual_prefix` is `""` inside its body — which is why only depth >= 2 was
   affected.

2. **Dropped at the enclosing boundary.** The entry was consed onto
   `env'.module_caps`, which derives from the OUTER env, not `inner_env`. So an
   entry recorded by a module nested inside another `DMod` never propagated past
   that `DMod` — `DeeplyNested`'s row existed only inside `Innocent`'s scope and
   never reached the top-level env the ceiling reads. Either mistake alone
   produces the same false positive, so both had to be fixed.

## Fix

Key each module under its fully-qualified path, keep the bare name as a second
entry when the two differ (Check 4 and `module_wide_caps` look up `use` paths AS
WRITTEN, so a sibling imported by short name must still resolve), and carry
`inner_env.module_caps` outward instead of the outer env's.

## Tests

`test/test_cap_ceiling.ml`:

- accept: a doubly-nested module that declares its own `needs` compiles clean
  under `--cap-strict`.
- reject: the same shape without the declaration still fails, and the new
  `rejects_naming` helper pins the reported owner as `Innocent.DeeplyNested` —
  an accept-only pair, or a reject test that only checked "some ceiling
  violation fired", would pass on the buggy spelling too.

## Adjacent, NOT fixed

Two things noticed while measuring, both pre-existing and out of scope here:

- A `--cap-strict` program that never calls `println` itself still reports
  `` `IO.Console` is used but cannot be attributed to any module`` — an
  unattributed capability reaching the emitted code through an indirect call.
  Reproduces with no nesting at all, so it is unrelated to the keying bug; the
  regression tests above call `println` from the entry module (as the existing
  accept tests do) so the capability is attributed.
- `cap_strip` test 3 (`--cap-sandbox` pure binary embeds a deny-default
  profile) fails on this machine at the base commit as well — verified by
  reverting the fix, rebuilding and re-running that suite alone.
