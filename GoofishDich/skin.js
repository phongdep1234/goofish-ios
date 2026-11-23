// Goofish Dịch — lớp giao diện kiểu app điện thoại cho trang www.goofish.com (bản máy tính).
(function () {
  var H = location.hostname;
  if (H !== "www.goofish.com" && H !== "goofish.com") return;
  if (window.top !== window) return; // chỉ trang chính, không chạy trong khung con
  if (window.__gfSkin) return;
  window.__gfSkin = true;

  var lang = window.__gfLang || "en";
  var L = {
    en: { home: "Home", msg: "Messages", sell: "Sell", me: "Me", search: "Search" },
    vi: { home: "Trang chủ", msg: "Tin nhắn", sell: "Đăng bán", me: "Của tôi", search: "Tìm" },
    off: { home: "首页", msg: "消息", sell: "卖闲置", me: "我的", search: "搜索" }
  }[lang] || { home: "Home", msg: "Messages", sell: "Sell", me: "Me", search: "Search" };

  // ---------- 1. Viewport theo chiều rộng điện thoại ----------
  var VP = "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover";
  function fixViewport() {
    if (!document.documentElement) return;
    var metas = document.querySelectorAll('meta[name="viewport"]');
    if (!metas.length && document.head) {
      var m = document.createElement("meta");
      m.name = "viewport";
      document.head.appendChild(m);
      metas = [m];
    }
    for (var i = 0; i < metas.length; i++) if (metas[i].content !== VP) metas[i].content = VP;
  }

  // ---------- 2. CSS ----------
  var C = function (name) { return '[class*="' + name + '--"]'; };
  var css = [
    "html,body{min-width:0!important;width:100%!important;overflow-x:hidden!important;background:#f6f6f6!important;-webkit-text-size-adjust:100%!important}",
    "body{padding-bottom:calc(64px + env(safe-area-inset-bottom))!important}",
    "*{max-width:100vw}",
    "img,video{max-width:100%!important}",

    // Ẩn phần chỉ dành cho máy tính
    C("sidebar-container") + "," + C("bottomLead") + "," + C("announcementWrap") + "," + C("logo-container") + "," +
    C("search-tip") + "," + C("banner-container") + ",footer," + C("footer") + "{display:none!important}",

    // Đầu trang: chỉ còn ô tìm kiếm, dính trên cùng
    C("header-container") + "{position:sticky!important;top:0!important;z-index:50!important;height:auto!important;min-width:0!important;width:100%!important;background:#f6f6f6!important;padding:calc(env(safe-area-inset-top) + 8px) 10px 8px!important;box-sizing:border-box!important}",
    C("header-main") + "{width:100%!important;min-width:0!important;height:auto!important;padding:0!important;margin:0!important;display:flex!important;gap:8px!important;align-items:center!important}",
    C("header-right") + "{width:100%!important;min-width:0!important;height:auto!important;padding:0!important;margin:0!important;display:flex!important;align-items:center!important;gap:10px!important}",
    C("search-container") + "{flex:1!important;width:auto!important;min-width:0!important;height:42px!important;margin:0!important;position:relative!important;border:2px solid #111!important;border-radius:21px!important;background:#fff!important;box-sizing:border-box!important;overflow:hidden!important;display:flex!important;align-items:center!important}",
    C("search-input") + "{width:100%!important;height:38px!important;border:0!important;outline:0!important;background:transparent!important;padding:0 84px 0 16px!important;font-size:15px!important;box-sizing:border-box!important}",
    C("search-icon") + "{position:absolute!important;right:3px!important;top:3px!important;width:72px!important;height:32px!important;border-radius:16px!important;background:#111!important;color:#fff!important;border:0!important;display:flex!important;align-items:center!important;justify-content:center!important;gap:4px!important}",
    C("search-icon") + " img{filter:invert(1)!important}",
    C("search-icon") + " span{color:#fff!important;font-size:13px!important;white-space:nowrap!important;overflow:hidden!important;max-width:44px!important;text-overflow:ellipsis!important}",
    C("user-order-container") + "{display:flex!important;gap:10px!important;margin:0!important;flex:none!important}",
    C("user-order-container") + " " + C("nick") + "," + C("orderText") + "{display:none!important}",

    // Nội dung
    C("content-container") + "{width:100%!important;min-width:0!important;padding:0 8px!important;margin:0!important;box-sizing:border-box!important}",
    C("content-container") + ">main:not(" + C("feeds-main") + "){display:none!important}",
    C("feeds-main") + "," + C("feeds-container") + "{background:transparent!important;border-radius:0!important;width:100%!important;min-width:0!important;padding:0!important;margin:0!important}",

    // Thanh lọc thành hàng cuộn ngang như app
    C("tags-container") + "{display:flex!important;flex-wrap:nowrap!important;overflow-x:auto!important;width:100%!important;gap:4px!important;padding:6px 2px!important;margin:0!important;scrollbar-width:none!important;-webkit-overflow-scrolling:touch}",
    C("tags-container") + "::-webkit-scrollbar{display:none}",
    C("filter-tab") + "{flex:none!important;width:auto!important;height:32px!important;padding:0 10px!important;margin:0!important;border-radius:16px!important;display:flex!important;align-items:center!important;background:transparent!important}",
    C("filter-tab") + " img{display:none!important}",
    C("filter-tab") + " span{font-size:15px!important;color:#666!important}",
    C("filter-tab-checked") + " span{font-size:17px!important;font-weight:700!important;color:#111!important}",
    C("filter-tab-bold") + "," + C("filter-tab-normal") + "{position:static!important;padding:0!important;width:auto!important}",
    C("filter-tab") + ":not(" + C("filter-tab-checked") + ") " + C("filter-tab-bold") + "{display:none!important}",
    C("filter-tab-checked") + " " + C("filter-tab-normal") + "{display:none!important}",

    // Lưới sản phẩm 2 cột
    C("feeds-list-container") + "{display:grid!important;grid-template-columns:1fr 1fr!important;align-items:start!important;gap:8px!important;width:100%!important;min-width:0!important;height:auto!important;padding:4px 0 12px!important;margin:0!important}",
    C("feeds-item-wrap") + "{width:auto!important;min-width:0!important;height:auto!important;margin:0!important;padding:0!important;background:#fff!important;border-radius:10px!important;overflow:hidden!important;position:relative!important;transform:none!important;left:auto!important;top:auto!important;box-shadow:none!important}",
    C("feeds-image-container") + "{width:100%!important;height:auto!important;aspect-ratio:1/1!important;margin:0!important;padding:0!important;border-radius:0!important;overflow:hidden!important}",
    C("feeds-item-wrap") + ">div{margin-left:0!important;margin-right:0!important}",
    C("feeds-image") + "{width:100%!important;height:100%!important;object-fit:cover!important;border-radius:0!important}",
    C("feeds-content") + "{width:auto!important;height:auto!important;padding:8px 10px 10px!important;margin:0!important}",
    C("row1-wrap-title") + "{width:auto!important;height:auto!important;max-height:none!important;margin:0 0 4px!important;padding:0!important;font-size:14px!important;line-height:19px!important;display:-webkit-box!important;-webkit-line-clamp:2!important;-webkit-box-orient:vertical!important;overflow:hidden!important}",
    C("main-title") + "{font-size:14px!important;line-height:19px!important;color:#111!important;display:inline!important;height:auto!important;max-height:none!important;width:auto!important;overflow:visible!important;margin:0!important;position:static!important;-webkit-line-clamp:unset!important}",
    C("main-title") + " *{line-height:19px!important;vertical-align:baseline!important}",
    C("row2-wrap-placeholder") + "{display:none!important}",
    C("row3-wrap-price") + "{width:auto!important;height:auto!important;display:flex!important;align-items:baseline!important;gap:6px!important;flex-wrap:wrap!important;margin:2px 0!important}",
    C("price-wrap") + "{color:#ff4400!important;font-weight:700!important;width:auto!important}",
    C("price-desc") + "{font-size:12px!important;color:#999!important;width:auto!important;overflow:hidden!important;white-space:nowrap!important;text-overflow:ellipsis!important}",
    C("row4-wrap-seller") + "{width:auto!important;height:auto!important;display:flex!important;align-items:center!important;gap:6px!important;margin-top:4px!important;flex-wrap:nowrap!important;overflow:hidden!important}",
    C("seller-text-wrap") + "{font-size:12px!important;color:#888!important;width:auto!important;min-width:0!important;overflow:hidden!important;white-space:nowrap!important;text-overflow:ellipsis!important;flex:1!important}",
    C("credit-container") + "{display:none!important}",

    // ===== Trang chi tiết sản phẩm (/item): ảnh to ở trên, thông tin bên dưới, nút mua dính đáy như app =====
    "html.gf-item #gf-tabbar{display:none!important}",
    "html.gf-item body{padding-bottom:calc(72px + env(safe-area-inset-bottom))!important}",
    "html.gf-item " + C("item-container") + "{display:block!important;min-height:0!important}",
    "html.gf-item " + C("item-user-container") + "{width:100%!important;height:auto!important;min-height:60px!important;margin:8px 0 0!important;padding:8px 0!important;border-radius:12px!important;box-sizing:border-box!important}",
    "html.gf-item " + C("item-user-info-container") + "{width:auto!important;flex:1!important;min-width:0!important;margin-left:10px!important;overflow:hidden!important}",
    "html.gf-item " + C("item-user-fish-shop") + "{margin-right:10px!important}",
    "html.gf-item " + C("item-main-container") + "{display:flex!important;flex-direction:column!important;width:100%!important;min-height:0!important;margin-top:8px!important;border-radius:12px!important;overflow:hidden!important}",
    "html.gf-item " + C("item-main-container") + " " + C("window") + ",html.gf-item " + C("item-main-window") + "{display:flex!important;flex-direction:column!important;width:100%!important;height:auto!important;margin:0!important;position:static!important}",
    "html.gf-item " + C("item-main-window-list") + ",html.gf-item " + C("item-main-container") + " " + C("list") + "{display:none!important}",
    "html.gf-item " + C("item-main-window-carousel") + ",html.gf-item " + C("item-main-container") + " " + C("carousel") + "{width:100%!important;height:auto!important;aspect-ratio:1/1!important;margin:0!important;border-radius:0!important;display:block!important}",
    "html.gf-item " + C("carousel-container") + "{width:100%!important;height:100%!important;border-radius:0!important}",
    "html.gf-item " + C("carousel-container") + " img{width:100%!important;height:100%!important;object-fit:contain!important}",
    "html.gf-item " + C("player-wrapper") + "{height:100%!important}",
    "html.gf-item " + C("item-main-window-carousel") + " " + C("tips") + "{display:none!important}",
    "html.gf-item " + C("item-main-info") + ",html.gf-item " + C("item-main-container") + " " + C("info") + "{width:100%!important;max-width:100%!important;margin:0!important;padding:12px 12px 16px!important;box-sizing:border-box!important}",
    "html.gf-item " + C("labels") + ">*{width:50%!important;box-sizing:border-box!important;padding-right:8px!important}",
    "html.gf-item " + C("labels") + " " + C("value") + "{max-width:none!important}",
    "html.gf-item " + C("labels") + " " + C("label") + "{margin-right:6px!important;white-space:nowrap!important;flex:none!important}",
    "html.gf-item " + C("notloginMask") + "{width:100%!important;left:0!important}",
    // Thanh nút Muốn mua / Mua ngay dính đáy màn hình
    "html.gf-item " + C("buttons") + "{position:fixed!important;left:0!important;right:0!important;bottom:0!important;top:auto!important;width:100%!important;height:auto!important;margin:0!important;padding:8px 10px calc(8px + env(safe-area-inset-bottom))!important;background:#fff!important;box-shadow:0 -1px 6px rgba(0,0,0,.08)!important;box-sizing:border-box!important;z-index:2147482000!important;display:flex!important;gap:8px!important}",
    "html.gf-item " + C("buttons") + " " + C("left") + "{flex:1!important;width:auto!important;height:46px!important;margin:0!important;font-size:16px!important}",
    "html.gf-item " + C("buttons") + " " + C("left") + ">*{flex:1!important;width:auto!important;height:46px!important}",
    "html.gf-item " + C("buttons") + " " + C("right") + "{width:auto!important;height:46px!important;padding:0 16px!important;font-size:15px!important}",
    "html.gf-item " + C("buttons") + " " + C("banned") + "{height:46px!important;font-size:15px!important}",
    "html.gf-item " + C("buttons") + " " + C("notice") + "{display:none!important}",
    "html.gf-item " + C("sellerButtonGroup") + "{gap:8px!important}",
    "html.gf-item " + C("sellerButton") + "{height:46px!important;font-size:15px!important}",
    // Phần "Gợi ý cho bạn" bên dưới
    "html.gf-item " + C("item-feeds-container") + "{display:flex!important;flex-direction:column!important;align-items:stretch!important;background:transparent!important;margin-top:12px!important}",
    "html.gf-item " + C("item-feeds-container") + ">*{width:100%!important;max-width:100%!important;margin-left:0!important;margin-right:0!important}",

    // Thẻ sản phẩm ở mọi trang: không để chữ tràn ra ngoài thẻ
    C("feeds-item-wrap") + "{justify-content:flex-start!important;align-content:flex-start!important;border:0!important}",
    C("feeds-item-wrap") + " *{min-width:0!important;max-width:100%!important;box-sizing:border-box!important}",

    // Hộp thoại (đăng nhập...) vừa màn hình
    ".ant-modal{max-width:calc(100vw - 16px)!important;width:calc(100vw - 16px)!important;margin:0 auto!important;top:max(20px,env(safe-area-inset-top))!important;padding:0!important}",
    ".ant-modal-content{border-radius:16px!important}",
    ".ant-modal-body>div,.ant-modal-body>div>div{flex-wrap:wrap!important}",

    // Thanh tab dưới cùng
    "#gf-tabbar{position:fixed;left:0;right:0;bottom:0;z-index:2147483000;height:calc(58px + env(safe-area-inset-bottom));padding-bottom:env(safe-area-inset-bottom);background:#fff;border-top:1px solid #eee;display:flex;align-items:flex-start;justify-content:space-around;font-family:-apple-system,system-ui,sans-serif;box-sizing:border-box}",
    "#gf-tabbar a{flex:1;display:flex;flex-direction:column;align-items:center;gap:2px;padding-top:7px;color:#333;text-decoration:none;font-size:11px;line-height:13px}",
    "#gf-tabbar a svg{width:25px;height:25px}",
    "#gf-tabbar a.on{color:#111;font-weight:700}",
    "#gf-tabbar a.on .gf-fill{fill:#ffe60f}",
    "#gf-tabbar a.gf-sell{position:relative;top:-14px;padding-top:0;gap:0}",
    "#gf-tabbar a.gf-sell .gf-bubble{width:50px;height:50px;border-radius:50%;background:#ffe60f;display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,.15);border:4px solid #fff}",
    "#gf-tabbar a.gf-sell span{font-weight:700;color:#111;margin-top:1px}",
    C("login-modal-wrap") + "{opacity:0!important}",
    "body:has(" + C("login-modal-wrap") + ") .ant-modal-mask{display:none!important}"
  ].join("\n");

  function addStyle() {
    if (!document.documentElement || document.getElementById("gf-skin-css")) return;
    var s = document.createElement("style");
    s.id = "gf-skin-css";
    s.textContent = css;
    (document.head || document.documentElement).appendChild(s);
  }

  // ---------- 3. Thanh tab dưới cùng ----------
  var ICON = {
    home: '<svg viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="1.8" stroke-linejoin="round"><path class="gf-fill" fill="none" d="M4 10.5 12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19z"/><path d="M12 13v3"/></svg>',
    msg: '<svg viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="1.8" stroke-linejoin="round"><path class="gf-fill" fill="none" d="M12 4c4.7 0 8.5 3.2 8.5 7.2s-3.8 7.2-8.5 7.2c-1 0-2-.1-2.9-.4L5 20l.9-3.4C4.4 15.3 3.5 13.3 3.5 11.2 3.5 7.2 7.3 4 12 4z"/><circle cx="8.5" cy="11.2" r=".9" fill="#111"/><circle cx="12" cy="11.2" r=".9" fill="#111"/><circle cx="15.5" cy="11.2" r=".9" fill="#111"/></svg>',
    sell: '<svg viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="2" stroke-linejoin="round"><path d="M4 8.5h3l1.5-2.5h7L17 8.5h3V19H4z"/><circle cx="12" cy="13.3" r="3.3"/></svg>',
    me: '<svg viewBox="0 0 24 24" fill="none" stroke="#111" stroke-width="1.8"><circle class="gf-fill" fill="none" cx="12" cy="12" r="8.5"/><path d="M8.5 13.5c.9 1.4 2.1 2 3.5 2s2.6-.6 3.5-2" stroke-linecap="round"/></svg>'
  };
  function addTabbar() {
    if (!document.body || document.getElementById("gf-tabbar")) return;
    var path = location.pathname;
    function on(p) { return (p === "/" ? path === "/" : path.indexOf(p) === 0) ? " on" : ""; }
    var bar = document.createElement("nav");
    bar.id = "gf-tabbar";
    bar.className = "notranslate";
    bar.innerHTML =
      '<a href="/" class="' + on("/") + '">' + ICON.home + "<span>" + L.home + "</span></a>" +
      '<a href="/publish" class="gf-sell"><div class="gf-bubble">' + ICON.sell + "</div><span>" + L.sell + "</span></a>" +
      '<a href="/im" class="' + on("/im") + '">' + ICON.msg + "<span>" + L.msg + "</span></a>" +
      '<a href="/personal" class="' + on("/personal") + '">' + ICON.me + "<span>" + L.me + "</span></a>";
    document.body.appendChild(bar);
  }
  function markPage() {
    if (document.documentElement) document.documentElement.classList.toggle("gf-item", location.pathname === "/item");
  }
  function refreshTabbar() {
    markPage();
    var bar = document.getElementById("gf-tabbar");
    if (bar) bar.remove();
    addTabbar();
  }
  // Trang tự đổi địa chỉ (không tải lại) → cập nhật tab đang chọn
  ["pushState", "replaceState"].forEach(function (k) {
    var orig = history[k];
    history[k] = function () { var r = orig.apply(this, arguments); setTimeout(refreshTabbar, 0); return r; };
  });
  window.addEventListener("popstate", function () { setTimeout(refreshTabbar, 0); });

  // ---------- 4. Co các khối quá rộng cho vừa màn hình (trang chưa có kiểu riêng) ----------
  var fitTimer = null;
  function fitWide() {
    fitTimer = null;
    var vw = document.documentElement.clientWidth || window.innerWidth;
    var all = document.body ? document.body.getElementsByTagName("*") : [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.id === "gf-tabbar" || el.closest && el.closest("#gf-tabbar")) continue;
      var w = el.offsetWidth;
      if (w <= vw + 1) continue;
      var cs = getComputedStyle(el);
      if (cs.position === "fixed" || cs.position === "absolute") { el.style.setProperty("max-width", "100vw", "important"); continue; }
      if (el.scrollWidth > w + 4 && /auto|scroll/.test(cs.overflowX)) continue; // hàng cuộn ngang: giữ nguyên
      el.style.setProperty("width", "100%", "important");
      el.style.setProperty("min-width", "0", "important");
      el.style.setProperty("max-width", "100%", "important");
      el.style.setProperty("box-sizing", "border-box", "important");
      if (cs.display.indexOf("flex") >= 0 && cs.flexDirection.indexOf("row") === 0) el.style.setProperty("flex-wrap", "wrap", "important");
    }
  }
  function scheduleFit() { if (!fitTimer) fitTimer = setTimeout(fitWide, 400); }

  // ---------- 5. Hộp đăng nhập bản máy tính → trang đăng nhập bản điện thoại của Xianyu ----------
  var loginRedirected = false;
  function checkLogin() {
    if (loginRedirected) return;
    if (!document.querySelector('[class*="login-modal-wrap--"]')) return;
    loginRedirected = true;
    location.href = "https://passport.goofish.com/mini_login.htm?appName=xianyu&appEntrance=web&redirectType=redirect&isMobile=true&returnUrl=" +
      encodeURIComponent(location.href);
  }

  // ---------- Khởi động ----------
  fixViewport();
  addStyle();
  markPage();
  new MutationObserver(function () {
    markPage();
    fixViewport();
    addStyle();
    addTabbar();
    checkLogin();
    scheduleFit();
  }).observe(document, { childList: true, subtree: true });
  document.addEventListener("DOMContentLoaded", function () { fixViewport(); addStyle(); addTabbar(); scheduleFit(); });
  window.addEventListener("resize", scheduleFit);
})();
