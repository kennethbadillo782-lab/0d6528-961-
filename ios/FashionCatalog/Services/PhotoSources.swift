import Foundation

/// Reglas por tienda para encontrar las fotos del anuncio de un producto concreto. Funciones puras
/// (sin red) para poder probarlas con páginas guardadas.
enum PhotoSources {
    enum Store: String { case weidian, taobao, tmall, ali1688 = "1688", yupoo, other }

    /// Resultado de leer una página: fotos del producto exacto, o el motivo por el que no se pudo.
    enum Extraction: Equatable {
        case photos([URL])
        case ambiguous(String)
        case nothing
    }

    static func store(of url: URL) -> Store {
        let host = (url.host ?? "").lowercased()
        if host == "weidian.com" || host.hasSuffix(".weidian.com") { return .weidian }
        if host.hasSuffix("taobao.com") { return .taobao }
        if host.hasSuffix("tmall.com") { return .tmall }
        if host.hasSuffix("1688.com") { return .ali1688 }
        if host.hasSuffix("yupoo.com") { return .yupoo }
        return .other
    }

    // MARK: Agentes → tienda original

    /// Enlace de la tienda original a partir del de un agente (Hipobuy, KakoBuy, CSSBuy, Sugargoo, CNFans, Mulebuy…).
    /// Solo usa lo que el enlace trae: un parámetro con la URL o la plataforma con el número del artículo.
    static func storeURL(fromAgent url: URL) -> URL? {
        if let inner = LinkImportService.embeddedOriginalURL(url) { return inner }
        // Sugargoo y otros guardan los parámetros en el fragmento (#/…?productLink=…).
        if let fragment = url.fragment, let q = fragment.firstIndex(of: "?") {
            let items = URLComponents(string: "x://x" + String(fragment[q...]))?.queryItems ?? []
            for item in items where ["productlink", "url", "link", "itemurl", "goodsurl"].contains(item.name.lowercased()) {
                if let v = item.value, let inner = LinkImportService.cleanURL(v), inner.host != url.host { return inner }
            }
        }
        let path = url.path.lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ names: [String]) -> String? {
            items.first { names.contains($0.name.lowercased()) }?.value
        }
        // Hipobuy y similares: /product/weidian/7815143816
        if let m = firstMatch(#"/(?:product|item|goods)s?/(weidian|taobao|tmall|1688|ali_1688|alibaba)/(\d{5,20})"#, in: path) {
            return itemURL(platform: m[0], id: m[1])
        }
        // CSSBuy: item-micro-<id> (Weidian), item-1688-<id>, item-<id> (Taobao)
        if (url.host ?? "").contains("cssbuy") {
            if let m = firstMatch(#"item-micro-(\d{5,20})"#, in: path) { return itemURL(platform: "weidian", id: m[0]) }
            if let m = firstMatch(#"item-1688-(\d{5,20})"#, in: path) { return itemURL(platform: "1688", id: m[0]) }
            if let m = firstMatch(#"item-(\d{5,20})"#, in: path) { return itemURL(platform: "taobao", id: m[0]) }
        }
        // CNFans, Mulebuy, Oopbuy…: ?shop_type=weidian&id=… o ?platform=TAOBAO&id=…
        if let platform = param(["shop_type", "shoptype", "platform", "channel", "source"]),
           let id = param(["id", "itemid", "item_id", "goodsid", "offerid"]),
           let built = itemURL(platform: platform.lowercased(), id: id) { return built }
        return nil
    }

    static func itemURL(platform: String, id: String) -> URL? {
        guard id.range(of: #"^\d{5,20}$"#, options: .regularExpression) != nil else { return nil }
        switch platform {
        case "weidian", "wd", "micro": return URL(string: "https://weidian.com/item.html?itemID=\(id)")
        case "taobao", "tb", "tmall": return URL(string: "https://item.taobao.com/item.htm?id=\(id)")
        case "1688", "ali_1688", "alibaba": return URL(string: "https://detail.1688.com/offer/\(id).html")
        default: return nil
        }
    }

    // MARK: Weidian

    struct Variant: Equatable { let name: String; let image: URL }

    /// Galería y modelos con foto de los datos que Weidian inserta en la página del artículo.
    static func weidianData(html: String) -> (gallery: [URL], variants: [Variant])? {
        guard let raw = firstMatch(#"id="__rocker-render-inject__" data-obj="([^"]*)""#, in: html)?.first,
              let data = decodeEntities(raw).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = (root["result"] as? [String: Any])?["default_model"] as? [String: Any] else { return nil }
        let info = model["item_info"] as? [String: Any] ?? [:]
        var gallery = (info["imgs"] as? [String] ?? []).compactMap(cdnURL)
        if gallery.isEmpty, let head = info["item_head"] as? String, let u = cdnURL(head) { gallery = [u] }
        var variants: [Variant] = []
        let attrs = (model["sku_properties"] as? [String: Any])?["attr_list"] as? [[String: Any]] ?? []
        for attr in attrs {
            for value in attr["attr_values"] as? [[String: Any]] ?? [] {
                if let name = value["attr_value"] as? String, let img = value["img"] as? String, let u = cdnURL(img) {
                    variants.append(Variant(name: name, image: u))
                }
            }
        }
        return (gallery, variants)
    }

    /// Fotos de Weidian del producto exacto. Si el anuncio agrupa varios modelos (cada uno con su foto),
    /// solo se acepta la foto del modelo cuyo nombre coincide con el del producto; si no hay coincidencia
    /// clara, no se elige ninguna para no mostrar otro modelo.
    static func weidianPhotos(html: String, productName: String) -> Extraction {
        guard let data = weidianData(html: html) else { return .nothing }
        let distinctImages = Set(data.variants.map(\.image.absoluteString))
        if distinctImages.count >= 2 {
            guard let match = bestVariant(for: productName, in: data.variants) else {
                return .ambiguous("El anuncio tiene varios modelos y ninguno coincide claramente con el nombre del producto.")
            }
            return .photos([match.image])
        }
        let all = data.gallery + data.variants.map(\.image)
        return all.isEmpty ? .nothing : .photos(unique(all))
    }

    /// Palabras que no distinguen un modelo de otro dentro del mismo anuncio.
    private static let genericWords: Set<String> = [
        "air", "jordan", "aj", "aj1", "aj4", "aj11", "nike", "retro", "og", "gx", "batch", "version", "ver", "new",
        "the", "de", "del", "la", "el", "con", "and", "with", "high", "low", "mid", "sneaker", "sneakers", "shoe", "shoes",
        "zapatillas", "tenis", "best", "selling", "arrive", "arrival", "upgraded", "leather", "women", "womens", "men", "mens",
    ]

    static func tokens(_ text: String) -> [String] {
        let lowered = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        return lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !genericWords.contains($0) && !($0.count == 1 && $0.allSatisfy(\.isNumber)) }
    }

    static func bestVariant(for productName: String, in variants: [Variant]) -> Variant? {
        // Lo que va tras "—" suele ser el lote o el vendedor ("GX Batch"), no el modelo.
        let base = productName.components(separatedBy: CharacterSet(charactersIn: "—–|")).first ?? productName
        let all = tokens(base)
        let years = all.filter { $0.count == 4 && $0.hasPrefix("20") && $0.allSatisfy(\.isNumber) }
        let words = Set(all.filter { !years.contains($0) })
        guard !words.isEmpty else { return nil }
        let scored = variants.map { v -> (Variant, Double) in
            let vt = Set(tokens(v.name))
            var score = Double(words.intersection(vt).count) / Double(words.count)
            if !years.isEmpty, years.contains(where: vt.contains) { score += 0.1 }
            return (v, score)
        }.sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 >= 0.99 else { return nil }
        // Empate con otro modelo de foto distinta: no se puede saber cuál es.
        if scored.dropFirst().contains(where: { $0.1 >= best.1 && $0.0.image != best.0.image }) { return nil }
        return best.0
    }

    // MARK: Yupoo

    /// Fotos grandes de un álbum de Yupoo (se descargan con la página del álbum como Referer).
    static func yupooPhotos(html: String) -> [URL] {
        unique(allMatches(#"photo\.yupoo\.com\\?/([A-Za-z0-9_.-]{1,64}\\?/[A-Za-z0-9]{4,64})\\?/(?:big|medium|small|square)\.(?:jpg|jpeg|png|webp)"#, in: html)
            .compactMap { URL(string: "https://photo.yupoo.com/\($0.replacingOccurrences(of: "\\", with: ""))/big.jpg") })
    }

    // MARK: Utilidades

    private static func cdnURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("//") { s = "https:" + s }
        guard var c = URLComponents(string: s), c.scheme == "https" || c.scheme == "http",
              let host = c.host?.lowercased(), host.hasSuffix("geilicdn.com") else { return nil }
        c.scheme = "https"
        c.query = "w=1080&h=1080&cp=1"
        return c.url
    }

    static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    static func decodeEntities(_ s: String) -> String {
        var r = s
        for (k, v) in [("&#34;", "\""), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            r = r.replacingOccurrences(of: k, with: v)
        }
        return r
    }

    /// Grupos capturados de la primera coincidencia.
    static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: text).map { String(text[$0]) } }
    }

    static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }
}
