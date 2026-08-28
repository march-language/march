---
layout: cookbook
title: "Cookbook: Capabilities"
permalink: /docs/cookbook/capabilities/
---

# Capabilities

The capability system lets you express resource requirements in function types. A module that declares `needs IO` can only be used by code that also possesses that capability, enforced at compile time with no runtime cost.

---

## Declaring requirements

`needs` lists the capabilities a function requires:

```march
needs IO
fn write_log(msg : String) : Result((), String) do
  File.append("app.log", msg ++ "\n")
end
```

A caller that doesn't declare `needs IO` will get a compile error if it tries to call `write_log`. The requirement propagates upward through the call graph automatically.

---

## Proof capabilities

`proof cap` declares a capability that can only be *created* inside one module, useful for authority tokens. Minting goes through the gated `mint_cap` builtin, which only typechecks inside a public function of the declaring module and takes the ambient `Cap(IO)` (or a narrower cap) to authorize the mint. Proof-cap types are always referred to by their qualified `Module.Name` form, even from inside the declaring module:

```march
mod Admin do
  proof cap AdminCap
  needs IO
  needs Admin.AdminCap

  fn make_cap(io : Cap(IO)) : Cap(Admin.AdminCap) do
    mint_cap(io)
  end

  fn delete_all_users(_admin : Cap(Admin.AdminCap)) : Result((), String) do
    Db.execute("DELETE FROM users")
  end
end
```

Outside `Admin`, no code can manufacture a `Cap(Admin.AdminCap)`. It can only pass one through that it received from `Admin.make_cap()`. The capability becomes an unforgeable proof of authorization.

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
mod PluginDemo do
  mod Plugin do
    proof cap PluginCap
    needs IO
    needs Plugin.PluginCap

    fn grant(io : Cap(IO)) : Cap(Plugin.PluginCap) do
      mint_cap(io)
    end

    -- Stand-in for a real sandboxed evaluator — the point of this example is
    -- the capability gate around `run`, not the evaluation strategy itself.
    fn sandbox_eval(code : String) : Result(String, String) do
      Ok("evaluated: " ++ code)
    end

    fn run(_cap : Cap(Plugin.PluginCap), code : String) : Result(String, String) do
      sandbox_eval(code)
    end
  end

  mod Main do
    needs IO
    needs Plugin.PluginCap

    fn main(root : Cap(IO)) do
      let cap = Plugin.grant(root)
      -- `cap` must be threaded explicitly into `run` below — capabilities
      -- are ordinary values passed as arguments, not ambient state; there is
      -- no way to manufacture one without going through `Plugin.grant`
      match Plugin.run(cap, "1 + 1") do
        Ok(v)  -> println("result: " ++ v)
        Err(e) -> println("error: " ++ e)
      end
    end
  end
end
```

The `PluginCap` ensures that only code explicitly granted the capability can invoke the sandbox runner. Untrusted code paths can never call `Plugin.run`: not because of a runtime check, but because the type won't compile without the cap.
