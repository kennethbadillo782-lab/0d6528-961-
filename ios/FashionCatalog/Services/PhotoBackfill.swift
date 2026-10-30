import Foundation
import SwiftData

/// Busca las fotos del anuncio de productos que no tienen ninguna (las de ChatGPT tienen prioridad: solo
/// actúa si no llegó ninguna foto del anuncio). Lee la página de la tienda desde el iPhone, guarda las fotos
/// en el dispositivo y la sincronización normal las sube a la nube. Lo que no se consigue queda pendiente
/// con su motivo y se reintenta más tarde.
@MainActor
final class PhotoBackfill: ObservableObject {
    static let shared = PhotoBackfill()

    /// Modelo candidato que el usuario puede elegir cuando la app no puede decidir sola.
    struct Choice: Codable, Equatable, Identifiable {
        var name: String
        var image: URL
        var price: Double?
        var id: URL { image }
    }

    struct State: Codable, Equatable {
        var attempts = 0
        var nextTry: Date = .distantPast
        var reason = ""
        var working = false
        var choices: [Choice] = []
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

    /// El usuario eligió su modelo entre los candidatos: se guarda esa foto como foto del anuncio.
    func choose(_ choice: Choice, for product: Product, context: ModelContext) async {
        states[product.id, default: State()].working = true
        let data = await ImageService.download(choice.image)
        guard let data, product.modelContext != nil else {
            states[product.id, default: State()].working = false
            states[product.id]?.reason = "No se pudo descargar esa foto. Inténtalo de nuevo."
            persist(); return
        }
        save([(choice.image, data)], to: product, context: context)
        states[product.id] = nil
        persist()
    }

    private func save(_ photos: [(url: URL, data: Data)], to product: Product, context: ModelContext) {
        let start = (product.images.map(\.order).max() ?? -1) + 1
        for (i, photo) in photos.enumerated() {
            let image = ProductImage(data: photo.data, remoteURL: photo.url.absoluteString, kind: .official, order: start + i)
            image.product = product
            context.insert(image)
        }
        product.updatedAt = Date()
        try? context.save()
    }

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
            save(photos, to: product, context: context)
            states[product.id] = nil
        } else if case .found = outcome {
            states[product.id] = nil
        } else {
            if case .pending(let reason, let choices) = outcome { state.reason = reason; state.choices = choices }
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

    enum Outcome { case found([(url: URL, data: Data)]), pending(String, [Choice]) }

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
        guard !pages.isEmpty else { return .pending("El producto no tiene enlace de la tienda. Añádelo al editarlo.", []) }
        var reasons: [String] = []
        var choices: [Choice] = []
        for page in pages {
            let (candidates, reason, options) = await candidates(page: page, productName: product.name, price: product.priceCurrent,
                                                                  listingHints: listingHints(of: product))
            if let reason { reasons.append(reason) }
            if choices.isEmpty { choices = options }
            guard !candidates.isEmpty else { continue }
            // Todas a la vez: antes, una tras otra, tardaba mucho en "Buscando fotos…".
            let result: [(url: URL, data: Data)] = await withTaskGroup(of: (Int, URL, Data?).self) { group in
                for (i, url) in candidates.prefix(9).enumerated() {
                    let ref = referer(page: page, image: url)
                    group.addTask { (i, url, await ImageService.download(url, referer: ref)) }
                }
                var got: [(Int, URL, Data)] = []
                for await (i, url, data) in group { if let data { got.append((i, url, data)) } }
                return got.sorted { $0.0 < $1.0 }.map { (url: $0.1, data: $0.2) }
            }
            if !result.isEmpty { return .found(result) }
            reasons.append("La tienda no dejó descargar las fotos.")
        }
        return .pending(reasons.first ?? "La página no muestra fotos sin iniciar sesión o cargó otra cosa.", choices)
    }

    /// Fotos candidatas del producto exacto en una página y, si no hay, el motivo.
    /// Modelo exacto del anuncio que guardó ChatGPT (attributes.modelo_anuncio), si lo hay.
    /// Pistas del modelo exacto que guardó ChatGPT en attributes, sea cual sea el nombre del campo
    /// (modelo_anuncio, variante_exacta_anuncio, sku…): primero la variante, luego el modelo.
    static func listingHints(of product: Product) -> [String] {
        let attrs = product.attributes.sorted { $0.key < $1.key }
        func values(_ words: [String]) -> [String] {
            attrs.filter { a in words.contains { a.key.lowercased().contains($0) } }.map(\.value)
        }
        var seen = Set<String>()
        return (values(["variant", "sku"]) + values(["modelo", "model"]))
            .flatMap(PhotoSources.hints(from:)).filter { seen.insert($0).inserted }
    }

    static func candidates(page: URL, productName: String, price: Double?, listingHints: [String] = []) async -> ([URL], String?, [Choice]) {
        let store = PhotoSources.store(of: page)
        switch store {
        case .weidian:
            guard let item = URLComponents(url: page, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name.lowercased() == "itemid" })?.value,
                  let fixed = PhotoSources.itemURL(platform: "weidian", id: item) else { break }
            guard let html = await LinkImportService.html(fixed) else { return ([], "Weidian no respondió.", []) }
            // El análisis (JSON de cientos de combinaciones) fuera del hilo principal: la app no se traba.
            let extraction = await Task.detached(priority: .utility) {
                PhotoSources.weidianPhotos(html: html, productName: productName, price: price, listingHints: listingHints)
            }.value
            switch extraction {
            case .photos(let urls): return (urls, nil, [])
            case .ambiguous(let why, let options):
                return ([], why, options.map { Choice(name: $0.name, image: $0.image, price: $0.price) })
            case .nothing: break
            }
        case .yupoo:
            if let html = await LinkImportService.html(page) {
                let photos = PhotoSources.yupooPhotos(html: html)
                if !photos.isEmpty { return (photos, nil, []) }
            }
        case .other:
            // Agentes sin la tienda en el enlace: sus páginas son aplicaciones web sin fotos útiles.
            if LinkImportService.agentName(for: page) != nil { return ([], nil, []) }
            if let html = await LinkImportService.html(page) {
                let photos = LinkImportService.parse(html: html, baseURL: page).imageURLs
                if !photos.isEmpty { return (photos, nil, []) }
            }
        case .taobao, .tmall, .ali1688:
            break
        }
        // Páginas que cargan las fotos con JavaScript (Taobao, 1688 y muchas otras): navegador invisible.
        let rendered = await PageRenderer.render(page)
        if !rendered.images.isEmpty { return (rendered.images, nil, []) }
        if rendered.needsLogin { return ([], "La tienda pide iniciar sesión. Usa «Abrir página», inicia sesión y pulsa «Reintentar».", []) }
        if rendered.blocked { return ([], "La tienda pidió una verificación anti-robots. Ábrela una vez desde «Abrir página».", []) }
        return ([], nil, [])
    }

    static func referer(page: URL, image: URL) -> String? {
        (image.host ?? "").hasSuffix("yupoo.com") ? "https://\(page.host ?? "x.yupoo.com")/" : nil
    }
}
