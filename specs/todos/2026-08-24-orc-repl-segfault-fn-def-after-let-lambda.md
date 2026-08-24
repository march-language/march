# ORC REPL backend: SIGSEGV defining a fn after a let-bound lambda/map

## Minimal repro

```
fn fib(n) do if n < 2 do n else fib(n-1) + fib(n-2) end end
let ys = List.map(List.range(1, 10), fn x -> x * 2)
fn sq(x) do x * x end
```

Run via:
```bash
MARCH_JIT_BACKEND=orc ./_build/default/bin/main.exe < repro.txt
```

**Result:** Process exits with code 139 (SIGSEGV) on the third line.

## Control case

Two consecutive `fn` definitions without the intervening let-lambda work fine:

```
fn fib(n) do if n < 2 do n else fib(n-1) + fib(n-2) end end
fn sq(x) do x * x end
```

**Result:** Both backends handle this without error.

## Context

The default clang backend handles the same session fine. This blocks flipping ORC to the default REPL backend (perf plan Phase 2.2) until fixed or root-caused. Found while building `bench/interp/repl_session.txt`, which was narrowed to avoid it.
