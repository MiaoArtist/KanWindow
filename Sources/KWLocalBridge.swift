import Foundation
import WebKit

/// 本地服务桥：把页面里对 http://127.0.0.1:* / http://localhost:* 的 fetch/XHR 请求
/// 改写为 kwlocal://fetch?… 自定义 scheme，由本类用 URLSession 转发。
///
/// 解决的问题：WKWebView（WebKit）不允许 https 页面发起对明文 loopback 的
/// “混合内容”请求（Chrome 对 localhost 有豁免，WebKit 没有），导致
/// AnkiConnect（http://127.0.0.1:8765）等本机 WebUI 在窥窗里不可用。
/// 自定义 scheme 不受混合内容策略限制，响应再带上 CORS 放行头，页面即可正常调用。
final class KWLocalBridge: NSObject, WKURLSchemeHandler {

    private let session: URLSession

    override init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(), host == "fetch",
              let items = comps.queryItems else {
            fail(urlSchemeTask, code: 400, message: "bad kwlocal url")
            return
        }
        func v(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let target = v("u"),
              let targetURL = URL(string: target),
              Self.isLocalHostURL(targetURL) else {
            fail(urlSchemeTask, code: 400, message: "bad target url")
            return
        }

        var req = URLRequest(url: targetURL)
        req.httpMethod = v("m") ?? "GET"
        if let hJson = v("h"), let d = hJson.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
            for (k, val) in obj {
                // 浏览器本身会带的头不重复设置，避免冲突
                if k.lowercased().hasPrefix("sec-") || k.lowercased() == "origin"
                    || k.lowercased() == "referer" { continue }
                req.setValue(val, forHTTPHeaderField: k)
            }
        }
        if let b64 = v("b"), !b64.isEmpty, let data = Data(base64Encoded: b64) {
            req.httpBody = data
        }

        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            if let err = err {
                self.fail(urlSchemeTask, code: 502, message: err.localizedDescription)
                return
            }
            var headers: [String: String] = [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Expose-Headers": "*",
                "Cache-Control": "no-store",
            ]
            var status = 200
            if let http = resp as? HTTPURLResponse {
                status = http.statusCode
                if let ct = http.allHeaderFields["Content-Type"] as? String {
                    headers["Content-Type"] = ct
                }
            }
            let response = HTTPURLResponse(url: url,
                                           statusCode: status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            urlSchemeTask.didReceive(response)
            if let data = data { urlSchemeTask.didReceive(data) }
            urlSchemeTask.didFinish()
        }.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 请求已被取消/页面离开：无需额外处理
    }

    // MARK: - 工具

    static func isLocalHostURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let h = url.host?.lowercased() else {
            return false
        }
        return h == "127.0.0.1" || h == "localhost" || h == "[::1]" || h == "::1"
    }

    private func fail(_ task: WKURLSchemeTask, code: Int, message: String) {
        let url = task.request.url ?? URL(string: "kwlocal://fetch")!
        let response = HTTPURLResponse(url: url,
                                       statusCode: code,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Access-Control-Allow-Origin": "*"])!
        task.didReceive(response)
        task.didFinish()
    }
}