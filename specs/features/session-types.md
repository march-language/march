# March Session Types

**Last Updated:** April 13, 2026
**Status:** Complete — type system, eval, and compiled (TIR → LLVM) paths all working.

**Implementation:**
- `lib/typecheck/typecheck.ml` — `session_ty` type (line 92), `TChan` (line 87), `dual_session_ty` (~2680), `project_protocol` (~2693), Chan.* special cases in `infer_expr` (~1510–1600)
- `lib/ast/ast.ml` — `session_ty`, `protocol_def`, `proto_step` AST types
- `lib/eval/eval.ml` — `VChan`, `chan_endpoint` (~line 40), `Chan.new/send/recv/close/choose/offer` builtins (~3213)
- `lib/tir/lower.ml` — `Chan.*` and `MPST.*` calls lowered to `chan_new`/`chan_send`/`chan_recv`/`chan_close`/`chan_choose`/`chan_offer` and `mpst_new`/`mpst_send`/`mpst_recv`/`mpst_close` TIR function calls
- `lib/tir/llvm_emit.ml` — `builtin_ret_ty` and `mangle_extern` entries for channel builtins; LLVM `declare` for all `march_chan_*` and `march_mpst_*` functions
- `lib/tir/defun.ml` — channel builtin names registered so defun doesn't treat them as free variables
- `runtime/march_extras.c` — C runtime: `march_chan_new/send/recv/close/choose/offer` (binary, queue-based), `march_mpst_new/send/recv/close` (multi-party, N×N queue matrix)
- `runtime/march_runtime.h` — declarations for all channel runtime functions

---

## Overview

March implements **binary session types** for typed two-party protocols. A `protocol` declaration defines the communication sequence between two roles. The compiler projects the global protocol onto each role's local type, verifies duality (one role's send = the other's receive), and tracks the channel's state as a linear type that advances at each operation.

This catches protocol violations, missing branches, and use-after-close bugs at compile time.

---

## 1. Core Types

### Internal type representation (`lib/typecheck/typecheck.ml:87–98`)

```ocaml
(* A channel endpoint carries a linear session type *)
| TChan of session_ty ref   (* Linear session-typed channel endpoint *)

and session_ty =
  | SSend   of ty * session_ty           (* Send a value of type T, then follow S *)
  | SRecv   of ty * session_ty           (* Receive a value of type T, then follow S *)
  | SChoose of (string * session_ty) list (* Actively select a branch label *)
  | SOffer  of (string * session_ty) list (* Passively wait for the other side to pick *)
  | SVar    of string                    (* Recursive type variable: µX.S *)
  | SRec    of string * session_ty       (* Recursive binding: Rec(X, S) *)
  | SEnd                                 (* Protocol complete — channel may be closed *)
  | SError                               (* Error sentinel *)
```

`TChan` is always **linear** — the type checker enforces that the channel endpoint is not duplicated or dropped without closing.

### Surface syntax (AST, `lib/ast/ast.ml`)

```march
protocol Echo between Alice, Bob do
  Alice -> Bob : String
  Bob -> Alice : String
end
```

Parsed into `Ast.protocol_def` with `proto_steps` listing each interaction.

---

## 2. Protocol Registration and Projection

### `project_protocol` (`lib/typecheck/typecheck.ml:~2693`)

When a `DProtocol` declaration is type-checked:
1. All roles are collected from the protocol steps
2. Each role's **local session type** is projected from the global choreography
3. For two-party protocols, **duality** is verified: `dual_session_ty(proj_A) = proj_B`
4. The protocol info is stored in `env.protocols`

### Duality (`dual_session_ty`, line ~2680)

```ocaml
SSend (t, s)  → SRecv (t, dual_session_ty s)
SRecv (t, s)  → SSend (t, dual_session_ty s)
SChoose bs    → SOffer  (map dual bs)
SOffer  bs    → SChoose (map dual bs)
SEnd          → SEnd
SRec (x, s)   → SRec (x, dual_session_ty s)
```

---

## 3. Type-Checking Channel Operations

All `Chan.*` operations are **special-cased** in `infer_expr` (`lib/typecheck/typecheck.ml:~1510–1620`) — they don't go through normal function application typing because they advance the channel's linear type.

### `Chan.new(proto_name)` → `(Chan(RoleA), Chan(RoleB))`

Creates two dual endpoints. Both are typed `TLin(Linear, TChan(ref proj_role))`. The channel is linear — it must be consumed exactly once.

### `Chan.send(ch, value)` → new `Chan`

```
ch   : TLin(Linear, TChan(ref SSend(T, S)))
value: T
────────────────────────────────────────────
result: TLin(Linear, TChan(ref S))
```

The channel advances from `SSend(T, S)` to `S`. The old binding is consumed (linear).

### `Chan.recv(ch)` → `(value, new Chan)`

```
ch : TLin(Linear, TChan(ref SRecv(T, S)))
────────────────────────────────────────────
result: TTuple [T; TLin(Linear, TChan(ref S))]
```

### `Chan.close(ch)` → `Unit`

```
ch : TLin(Linear, TChan(ref SEnd))
────────────────────────────────
result: Unit
```

Errors if channel is not at `SEnd`.

### `Chan.choose(ch, label)` → new `Chan`

```
ch    : TLin(Linear, TChan(ref SChoose [(l₁, S₁); …]))
label : Atom
─────────────────────────────────────────────────────
result: TLin(Linear, TChan(ref Sᵢ))  where lᵢ = label
```

### `Chan.offer(ch)` → `(label, new Chan)`

```
ch : TLin(Linear, TChan(ref SOffer [(l₁, S₁); …]))
──────────────────────────────────────────────────
result: TTuple [Atom; TLin(Linear, TChan(ref S_chosen))]
```

---

## 4. Evaluation (`lib/eval/eval.ml:~40, ~1529, ~3213`)

### `VChan` value

```ocaml
type chan_endpoint = {
  ce_proto : string;       (* protocol name *)
  ce_id    : int;          (* unique channel pair id *)
  ce_role  : string;       (* which role this endpoint is *)
  ce_state : session_ty ref; (* current local session state, mutable *)
  ce_buf   : value Queue.t;  (* shared message buffer between endpoints *)
  ce_closed: bool ref;
}
```

Channels are created in pairs sharing the same `ce_buf`. `Chan.send` enqueues; `Chan.recv` dequeues. The session state is advanced on each operation and checked for protocol conformance at runtime (belt-and-suspenders over compile-time checking).

### Builtins registered in `base_env` (`lib/eval/eval.ml:~3213`)

| Builtin | Behavior |
|---------|----------|
| `Chan.new` | Creates dual `VChan` endpoints |
| `Chan.send` | Enqueues value, advances state, returns new endpoint |
| `Chan.recv` | Dequeues value (blocks if empty), returns `(val, new_endpoint)` |
| `Chan.close` | Marks endpoint closed, errors if state ≠ `SEnd` |
| `Chan.choose` | Sends label, advances state to selected branch |
| `Chan.offer` | Receives label, advances state to selected branch |

---

## 5. Example

```march
protocol Ping between Client, Server do
  Client -> Server : String  -- the ping message
  Server -> Client : String  -- the pong reply
end

fn client(ch : Chan) do
  let ch = Chan.send(ch, "ping")
  let (reply, ch) = Chan.recv(ch)
  Chan.close(ch)
  reply
end

fn server(ch : Chan) do
  let (msg, ch) = Chan.recv(ch)
  let ch = Chan.send(ch, "pong: " ++ msg)
  Chan.close(ch)
end

fn main do
  let (client_ch, server_ch) = Chan.new("Ping")
  server(server_ch)
  client(client_ch)
end
```

See also: `examples/session_echo.march` (if present)

---

## 6. TIR Lowering and Native Compilation

Session-typed channels compile to native binaries via the standard TIR pipeline:

1. **Lower** (`lower.ml`): `Chan.*`/`MPST.*` AST calls are pattern-matched before the general `EApp` case and lowered to `EApp(chan_new, args)` etc.
2. **Mono** (`mono.ml`): Channel types are `TCon("Chan", [])` — already monomorphic, no specialization needed.
3. **Defun** (`defun.ml`): Channel builtins registered in `builtin_names` so they're treated as top-level, not captured.
4. **Perceus** (`perceus.ml`): `TCon("Chan", [])` matches `needs_rc = true`, so channel endpoints get proper RC tracking.
5. **LLVM emit** (`llvm_emit.ml`): Channel calls map to `march_chan_*` / `march_mpst_*` C runtime functions.

### Runtime representation

**Binary channels:** Each endpoint is a 3-field heap object `(pair_ptr, role_index, closed)`. A shared `march_chan_pair` struct holds two directional queues (A→B and B→A) protected by a mutex. Pair refcount tracks live endpoints.

**Multi-party (MPST):** Each endpoint is a 3-field heap object `(session_ptr, role_index, closed)`. A shared `march_mpst_session` struct holds N×N directed queues. Role names passed as strings are resolved to indices at runtime.

---

## 7. Known Limitations

- **No `needs` capability** — There's no `needs Chan` or similar declaration required to use session types.
- **Synchronous channels** — The native runtime uses blocking dequeue. If a receiver calls `Chan.recv` before the sender has sent, the program aborts. This matches the interpreter behavior. True async channels (with blocking/waking) would require scheduler integration.
