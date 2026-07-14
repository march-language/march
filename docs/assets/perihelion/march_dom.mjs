// march_dom.mjs — DOM wrapper functions for March programs compiled with --target js.
// Imported automatically when the compiled module uses the Dom stdlib module.
// All functions use the March closure ABI for callbacks: handler._0(handler, args...).

// ── Helpers ──────────────────────────────────────────────────────────────────

function some(v) { return { $: "Some", _0: v }; }
const none = { $: "None" };
function opt(v) { return (v != null) ? some(v) : none; }

function list_of_array(arr) {
  let result = { $: "Nil" };
  for (let i = arr.length - 1; i >= 0; i--)
    result = { $: "Cons", _0: arr[i], _1: result };
  return result;
}

// ── Query ─────────────────────────────────────────────────────────────────────

export function march_dom_get_element_by_id(id) {
  return opt(document.getElementById(id));
}

export function march_dom_query_selector(sel) {
  return opt(document.querySelector(sel));
}

export function march_dom_query_selector_all(sel) {
  return list_of_array(Array.from(document.querySelectorAll(sel)));
}

// ── Document ─────────────────────────────────────────────────────────────────

export function march_dom_body() { return document.body; }
export function march_dom_document_element() { return document.documentElement; }

// ── Construction ─────────────────────────────────────────────────────────────

export function march_dom_create_element(tag) { return document.createElement(tag); }
export function march_dom_create_text_node(text) { return document.createTextNode(text); }
export function march_dom_clone(el) { return el.cloneNode(true); }

// ── Tree manipulation ─────────────────────────────────────────────────────────

export function march_dom_append_child(parent, child) { parent.appendChild(child); }
export function march_dom_prepend_child(parent, child) { parent.prepend(child); }
export function march_dom_remove_child(parent, child) { parent.removeChild(child); }
export function march_dom_replace_child(parent, new_child, old_child) {
  parent.replaceChild(new_child, old_child);
}
export function march_dom_remove(el) { el.remove(); }
export function march_dom_parent(el) { return opt(el.parentElement); }
export function march_dom_children(el) {
  return list_of_array(Array.from(el.children));
}
export function march_dom_first_child(el) { return opt(el.firstElementChild); }
export function march_dom_last_child(el) { return opt(el.lastElementChild); }
export function march_dom_clear_children(el) { el.replaceChildren(); }

// ── Content ──────────────────────────────────────────────────────────────────

export function march_dom_get_text(el) { return el.textContent ?? ""; }
export function march_dom_set_text(el, text) { el.textContent = text; }
export function march_dom_get_html(el) { return el.innerHTML; }
export function march_dom_set_html(el, html) { el.innerHTML = html; }

// ── Attributes ───────────────────────────────────────────────────────────────

export function march_dom_get_attribute(el, name) {
  return opt(el.getAttribute(name));
}
export function march_dom_set_attribute(el, name, val) { el.setAttribute(name, val); }
export function march_dom_remove_attribute(el, name) { el.removeAttribute(name); }
export function march_dom_has_attribute(el, name) { return el.hasAttribute(name); }

// ── CSS classes ───────────────────────────────────────────────────────────────

export function march_dom_class_add(el, cls) { el.classList.add(cls); }
export function march_dom_class_remove(el, cls) { el.classList.remove(cls); }
export function march_dom_class_toggle(el, cls) { el.classList.toggle(cls); }
export function march_dom_class_contains(el, cls) { return el.classList.contains(cls); }

// ── Inline style ──────────────────────────────────────────────────────────────

export function march_dom_set_style(el, prop, val) { el.style.setProperty(prop, val); }
export function march_dom_get_style(el, prop) {
  return el.style.getPropertyValue(prop);
}

// ── Form values ───────────────────────────────────────────────────────────────

export function march_dom_get_value(el) { return el.value ?? ""; }
export function march_dom_set_value(el, val) { el.value = val; }

// ── Events ────────────────────────────────────────────────────────────────────
// March closures use the protocol: handler._0(handler, arg1, arg2, ...)

export function march_dom_add_event_listener(el, event_name, handler) {
  el.addEventListener(event_name, (e) => { handler._0(handler, e); });
}

export function march_dom_remove_event_listener(el, event_name, handler) {
  // Note: removeEventListener requires the exact same function reference.
  // This wrapper creates a new function each time, so it cannot remove by value.
  // For removable listeners, store the handler reference at the March level.
  el.removeEventListener(event_name, (e) => { handler._0(handler, e); });
}

// ── Event properties ──────────────────────────────────────────────────────────

export function march_dom_event_target(ev) { return ev.target; }
export function march_dom_event_type(ev) { return ev.type; }
export function march_dom_event_key(ev) { return ev.key ?? ""; }
export function march_dom_prevent_default(ev) { ev.preventDefault(); }
export function march_dom_stop_propagation(ev) { ev.stopPropagation(); }
export function march_dom_event_x(ev) { return Math.trunc(ev.offsetX); }
export function march_dom_event_y(ev) { return Math.trunc(ev.offsetY); }

// ── Input polling ─────────────────────────────────────────────────────────────
// Buffers pointerdown taps per element; march_dom_taps drains the buffer.
// Poll once per animation frame for exactly-once delivery of each tap.

const __tap_buffers = new WeakMap();

export function march_dom_taps(el) {
  let buf = __tap_buffers.get(el);
  if (buf === undefined) {
    buf = [];
    __tap_buffers.set(el, buf);
    // Pointer Events unify mouse / trackpad / touch / pen into ONE event that
    // fires exactly once per press. Listen to `pointerdown` alone: with a
    // single event type there is nothing to de-duplicate, so none of the
    // dedup schemes this code cycled through -- a shared time window, then a
    // gesture-state machine -- can exist, and neither can their failure modes
    // (a window too short/long to match a real press-hold; a `pressActive`
    // flag left stuck true when a release event was missed, silently eating
    // every tap until a multi-second timeout). Acting on press rather than
    // release is also the most responsive choice for a tap-to-act game and
    // the least-missed event in a gesture.
    const push = (x, y) => buf.push({ _0: Math.trunc(x), _1: Math.trunc(y) });
    if (window.PointerEvent) {
      el.addEventListener("pointerdown", (e) => push(e.offsetX, e.offsetY));
    } else {
      // No Pointer Events (very old engines only): mouse and touch events do
      // not both fire here the way they would alongside pointer events, so
      // listening to each is safe without de-duplication.
      el.addEventListener("mousedown", (e) => push(e.offsetX, e.offsetY));
      el.addEventListener("touchstart", (e) => {
        e.preventDefault();
        const t = e.changedTouches[0];
        const rect = el.getBoundingClientRect();
        push(t.clientX - rect.left, t.clientY - rect.top);
      }, { passive: false });
    }
  }
  return list_of_array(buf.splice(0, buf.length));
}

let __key_buffer = null;

export function march_dom_key_presses() {
  if (__key_buffer === null) {
    __key_buffer = [];
    document.addEventListener("keydown", (e) => {
      if (e.key === " " || e.key.startsWith("Arrow")) e.preventDefault();
      __key_buffer.push(e.key);
    });
  }
  return list_of_array(__key_buffer.splice(0, __key_buffer.length));
}

// ── Storage ───────────────────────────────────────────────────────────────────

export function march_dom_store_get(key) {
  try { return opt(window.localStorage.getItem(key)); } catch (e) { return none; }
}

export function march_dom_store_set(key, val) {
  try { window.localStorage.setItem(key, val); } catch (e) { }
}

// ── Pointer / viewport polling ──────────────────────────────────────────────

const __pointer_positions = new WeakMap();

export function march_dom_pointer_pos(el) {
  let pos = __pointer_positions.get(el);
  if (pos === undefined) {
    const rect = el.getBoundingClientRect();
    pos = { x: Math.trunc(rect.width / 2), y: Math.trunc(rect.height / 2) };
    __pointer_positions.set(el, pos);
    el.addEventListener("mousemove", (e) => {
      pos.x = Math.trunc(e.offsetX);
      pos.y = Math.trunc(e.offsetY);
    });
  }
  return { _0: pos.x, _1: pos.y };
}

export function march_dom_window_size() {
  return { _0: Math.trunc(window.innerWidth), _1: Math.trunc(window.innerHeight) };
}

// ── Window ────────────────────────────────────────────────────────────────────

export function march_dom_alert(msg) { window.alert(msg); }
export function march_dom_href() { return window.location.href; }
export function march_dom_set_href(url) { window.location.href = url; }

// cb : Int -> Unit — called with a dummy 0 argument (ignored). A true
// zero-arg March closure can't be spelled at the extern boundary; see
// stdlib/dom.march's module doc.
export function march_dom_set_timeout(ms, cb) {
  setTimeout(() => { cb._0(cb, 0); }, ms);
}
export function march_dom_set_interval(ms, cb) {
  setInterval(() => { cb._0(cb, 0); }, ms);
}
export function march_dom_request_animation_frame(cb) {
  requestAnimationFrame(() => { cb._0(cb, 0); });
}
