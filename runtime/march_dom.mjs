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
export function march_dom_prevent_default(ev) { ev.preventDefault(); }
export function march_dom_stop_propagation(ev) { ev.stopPropagation(); }

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
