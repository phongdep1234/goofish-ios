// Goofish Dịch — chèn vào trang: tìm chữ Trung và thay bằng bản dịch (qua cầu nối GoofishNative).
(function () {
  if (window.__goofishDich) return;
  window.__goofishDich = true;
  var bridge = window.GoofishNative || null;
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

  // Gọi thẳng Google Translate từ trang (trả về CORS *), giữ bản fetch gốc trước khi trang kịp sửa nó.
  var nativeFetch = window.fetch ? window.fetch.bind(window) : null;
  // Nguồn 1 + 2: dịch nhiều câu một lúc, trả về đúng thứ tự (POST, nhiều tham số q)
  var MULTI = [
    "https://translate.googleapis.com/translate_a/t?client=dict-chrome-ex&sl=zh-CN&tl=",
    "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=zh-CN&tl="
  ];
  // Nguồn 3: dịch cả khối, tách theo dòng
  var SINGLE = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=zh-CN&dt=t&tl=";

  function post(url, body) {
    if (!nativeFetch) return Promise.reject(new Error("no fetch"));
    return nativeFetch(url + encodeURIComponent(lang), {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
      body: body,
      credentials: "omit"
    }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    });
  }

  function multi(url, texts) {
    var body = texts.map(function (t) { return "q=" + encodeURIComponent(t); }).join("&");
    return post(url, body).then(function (arr) {
      if (typeof arr === "string") arr = [arr];
      if (!Array.isArray(arr) || arr.length !== texts.length) throw new Error("bad length");
      return arr.map(function (x) {
        if (Array.isArray(x)) x = x[0];
        return typeof x === "string" && x.trim() ? x.trim() : null;
      });
    });
  }

  function single(texts) {
    var clean = texts.map(function (t) { return t.replace(/\s*\n\s*/g, " "); });
    return post(SINGLE, "q=" + encodeURIComponent(clean.join("\n"))).then(function (j) {
      var joined = (j && j[0] ? j[0] : []).map(function (seg) { return (seg && seg[0]) || ""; }).join("");
      var parts = joined.split("\n");
      if (parts.length !== clean.length) throw new Error("bad length");
      return parts.map(function (x) { return x.trim() || null; });
    });
  }

  function translateDirect(texts) {
    return multi(MULTI[0], texts)
      .catch(function () { return multi(MULTI[1], texts); })
      .catch(function () { return single(texts); });
  }

  // Dự phòng: nhờ app dịch (cầu nối GoofishNative), nếu gọi thẳng bị lỗi
  if (bridge) bridge.onmessage = function (ev) {
    var msg = null;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    var cb = msg && callbacks[msg.id];
    if (!cb) return;
    delete callbacks[msg.id];
    cb(msg.result || null);
  };

  function askBridge(texts) {
    return new Promise(function (resolve) {
      if (!bridge) return resolve(null);
      var id = "r" + (++reqSeq) + "_" + Math.random().toString(36).slice(2, 8);
      callbacks[id] = resolve;
      setTimeout(function () { if (callbacks[id]) { delete callbacks[id]; resolve(null); } }, 30000);
      try { bridge.postMessage(JSON.stringify({ id: id, texts: texts, tl: lang })); }
      catch (e) { delete callbacks[id]; resolve(null); }
    });
  }

  function askNative(texts) {
    return translateDirect(texts).catch(function () { return askBridge(texts); });
  }

  // Bộ nhớ dịch lưu lại giữa các lần mở app (localStorage của trang)
  var STORE = "gfTr_" + lang;
  try {
    var saved = JSON.parse(localStorage.getItem(STORE) || "{}");
    Object.keys(saved).forEach(function (k) { memo.set(k, saved[k]); });
  } catch (e) {}
  var saveTimer = null;
  function persist() {
    if (saveTimer) return;
    saveTimer = setTimeout(function () {
      saveTimer = null;
      try {
        var obj = {}, keys = Array.from(memo.keys()), from = Math.max(0, keys.length - 4000);
        for (var i = from; i < keys.length; i++) obj[keys[i]] = memo.get(keys[i]);
        localStorage.setItem(STORE, JSON.stringify(obj));
      } catch (e) {}
    }, 2000);
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
            persist();
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

  // Quét lại định kỳ: trang có thể tự vẽ lại chữ gốc (đã có trong bộ nhớ dịch thì thay ngay, không cần mạng)
  setInterval(function () { if (document.body) scan(document.body); }, 3000);

  if (document.documentElement) start();
  else document.addEventListener("DOMContentLoaded", start);
})();
