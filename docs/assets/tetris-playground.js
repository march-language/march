(function () {
  "use strict";
  var base = document.getElementById("tp-wrap").dataset.base || "";
  var ver = document.getElementById("tp-wrap").dataset.ver || "0";
  var loaded = false, loading = false, pending = null;

  function loadScript(src, ok, err) {
    var s = document.createElement("script");
    s.src = src; s.onload = ok; s.onerror = err;
    document.head.appendChild(s);
  }

  function ensureCompilerLoaded(cb) {
    if (loaded) { cb(); return; }
    if (loading) { pending = cb; return; }
    loading = true;
    setStatus("Loading compiler…");
    loadScript(base + "/assets/march_stdlib.js?v=" + ver, function () {
      loadScript(base + "/assets/march_compile.js?v=" + ver, function () {
        loaded = true; loading = false;
        setStatus("Ready.");
        cb();
        if (pending) { var f = pending; pending = null; f(); }
      }, onLoadFail);
    }, function () {
      loadScript(base + "/assets/march_compile.js?v=" + ver, function () {
        loaded = true; loading = false;
        setStatus("Ready (no stdlib bundle).");
        cb();
      }, onLoadFail);
    });
  }

  function onLoadFail() {
    loading = false;
    setStatus("Failed to load compiler.");
  }

  function setStatus(s) { document.getElementById("tp-status").textContent = s; }

  /* ------------------------------------------------------------------ */
  /* Syntax highlighter — same tokenizer as march-repl.js's _hlLine, but */
  /* applied LIVE to the editable textarea (that one only highlights    */
  /* already-submitted read-only history entries). Duplicated rather    */
  /* than shared: these are two independent js_of_ocaml-adjacent bundle */
  /* pages, not meant to be coupled.                                    */
  /* ------------------------------------------------------------------ */

  var _KWS = ['fn', 'pfn', 'let', 'type', 'ptype', 'mod', 'do', 'end', 'match', 'if', 'else', 'with', 'when',
              'actor', 'state', 'init', 'on', 'reply', 'spawn', 'send', 'run_until_idle',
              'true', 'false', 'in', 'import', 'use', 'doc',
              'linear', 'always_linear', 'needs', 'cap', 'proof', 'tag', 'transitions'];

  function _esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function _col(v, s) {
    return '<span style="color:var(' + v + ')">' + _esc(s) + '</span>';
  }

  function _hlLine(line) {
    var out = "", i = 0, n = line.length;
    while (i < n) {
      var c = line[i];
      if (c === "-" && line[i + 1] === "-") { out += _col("--syn-cm", line.slice(i)); break; }
      if (c === '"') {
        var j = i + 1;
        while (j < n && line[j] !== '"') { if (line[j] === "\\") j++; j++; }
        out += _col("--syn-st", line.slice(i, j + 1));
        i = j + 1; continue;
      }
      if (c >= "0" && c <= "9") {
        var j = i;
        while (j < n && ((line[j] >= "0" && line[j] <= "9") || line[j] === ".")) j++;
        out += _col("--syn-nm", line.slice(i, j));
        i = j; continue;
      }
      var lo = c >= "a" && c <= "z", hi = c >= "A" && c <= "Z";
      if (lo || hi || c === "_") {
        var j = i;
        while (j < n) {
          var d = line[j];
          if (!((d >= "a" && d <= "z") || (d >= "A" && d <= "Z") ||
                (d >= "0" && d <= "9") || d === "_")) break;
          j++;
        }
        var w = line.slice(i, j);
        out += (_KWS.indexOf(w) >= 0) ? _col("--syn-kw", w) :
               hi                      ? _col("--syn-tp", w) :
               _col("--syn-id", w);
        i = j; continue;
      }
      var tw = c + (line[i + 1] || "");
      if (tw === "->" || tw === "<-" || tw === "|>" || tw === "++" ||
          tw === "+." || tw === "-." || tw === "*." || tw === "/." ||
          tw === "==" || tw === "!=" || tw === "<=" || tw === ">=" || tw === "..") {
        out += _col("--syn-op", tw); i += 2; continue;
      }
      if ("|=:+-*/<>!".indexOf(c) >= 0) { out += _col("--syn-op", c); i++; continue; }
      out += _esc(c);
      i++;
    }
    return out;
  }

  function renderHighlight() {
    var editor = document.getElementById("tp-editor");
    var hl = document.getElementById("tp-highlight");
    var html = editor.value.split("\n").map(_hlLine).join("\n");
    // A trailing newline needs an extra blank line in the backdrop too,
    // or the <pre> collapses it and the caret drifts out of sync on the
    // last line.
    hl.innerHTML = html + (editor.value.endsWith("\n") ? "\n" : "") + " ";
  }

  function syncHighlightScroll() {
    var editor = document.getElementById("tp-editor");
    var hl = document.getElementById("tp-highlight");
    hl.scrollTop = editor.scrollTop;
    hl.scrollLeft = editor.scrollLeft;
  }

  function showErrors(errs) {
    var el = document.getElementById("tp-errors");
    if (!errs || !errs.length) {
      el.textContent = ""; el.classList.remove("visible");
      return;
    }
    el.textContent = errs.join("\n");
    el.classList.add("visible");
  }

  // Reads the SITE's actual theme colors (light/dark toggle, see docs.html's
  // :root / :root.light) so the game iframe blends with the page instead of
  // carrying its own hardcoded dark-blue palette. Read once per Run — the
  // iframe won't live-follow a theme toggle mid-session, only on next Run,
  // which is an acceptable tradeoff for how rarely that happens mid-edit.
  function themeColors() {
    var s = getComputedStyle(document.documentElement);
    function v(name, fallback) {
      var val = s.getPropertyValue(name).trim();
      return val || fallback;
    }
    return {
      bg: v("--bg", "#07101a"),
      bgCode: v("--bg-code", "#0c1928"),
      text: v("--text", "#cce5f5"),
      textMuted: v("--text-muted", "#4a7898"),
      border: v("--border", "#0f2438")
    };
  }

  function buildSrcdoc(js) {
    // tetris.mjs's own emitted code imports "./march_runtime.mjs" and
    // "./march_dom.mjs" by RELATIVE path. A srcdoc iframe's base URL is the
    // embedding page's URL, not the assets directory, so a plain relative
    // import silently resolves to the wrong place (and fails) unless we set
    // an explicit <base href> pointing at the assets directory.
    var assetsBase = window.location.origin + base + "/assets/tetris/";
    var t = themeColors();
    return (
      "<!DOCTYPE html><html><head><meta charset='utf-8'>" +
      "<base href='" + assetsBase + "'>" +
      "<style>" +
      "*{box-sizing:border-box;margin:0;padding:0}" +
      "body{background:" + t.bg + ";color:" + t.text + ";font-family:system-ui,sans-serif;" +
      "display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.75rem;height:100vh}" +
      "#board{display:flex;flex-direction:column;border:2px solid " + t.border + ";background:" + t.bgCode + "}" +
      ".tetris-row{display:flex}.tetris-cell{width:16px;height:16px;border:1px solid " + t.border + ";background:" + t.bgCode + "}" +
      "#hud{display:flex;gap:1rem;font-size:.85rem;color:" + t.textMuted + "}" +
      "#game-over{color:#f87171;font-weight:600;min-height:1.2em;font-size:.85rem}" +
      "</style></head><body>" +
      "<div id='board'></div>" +
      "<div id='hud'><span id='score'>Score: 0</span><span id='level'>Level: 0</span><span id='next'>Next: O</span></div>" +
      "<div id='game-over'></div>" +
      "<div id='game-state' data-board='' data-piece='I' data-rot='0' data-x='3' data-y='0' " +
      "data-next='O' data-score='0' data-lines='0' data-rng='' data-over='false' style='display:none'></div>" +
      "<script>window.onerror = function (msg) { parent.postMessage({tpError: String(msg)}, '*'); };<\/script>" +
      "<script type='module'>" +
      js +
      "<\/script>" +
      "</body></html>"
    );
  }

  // Each Run rebuilds a FRESH iframe rather than reusing the existing one —
  // this cleanly discards any intervals/listeners/DOM state left over from
  // the previous run instead of trying to individually tear them down.
  function mountJs(js) {
    var host = document.getElementById("tp-iframe-host");
    host.innerHTML = "";
    var iframe = document.createElement("iframe");
    iframe.id = "tp-iframe";
    iframe.style.width = "100%";
    iframe.style.height = "100%";
    iframe.style.border = "0";
    host.appendChild(iframe);
    iframe.srcdoc = buildSrcdoc(js);
  }

  function mountStatic() {
    fetch(base + "/assets/tetris/tetris.mjs")
      .then(function (r) { return r.text(); })
      .then(mountJs);
  }

  window.addEventListener("message", function (ev) {
    if (ev.data && ev.data.tpError) showErrors(["runtime error: " + ev.data.tpError]);
  });

  window.tpRun = function () {
    var src = document.getElementById("tp-editor").value;
    ensureCompilerLoaded(function () {
      setStatus("Compiling…");
      var result = window.marchCompileToJs(src);
      if (result.js !== null) {
        showErrors([]);
        setStatus("Running.");
        mountJs(result.js);
      } else {
        showErrors(result.errors);
        setStatus("Compile failed.");
      }
    });
  };

  (function () {
    var editor = document.getElementById("tp-editor");
    editor.addEventListener("input", renderHighlight);
    editor.addEventListener("scroll", syncHighlightScroll);
    // Tab inserts a literal tab instead of moving focus, matching a real
    // code editor (and keeping March's 2-space-indent convention easy to
    // reach — Shift+Tab is intentionally not handled, out of scope for a
    // minimal editor).
    editor.addEventListener("keydown", function (ev) {
      if (ev.key !== "Tab") return;
      ev.preventDefault();
      var start = editor.selectionStart, end = editor.selectionEnd;
      editor.value = editor.value.slice(0, start) + "  " + editor.value.slice(end);
      editor.selectionStart = editor.selectionEnd = start + 2;
      renderHighlight();
    });
  })();

  fetch(base + "/assets/tetris/tetris-source.march.txt")
    .then(function (r) { return r.text(); })
    .then(function (src) {
      document.getElementById("tp-editor").value = src;
      renderHighlight();
    });

  window.addEventListener("load", mountStatic);
})();
