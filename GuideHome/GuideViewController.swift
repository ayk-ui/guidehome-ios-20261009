import UIKit
@preconcurrency import WebKit

@MainActor
private final class WeakThemeHandler: NSObject, WKScriptMessageHandler {
    weak var owner: GuideViewController?

    init(owner: GuideViewController) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        owner?.receiveTheme(message)
    }
}

@MainActor
final class GuideViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private var statusStyle: UIStatusBarStyle = .darkContent
    private var currentTheme = "#ffffff"
    private let themeHandlerName = "guideTheme_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var lastExternalURL: URL?
    private var lastExternalOpenedAt = Date.distantPast
    private var hasPresentedLoadFailure = false

    override var preferredStatusBarStyle: UIStatusBarStyle { statusStyle }
    override var prefersStatusBarHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .white

        let content = WKUserContentController()
        content.add(WeakThemeHandler(owner: self), contentWorld: .defaultClient, name: themeHandlerName)
        content.addUserScript(WKUserScript(source: themeScript,
                                          injectionTime: .atDocumentEnd,
                                          forMainFrameOnly: true,
                                          in: .defaultClient))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = content
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        openEntry()
    }

    private func openEntry() {
        hasPresentedLoadFailure = false
        webView.load(URLRequest(url: AppConfiguration.entryURL,
                                cachePolicy: .useProtocolCachePolicy,
                                timeoutInterval: 30))
    }

    private func retryCurrentPage() {
        hasPresentedLoadFailure = false
        if AppConfiguration.owns(webView.url) {
            webView.reload()
        } else {
            openEntry()
        }
    }

    // Isolated-world, per-controller random handler name; the only body is a color.
    // No account/session/storage observation or native request bridge is installed.
    private var themeScript: String {
        """
        (() => {
          let last = '';
          const send = () => {
            const color = document.querySelector('meta[name="theme-color"]')?.content || '#ffffff';
            if (!/^#[0-9a-fA-F]{6}$/.test(color) || color === last) return;
            last = color;
            window.webkit.messageHandlers["\(themeHandlerName)"].postMessage(color);
          };
          const observer = new MutationObserver(send);
          if (document.head) observer.observe(document.head, {
            subtree: true, childList: true, attributes: true, attributeFilter: ['content']
          });
          send();
        })();
        """
    }

    fileprivate func receiveTheme(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.name == themeHandlerName,
              message.webView === webView,
              message.frameInfo.isMainFrame,
              origin.`protocol` == "https",
              origin.host.lowercased() == AppConfiguration.host,
              (origin.port == 0 || origin.port == 443),
              let color = message.body as? String,
              color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
              color.lowercased() != currentTheme,
              let value = UInt32(color.dropFirst(), radix: 16) else { return }
        currentTheme = color.lowercased()
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat(value & 0xff) / 255
        let background = UIColor(red: red, green: green, blue: blue, alpha: 1)
        view.backgroundColor = background
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        statusStyle = 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.6 ? .lightContent : .darkContent
        setNeedsStatusBarAppearanceUpdate()
    }

    private func externalOpeningAllowed(_ action: WKNavigationAction) -> Bool {
        action.sourceFrame.isMainFrame
            && (action.navigationType == .linkActivated || action.targetFrame == nil)
    }

    private func openExternal(_ url: URL, from action: WKNavigationAction) {
        guard externalOpeningAllowed(action),
              let scheme = url.scheme?.lowercased(),
              ["https", "http", "tel", "mailto"].contains(scheme),
              url.user == nil, url.password == nil else { return }
        if lastExternalURL == url && Date().timeIntervalSince(lastExternalOpenedAt) < 1 { return }
        lastExternalURL = url
        lastExternalOpenedAt = Date()
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if AppConfiguration.owns(url) {
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                webView.load(navigationAction.request)
            } else {
                decisionHandler(.allow)
            }
            return
        }
        decisionHandler(.cancel)
        openExternal(url, from: navigationAction)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else { return nil }
        if AppConfiguration.owns(url) {
            webView.load(navigationAction.request)
        } else {
            openExternal(url, from: navigationAction)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasPresentedLoadFailure = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        showLoadFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showLoadFailure(nil)
    }

    private func showLoadFailure(_ error: Error?) {
        if let error = error as NSError?, error.domain == NSURLErrorDomain,
           error.code == NSURLErrorCancelled { return }
        guard !hasPresentedLoadFailure, presentedViewController == nil else { return }
        hasPresentedLoadFailure = true
        let alert = UIAlertController(title: "连接失败", message: "请检查网络后重试。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.hasPresentedLoadFailure = false
        })
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in
            self?.retryCurrentPage()
        })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard presentedViewController == nil else { completionHandler(); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard presentedViewController == nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
    // Intentionally do not implement runOpenPanel: WKWebView's system photo/file chooser remains enabled.
}
