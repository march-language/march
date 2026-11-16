`[P2]` Js.Dom.unlisten never removes the listener (2026-11-11)

`march_dom_add_event_listener` registers a fresh arrow function wrapping the March closure. `march_dom_remove_event_listener` passes another fresh arrow function to `removeEventListener`, which matches nothing, so the original listener stays attached. `Js.Dom.unlisten` is a silent no-op and handlers accumulate. The doc string in `stdlib/dom.march` now says so.

Repro (JS runtime, run with `node dom_unlisten.mjs runtime/march_dom.mjs`):
```js
import { pathToFileURL } from "node:url";
const dom = await import(pathToFileURL(process.argv[2]).href);
const el = new EventTarget();
let calls = 0;
const handler = { _0: (_self, _ev) => { calls += 1; } };
dom.march_dom_add_event_listener(el, "click", handler);
el.dispatchEvent(new Event("click"));
dom.march_dom_remove_event_listener(el, "click", handler);
el.dispatchEvent(new Event("click"));
console.log(calls);
```

Expected: `1`.

Actual (node, JS runtime): `2`.

Source: `march_dom_add_event_listener` / `march_dom_remove_event_listener` in `runtime/march_dom.mjs`. Keeping the wrapper in a WeakMap keyed by the closure would fix it.

Found by the 2026-10-18 doc sweep; re-verified 2026-11-11 on a7110f95f.
