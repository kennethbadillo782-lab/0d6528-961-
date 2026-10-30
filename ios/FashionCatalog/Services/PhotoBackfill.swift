import Foundation
import SwiftData

/// Busca las fotos del anuncio de productos que no tienen ninguna (las de ChatGPT tienen prioridad: solo
/// actúa si no llegó ninguna foto del anuncio). Lee la página de la tienda desde el iPhone, guarda las fotos
/// en el dispositivo y la sincronización normal las sube a la nube. Lo que no se consigue queda pendiente
/// con su motivo y se reintenta más tarde.
@MainActor
final class PhotoBackfill: ObservableObject {
    static let shared = PhotoBackfill()

    struct State: Codable, Equatable {
        var attempts = 0
        var nextTry: Date = .distantPast
        var reason = ""
        var working = false
    }

    @Published private(set) var states: [UUID: State] = [:]
    /// Pocos productos por pasada para no gastar datos ni batería; el resto sigue en la siguiente.
    private let perRun = 2
    /// 10 min, 1 h, 6 h y después una vez al día.
    private let backoff: [TimeInterval] = [600, 3600, 6 * 3600, 24 * 3600]
    private let storeKey = "photo.backfill.state"
    private var busy = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([UUID: State].self, from: data) {
            states = saved.mapValues { var s = $0; s.working = false; return s }
        }
    }

    static func needsPhotos(_ p: Product) -> Bool {
        !p.isDemo && !p.images.contains { $0.kind == .official }
    }

    func state(for product: Product) -> State? { states[product.id] }

    /// Reintento inmediato desde la ficha (por ejemplo tras iniciar sesión en la tienda).
    func retryNow(_ product: Product, context: ModelContext) async {
        states[product.id, default: State()].nextTry = .distantPast
        await attempt(product, context: context)
    }

    func run(context: ModelContext) async {
        guard !busy, !CatalogSync.shared.isSyncing,
              let products = try? context.fetch(FetchDescriptor<Product>()) else { return }
        let now = Date()
        let due = products.filter { Self.needsPhotos($0) && (states[$0.id]?.nextTry ?? .distantPast) <= now }
        for product in due.prefix(perRun) { await attempt(product, context: context) }
        // Olvidar productos que ya tienen fotos o se borraron.
        let alive = Set(products.filter(Self.needsPhotos).map(\.id))
        if states.keys.contains(where: { !alive.contains($0) }) { states = states.filter { alive.contains($0.key) }; persist() }
    }

    private func attempt(_ product: Product, context: ModelContext) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        var state = states[product.id] ?? State()
        state.working = true; states[product.id] = state

        let outcome = await Self.find(for: product)
        state.working = false
        // Puede haber recibido fotos del anuncio (sincronización o edición) mientras se descargaban.
        if case .found(let photos) = outcome, Self.needsPhotos(product), product.modelContext != nil {
            let start = (product.images.map(\.order).max() ?? -1) + 1
            for (i, photo) in photos.enumerated() {
                let image = ProductImage(data: photo.data, remoteURL: photo.url.absoluteString, kind: .official, order: start + i)
                image.product = product
                context.insert(image)
            }
            product.updatedAt = Date()
            try? context.save()
            states[product.id] = nil
        } else if case .found = outcome {
            states[product.id] = nil
        } else {
            if case .pending(let reason) = outcome { state.reason = reason }
            state.nextTry = Date().addingTimeInterval(backoff[min(state.attempts, backoff.count - 1)])
            state.attempts += 1
            states[product.id] = state
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(states) { UserDefaults.standard.set(data, forKey: storeKey) }
    }

    // MARK: Búsqueda

    enum Outcome { case found([(url: URL, data: Data)]), pending(String) }

    /// Páginas a consultar, en orden: la tienda original y después los agentes (convertidos a su tienda).
    static func pages(for product: Product) -> [URL] {
        var urls: [URL] = []
        let links = [product.originalURL] + product.agentLinks.map(\.url)
        for raw in links {
            guard let u = LinkImportService.cleanURL(raw) else { continue }
            if let store = PhotoSources.storeURL(fromAgent: u) { urls.append(store) }
            urls.append(u)
        }
        return PhotoSources.unique(urls)
    }

    static func find(for product: Product) async -> Outcome {
        let pages = pages(for: product)
        guard !pages.isEmpty else { return .pending("El producto no tiene enlace de la tienda. Añádelo al editarlo.") }
        var reasons: [String] = []
        for page in pages {
            let (candidates, reason) = await candidates(page: page, productName: product.name, price: product.priceCurrent)
            if let reason { reasons.append(reason) }
            guard !candidates.isEmpty else { continue }
            var result: [(url: URL, data: Data)] = []
            for url in candidates.prefix(9) {
                if let data = await ImageService.download(url, referer: referer(page: page, image: url)) { result.append((url, data)) }
            }
            if !result.isEmpty { return .found(result) }
            reasons.append("La tienda no dejó descargar las fotos.")
        }
        return .pending(reasons.first ?? "La página no muestra fotos sin iniciar sesión o cargó otra cosa.")
    }

    /// Fotos candidatas del producto exacto en una página y, si no hay, el motivo.
    static func candidates(page: URL, productName: String, price: Double?) async -> ([URL], String?) {
        let store = PhotoSources.store(of: page)
        switch store {
        case .weidian:
            guard let item = URLComponents(url: page, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name.lowercased() == "itemid" })?.value,
                  let fixed = PhotoSources.itemURL(platform: "weidian", id: item) else { break }
            guard let html = await LinkImportService.html(fixed) else { return ([], "Weidian no respondió.") }
            switch PhotoSources.weidianPhotos(html: html, productName: productName, price: price) {
            case .photos(let urls): return (urls, nil)
            case .ambiguous(let why): return ([], why)
            case .nothing: break
            }
        case .yupoo:
            if let html = await LinkImportService.html(page) {
                let photos = PhotoSources.yupooPhotos(html: html)
                if !photos.isEmpty { return (photos, nil) }
            }
        case .other:
            // Agentes sin la tienda en el enlace: sus páginas son aplicaciones web sin fotos útiles.
            if LinkImportService.agentName(for: page) != nil { return ([], nil) }
            if let html = await LinkImportService.html(page) {
                let photos = LinkImportService.parse(html: html, baseURL: page).imageURLs
                if !photos.isEmpty { return (photos, nil) }
            }
        case .taobao, .tmall, .ali1688:
            break
        }
        // Páginas que cargan las fotos con JavaScript (Taobao, 1688 y muchas otras): navegador invisible.
        let rendered = await PageRenderer.render(page)
        if !rendered.images.isEmpty { return (rendered.images, nil) }
        if rendered.needsLogin { return ([], "La tienda pide iniciar sesión. Usa «Abrir página», inicia sesión y pulsa «Reintentar».") }
        if rendered.blocked { return ([], "La tienda pidió una verificación anti-robots. Ábrela una vez desde «Abrir página».") }
        return ([], nil)
    }

    static func referer(page: URL, image: URL) -> String? {
        (image.host ?? "").hasSuffix("yupoo.com") ? "https://\(page.host ?? "x.yupoo.com")/" : nil
    }
}
