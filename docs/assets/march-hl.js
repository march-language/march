/*
 * march-hl.js — static syntax highlighting for March code blocks.
 *
 * Finds every <code class="language-march"> on the page and rewrites its
 * innerHTML with highlighted spans using the same --syn-* CSS variables
 * that the interactive REPL uses.
 *
 * Exposes window.MarchHL = { hlLine } for other scripts.
 * Keep the keyword list in sync with march-repl.js.
 */
(function () {
  'use strict';

  var KWS = [
    'fn', 'pfn', 'let', 'type', 'ptype', 'mod', 'do', 'end',
    'match', 'if', 'else', 'with', 'when',
    'actor', 'state', 'init', 'on', 'reply', 'spawn', 'send', 'run_until_idle',
    'true', 'false', 'in', 'import', 'use', 'doc',
    'linear', 'always_linear', 'needs', 'cap', 'proof', 'tag', 'transitions',
    'need'
  ];

  function esc(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function col(v, s) {
    return '<span style="color:var(' + v + ')">' + esc(s) + '</span>';
  }

  function hlLine(line) {
    var out = '', i = 0, n = line.length;
    while (i < n) {
      var c = line[i];
      // comment
      if (c === '-' && line[i + 1] === '-') {
        out += col('--syn-cm', line.slice(i));
        break;
      }
      // string
      if (c === '"') {
        var j = i + 1;
        while (j < n && line[j] !== '"') { if (line[j] === '\\') j++; j++; }
        out += col('--syn-st', line.slice(i, j + 1));
        i = j + 1; continue;
      }
      // number
      if (c >= '0' && c <= '9') {
        var j = i;
        while (j < n && ((line[j] >= '0' && line[j] <= '9') || line[j] === '.')) j++;
        out += col('--syn-nm', line.slice(i, j));
        i = j; continue;
      }
      // word (identifier or keyword)
      var lo = c >= 'a' && c <= 'z', hi = c >= 'A' && c <= 'Z';
      if (lo || hi || c === '_') {
        var j = i;
        while (j < n) {
          var d = line[j];
          if (!((d >= 'a' && d <= 'z') || (d >= 'A' && d <= 'Z') ||
                (d >= '0' && d <= '9') || d === '_')) break;
          j++;
        }
        var w = line.slice(i, j);
        out += (KWS.indexOf(w) >= 0) ? col('--syn-kw', w) :
               hi                    ? col('--syn-tp', w) :
               col('--syn-id', w);
        i = j; continue;
      }
      // two-char operators
      var tw = c + (line[i + 1] || '');
      if (tw === '->' || tw === '<-' || tw === '|>' || tw === '++' ||
          tw === '+.' || tw === '-.' || tw === '*.' || tw === '/.' ||
          tw === '==' || tw === '!=' || tw === '<=' || tw === '>=' || tw === '..') {
        out += col('--syn-op', tw); i += 2; continue;
      }
      // single-char operators
      if ('|=:+-*/<>!'.indexOf(c) >= 0) { out += col('--syn-op', c); i++; continue; }
      // everything else (whitespace, punctuation, ?)
      out += esc(c);
      i++;
    }
    return out;
  }

  function highlightBlocks() {
    var els = document.querySelectorAll('code.language-march');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var lines = el.textContent.split('\n');
      if (lines[lines.length - 1] === '') lines.pop();
      el.innerHTML = lines.map(hlLine).join('\n');
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', highlightBlocks);
  } else {
    highlightBlocks();
  }

  window.MarchHL = { hlLine: hlLine };
}());
