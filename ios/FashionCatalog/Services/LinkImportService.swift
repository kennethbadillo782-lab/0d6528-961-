import Foundation

/// Datos que se pudieron leer de una página. Todo es editable antes de guardar.
struct ImportedProductInfo {
    var sourceURL: URL
    var title: String = ""
    var description: String = ""
    var brand: String = ""
    var price: Double?
    var currency: String?
    var seller: String = ""
    var platform: String = ""
    var agentName: String?
    /// Enlace de la tienda original cuando el enlace pegado es de un agente y lo incluye explícitamente.
    var originalURL: URL?
    var imageURLs: [URL] = []

    var foundSomething: Bool { !title.isEmpty || price != nil || !imageURLs.isEmpty }
}

enum LinkImportError: LocalizedError {
    case invalidURL
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "El enlace no es válido."
        case .httpStatus(let code): return "La página respondió con el código \(code)."
        }
    }
}

enum LinkImportService {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static let knownAgents: [(name: String, host: String)] = [
        ("Hipobuy", "hipobuy"), ("Sugargoo", "sugargoo"), ("KakoBuy", "kakobuy"), ("CSSBuy", "cssbuy"),
        ("Mulebuy", "mulebuy"), ("AllChinaBuy", "allchinabuy"), ("Superbuy", "superbuy"), ("CNFans", "cnfans"),
        ("Oopbuy", "oopbuy"), ("LitBuy", "litbuy"), ("ACBuy", "acbuy"), ("Hoobuy", "hoobuy")
    ]

    static let agentNames: [String] = ["Hipobuy", "Sugargoo", "KakoBuy", "CSSBuy", "Mulebuy", "AllChinaBuy",
                                       "Superbuy", "CNFans", "Oopbuy", "LitBuy", "ACBuy", "Hoobuy"]

    private static let platforms: [(name: String, host: String)] = [
        ("Taobao", "taobao.com"), ("Tmall", "tmall.com"), ("Weidian", "weidian.com"), ("1688", "1688.com"),
        ("Yupoo", "yupoo.com"), ("AliExpress", "aliexpress"), ("Instagram", "instagram.com"),
        ("TikTok", "tiktok.com"), ("Goofish", "goofish.com")
    ]

    private static let chinesePlatforms: Set<String> = ["Taobao", "Tmall", "Weidian", "1688", "Yupoo", "Goofish"]

    // MARK: Normalización

    /// Acepta texto compartido desde apps (que a veces incluye texto además del enlace).
    static func cleanURL(_ raw: String) -> URL? {
        var s = raw.trimmed
        guard !s.isEmpty else { return nil }
        if let found = firstURL(in: s) { s = found }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              let host = url.host, host.contains("."), !host.contains(" ") else { return nil }
        return url
    }

    static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url?.absoluteString
    }

    static func looksLikeURL(_ text: String) -> Bool {
        let t = text.trimmed
        guard !t.isEmpty else { return false }
        if t.lowercased().hasPrefix("http") || t.lowercased().hasPrefix("www.") { return true }
        return firstURL(in: t) != nil && t.contains(".")
    }

    static func agentName(for url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        return knownAgents.first { host.contains($0.host) }?.name
    }

    static func platformName(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if let p = platforms.first(where: { host.contains($0.host) }) { return p.name }
        if let a = agentName(for: url) { return a }
        return stripHostPrefixes(host)
    }

    /// Algunos agentes incluyen el enlace original en un parámetro (`?url=...`). Solo se usa si existe.
    static func embeddedOriginalURL(_ url: URL) -> URL? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let keys = ["url", "link", "producturl", "goodsurl", "itemurl"]
        for item in items where keys.contains(item.name.lowercased()) {
            if let decoded = item.value,
               let inner = cleanURL(decoded), inner.host != url.host {
                return inner
            }
        }
        return nil
    }

    private static func stripHostPrefixes(_ host: String) -> String {
        var h = host.lowercased()
        for prefix in ["www.", "m.", "h5.", "mobile."] where h.hasPrefix(prefix) {
            h.removeFirst(prefix.count)
        }
        return h
    }

    /// Clave estable para detectar duplicados (mismo producto aunque cambien parámetros de seguimiento).
    static func duplicateKey(_ raw: String) -> String {
        guard let url = cleanURL(raw) else { return "" }
        let target = embeddedOriginalURL(url) ?? url
        guard let components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return "" }
        let host = stripHostPrefixes(components.host ?? "")
        let idKeys: Set<String> = ["id", "itemid", "item_id", "offerid", "productid", "goodsid"]
        var key = host + components.path
        if let id = components.queryItems?.first(where: { idKeys.contains($0.name.lowercased()) })?.value, !id.isEmpty {
            key += "?id=" + id
        }
        while key.hasSuffix("/") { key.removeLast() }
        return key.lowercased()
    }

    // MARK: Descarga y lectura

    private static func pageRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("es-ES,es;q=0.9,en;q=0.8,zh-CN;q=0.6", forHTTPHeaderField: "Accept-Language")
        return request
    }

    /// HTML de una página (primer 3 MB), o nil si no responde bien. Para buscar fotos en segundo plano.
    static func html(_ url: URL) async -> String? {
        guard let (data, response) = try? await NetworkSafety.data(for: pageRequest(url), maxBytes: 3_000_000),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func fetch(_ url: URL) async throws -> ImportedProductInfo {
        let (data, response) = try await NetworkSafety.data(for: pageRequest(url), maxBytes: 3_000_000)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LinkImportError.httpStatus(http.statusCode)
        }
        let finalURL = response.url ?? url
        // Solo se analiza el primer 1,5 MB: una página enorme o hecha a propósito no congela la app.
        let html = String(decoding: data.prefix(1_500_000), as: UTF8.self)
        var info = parse(html: html, baseURL: finalURL)

        info.sourceURL = url
        info.agentName = agentName(for: url) ?? agentName(for: finalURL)
        if info.agentName != nil {
            info.originalURL = embeddedOriginalURL(url) ?? embeddedOriginalURL(finalURL)
        }
        let reference = info.originalURL ?? finalURL
        info.platform = platformName(for: reference)
        if info.currency == nil,
           chinesePlatforms.contains(info.platform) || info.agentName != nil {
            info.currency = "CNY"
        }
        return info
    }

    static func downloadImages(_ urls: [URL], limit: Int = 8) async -> [Data] {
        let selected = Array(urls.prefix(limit))
        return await withTaskGroup(of: (Int, Data?).self) { group in
            for (index, url) in selected.enumerated() {
                group.addTask {
                    let data = await ImageService.download(url)
                    return (index, data)
                }
            }
            var results: [(Int, Data)] = []
            for await (index, data) in group {
                if let data { results.append((index, data)) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: Análisis de HTML (Open Graph, metadatos y JSON-LD)

    static func parse(html: String, baseURL: URL) -> ImportedProductInfo {
        var info = ImportedProductInfo(sourceURL: baseURL)
        let metas = metaTags(in: html)

        func meta(_ keys: [String]) -> String? {
            for key in keys {
                if let value = metas.first(where: { $0.key == key })?.value.trimmed, !value.isEmpty {
                    return value
                }
            }
            return nil
        }

        info.title = meta(["og:title", "twitter:title"]) ?? titleTag(in: html) ?? ""
        info.description = meta(["og:description", "description", "twitter:description"]) ?? ""
        info.brand = meta(["product:brand", "og:brand"]) ?? ""
        if let amount = meta(["product:price:amount", "og:price:amount"]) {
            info.price = parsePrice(amount)
        }
        info.currency = meta(["product:price:currency", "og:price:currency"])?.uppercased()

        let imageKeys: Set<String> = ["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"]
        var images: [URL] = metas
            .filter { imageKeys.contains($0.key) }
            .compactMap { resolve($0.value, base: baseURL) }

        for object in jsonLDObjects(in: html) {
            guard let product = findProduct(in: object) else { continue }
            if info.title.isEmpty, let name = product["name"] as? String { info.title = decodeEntities(name) }
            if info.description.isEmpty, let d = product["description"] as? String { info.description = decodeEntities(d) }
            if info.brand.isEmpty {
                if let b = product["brand"] as? String { info.brand = b }
                else if let b = product["brand"] as? [String: Any], let n = b["name"] as? String { info.brand = n }
            }
            images.append(contentsOf: imageURLs(from: product["image"], base: baseURL))
            let offers: [String: Any]? = (product["offers"] as? [String: Any])
                ?? (product["offers"] as? [[String: Any]])?.first
            if let offers {
                if info.price == nil {
                    info.price = number(offers["price"]) ?? number(offers["lowPrice"])
                }
                if info.currency == nil, let c = offers["priceCurrency"] as? String { info.currency = c.uppercased() }
                if info.seller.isEmpty, let s = offers["seller"] as? [String: Any], let n = s["name"] as? String {
                    info.seller = n
                }
            }
        }

        var seen = Set<String>()
        info.imageURLs = images.filter { seen.insert($0.absoluteString).inserted }
        info.title = info.title.trimmed
        if let c = info.currency, !Money.supported.contains(c) { info.currency = nil }
        return info
    }

    private static func metaTags(in html: String) -> [(key: String, value: String)] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<meta\\b[^>]*>", options: [.caseInsensitive]),
              let attrRegex = try? NSRegularExpression(
                pattern: "([a-zA-Z_:.-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", options: []) else { return [] }
        let ns = html as NSString
        var result: [(key: String, value: String)] = []
        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let tagNS = tag as NSString
            var attrs: [String: String] = [:]
            for a in attrRegex.matches(in: tag, range: NSRange(location: 0, length: tagNS.length)) {
                let name = tagNS.substring(with: a.range(at: 1)).lowercased()
                let valueRange = a.range(at: 2).location != NSNotFound ? a.range(at: 2) : a.range(at: 3)
                guard valueRange.location != NSNotFound else { continue }
                attrs[name] = decodeEntities(tagNS.substring(with: valueRange))
            }
            if let key = attrs["property"] ?? attrs["name"] ?? attrs["itemprop"], let content = attrs["content"] {
                result.append((key: key.lowercased(), value: content))
            }
        }
        return result
    }

    private static func titleTag(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>",
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let value = decodeEntities(ns.substring(with: m.range(at: 1))).trimmed
        return value.isEmpty ? nil : value
    }

    private static func jsonLDObjects(in html: String) -> [Any] {
        guard let regex = try? NSRegularExpression(
            pattern: "<script[^>]*application/ld\\+json[^>]*>(.*?)</script>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let json = ns.substring(with: m.range(at: 1)).trimmed
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
    }

    private static func findProduct(in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if let type = dict["@type"] as? String, type.lowercased().contains("product") { return dict }
            if let types = dict["@type"] as? [String], types.contains(where: { $0.lowercased().contains("product") }) {
                return dict
            }
            if let graph = dict["@graph"] { return findProduct(in: graph) }
            return nil
        }
        if let array = object as? [Any] {
            for item in array {
                if let found = findProduct(in: item) { return found }
            }
        }
        return nil
    }

    private static func imageURLs(from value: Any?, base: URL) -> [URL] {
        if let s = value as? String { return resolve(s, base: base).map { [$0] } ?? [] }
        if let array = value as? [Any] { return array.flatMap { imageURLs(from: $0, base: base) } }
        if let dict = value as? [String: Any] {
            return imageURLs(from: dict["url"] ?? dict["contentUrl"], base: base)
        }
        return []
    }

    private static func resolve(_ raw: String, base: URL) -> URL? {
        var s = raw.trimmed
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        guard let url = URL(string: s, relativeTo: base)?.absoluteURL,
              let safe = NetworkSafety.webURL(url.absoluteString), NetworkSafety.isPublic(safe) else { return nil }
        return safe
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return parsePrice(s) }
        return nil
    }

    static func parsePrice(_ raw: String) -> Double? {
        let first = raw.components(separatedBy: CharacterSet(charactersIn: "-~–")).first ?? raw
        var cleaned = first.filter { $0.isNumber || $0 == "." || $0 == "," }
        if cleaned.contains(".") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private static func decodeEntities(_ s: String) -> String {
        var r = s
        let map = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'",
                   "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#x2F;": "/", "&#47;": "/"]
        for (k, v) in map { r = r.replacingOccurrences(of: k, with: v) }
        return r
    }
}
