import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Copia de seguridad en JSON (incluye fotos). Los productos de ejemplo no se exportan.
/// El mismo formato servirá como base para la futura API de sincronización.
struct BackupFile: Codable {
    var version: Int = 1
    var exportedAt: Date
    var products: [ProductDTO]
    var collections: [CollectionDTO]
    var categories: [CategoryDTO]
}

struct ImageDTO: Codable {
    var id: UUID
    var data: Data?
    var remoteURL: String
    var kind: String
    var order: Int
}

struct ProductDTO: Codable {
    var id: UUID
    var name, brand, categoryKey, subcategory, productDescription: String
    var priceCurrent, pricePrevious, shippingEstimateUSD: Double?
    var currency: String
    var originalURL, normalizedURL, platform: String
    var agentLinks: [AgentLink]
    var sellerName: String
    var sellerRating: Double?
    var sellerRatingSource: String
    var color, size, material: String
    var attributes: [String: String]
    var declaredQuality, verifiedQuality, includedAccessories, notes: String
    var isFavorite: Bool
    var priority: Int
    var status: String
    var createdAt, updatedAt: Date
    var images: [ImageDTO]
    var collectionIDs: [UUID]
}

struct CollectionDTO: Codable {
    var id: UUID
    var name: String
    var coverData: Data?
    var sortOrder: Int
    var createdAt: Date
}

struct CategoryDTO: Codable {
    var key, name, symbol, group: String
    var subcategories: [String]
    var sortOrder: Int
    var isBuiltIn, showOnHome: Bool
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    @MainActor
    static func makeBackup(context: ModelContext) throws -> Data {
        let products = try context.fetch(FetchDescriptor<Product>()).filter { !$0.isDemo }
        let collections = try context.fetch(FetchDescriptor<ProductCollection>())
        let categories = try context.fetch(FetchDescriptor<CatalogCategory>())

        let file = BackupFile(
            exportedAt: Date(),
            products: products.map { p in
                ProductDTO(
                    id: p.id, name: p.name, brand: p.brand, categoryKey: p.categoryKey, subcategory: p.subcategory,
                    productDescription: p.productDescription, priceCurrent: p.priceCurrent,
                    pricePrevious: p.pricePrevious, shippingEstimateUSD: p.shippingEstimateUSD,
                    currency: p.currency, originalURL: p.originalURL, normalizedURL: p.normalizedURL,
                    platform: p.platform, agentLinks: p.agentLinks, sellerName: p.sellerName,
                    sellerRating: p.sellerRating, sellerRatingSource: p.sellerRatingSource, color: p.color,
                    size: p.size, material: p.material, attributes: p.attributes,
                    declaredQuality: p.declaredQuality, verifiedQuality: p.verifiedQuality,
                    includedAccessories: p.includedAccessories, notes: p.notes, isFavorite: p.isFavorite,
                    priority: p.priorityRaw, status: p.statusRaw, createdAt: p.createdAt, updatedAt: p.updatedAt,
                    images: p.orderedImages.map {
                        ImageDTO(id: $0.id, data: $0.data, remoteURL: $0.remoteURL, kind: $0.kindRaw, order: $0.order)
                    },
                    collectionIDs: p.collections.map(\.id)
                )
            },
            collections: collections.map {
                CollectionDTO(id: $0.id, name: $0.name, coverData: $0.coverData,
                              sortOrder: $0.sortOrder, createdAt: $0.createdAt)
            },
            categories: categories.map {
                CategoryDTO(key: $0.key, name: $0.name, symbol: $0.symbol, group: $0.groupRaw,
                            subcategories: $0.subcategories, sortOrder: $0.sortOrder,
                            isBuiltIn: $0.isBuiltIn, showOnHome: $0.showOnHome)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    /// Importa sin duplicar: los productos y colecciones que ya existen (mismo id) se omiten.
    @MainActor
    static func restore(_ data: Data, context: ModelContext) throws -> (added: Int, skipped: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Una copia manipulada no puede llenar el teléfono ni colar enlaces peligrosos.
        guard data.count <= 300_000_000 else { throw NetworkSafety.SafetyError.tooLarge }
        let file = try decoder.decode(BackupFile.self, from: data)
        func clip(_ s: String, _ max: Int) -> String { String(s.prefix(max)) }
        func safeLink(_ s: String) -> String { NetworkSafety.webURL(s)?.absoluteString ?? "" }

        let existingCategories = try context.fetch(FetchDescriptor<CatalogCategory>())
        let categoryKeys = Set(existingCategories.map(\.key))
        var seenKeys = categoryKeys
        for c in file.categories.prefix(200) where !seenKeys.contains(c.key) {
            let key = clip(c.key.lowercased(), 40)
            guard !key.isEmpty, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            context.insert(CatalogCategory(
                key: key, name: clip(c.name, 60), symbol: clip(c.symbol, 60), group: QuickGroup(rawValue: c.group) ?? .accessories,
                subcategories: c.subcategories.prefix(40).map { clip($0, 60) }, sortOrder: c.sortOrder, isBuiltIn: c.isBuiltIn,
                showOnHome: c.showOnHome
            ))
        }

        var collectionsByID: [UUID: ProductCollection] = [:]
        for c in try context.fetch(FetchDescriptor<ProductCollection>()) { collectionsByID[c.id] = c }
        for dto in file.collections.prefix(500) where collectionsByID[dto.id] == nil {
            let c = ProductCollection(name: clip(dto.name, 80), sortOrder: dto.sortOrder)
            c.id = dto.id
            c.coverData = (dto.coverData?.count ?? 0) <= 5_000_000 ? dto.coverData : nil
            c.createdAt = dto.createdAt
            context.insert(c)
            collectionsByID[dto.id] = c
        }

        var existingIDs = Set(try context.fetch(FetchDescriptor<Product>()).map(\.id))
        var added = 0, skipped = 0
        for dto in file.products.prefix(20_000) {
            if existingIDs.contains(dto.id) { skipped += 1; continue }
            existingIDs.insert(dto.id) // ids repetidos dentro del mismo archivo cuentan como duplicados
            let p = Product(name: clip(dto.name, 300), categoryKey: clip(dto.categoryKey, 40))
            context.insert(p)
            p.id = dto.id
            p.brand = clip(dto.brand, 120)
            p.subcategory = clip(dto.subcategory, 60)
            p.productDescription = clip(dto.productDescription, 5000)
            p.priceCurrent = dto.priceCurrent
            p.pricePrevious = dto.pricePrevious
            p.shippingEstimateUSD = dto.shippingEstimateUSD
            p.currency = clip(dto.currency, 3)
            p.originalURL = safeLink(dto.originalURL)
            p.normalizedURL = clip(dto.normalizedURL, 2048)
            p.platform = clip(dto.platform, 60)
            p.agentLinks = dto.agentLinks.prefix(10).compactMap { link in
                let url = safeLink(link.url)
                return url.isEmpty ? nil : AgentLink(name: clip(link.name, 40), url: url)
            }
            p.sellerName = clip(dto.sellerName, 120)
            p.sellerRating = dto.sellerRating.flatMap { (0.0...5.0).contains($0) ? $0 : nil }
            p.sellerRatingSource = clip(dto.sellerRatingSource, 120)
            p.color = clip(dto.color, 60)
            p.size = clip(dto.size, 60)
            p.material = clip(dto.material, 120)
            p.attributes = Dictionary(dto.attributes.prefix(30).map { (clip($0.key, 40), clip($0.value, 120)) }, uniquingKeysWith: { a, _ in a })
            p.declaredQuality = clip(dto.declaredQuality, 120)
            p.verifiedQuality = clip(dto.verifiedQuality, 120)
            p.includedAccessories = clip(dto.includedAccessories, 200)
            p.notes = clip(dto.notes, 5000)
            p.isFavorite = dto.isFavorite
            p.priorityRaw = dto.priority
            p.statusRaw = dto.status
            p.createdAt = dto.createdAt
            p.updatedAt = dto.updatedAt
            var images: [ProductImage] = []
            for i in dto.images.prefix(30) where (i.data?.count ?? 0) <= 15_000_000 {
                let image = ProductImage(data: i.data, remoteURL: NetworkSafety.webURL(i.remoteURL)?.absoluteString ?? "",
                                         kind: ImageKind(rawValue: i.kind) ?? .manual, order: i.order)
                image.id = i.id
                context.insert(image)
                images.append(image)
            }
            p.images = images
            p.collections = dto.collectionIDs.compactMap { collectionsByID[$0] }
            added += 1
        }
        try context.save()
        return (added, skipped)
    }
}
