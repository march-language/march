(function () {
  "use strict";

  // Read the Jekyll baseurl from the data attribute on the root element.
  // This avoids putting {{ }} Liquid tags inside JS where Jekyll mangles braces.
  var base = (document.getElementById("pg-wrap") || {}).dataset.base || "";

  /* ------------------------------------------------------------------ */
  /* State                                                               */
  /* ------------------------------------------------------------------ */
  var bundleLoaded  = false;
  var bundleLoading = false;
  var inputHistory  = [];
  var historyIdx    = -1;
  var pendingCode   = null;

  var historyEl = document.getElementById("pg-history");
  var inputEl   = document.getElementById("pg-input");
  var loadingEl = document.getElementById("pg-loading-msg");

  /* ------------------------------------------------------------------ */
  /* Bundle loading                                                      */
  /* ------------------------------------------------------------------ */
  function loadScript(src, onload, onerror) {
    var s = document.createElement("script");
    s.src = src;
    s.onload = onload;
    s.onerror = onerror;
    document.head.appendChild(s);
  }

  function loadBundle(callback) {
    if (bundleLoaded) { callback(); return; }
    if (bundleLoading) { pendingCode = callback; return; }
    bundleLoading = true;
    loadingEl.textContent = "Loading interpreter\u2026";

    // Load stdlib first, then the interpreter bundle
    loadScript(base + "/assets/march_stdlib.js", function () {
      loadScript(base + "/assets/march.js", function () {
        bundleLoaded  = true;
        bundleLoading = false;
        loadingEl.textContent = "Ready.";
        setTimeout(function () { loadingEl.textContent = ""; }, 1500);
        callback();
        if (pendingCode) { var cb = pendingCode; pendingCode = null; cb(); }
      }, function () {
        bundleLoading = false;
        loadingEl.textContent = "Failed to load interpreter.";
      });
    }, function () {
      // stdlib failed — try loading the interpreter anyway (REPL will work without stdlib)
      loadScript(base + "/assets/march.js", function () {
        bundleLoaded  = true;
        bundleLoading = false;
        loadingEl.textContent = "Ready (no stdlib).";
        setTimeout(function () { loadingEl.textContent = ""; }, 1500);
        callback();
        if (pendingCode) { var cb = pendingCode; pendingCode = null; cb(); }
      }, function () {
        bundleLoading = false;
        loadingEl.textContent = "Failed to load interpreter.";
      });
    });
  }

  /* ------------------------------------------------------------------ */
  /* Append output to history                                            */
  /* ------------------------------------------------------------------ */
  function appendLine(text, cssClass) {
    var entry = document.createElement("div");
    entry.className = "pg-entry";
    var span = document.createElement("span");
    span.className = cssClass;
    span.textContent = text;
    entry.appendChild(span);
    historyEl.appendChild(entry);
    historyEl.scrollTop = historyEl.scrollHeight;
  }

  function appendInput(code) {
    code.split("\n").forEach(function (line, i) {
      var entry = document.createElement("div");
      entry.className = "pg-entry";
      var span = document.createElement("span");
      if (i === 0) {
        span.className = "pg-input-line";
        span.textContent = line;
      } else {
        span.style.color = "#6b7280";
        span.textContent = "      " + line;
      }
      entry.appendChild(span);
      historyEl.appendChild(entry);
    });
    historyEl.scrollTop = historyEl.scrollHeight;
  }

  /* ------------------------------------------------------------------ */
  /* Submit code                                                         */
  /* ------------------------------------------------------------------ */
  function submitCode(code) {
    if (!code.trim()) return;

    if (inputHistory[0] !== code) inputHistory.unshift(code);
    if (inputHistory.length > 50) inputHistory.pop();
    historyIdx = -1;

    appendInput(code);
    inputEl.value = "";
    autoResize();

    if (code.trim() === ":reset") {
      if (bundleLoaded && window.marchResetSession) {
        window.marchResetSession();
      }
      historyEl.innerHTML = "";
      appendLine("Session reset.", "pg-info");
      return;
    }

    loadBundle(function () {
      if (!window.marchEvalLine) {
        appendLine("Interpreter not available.", "pg-error");
        return;
      }
      var result = window.marchEvalLine(code);
      if (result.output && result.output.trim()) {
        appendLine(result.output.trimEnd(), "pg-output");
      }
      if (result.error !== null) {
        appendLine(result.error, "pg-error");
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /* Auto-resize textarea                                                */
  /* ------------------------------------------------------------------ */
  function autoResize() {
    inputEl.style.height = "auto";
    inputEl.style.height = inputEl.scrollHeight + "px";
  }

  /* ------------------------------------------------------------------ */
  /* Input event handlers                                                */
  /* ------------------------------------------------------------------ */
  inputEl.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submitCode(inputEl.value);
    } else if (e.key === "ArrowUp" && !e.shiftKey) {
      if (inputHistory.length > 0) {
        historyIdx = Math.min(historyIdx + 1, inputHistory.length - 1);
        inputEl.value = inputHistory[historyIdx];
        autoResize();
        setTimeout(function () {
          inputEl.selectionStart = inputEl.selectionEnd = inputEl.value.length;
        }, 0);
        e.preventDefault();
      }
    } else if (e.key === "ArrowDown" && !e.shiftKey) {
      if (historyIdx > 0) {
        historyIdx--;
        inputEl.value = inputHistory[historyIdx];
      } else {
        historyIdx = -1;
        inputEl.value = "";
      }
      autoResize();
      e.preventDefault();
    } else {
      if (!bundleLoaded && !bundleLoading) {
        loadBundle(function () {});
      }
    }
  });

  inputEl.addEventListener("input", autoResize);

  /* ------------------------------------------------------------------ */
  /* Public helpers (called by onclick attrs in playground.html)         */
  /* ------------------------------------------------------------------ */
  window.pgLoad = function (code) {
    var txt = document.createElement("textarea");
    txt.innerHTML = code;
    inputEl.value = txt.value;
    autoResize();
    inputEl.focus();
  };

  window.pgSubmit = function () {
    submitCode(inputEl.value);
  };

  window.pgReset = function () {
    submitCode(":reset");
  };

  // Start loading the bundle immediately on page load
  window.addEventListener("load", function () {
    loadBundle(function () {});
  });
})();
