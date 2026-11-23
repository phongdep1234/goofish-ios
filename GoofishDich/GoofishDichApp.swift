import SwiftUI
import UIKit
import WebKit

@main
struct GoofishDichApp: App {
    var body: some Scene {
        WindowGroup {
            BrowserView().ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

struct BrowserView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BrowserVC { BrowserVC() }
    func updateUIViewController(_ vc: BrowserVC, context: Context) {}
}

// MARK: - Dịch qua Google Translate (miễn phí), có bộ nhớ đệm

actor Translator {
    private var cache: [String: String] = [:]

    func translate(_ texts: [String], tl: String) async -> [String?] {
        var out = [String?](repeating: nil, count: texts.count)
        var todo: [Int] = []
        for (i, t) in texts.enumerated() {
            if let hit = cache[tl + "|" + t] { out[i] = hit } else { todo.append(i) }
        }
        if todo.isEmpty { return out }

        let clean = todo.map {
            texts[$0].replacingOccurrences(of: "\\s*\\n\\s*", with: " ", options: .regularExpression)
        }
        var parts: [String?]? = nil
        if let joined = try? await request(clean.joined(separator: "\n"), tl: tl) {
            let p = joined.components(separatedBy: "\n")
            if p.count == clean.count { parts = p }
        }
        if parts == nil { // số dòng không khớp → dịch từng câu
            var arr: [String?] = []
            for c in clean { arr.append(try? await request(c, tl: tl)) }
            parts = arr
        }
        for (k, i) in todo.enumerated() {
            if let v = parts?[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                out[i] = v
                cache[tl + "|" + texts[i]] = v
            }
        }
        if cache.count > 20000 { cache.removeAll() }
        return out
    }

    private func request(_ text: String, tl: String) async throws -> String {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"), URLQueryItem(name: "sl", value: "zh-CN"),
            URLQueryItem(name: "tl", value: tl), URLQueryItem(name: "dt", value: "t"),
        ]
        var req = URLRequest(url: comps.url!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let q = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        req.httpBody = ("q=" + q).data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let segs = root.first as? [Any] else { throw URLError(.badServerResponse) }
        var s = ""
        for seg in segs {
            if let arr = seg as? [Any], let t = arr.first as? String { s += t }
        }
        return s
    }
}

// MARK: - Giữ đăng nhập: lưu cookie của Xianyu/Taobao/Alipay, kể cả cookie "phiên" mà iOS xoá khi app bị tắt

enum CookieVault {
    static let domains = ["goofish.com", "taobao.com", "tmall.com", "alipay.com", "alibaba.com", "tb.cn", "mmstat.com", "alicdn.com"]
    static let keepDays: TimeInterval = 30 * 24 * 3600

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cookies.plist")
    }

    static func relevant(_ c: HTTPCookie) -> Bool {
        let d = c.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domains.contains { d == $0 || d.hasSuffix("." + $0) }
    }

    /// Lưu toàn bộ cookie liên quan xuống máy.
    static func save(_ store: WKHTTPCookieStore) {
        store.getAllCookies { cookies in
            var list: [[String: Any]] = []
            for c in cookies where relevant(c) {
                var d: [String: Any] = ["name": c.name, "value": c.value, "domain": c.domain, "path": c.path,
                                        "secure": c.isSecure]
                if let e = c.expiresDate { d["expires"] = e.timeIntervalSince1970 }
                if let ss = c.sameSitePolicy?.rawValue { d["sameSite"] = ss }
                list.append(d)
            }
            guard !list.isEmpty,
                  let data = try? PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0) else { return }
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Đặt lại các cookie đã lưu mà hiện đang thiếu, rồi gọi done().
    static func restore(_ store: WKHTTPCookieStore, done: @escaping () -> Void) {
        guard let data = try? Data(contentsOf: fileURL),
              let list = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]],
              !list.isEmpty else { done(); return }
        store.getAllCookies { existing in
            let have = Set(existing.map { "\($0.name)|\($0.domain)|\($0.path)" })
            let group = DispatchGroup()
            let now = Date()
            for d in list {
                guard let name = d["name"] as? String, let value = d["value"] as? String,
                      let domain = d["domain"] as? String else { continue }
                let path = d["path"] as? String ?? "/"
                if have.contains("\(name)|\(domain)|\(path)") { continue }
                var expires = now.addingTimeInterval(keepDays) // cookie phiên → giữ 30 ngày
                if let e = d["expires"] as? Double {
                    let date = Date(timeIntervalSince1970: e)
                    if date < now { continue } // đã hết hạn
                    expires = date
                }
                var props: [HTTPCookiePropertyKey: Any] = [
                    .name: name, .value: value, .domain: domain, .path: path, .expires: expires,
                ]
                if (d["secure"] as? Bool) == true { props[.secure] = "TRUE" }
                if let ss = d["sameSite"] as? String { props[.sameSitePolicy] = ss }
                guard let cookie = HTTPCookie(properties: props) else { continue }
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { done() }
        }
    }

    static func clear() { try? FileManager.default.removeItem(at: fileURL) }
}

// MARK: - Màn hình trình duyệt

final class BrowserVC: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
    static let home = URL(string: "https://www.goofish.com/")!
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1"
    /// Lược đồ mở app Xianyu/Taobao gốc: chặn để luôn ở lại trong app này.
    static let blockedSchemes: Set<String> = ["fleamarket", "idlefish", "taobao", "tbopen", "tmall", "tbfleamarket"]
    /// Các trang của Xianyu/Taobao: không cho iOS tự nhảy sang app gốc qua "universal link".
    static let noAppLinkHosts = ["goofish.com", "taobao.com", "tmall.com", "tb.cn"]

    /// Cầu nối cho bộ dịch; chỉ bật trên các trang của Xianyu/Taobao/Alipay.
    static let shim = """
    (function(){
      var H = location.hostname || "";
      if (!/(^|\\.)(goofish\\.com|taobao\\.com|tmall\\.com|alipay\\.com|alibaba\\.com|tb\\.cn)$/.test(H)) return;
      var mh = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.goofish;
      if (!mh) return;
      var b = { onmessage: null };
      b.postMessage = function (s) {
        mh.postMessage(s).then(function (r) { if (r && b.onmessage) b.onmessage({ data: r }); }).catch(function () {});
      };
      window.GoofishNative = b;
    })();

    """

    private var web: WKWebView!
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let menuButton = UIButton(type: .system)
    private let translator = Translator()
    private var progressObs: NSKeyValueObservation?
    private var urlObs: NSKeyValueObservation?
    private let defaults = UserDefaults.standard
    private lazy var scriptSource: String = {
        guard let url = Bundle.main.url(forResource: "translate", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }()

    private var lang: String { defaults.string(forKey: "lang") ?? "en" }
    /// Lớp giao diện kiểu app điện thoại cho trang goofish.com (mặc định bật).
    private var appSkin: Bool { !defaults.bool(forKey: "skinOff") }
    private lazy var skinSource: String = {
        guard let url = Bundle.main.url(forResource: "skin", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }()
    /// Mở trang sản phẩm bằng bản điện thoại (h5.m.goofish.com). Xianyu chỉ có bản điện thoại cho trang sản phẩm.
    private var mobileItems: Bool { defaults.bool(forKey: "mobileItems") }

    /// Lấy mã sản phẩm từ link trang sản phẩm (bản máy tính hoặc bản điện thoại).
    private static func itemId(_ url: URL?, mobileHost: Bool) -> String? {
        guard let url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = comps.host?.lowercased() ?? ""
        let ok = mobileHost ? host == "h5.m.goofish.com" : (host == "www.goofish.com" || host == "goofish.com")
        guard ok, comps.path == "/item",
              let id = comps.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return id
    }

    /// Đang ở chế độ điện thoại + link là trang sản phẩm bản máy tính → link bản điện thoại.
    private func mobileRedirect(_ url: URL?) -> URL? {
        guard mobileItems, let id = Self.itemId(url, mobileHost: false) else { return nil }
        return URL(string: "https://h5.m.goofish.com/item?id=\(id)")
    }

    private func toggleItemMode() {
        let toMobile = !mobileItems
        defaults.set(toMobile, forKey: "mobileItems")
        if toMobile, let id = Self.itemId(web.url, mobileHost: false) {
            web.load(URLRequest(url: URL(string: "https://h5.m.goofish.com/item?id=\(id)")!))
        } else if !toMobile, let id = Self.itemId(web.url, mobileHost: true) {
            web.load(URLRequest(url: URL(string: "https://www.goofish.com/item?id=\(id)")!))
        }
        showMessage(toMobile
            ? "Trang sản phẩm sẽ mở bằng bản điện thoại. Trang chủ, tìm kiếm, tin nhắn vẫn là bản máy tính (Xianyu không có bản điện thoại cho các trang này)."
            : "Trang sản phẩm sẽ mở bằng bản máy tính (đầy đủ tính năng).")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default() // lưu đăng nhập
        cfg.allowsInlineMediaPlayback = true
        cfg.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "goofish")
        installScript(cfg.userContentController)

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true // vuốt từ mép trái để quay lại
        web.customUserAgent = Self.mobileUA
        if #available(iOS 16.4, *) { web.isInspectable = true }
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullRefresh(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh

        web.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        view.addSubview(progress)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        progressObs = web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
            self?.progress.setProgress(Float(w.estimatedProgress), animated: true)
            self?.progress.isHidden = w.estimatedProgress >= 1
        }
        // Trang máy tính đổi địa chỉ bằng JavaScript (không tải lại trang) → bắt ở đây
        urlObs = web.observe(\.url, options: [.new]) { [weak self] w, _ in
            DispatchQueue.main.async {
                guard let self, let m = self.mobileRedirect(w.url) else { return }
                w.load(URLRequest(url: m))
            }
        }
        setupMenuButton()
        // Khôi phục đăng nhập trước khi mở trang
        let cookieStore = cfg.websiteDataStore.httpCookieStore
        CookieVault.restore(cookieStore) { [weak self] in
            self?.web.load(URLRequest(url: Self.home))
        }
        // Lưu đăng nhập mỗi khi app chuyển xuống nền
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            CookieVault.save(cookieStore)
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            CookieVault.save(cookieStore)
        }
    }

    private func installScript(_ ucc: WKUserContentController) {
        ucc.removeAllUserScripts()
        if appSkin { // chèn trước bộ dịch; tự kiểm tra chỉ chạy trên www.goofish.com
            ucc.addUserScript(WKUserScript(source: "window.__gfLang=\"\(lang)\";\n" + skinSource,
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        guard lang != "off" else { return }
        let src = Self.shim + "window.__gfLang=\"\(lang)\";\n" + scriptSource
        ucc.addUserScript(WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    @objc private func pullRefresh(_ rc: UIRefreshControl) {
        web.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { rc.endRefreshing() }
    }

    // MARK: Cầu nối dịch
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let raw = message.body as? String,
              let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = obj["id"] as? String,
              let texts = obj["texts"] as? [String] else { replyHandler(nil, nil); return }
        let tl = obj["tl"] as? String ?? "en"
        let translator = self.translator
        Task {
            let out = await translator.translate(Array(texts.prefix(100)), tl: tl)
            let result: [Any] = out.map { v -> Any in
                if let v { return v }
                return NSNull()
            }
            var answer: String? = nil
            if let d = try? JSONSerialization.data(withJSONObject: ["id": id, "result": result]) {
                answer = String(data: d, encoding: .utf8)
            }
            await MainActor.run { replyHandler(answer, nil) }
        }
    }

    // MARK: Điều hướng
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = .mobile
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow, preferences); return
        }
        if action.targetFrame?.isMainFrame ?? true, let m = mobileRedirect(url) {
            decisionHandler(.cancel, preferences)
            webView.load(URLRequest(url: m))
            return
        }
        if ["http", "https", "about", "data", "blob", "javascript"].contains(scheme) {
            let host = url.host?.lowercased() ?? ""
            let isAliApp = Self.noAppLinkHosts.contains { host == $0 || host.hasSuffix("." + $0) }
            if isAliApp, let noAppLink = WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) {
                decisionHandler(noAppLink, preferences) // ở lại trong app, không nhảy sang app Xianyu
            } else {
                decisionHandler(.allow, preferences)
            }
            return
        }
        decisionHandler(.cancel, preferences)
        if Self.blockedSchemes.contains(scheme) { return }
        // alipays://, alipay://, tel:, mailto: ... → mở app tương ứng
        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            guard !ok else { return }
            let msg = scheme.hasPrefix("alipay")
                ? "Chưa cài app Alipay. Hãy cài Alipay từ App Store để thanh toán."
                : "Không có app nào mở được liên kết này."
            self?.showMessage(msg)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        CookieVault.save(webView.configuration.websiteDataStore.httpCookieStore) // lưu sau mỗi lần tải trang
        webView.scrollView.refreshControl?.endRefreshing()
    }

    // Link "mở tab mới" → mở ngay trong app
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }

    // Hộp thoại alert / confirm / prompt của trang
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentSafely(a, fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presentSafely(a) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        presentSafely(a) { completionHandler(nil) }
    }

    private func presentSafely(_ vc: UIViewController, fallback: @escaping () -> Void) {
        if presentedViewController == nil { present(vc, animated: true) } else { fallback() }
    }

    private func showMessage(_ msg: String) {
        let a = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        if presentedViewController == nil { present(a, animated: true) }
    }

    // MARK: Nút menu nổi "文"
    private func setupMenuButton() {
        menuButton.setTitle("文", for: .normal)
        menuButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        menuButton.tintColor = .white
        menuButton.backgroundColor = UIColor(white: 0.12, alpha: 0.65)
        menuButton.layer.cornerRadius = 22
        menuButton.layer.shadowOpacity = 0.3
        menuButton.layer.shadowRadius = 4
        menuButton.frame = CGRect(x: 6, y: 0, width: 44, height: 44)
        menuButton.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        menuButton.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragMenu(_:))))
        view.addSubview(menuButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let saved = (defaults.object(forKey: "btnY") as? Double).map { CGFloat($0) } ?? view.bounds.height * 0.35
        menuButton.center.y = clampY(saved)
    }

    private func clampY(_ y: CGFloat) -> CGFloat {
        let top = view.safeAreaInsets.top + 30
        let bottom = view.bounds.height - view.safeAreaInsets.bottom - 30
        return min(max(y, top), max(top, bottom))
    }

    @objc private func dragMenu(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: view)
        menuButton.center.y = clampY(p.y)
        defaults.set(Double(menuButton.center.y), forKey: "btnY")
    }

    @objc private func showMenu() {
        let langLabel = lang == "vi" ? "Tiếng Việt" : lang == "off" ? "Tắt (tiếng Trung gốc)" : "English"
        let sheet = UIAlertController(title: "Goofish Dịch", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "🏠  Trang chủ", style: .default) { [weak self] _ in
            self?.web.load(URLRequest(url: Self.home))
        })
        sheet.addAction(UIAlertAction(title: "🔄  Tải lại trang", style: .default) { [weak self] _ in
            self?.web.reload()
        })
        sheet.addAction(UIAlertAction(title: "🌐  Ngôn ngữ dịch: \(langLabel)", style: .default) { [weak self] _ in
            self?.chooseLanguage()
        })
        sheet.addAction(UIAlertAction(title: appSkin ? "🖥  Tắt giao diện app (xem trang gốc)"
                                                     : "📲  Bật giao diện app", style: .default) { [weak self] _ in
            guard let self else { return }
            self.defaults.set(self.appSkin, forKey: "skinOff")
            self.installScript(self.web.configuration.userContentController)
            self.web.reload()
        })
        sheet.addAction(UIAlertAction(title: mobileItems ? "💻  Trang sản phẩm: chuyển về bản máy tính"
                                                         : "📱  Trang sản phẩm: chuyển sang bản điện thoại", style: .default) { [weak self] _ in
            self?.toggleItemMode()
        })
        sheet.addAction(UIAlertAction(title: "📋  Sao chép link trang này", style: .default) { [weak self] _ in
            UIPasteboard.general.string = self?.web.url?.absoluteString
        })
        sheet.addAction(UIAlertAction(title: "🚪  Đăng xuất", style: .destructive) { [weak self] _ in
            self?.confirmLogout()
        })
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        anchor(sheet)
        present(sheet, animated: true)
    }

    private func chooseLanguage() {
        let sheet = UIAlertController(title: "Dịch sang", message: nil, preferredStyle: .actionSheet)
        for (label, code) in [("English", "en"), ("Tiếng Việt", "vi"), ("Tắt dịch (xem tiếng Trung gốc)", "off")] {
            sheet.addAction(UIAlertAction(title: (code == lang ? "✓ " : "") + label, style: .default) { [weak self] _ in
                guard let self else { return }
                self.defaults.set(code, forKey: "lang")
                self.installScript(self.web.configuration.userContentController)
                self.web.reload()
            })
        }
        sheet.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        anchor(sheet)
        present(sheet, animated: true)
    }

    private func confirmLogout() {
        let a = UIAlertController(title: nil,
                                  message: "Xoá cookie và dữ liệu đăng nhập trong app? Lần sau bạn sẽ phải đăng nhập lại.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Huỷ", style: .cancel))
        a.addAction(UIAlertAction(title: "Đăng xuất", style: .destructive) { [weak self] _ in
            let store = WKWebsiteDataStore.default()
            CookieVault.clear()
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
                self?.web.load(URLRequest(url: Self.home))
            }
        })
        present(a, animated: true)
    }

    private func anchor(_ sheet: UIAlertController) {
        sheet.popoverPresentationController?.sourceView = menuButton
        sheet.popoverPresentationController?.sourceRect = menuButton.bounds
    }
}
