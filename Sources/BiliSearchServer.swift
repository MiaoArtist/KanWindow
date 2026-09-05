import Foundation
import Network

/// B站极简搜索的本地代理服务器
/// 监听 127.0.0.1:9327，为「娱乐」组的“B站极简搜索”站点提供：
///  - 首页：定制的极简搜索 UI（搜索框 → 结果列表 → 播放+评论）
///  - /api/*：把 B 站接口请求转发出去（服务端转发没有浏览器跨域问题），
///    并自动带上 buvid 指纹 Cookie 以通过风控。
final class BiliSearchServer {

    static let shared = BiliSearchServer()
    static let port: UInt16 = 9327
    static var baseURL: String { "http://127.0.0.1:\(port)/" }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "bili-search.server", qos: .userInitiated)
    private let startedLock = NSLock()
    private var started = false

    // B站风控指纹 cookie
    private var buvid3 = ""
    private var buvid4 = ""
    private var bNut = ""
    private let lock = NSLock()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 40
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()

    private init() {}

    func start() {
        startedLock.lock()
        if started { startedLock.unlock(); return }
        started = true
        startedLock.unlock()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: Self.port)!
        )
        do {
            let l = try NWListener(using: params)
            listener = l
            l.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            l.start(queue: queue)
            // 预热指纹 cookie（失败也无妨，请求时会重试）
            fetchBuvidIfNeeded {}
        } catch {
            NSLog("BiliSearchServer: listen failed \(error)")
        }
    }

    // MARK: - 连接处理

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        var buffer = Data()

        func readLoop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else {
                    conn.cancel()
                    return
                }
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                    if let sep = buffer.range(of: Data("\r\n\r\n".utf8)) {
                        let head = String(data: buffer[buffer.startIndex..<sep.lowerBound],
                                          encoding: .utf8) ?? ""
                        self.route(head, conn: conn)
                        return
                    }
                }
                if isComplete || error != nil {
                    conn.cancel()
                    return
                }
                readLoop()
            }
        }
        readLoop()
    }

    // MARK: - 路由

    private func route(_ head: String, conn: NWConnection) {
        guard let first = head.split(separator: "\n").first else {
            notFound(conn)
            return
        }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let comps = URLComponents(string: String(parts[1])) else {
            notFound(conn)
            return
        }
        let qs = comps.queryItems ?? []
        func val(_ name: String) -> String {
            qs.first { $0.name == name }?.value ?? ""
        }
        let path = comps.path

        switch path {
        case "/", "/index.html":
            if let html = Self.htmlData {
                respond(conn, status: 200, type: "text/html; charset=utf-8", body: html)
            } else {
                respond(conn, status: 500, type: "text/plain; charset=utf-8",
                        body: Data("missing page".utf8))
            }

        case "/api/search":
            let kw = val("kw")
            let page = val("page").isEmpty ? "1" : val("page")
            guard !kw.isEmpty else {
                respondJSON(conn, status: 400, msg: "empty keyword")
                return
            }
            proxy(conn, path: "/x/web-interface/search/type", items: [
                URLQueryItem(name: "search_type", value: "video"),
                URLQueryItem(name: "keyword", value: kw),
                URLQueryItem(name: "page", value: page),
            ], referer: "https://www.bilibili.com/")

        case "/api/view":
            let bvid = val("bvid")
            guard !bvid.isEmpty else {
                respondJSON(conn, status: 400, msg: "no bvid")
                return
            }
            proxy(conn, path: "/x/web-interface/view", items: [
                URLQueryItem(name: "bvid", value: bvid),
            ], referer: "https://www.bilibili.com/")

        case "/api/reply":
            let aid = val("aid")
            let pn = val("pn").isEmpty ? "1" : val("pn")
            guard !aid.isEmpty else {
                respondJSON(conn, status: 400, msg: "no aid")
                return
            }
            proxy(conn, path: "/x/v2/reply", items: [
                URLQueryItem(name: "type", value: "1"),
                URLQueryItem(name: "oid", value: aid),
                URLQueryItem(name: "sort", value: "2"),
                URLQueryItem(name: "ps", value: "20"),
                URLQueryItem(name: "pn", value: pn),
            ], referer: "https://www.bilibili.com/video/av\(aid)")

        default:
            notFound(conn)
        }
    }

    // MARK: - 转发 B 站 API

    private func proxy(_ conn: NWConnection,
                       path: String,
                       items: [URLQueryItem],
                       referer: String) {
        fetchBuvidIfNeeded { [weak self] in
            guard let self = self else { return }
            guard var comps = URLComponents(string: "https://api.bilibili.com" + path) else {
                self.respondJSON(conn, status: 502, msg: "bad url")
                return
            }
            comps.queryItems = items
            guard let url = comps.url else {
                self.respondJSON(conn, status: 502, msg: "bad url")
                return
            }
            var req = URLRequest(url: url)
            req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue(referer, forHTTPHeaderField: "Referer")
            req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            req.setValue(self.cookieHeader(), forHTTPHeaderField: "Cookie")
            self.session.dataTask(with: req) { [weak self] data, _, _ in
                guard let self = self else { return }
                if let data = data {
                    // 原样回传（code!=0 的错误 JSON 也交给前端展示，如 -412 风控）
                    self.respond(conn, status: 200,
                                 type: "application/json; charset=utf-8",
                                 body: data)
                } else {
                    self.respondJSON(conn, status: 502, msg: "proxy error")
                }
            }.resume()
        }
    }

    // MARK: - buvid 指纹

    private func fetchBuvidIfNeeded(_ done: @escaping () -> Void) {
        lock.lock()
        let has = !buvid3.isEmpty
        lock.unlock()
        guard !has,
              let url = URL(string: "https://api.bilibili.com/x/frontend/finger/spi") else {
            done()
            return
        }
        var req = URLRequest(url: url)
        req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        session.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self else {
                done()
                return
            }
            if let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = obj["data"] as? [String: Any] {
                self.lock.lock()
                self.buvid3 = d["b_3"] as? String ?? ""
                self.buvid4 = d["b_4"] as? String ?? ""
                self.bNut = String(Int(Date().timeIntervalSince1970))
                self.lock.unlock()
            }
            done()
        }.resume()
    }

    private func cookieHeader() -> String {
        lock.lock()
        var c = ""
        if !buvid3.isEmpty { c += "buvid3=\(buvid3); " }
        if !buvid4.isEmpty { c += "buvid4=\(buvid4); " }
        if !bNut.isEmpty { c += "b_nut=\(bNut); " }
        lock.unlock()
        return c
    }

    // MARK: - HTTP 响应

    private func respondJSON(_ conn: NWConnection, status: Int, msg: String) {
        let body = "{\"code\":\(status),\"message\":\"\(msg)\"}"
            .data(using: .utf8) ?? Data()
        respond(conn, status: status, type: "application/json; charset=utf-8", body: body)
    }

    private func notFound(_ conn: NWConnection) {
        respond(conn, status: 404, type: "text/plain; charset=utf-8",
                body: Data("not found".utf8))
    }

    private func respond(_ conn: NWConnection, status: Int, type: String, body: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 500: reason = "Internal Server Error"
        case 502: reason = "Bad Gateway"
        default: reason = "Status"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: no-store\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static var htmlData: Data? {
        guard let url = Bundle.main.url(forResource: "biliSearch", withExtension: "html"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return data
    }
}
