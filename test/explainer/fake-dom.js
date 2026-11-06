// A very small DOM for the figure tests: enough for chapters.js to build its elements
// in, and to read back what it built as markup. Not a browser: no layout, no styles.
'use strict';

function element(tag, doc) {
  const el = {
    tag, attrs: {}, children: [], parentNode: null, ownerDocument: doc, style: {}, _text: '',
    setAttribute(k, v) { el.attrs[k] = String(v); },
    getAttribute(k) { return k in el.attrs ? el.attrs[k] : null; },
    removeAttribute(k) { delete el.attrs[k]; },
    appendChild(child) {
      if (child.parentNode) child.parentNode.removeChild(child);
      el.children.push(child); child.parentNode = el; return child;
    },
    removeChild(child) {
      const i = el.children.indexOf(child);
      if (i >= 0) { el.children.splice(i, 1); child.parentNode = null; }
      return child;
    },
    remove() { if (el.parentNode) el.parentNode.removeChild(el); },
    get className() { return el.attrs.class || ''; },
    set className(v) { el.attrs.class = v; },
    get textContent() { return el._text + el.children.map((c) => c.textContent).join(''); },
    set textContent(v) { el.children.forEach((c) => { c.parentNode = null; }); el.children = []; el._text = String(v); },
    get innerHTML() { return esc(el._text) + el.children.map((c) => c.outerHTML).join(''); },
    set innerHTML(v) {
      if (v !== '') throw new Error('fake-dom: innerHTML can only be cleared');
      el.textContent = '';
    },
    get outerHTML() {
      const attrs = Object.keys(el.attrs).map((k) => ` ${k}="${el.attrs[k]}"`).join('');
      return `<${tag}${attrs}>${el.innerHTML}</${tag}>`;
    },
    classList: {
      add(c) { const cs = el.className.split(' ').filter(Boolean); if (!cs.includes(c)) cs.push(c); el.className = cs.join(' '); },
      remove(c) { el.className = el.className.split(' ').filter((x) => x && x !== c).join(' '); },
      contains(c) { return el.className.split(' ').includes(c); },
    },
  };
  return el;
}

function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function document() {
  const doc = {
    createElement: (tag) => element(tag, doc),
    createElementNS: (_ns, tag) => element(tag, doc),
  };
  return doc;
}

// A figure's stage: an element with a width.
function stage(width) {
  const host = document().createElement('div');
  host.clientWidth = width || 680;
  return host;
}

module.exports = { document, stage };
