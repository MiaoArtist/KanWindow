/* 窥窗 · 临时文本编辑器：Markdown + 荧光笔
 * 纯前端实现。原生只通过 window.KW.setText/getText/flush 与 kwTextSave 消息通道交互。
 */
(function () {
  'use strict';

  var editor = document.getElementById('editor');
  var hlLayer = document.getElementById('hl-layer');
  var preview = document.getElementById('preview');
  var panes = document.getElementById('panes');
  var stat = document.getElementById('stat');
  var modeButtons = Array.prototype.slice.call(document.querySelectorAll('.mode-btn'));
  var TICK = String.fromCharCode(96);            // 单反引号，行内代码
  var FENCE = TICK + TICK + TICK;                // 三反引号，代码块

  var mode = 'edit';
  var saveTimer = null;
  var composing = false;
  var COLORS = { yellow: 1, red: 1, green: 1, blue: 1, orange: 1, purple: 1, pink: 1, gray: 1 };

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // ---------- 编辑器内的实时荧光笔（背景层，不影响输入法）----------
  var HL_RE = /==\{([a-z]+)\}([\s\S]*?)==|==([\s\S]*?)==|\$\$([\s\S]*?)\$\$|¥¥([\s\S]*?)¥¥/g;

  function highlightToHtml(src) {
    var out = '';
    var i = 0;
    var m;
    HL_RE.lastIndex = 0;
    while ((m = HL_RE.exec(src)) !== null) {
      out += esc(src.slice(i, m.index));
      if (m[1] !== undefined) {
        var c = COLORS[m[1]] ? m[1] : 'yellow';
        out += '<span class="mk">=={' + m[1] + '}</span><mark class="hl hl-' + c + '">' + esc(m[2]) + '</mark><span class="mk">==</span>';
      } else if (m[3] !== undefined) {
        out += '<span class="mk">==</span><mark class="hl hl-yellow">' + esc(m[3]) + '</mark><span class="mk">==</span>';
      } else if (m[4] !== undefined) {
        out += '<span class="mk">$$</span><mark class="hl hl-red">' + esc(m[4]) + '</mark><span class="mk">$$</span>';
      } else if (m[5] !== undefined) {
        out += '<span class="mk">¥¥</span><mark class="hl hl-red">' + esc(m[5]) + '</mark><span class="mk">¥¥</span>';
      }
      i = HL_RE.lastIndex;
    }
    out += esc(src.slice(i));
    return out;
  }

  function renderBackdrop() {
    hlLayer.innerHTML = highlightToHtml(editor.value) + '\n';
    syncScroll();
  }
  function syncScroll() {
    hlLayer.scrollTop = editor.scrollTop;
    hlLayer.scrollLeft = editor.scrollLeft;
  }

  // ---------- Markdown 渲染（marked + 荧光笔扩展）----------
  function installMarked() {
    if (typeof marked === 'undefined' || marked.__kwHighlightInstalled) return;
    marked.__kwHighlightInstalled = true;
    marked.use({
      extensions: [{
        name: 'kwhl',
        level: 'inline',
        start: function (src) {
          var m = src.match(/==|\$\$|¥¥/);
          return m ? m.index : undefined;
        },
        tokenizer: function (src) {
          var m = /^==\{([a-z]+)\}([\s\S]+?)==/.exec(src);
          if (m) return { type: 'kwhl', raw: m[0], color: COLORS[m[1]] ? m[1] : 'yellow', tokens: this.lexer.inlineTokens(m[2]) };
          m = /^==([\s\S]+?)==/.exec(src);
          if (m) return { type: 'kwhl', raw: m[0], color: 'yellow', tokens: this.lexer.inlineTokens(m[1]) };
          m = /^\$\$([\s\S]+?)\$\$/.exec(src);
          if (m) return { type: 'kwhl', raw: m[0], color: 'red', tokens: this.lexer.inlineTokens(m[1]) };
          m = /^¥¥([\s\S]+?)¥¥/.exec(src);
          if (m) return { type: 'kwhl', raw: m[0], color: 'red', tokens: this.lexer.inlineTokens(m[1]) };
          return undefined;
        },
        renderer: function (token) {
          return '<mark class="hl hl-' + token.color + '">' + this.parser.parseInline(token.tokens) + '</mark>';
        }
      }]
    });
  }

  function sanitize(html) {
    try {
      var doc = new DOMParser().parseFromString('<div>' + html + '</div>', 'text/html');
      var root = doc.body.firstChild;
      Array.prototype.slice.call(root.querySelectorAll('script, iframe, object, embed, link, meta, style, base')).forEach(function (n) { n.remove(); });
      Array.prototype.slice.call(root.querySelectorAll('*')).forEach(function (el) {
        Array.prototype.slice.call(el.attributes).forEach(function (a) {
          var n = a.name.toLowerCase();
          if (n.indexOf('on') === 0) el.removeAttribute(a.name);
          if ((n === 'href' || n === 'src') && /^\s*javascript:/i.test(a.value)) el.removeAttribute(a.name);
        });
      });
      return root.innerHTML;
    } catch (e) { return html; }
  }

  function renderPreview() {
    if (typeof marked === 'undefined') { preview.textContent = editor.value; return; }
    try {
      preview.innerHTML = sanitize(marked.parse(editor.value, { gfm: true, breaks: true }));
    } catch (e) { preview.textContent = editor.value; }
  }

  // ---------- 统计 / 保存 ----------
  function updateStat() {
    var v = editor.value;
    var chars = Array.from(v).length;
    var lines = v.length ? v.split('\n').length : 0;
    stat.textContent = chars + ' 字 · ' + lines + ' 行';
  }
  function saveSoon() {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(flushSave, 400);
  }
  function flushSave() {
    if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.kwTextSave) {
        window.webkit.messageHandlers.kwTextSave.postMessage(editor.value);
      }
    } catch (e) {}
  }
  function onChange() {
    renderBackdrop();
    updateStat();
    saveSoon();
    if (mode !== 'edit') renderPreview();
  }

  // ---------- 编辑命令 ----------
  function replaceRange(start, end, text, selStart, selEnd) {
    editor.setRangeText(text, start, end, 'end');
    if (typeof selStart === 'number') {
      editor.setSelectionRange(selStart, typeof selEnd === 'number' ? selEnd : selStart);
    }
    onChange();
    editor.focus();
  }
  function surround(before, after) {
    var s = editor.selectionStart, e = editor.selectionEnd;
    var sel = editor.value.slice(s, e);
    var innerStart = s + before.length;
    replaceRange(s, e, before + (sel || '') + after, innerStart, innerStart + sel.length);
  }
  function lineBounds() {
    var s = editor.selectionStart, e = editor.selectionEnd, v = editor.value;
    var start = v.lastIndexOf('\n', s - 1) + 1;
    var end = v.indexOf('\n', e);
    if (end === -1) end = v.length;
    return { start: start, end: end };
  }
  function stripPrefix(line) {
    return line.replace(/^\s*(#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+\.\s+)/, '');
  }
  function eachLine(fn) {
    var b = lineBounds();
    var out = editor.value.slice(b.start, b.end).split('\n').map(fn).join('\n');
    replaceRange(b.start, b.end, out);
  }
  function applyHighlight(color) {
    var s = editor.selectionStart, e = editor.selectionEnd;
    var sel = editor.value.slice(s, e);
    var before, after;
    if (color === 'yellow') { before = '=='; after = '=='; }
    else if (color === 'red') { before = '$$'; after = '$$'; }
    else { before = '=={' + color + '}'; after = '=='; }
    var body = sel || '高亮文字';
    replaceRange(s, e, before + body + after, s + before.length, s + before.length + body.length);
  }
  function clearHighlight() {
    var b = lineBounds();
    var block = editor.value.slice(b.start, b.end)
      .replace(/==\{[a-z]+\}/g, '')
      .replace(/==/g, '')
      .replace(/\$\$/g, '')
      .replace(/¥¥/g, '');
    replaceRange(b.start, b.end, block);
  }

  var actions = {
    h1: function () { eachLine(function (l) { return '# ' + stripPrefix(l); }); },
    h2: function () { eachLine(function (l) { return '## ' + stripPrefix(l); }); },
    h3: function () { eachLine(function (l) { return '### ' + stripPrefix(l); }); },
    bold: function () { surround('**', '**'); },
    italic: function () { surround('*', '*'); },
    strike: function () { surround('~~', '~~'); },
    code: function () { surround(TICK, TICK); },
    codeblock: function () {
      var s = editor.selectionStart, e = editor.selectionEnd, sel = editor.value.slice(s, e);
      replaceRange(s, e, '\n' + FENCE + '\n' + (sel || '') + '\n' + FENCE + '\n');
    },
    ul: function () { eachLine(function (l) { return '- ' + stripPrefix(l); }); },
    ol: function () { eachLine(function (l, i) { return (i + 1) + '. ' + stripPrefix(l); }); },
    task: function () { eachLine(function (l) { return '- [ ] ' + stripPrefix(l); }); },
    quote: function () { eachLine(function (l) { return '> ' + stripPrefix(l); }); },
    link: function () {
      var s = editor.selectionStart, e = editor.selectionEnd, sel = editor.value.slice(s, e);
      var label = sel || '链接文字';
      var text = '[' + label + '](https://)';
      var urlStart = s + 1 + label.length + 2;
      replaceRange(s, e, text, urlStart, urlStart + 8);
    },
    table: function () {
      var s = editor.selectionStart, e = editor.selectionEnd;
      replaceRange(s, e, '\n| 列 1 | 列 2 | 列 3 |\n| --- | --- | --- |\n|  |  |  |\n');
    },
    hr: function () {
      var s = editor.selectionStart, e = editor.selectionEnd;
      replaceRange(s, e, '\n---\n');
    },
    'highlight-clear': clearHighlight
  };

  // ---------- 事件 ----------
  editor.addEventListener('input', function () { if (!composing) onChange(); });
  editor.addEventListener('scroll', syncScroll);
  editor.addEventListener('compositionstart', function () {
    composing = true;
    document.body.classList.add('composing');
  });
  editor.addEventListener('compositionend', function () {
    composing = false;
    document.body.classList.remove('composing');
    onChange();
  });
  editor.addEventListener('keydown', function (ev) {
    if (ev.key === 'Tab' && !ev.metaKey && !ev.ctrlKey && !ev.altKey) {
      ev.preventDefault();
      replaceRange(editor.selectionStart, editor.selectionEnd, '  ');
      return;
    }
    if (!(ev.metaKey || ev.ctrlKey)) return;
    var k = (ev.key || '').toLowerCase();
    if (k === 'b') { ev.preventDefault(); actions.bold(); }
    else if (k === 'i') { ev.preventDefault(); actions.italic(); }
  });
  window.addEventListener('resize', renderBackdrop);

  document.getElementById('toolbar').addEventListener('click', function (ev) {
    var t = ev.target;
    var pen = t && t.closest ? t.closest('.pen') : null;
    if (pen) { applyHighlight(pen.getAttribute('data-color')); return; }
    var btn = t && t.closest ? t.closest('button[data-cmd]') : null;
    if (btn) {
      var fn = actions[btn.getAttribute('data-cmd')];
      if (fn) fn();
    }
  });

  modeButtons.forEach(function (b) {
    b.addEventListener('click', function () { setMode(b.getAttribute('data-mode')); });
  });
  function setMode(next) {
    mode = next || 'edit';
    panes.className = 'mode-' + mode;
    modeButtons.forEach(function (b) {
      b.classList.toggle('active', b.getAttribute('data-mode') === mode);
    });
    if (mode !== 'edit') renderPreview();
    if (mode !== 'preview') { renderBackdrop(); editor.focus(); }
  }

  // ---------- 原生桥 ----------
  window.KW = {
    setText: function (t) {
      editor.value = (t == null ? '' : String(t));
      installMarked();
      renderBackdrop();
      updateStat();
      if (mode !== 'edit') renderPreview();
      try {
        var n = editor.value.length;
        editor.focus();
        editor.setSelectionRange(n, n);
      } catch (e) {}
      syncScroll();
    },
    getText: function () { return editor.value; },
    flush: flushSave,
    setMode: setMode
  };

  installMarked();
  renderBackdrop();
  updateStat();
  window.addEventListener('load', function () {
    installMarked();
    if (!editor.value) editor.focus();
  });
})();
