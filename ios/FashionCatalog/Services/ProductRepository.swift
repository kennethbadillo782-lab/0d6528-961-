import Foundation
import SwiftData

// MARK: - Datos iniciales

enum SeedService {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<CatalogCategory>())) ?? []
        let keys = Set(existing.map(\.key))
        for (index, b) in CategoryCatalog.builtIns.enumerated() where !keys.contains(b.key) {
            context.insert(CatalogCategory(
                key: b.key, name: b.name, symbol: b.symbol, group: b.group,
                subcategories: b.subcategories, sortOrder: index, isBuiltIn: true
            ))
        }

        let flag = "seededDefaultCollection"
        if !UserDefaults.standard.bool(forKey: flag) {
            let count = (try? context.fetchCount(FetchDescriptor<ProductCollection>())) ?? 0
            if count == 0 {
                context.insert(ProductCollection(name: "Lista principal", sortOrder: 0))
            }
            UserDefaults.standard.set(true, forKey: flag)
        }
        try? context.save()
    }
}

// MARK: - Borrador editable (crear y editar productos)

struct DraftImage: Identifiable, Equatable {
    let id: UUID
    var data: Data?
    var remoteURL: String = ""
    var kind: ImageKind
    var existing: ProductImage?

    init(data: Data?, remoteURL: String = "", kind: ImageKind) {
        self.id = UUID()
        self.data = data
        self.remoteURL = remoteURL
        self.kind = kind
        self.existing = nil
    }

    init(existing: ProductImage) {
        self.id = existing.id
        self.data = nil
        self.remoteURL = existing.remoteURL
        self.kind = existing.kind
        self.existing = existing
    }

    static func == (lhs: DraftImage, rhs: DraftImage) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }
}

struct ProductDraft {
    var name = ""
    var brand = ""
    var categoryKey = ""
    var subcategory = ""
    var productDescription = ""
    var priceText = ""
    var previousPriceText = ""
    var currency = "CNY"
    var shippingText = ""
    var originalURL = ""
    var platform = ""
    var agentLinks: [AgentLink] = []
    var sellerName = ""
    var sellerRatingText = ""
    var sellerRatingSource = ""
    var color = ""
    var size = ""
    var material = ""
    var declaredQuality = ""
    var verifiedQuality = ""
    var includedAccessories = ""
    var notes = ""
    var isFavorite = false
    var priority: PriorityLevel = .unset
    var status: PurchaseStatus = .researching
    var attributes: [String: String] = [:]
    var images: [DraftImage] = []
    var collectionIDs: Set<PersistentIdentifier> = []

    init() {}

    init(product p: Product) {
        name = p.name
        brand = p.brand
        categoryKey = p.categoryKey
        subcategory = p.subcategory
        productDescription = p.productDescription
        priceText = p.priceCurrent.map { Self.text($0) } ?? ""
        previousPriceText = p.pricePrevious.map { Self.text($0) } ?? ""
        currency = p.currency
        shippingText = p.shippingEstimateUSD.map { Self.text($0) } ?? ""
        originalURL = p.originalURL
        platform = p.platform
        agentLinks = p.agentLinks
        sellerName = p.sellerName
        sellerRatingText = p.sellerRating.map { Self.text($0) } ?? ""
        sellerRatingSource = p.sellerRatingSource
        color = p.color
        size = p.size
        material = p.material
        declaredQuality = p.declaredQuality
        verifiedQuality = p.verifiedQuality
        includedAccessories = p.includedAccessories
        notes = p.notes
        isFavorite = p.isFavorite
        priority = p.priority
        status = p.status
        attributes = p.attributes
        images = p.orderedImages.map { DraftImage(existing: $0) }
        collectionIDs = Set(p.collections.map(\.persistentModelID))
    }

    private static func text(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(v)
    }

    var hasContent: Bool {
        !name.trimmed.isEmpty || !images.isEmpty || !originalURL.trimmed.isEmpty || !agentLinks.isEmpty
    }

    /// Enlace usado para detectar duplicados.
    var duplicateKey: String {
        let link = originalURL.trimmed.isEmpty ? (agentLinks.first?.url ?? "") : originalURL
        return LinkImportService.duplicateKey(link)
    }

    /// Rellena solo los campos vacíos, para no pisar lo que el usuario ya escribió.
    mutating func apply(_ info: ImportedProductInfo, images downloaded: [Data]) {
        if name.trimmed.isEmpty { name = info.title }
        if brand.trimmed.isEmpty { brand = info.brand }
        if productDescription.trimmed.isEmpty { productDescription = info.description }
        if priceText.trimmed.isEmpty, let price = info.price { priceText = Self.text(price) }
        if let c = info.currency { currency = c }
        if sellerName.trimmed.isEmpty { sellerName = info.seller }
        if platform.trimmed.isEmpty { platform = info.platform }

        if let agent = info.agentName {
            let url = info.sourceURL.absoluteString
            if !agentLinks.contains(where: { $0.url == url }) {
                agentLinks.insert(AgentLink(name: agent, url: url), at: 0)
            }
            if let original = info.originalURL { originalURL = original.absoluteString }
            else if originalURL == url { originalURL = "" }
        } else {
            originalURL = info.sourceURL.absoluteString
        }

        if categoryKey.isEmpty, let guess = CategoryCatalog.guessKey(from: info.title) {
            categoryKey = guess
        }
        let existingCount = images.count
        for data in downloaded {
            images.append(DraftImage(data: data, kind: .official))
        }
        if downloaded.isEmpty && existingCount == 0 {
            // Si no se pudieron descargar, se conservan las URLs para intentarlo al mostrar.
            for url in info.imageURLs.prefix(8) {
                images.append(DraftImage(data: nil, remoteURL: url.absoluteString, kind: .official))
            }
        }
    }

    @MainActor
    func write(to product: Product, context: ModelContext, collections: [ProductCollection]) {
        product.name = name.trimmed
        product.brand = brand.trimmed
        product.categoryKey = categoryKey.isEmpty ? "otros" : categoryKey
        product.subcategory = subcategory.trimmed
        product.productDescription = productDescription.trimmed
        product.priceCurrent = priceText.parsedNumber
        product.pricePrevious = previousPriceText.parsedNumber
        product.currency = currency
        product.shippingEstimateUSD = shippingText.parsedNumber
        product.originalURL = originalURL.trimmed
        product.platform = platform.trimmed
        product.agentLinks = agentLinks
            .map { AgentLink(id: $0.id, name: $0.name.trimmed, url: $0.url.trimmed) }
            .filter { !$0.url.isEmpty }
        product.normalizedURL = duplicateKey
        product.sellerName = sellerName.trimmed
        product.sellerRating = sellerRatingText.parsedNumber
        product.sellerRatingSource = sellerRatingSource.trimmed
        product.color = color.trimmed
        product.size = size.trimmed
        product.material = material.trimmed
        product.declaredQuality = declaredQuality.trimmed
        product.verifiedQuality = verifiedQuality.trimmed
        product.includedAccessories = includedAccessories.trimmed
        product.notes = notes.trimmed
        product.isFavorite = isFavorite
        product.priority = priority
        product.status = status
        product.attributes = attributes
            .mapValues { $0.trimmed }
            .filter { !$0.value.isEmpty }

        // Imágenes: conservar, reordenar, borrar y añadir.
        let keptIDs = Set(images.compactMap { $0.existing?.id })
        for image in product.images where !keptIDs.contains(image.id) {
            context.delete(image)
        }
        var newList: [ProductImage] = []
        for (index, draft) in images.enumerated() {
            if let existing = draft.existing {
                existing.order = index
                existing.kind = draft.kind
                newList.append(existing)
            } else if draft.data != nil || !draft.remoteURL.isEmpty {
                let image = ProductImage(data: draft.data, remoteURL: draft.remoteURL, kind: draft.kind, order: index)
                context.insert(image)
                newList.append(image)
            }
        }
        product.images = newList

        product.collections = collections.filter { collectionIDs.contains($0.persistentModelID) }
        product.touch()
    }
}

// MARK: - Datos de ejemplo (claramente separados de los datos reales)

enum DemoData {
    @MainActor
    static func insert(into context: ModelContext) {
        let items: [(String, String, String, Double, [String: String], String, PurchaseStatus)] = [
            ("Camiseta gráfica blanca", "camisas", "T-Shirts", 189, [:], "Blanco", .researching),
            ("Camiseta estampada negra", "camisas", "T-Shirts", 168, [:], "Negro", .favorite),
            ("Polo negro de punto", "camisas", "Polo", 155, [:], "Negro", .pending),
            ("Jeans rotos azules", "pantalones", "Jeans", 238, ["largo": "Largo", "corte": "Straight"], "Azul", .researching),
            ("Cargo verde oliva", "pantalones", "Cargo", 168, ["largo": "Largo", "corte": "Relaxed"], "Verde", .ready),
            ("Shorts grises de algodón", "pantalones", "Shorts", 128, ["largo": "Corto"], "Gris", .researching),
            ("Crossbody negra", "carteras", "Crossbody", 268, ["tamano": "Pequeña", "compartimentos": "2"], "Negro", .favorite),
            ("Messenger con monograma", "carteras", "Messenger", 398, ["tamano": "Mediana"], "Negro", .pending),
            ("Pantallas redondas 6 mm", "pantallas", "Redondas", 128,
             ["tamanoMM": "6", "piedra": "Moissanita", "metal": "Plata 925"], "Plateado", .researching),
            ("Pantallas halo 8 mm", "pantallas", "Halo", 165,
             ["tamanoMM": "8", "piedra": "Moissanita", "metal": "Plata 925"], "Plateado", .ready),
            ("Sneakers blancos", "zapatos", "Sneakers", 320, [:], "Blanco", .researching),
            ("Gorra snapback negra", "gorras", "Snapback", 98, [:], "Negro", .researching),
            ("Reloj clásico plateado", "relojes", "Clásicos", 450, ["movimiento": "Automático"], "Plateado", .researching)
        ]
        for (i, item) in items.enumerated() {
            let p = Product(name: item.0, categoryKey: item.1)
            context.insert(p)
            p.subcategory = item.2
            p.priceCurrent = item.3
            p.currency = "CNY"
            p.attributes = item.4
            p.color = item.5
            p.status = item.6
            p.isFavorite = item.6 == .favorite
            p.isDemo = true
            p.notes = "Producto de ejemplo para probar el diseño. Puedes borrarlo desde Cuenta."
            p.createdAt = Date().addingTimeInterval(TimeInterval(-i * 3600))
        }
        try? context.save()
    }

    @MainActor
    static func remove(from context: ModelContext) {
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.isDemo == true })
        for p in (try? context.fetch(descriptor)) ?? [] {
            context.delete(p)
        }
        try? context.save()
    }

    @MainActor
    static func count(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.isDemo == true })
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
