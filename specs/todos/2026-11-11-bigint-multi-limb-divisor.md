`[P3]` `BigInt.div` / `BigInt.mod_` reject any divisor of 10000 or more, and the panic message gives the wrong bound (2026-11-11)

Division is only implemented for a single base-10000 limb. Any `|b| >= 10000` panics. The doc strings
state the limitation, but the panic text says `(use |b| < 10^9)`, and a divisor such as 123456 that
follows that advice still panics. A BigInt type that cannot divide by a five-digit number is a
functional gap.

Repro:

```march
mod A do
needs IO.Console
fn main(_c : Cap(IO.Console)) do
  let a = BigInt.from_int(123456789012)
  println(BigInt.to_string(BigInt.div(a, BigInt.from_int(9999))))
  println(BigInt.to_string(BigInt.div(a, BigInt.from_int(10000))))
end
end
```

Expected: `12346913` then `12345678`.

Actual (interpreted / compiled): interpreted and compiled agree: `12346913`, then `The program panicked: BigInt.div: multi-limb divisor not yet supported (use |b| < 10^9)`. `BigInt.mod_(a, BigInt.from_int(123456))` panics the same way.

Source: `div`, `mod_` in `stdlib/bigint.march`. One fix direction: schoolbook long division over limbs; until then the message should say 10^4.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
