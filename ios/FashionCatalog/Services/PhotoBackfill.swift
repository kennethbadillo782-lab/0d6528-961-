import Foundation
import SwiftData

/// Completa solo las fotos de productos guardados sin ninguna (por ejemplo desde ChatGPT, cuando la
/// tienda carga las fotos con JavaScript o bloquea la descarga). Lee la página del producto desde el
/// iPhone, guarda las fotos en el dispositivo y la sincronización normal las sube a la nube.
@MainActor
final class PhotoBackfill {
    static let shared = PhotoBackfill()
    /// Pocos productos por pasada para no gastar datos ni batería; el resto sigue en la siguiente.
    private let perRun = 3
    /// Un producto sin suerte se reintenta más tarde (la tienda puede estar caída o limitar).
    private let retryAfter: TimeInterval = 6 * 3600
    private let attemptsKey = "photo.backfill.attempts"
    private var busy = false

    func run(context: ModelContext) async {
        guard !busy, !CatalogSync.shared.isSyncing else { return }
        busy = true; defer { busy = false }
        guard let products = try? context.fetch(FetchDescriptor<Product>()) else { return }
        var attempts = UserDefaults.standard.dictionary(forKey: attemptsKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        let pending = products.filter { p in
            !p.isDemo && p.images.isEmpty && !Self.pages(for: p).isEmpty
                && now - (attempts[p.id.uuidString] ?? 0) > retryAfter
        }
        for product in pending.prefix(perRun) {
            attempts[product.id.uuidString] = now
            UserDefaults.standard.set(attempts, forKey: attemptsKey)
            let found = await Self.images(for: product)
            // Puede haber recibido fotos (sincronización o edición) mientras se descargaban.
            guard !found.isEmpty, product.images.isEmpty, product.modelContext != nil else { continue }
            for (index, item) in found.enumerated() {
                let image = ProductImage(data: item.data, remoteURL: item.url.absoluteString, kind: .official, order: index)
                image.product = product
                context.insert(image)
            }
            product.updatedAt = Date()
            try? context.save()
        }
    }

    /// Páginas candidatas: la tienda original y, si no hay, los enlaces de agente (con su tienda embebida si la traen).
    static func pages(for product: Product) -> [URL] {
        var urls: [URL] = []
        if let u = LinkImportService.cleanURL(product.originalURL) { urls.append(LinkImportService.embeddedOriginalURL(u) ?? u) }
        for link in product.agentLinks {
            guard let u = LinkImportService.cleanURL(link.url) else { continue }
            if let inner = LinkImportService.embeddedOriginalURL(u) { urls.append(inner) }
            urls.append(u)
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    static func images(for product: Product, limit: Int = 9) async -> [(url: URL, data: Data)] {
        for page in pages(for: product) {
            let candidates = await imageURLs(page: page)
            guard !candidates.isEmpty else { continue }
            var result: [(url: URL, data: Data)] = []
            for url in candidates.prefix(limit) {
                if let data = await ImageService.download(url, referer: referer(for: page, image: url)) { result.append((url, data)) }
            }
            if !result.isEmpty { return result }
        }
        return []
    }

    /// Enlaces de fotos de una página. Weidian y Yupoo se leen de su HTML; el resto, por Open Graph y JSON-LD.
    static func imageURLs(page: URL) async -> [URL] {
        let host = (page.host ?? "").lowercased()
        var target = page
        // Weidian: la página fija del artículo trae las fotos de su CDN aunque luego las muestre con JavaScript.
        if host == "weidian.com" || host.hasSuffix(".weidian.com"),
           let item = URLComponents(url: page, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name.lowercased() == "itemid" })?.value,
           item.range(of: "^\\d{4,20}$", options: .regularExpression) != nil,
           let fixed = URL(string: "https://weidian.com/item.html?itemID=\(item)") {
            target = fixed
        }
        guard let html = await LinkImportService.html(target) else { return [] }
        var found = weidianImages(in: html) + yupooImages(in: html)
        if found.isEmpty { found = LinkImportService.parse(html: html, baseURL: target).imageURLs }
        var seen = Set<String>()
        return found.filter { NetworkSafety.isPublic($0) && seen.insert($0.absoluteString).inserted }
    }

    static func weidianImages(in html: String) -> [URL] {
        matches(#"si\.geilicdn\.com\\?/(weidian[A-Za-z0-9_-]{8,120}\.(?:jpg|jpeg|png|webp)(?:\.webp)?)"#, in: html)
            .compactMap { URL(string: "https://si.geilicdn.com/\($0)?w=750&h=750&cp=1") }
    }

    /// Álbumes de Yupoo: fotos grandes de photo.yupoo.com (solo se sirven con la página como Referer).
    static func yupooImages(in html: String) -> [URL] {
        matches(#"photo\.yupoo\.com\\?/([A-Za-z0-9_.-]{1,64}\\?/[A-Za-z0-9]{4,64})\\?/(?:big|medium|small|square)\.(?:jpg|jpeg|png|webp)"#, in: html)
            .compactMap { URL(string: "https://photo.yupoo.com/\($0.replacingOccurrences(of: "\\", with: ""))/big.jpg") }
    }

    static func referer(for page: URL, image: URL) -> String? {
        (image.host ?? "").hasSuffix("yupoo.com") ? "https://\(page.host ?? "x.yupoo.com")/" : nil
    }

    private static func matches(_ pattern: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }
}
