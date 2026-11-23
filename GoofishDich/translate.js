// Goofish Dịch — chèn vào trang: tìm chữ Trung và thay bằng bản dịch (qua cầu nối GoofishNative).
(function () {
  if (window.__goofishDich) return;
  window.__goofishDich = true;
  var bridge = window.GoofishNative;
  if (!bridge) return;
  var lang = window.__gfLang || "en";
  if (lang === "off") return;

  var HAS_CJK = /[㐀-鿿豈-﫿]/;
  var SKIP_TAGS = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, CODE: 1, PRE: 1, SVG: 1, CANVAS: 1, IFRAME: 1 };
  var ATTRS = ["placeholder", "title", "aria-label", "alt"];
  var MAX_ITEMS = 50, MAX_CHARS = 2500;

  var memo = new Map();
  var ourText = new WeakMap();
  var ourAttr = new WeakMap();
  var pending = new Map();
  var timer = null;
  var reqSeq = 0;
  var callbacks = {};

  bridge.onmessage = function (ev) {
    var msg = null;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    var cb = msg && callbacks[msg.id];
    if (!cb) return;
    delete callbacks[msg.id];
    cb(msg.result || null);
  };

  function askNative(texts) {
    return new Promise(function (resolve) {
      var id = "r" + (++reqSeq) + "_" + Math.random().toString(36).slice(2, 8);
      callbacks[id] = resolve;
      setTimeout(function () { if (callbacks[id]) { delete callbacks[id]; resolve(null); } }, 30000);
      try { bridge.postMessage(JSON.stringify({ id: id, texts: texts, tl: lang })); }
      catch (e) { delete callbacks[id]; resolve(null); }
    });
  }

  function skippable(el) {
    for (var e = el; e && e !== document.documentElement; e = e.parentElement) {
      if (SKIP_TAGS[e.tagName]) return true;
      if (e.isContentEditable) return true;
      if (e.classList && e.classList.contains("notranslate")) return true;
    }
    return false;
  }

  function queue(text, target) {
    var key = text.trim();
    if (!key || !HAS_CJK.test(key)) return;
    if (memo.has(key)) { apply(target, memo.get(key)); return; }
    if (!pending.has(key)) pending.set(key, []);
    pending.get(key).push(target);
    if (!timer) timer = setTimeout(flush, 200);
  }

  function handleTextNode(node) {
    var v = node.nodeValue;
    if (!v || !HAS_CJK.test(v)) return;
    if (ourText.get(node) === v) return;
    if (!node.parentElement || skippable(node.parentElement)) return;
    queue(v, { kind: "text", node: node, raw: v });
  }

  function handleElementAttrs(el) {
    if (!el.getAttribute || skippable(el)) return;
    for (var i = 0; i < ATTRS.length; i++) {
      var a = ATTRS[i];
      var v = el.getAttribute(a);
      if (!v || !HAS_CJK.test(v)) continue;
      var ours = ourAttr.get(el);
      if (ours && ours[a] === v) continue;
      queue(v, { kind: "attr", el: el, attr: a, raw: v });
    }
  }

  function scan(root) {
    if (!root) return;
    if (root.nodeType === 3) return handleTextNode(root);
    if (root.nodeType !== 1 && root.nodeType !== 9) return;
    if (root.nodeType === 1) {
      if (SKIP_TAGS[root.tagName]) return;
      handleElementAttrs(root);
    }
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    var n;
    while ((n = walker.nextNode())) {
      if (n.nodeType === 3) handleTextNode(n);
      else handleElementAttrs(n);
    }
  }

  function keepSpaces(raw, tr) {
    return raw.match(/^\s*/)[0] + tr + raw.match(/\s*$/)[0];
  }

  function apply(t, tr) {
    if (!tr) return;
    if (t.kind === "text") {
      if (!t.node.isConnected || t.node.nodeValue !== t.raw) return;
      var v = keepSpaces(t.raw, tr);
      ourText.set(t.node, v);
      t.node.nodeValue = v;
    } else {
      if (!t.el.isConnected || t.el.getAttribute(t.attr) !== t.raw) return;
      var rec = ourAttr.get(t.el) || {};
      rec[t.attr] = tr;
      ourAttr.set(t.el, rec);
      t.el.setAttribute(t.attr, tr);
    }
  }

  function flush() {
    timer = null;
    var batchMap = pending;
    pending = new Map();
    var keys = Array.from(batchMap.keys());
    var i = 0;
    (function nextChunk() {
      if (i >= keys.length) return;
      var chunk = [], chars = 0;
      while (i < keys.length && chunk.length < MAX_ITEMS && chars + keys[i].length <= MAX_CHARS) {
        chunk.push(keys[i]); chars += keys[i].length; i++;
      }
      if (!chunk.length) chunk.push(keys[i++]);
      askNative(chunk).then(function (res) {
        if (res) {
          chunk.forEach(function (k, j) {
            var tr = res[j];
            if (!tr) return;
            memo.set(k, tr);
            batchMap.get(k).forEach(function (target) { apply(target, tr); });
          });
        }
        nextChunk();
      });
    })();
  }

  function start() {
    scan(document.documentElement);
    new MutationObserver(function (muts) {
      for (var k = 0; k < muts.length; k++) {
        var m = muts[k];
        if (m.type === "characterData") handleTextNode(m.target);
        else if (m.type === "attributes") handleElementAttrs(m.target);
        else m.addedNodes.forEach(scan);
      }
    }).observe(document.documentElement, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ATTRS
    });
  }

  if (document.documentElement) start();
  else document.addEventListener("DOMContentLoaded", start);
})();
