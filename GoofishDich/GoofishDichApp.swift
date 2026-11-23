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

// MARK: - Màn hình trình duyệt

final class BrowserVC: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
    static let home = URL(string: "https://www.goofish.com/")!
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1"
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"
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
    private let defaults = UserDefaults.standard
    private lazy var scriptSource: String = {
        guard let url = Bundle.main.url(forResource: "translate", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }()

    private var lang: String { defaults.string(forKey: "lang") ?? "en" }
    private var desktop: Bool { defaults.bool(forKey: "desktop") }

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
        web.customUserAgent = desktop ? Self.desktopUA : Self.mobileUA
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
        setupMenuButton()
        web.load(URLRequest(url: Self.home))
    }

    private func installScript(_ ucc: WKUserContentController) {
        ucc.removeAllUserScripts()
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
        preferences.preferredContentMode = desktop ? .desktop : .mobile
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow, preferences); return
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
        sheet.addAction(UIAlertAction(title: desktop ? "📱  Chuyển sang giao diện điện thoại"
                                                     : "💻  Chuyển sang giao diện máy tính", style: .default) { [weak self] _ in
            guard let self else { return }
            self.defaults.set(!self.desktop, forKey: "desktop")
            self.web.customUserAgent = self.desktop ? Self.desktopUA : Self.mobileUA
            self.web.reload()
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
