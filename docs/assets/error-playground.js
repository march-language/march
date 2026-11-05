/*
 * Error playground (docs/_includes/error-playground.html, on docs/error-messages.md).
 *
 * Every example's program and the output the native `march --check` prints for it
 * are in assets/error-tour/examples.json (scripts/gen-error-tour.py), so picking an
 * example shows its output at once, with no compiler. Once the program is edited,
 * Check runs window.marchCheck (js/march_browser_compile.ml): the real parser,
 * desugarer and typechecker, rendering diagnostics as `march --check` does
 * (scripts/browser-repl-smoke.js holds the two to the same text). The compiler
 * (about 3 MB) starts downloading on the first edit. The refinement checker needs
 * z3, which a browser does not have, so a refinement error is never reported here.
 *
 * Any element with data-error-example="<name>" (the "Try it" buttons on the page)
 * loads that example, checks it and scrolls the playground into view.
 */
(function () {
  "use strict";
  var wrap = document.getElementById("ep-wrap");
  if (!wrap) return;
  var base = wrap.dataset.base || "";
  var ver = wrap.dataset.ver || "0";
  var select = document.getElementById("ep-select");
  var editor = document.getElementById("ep-editor");
  var output = document.getElementById("ep-output");
  var status = document.getElementById("ep-status");
  var original = "";
  var shown = "playground.march"; // file name the current example's header uses
  var examples = null;            // examples.json, once fetched
  var compiler = null; // "loading" | "ready" | "failed"
  var waiting = [];

  function setStatus(s) { status.textContent = s; }

  function loadScript(src, ok, err) {
    var s = document.createElement("script");
    s.src = src; s.onload = ok; s.onerror = err;
    document.head.appendChild(s);
  }

  function withCompiler(cb) {
    if (compiler === "ready") { cb(); return; }
    if (compiler === "failed") { info("The checker failed to load. Reload the page to try again."); return; }
    waiting.push(cb);
    if (compiler === "loading") return;
    compiler = "loading";
    setStatus("Loading the compiler (about 2 MB)…");
    var done = function () {
      compiler = "ready";
      setStatus("");
      var q = waiting; waiting = [];
      q.forEach(function (f) { f(); });
    };
    loadScript(base + "/assets/march_stdlib.js?v=" + ver, function () {
      loadScript(base + "/assets/march_compile.js?v=" + ver, done, fail);
    }, fail);
  }

  function fail() {
    compiler = "failed";
    waiting = [];
    setStatus("");
    info("The checker failed to load. Reload the page to try again.");
  }

  function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function info(msg) {
    output.innerHTML = '<span class="ep-info">' + escapeHtml(msg) + "</span>";
  }

  // Colour the header lines and the caret lines; everything else stays plain.
  function show(text) {
    output.innerHTML = text.split("\n").map(function (line) {
      var h = escapeHtml(line);
      if (/^-- /.test(line)) return '<span class="ep-head">' + h + "</span>";
      if (/^\s+\^+\s*$/.test(line)) return '<span class="ep-caret">' + h + "</span>";
      return h;
    }).join("\n");
    output.scrollTop = 0;
  }

  function check() {
    // An unedited example: the output `march --check` printed for it when the page
    // was generated, which the in-browser checker is tested to match.
    if (examples && editor.value === original && examples[select.value] &&
        examples[select.value].source === original) {
      show(examples[select.value].output);
      return;
    }
    withCompiler(function () {
      if (typeof window.marchCheck !== "function") {
        info("This copy of the site's compiler bundle predates the in-browser checker. " +
             "It is rebuilt after each merge, so it will be here soon. Until then, run " +
             "`march --check` on the program locally.");
        return;
      }
      // Run the checker from a promise callback, not straight from the click or
      // load event. Measured in Chromium (2026-11-05): the same marchCheck call took
      // ~1,100 ms from any task (click, setTimeout, rAF, MessageChannel) and ~70 ms
      // from a microtask. Node shows no such gap; the cause is not established.
      var source = editor.value;
      Promise.resolve().then(function () {
        var r;
        try { r = window.marchCheck(source, shown); }
        catch (e) { info("The checker crashed: " + e); return; }
        if (r.output) show(r.output);
        else output.innerHTML = '<span class="ep-ok">No errors. The program typechecks.</span>';
      });
    });
  }

  var examplesReq = null;
  function fetchExamples() {
    if (!examplesReq) {
      examplesReq = fetch(base + "/assets/error-tour/examples.json?v=" + ver)
        .then(function (res) {
          if (!res.ok) throw new Error(res.status + " " + res.statusText);
          return res.json();
        })
        .then(function (j) { examples = j; return j; });
    }
    return examplesReq;
  }

  function load(name, then) {
    var put = function (ex) {
      original = ex.source;
      shown = ex.file;
      editor.value = ex.source;
      setStatus("");
      if (then) then();
    };
    if (examples && examples[name]) { put(examples[name]); return; }
    setStatus("Loading example…");
    fetchExamples()
      .then(function (j) {
        if (!j[name]) throw new Error("no example named " + name);
        put(j[name]);
      })
      .catch(function (e) {
        examplesReq = null;
        setStatus("");
        info("Could not load the example: " + e.message);
      });
  }

  select.addEventListener("change", function () { load(select.value, check); });
  document.getElementById("ep-check").addEventListener("click", check);
  document.getElementById("ep-revert").addEventListener("click", function () {
    editor.value = original;
    check();
  });

  // Start fetching the compiler as soon as someone edits, so it is usually ready by
  // the time they press Check.
  editor.addEventListener("input", function () { withCompiler(function () {}); });

  editor.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      check();
    } else if (e.key === "Tab" && !e.shiftKey) {
      // Indent instead of leaving the editor.
      e.preventDefault();
      var s = editor.selectionStart;
      editor.setRangeText("  ", s, editor.selectionEnd, "end");
    }
  });

  document.addEventListener("click", function (e) {
    var el = e.target.closest && e.target.closest("[data-error-example]");
    if (!el) return;
    e.preventDefault();
    var name = el.getAttribute("data-error-example");
    for (var i = 0; i < select.options.length; i++) {
      if (select.options[i].value === name) select.selectedIndex = i;
    }
    wrap.scrollIntoView({ behavior: "smooth", block: "start" });
    load(name, check);
  });

  // Start with the first example in the editor; the compiler loads on first check.
  load(select.value, function () {
    info("Pick an example or edit this one, then press Check (or Ctrl+Enter).");
  });
})();
