import Foundation
import SwiftData

/// Se llama ProductCollection para no chocar con el protocolo `Collection` de Swift.
@Model
final class ProductCollection {
    var id: UUID = UUID()
    var name: String = ""
    /// Portada elegida manualmente. Si es nil, se usa automáticamente el último producto.
    @Attribute(.externalStorage) var coverData: Data?
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(inverse: \Product.collections)
    var products: [Product] = []

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var automaticCover: ProductImage? {
        products
            .sorted { $0.createdAt > $1.createdAt }
            .lazy
            .compactMap { $0.coverImage }
            .first
    }
}
