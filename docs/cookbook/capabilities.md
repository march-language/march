---
layout: cookbook
title: "Cookbook: Capabilities"
permalink: /docs/cookbook/capabilities/
---

# Capabilities

The capability system lets you express resource requirements in function types. A function annotated with `needs Cap(IO)` can only be called by code that also holds that capability — enforced at compile time with no runtime cost.

---

## Declaring requirements

`needs` lists the capabilities a function requires:

```march
needs Cap(IO)
fn write_log(msg : String) : () do
  File.append("app.log", msg ++ "\n")
end
```

A caller that doesn't declare `needs Cap(IO)` will get a compile error if it tries to call `write_log`. The requirement propagates upward through the call graph automatically.

---

## Proof capabilities

`proof cap` declares a capability that can only be *created* inside one module — useful for authority tokens:

```march
mod Admin do
  proof cap AdminCap

  fn make_cap() : Cap(AdminCap) do
    cap AdminCap
  end

  needs Cap(AdminCap)
  fn delete_all_users() : Result((), String) do
    Db.execute("DELETE FROM users")
  end
end
```

Outside `Admin`, no code can manufacture a `Cap(AdminCap)`. It can only pass one through that it received from `Admin.make_cap()`. The capability becomes an unforgeable proof of authorization.

---

## Realtime exclusion

`Tagged(X, Realtime)` marks a computation as realtime-safe. Calling `Cap(Alloc)`, `Cap(IO)`, or `Cap(Panic)` inside a realtime-tagged function is a compile error:

```march
fn process_sample(buf : Tagged(Buffer, Realtime)) : Tagged(Buffer, Realtime) do
  -- allocating here would be a compile error
  transform(buf)
end
```

This statically prevents audio/video processing code from accidentally allocating or blocking.

---

## Complete example: sandboxed plugin runner

```march
mod Plugin do
  proof cap PluginCap

  fn grant() : Cap(PluginCap) do cap PluginCap end

  needs Cap(PluginCap)
  fn run(code : String) : Result(String, String) do
    sandbox_eval(code)
  end
end

mod Main do
  fn main() do
    let cap = Plugin.grant()
    match Plugin.run(cap, "1 + 1") do
      Ok(v)  -> println("result: " ++ v)
      Err(e) -> println("error: " ++ e)
    end
  end
end
```

The `PluginCap` ensures that only code explicitly granted the capability can invoke the sandbox runner. Untrusted code paths can never call `Plugin.run` — not because of a runtime check, but because the type won't compile without the cap.
