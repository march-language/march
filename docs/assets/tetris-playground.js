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

  function showErrors(errs) {
    var el = document.getElementById("tp-errors");
    if (!errs || !errs.length) {
      el.textContent = ""; el.classList.remove("visible");
      return;
    }
    el.textContent = errs.join("\n");
    el.classList.add("visible");
  }

  function buildSrcdoc(js) {
    // tetris.mjs's own emitted code imports "./march_runtime.mjs" and
    // "./march_dom.mjs" by RELATIVE path. A srcdoc iframe's base URL is the
    // embedding page's URL, not the assets directory, so a plain relative
    // import silently resolves to the wrong place (and fails) unless we set
    // an explicit <base href> pointing at the assets directory.
    var assetsBase = window.location.origin + base + "/assets/tetris/";
    return (
      "<!DOCTYPE html><html><head><meta charset='utf-8'>" +
      "<base href='" + assetsBase + "'>" +
      "<style>" +
      "*{box-sizing:border-box;margin:0;padding:0}" +
      "body{background:#1a1a2e;color:#eee;font-family:system-ui,sans-serif;" +
      "display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.75rem;height:100vh}" +
      "#board{display:flex;flex-direction:column;border:2px solid rgba(255,255,255,.2);background:#000}" +
      ".tetris-row{display:flex}.tetris-cell{width:16px;height:16px;border:1px solid #222;background:#111}" +
      "#hud{display:flex;gap:1rem;font-size:.85rem;color:#cbd5e0}" +
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

  fetch(base + "/assets/tetris/tetris-source.march.txt")
    .then(function (r) { return r.text(); })
    .then(function (src) {
      document.getElementById("tp-editor").value = src;
    });

  window.addEventListener("load", mountStatic);
})();
