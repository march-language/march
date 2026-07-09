(function () {
  "use strict";
  var base = document.getElementById("tp-wrap").dataset.base || "";

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
      "data-next='O' data-score='0' data-lines='0' data-over='false' style='display:none'></div>" +
      "<script>window.onerror = function (msg) { parent.postMessage({tpError: String(msg)}, '*'); };<\/script>" +
      "<script type='module'>" +
      js +
      "<\/script>" +
      "</body></html>"
    );
  }

  function mountStatic() {
    fetch(base + "/assets/tetris/tetris.mjs")
      .then(function (r) { return r.text(); })
      .then(function (js) {
        var host = document.getElementById("tp-iframe-host");
        host.innerHTML = "";
        var iframe = document.createElement("iframe");
        iframe.id = "tp-iframe";
        iframe.style.width = "100%";
        iframe.style.height = "100%";
        iframe.style.border = "0";
        host.appendChild(iframe);
        iframe.srcdoc = buildSrcdoc(js);
      });
  }

  fetch(base + "/assets/tetris/tetris-source.march.txt")
    .then(function (r) { return r.text(); })
    .then(function (src) { document.getElementById("tp-editor").value = src; });

  window.addEventListener("load", mountStatic);
  window.tpRun = function () {
    document.getElementById("tp-status").textContent = "(static preview — Run wiring lands in Task 7)";
  };
})();
