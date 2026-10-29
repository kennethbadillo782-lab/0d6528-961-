import Foundation
import SwiftData

/// Enlace a un agente de compra (Hipobuy, Sugargoo, etc.). Solo se guardan enlaces reales que el usuario aporta.
struct AgentLink: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var url: String
}

@Model
final class Product {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String = ""
    var categoryKey: String = "otros"
    var subcategory: String = ""
    var productDescription: String = ""

    // Precios
    var priceCurrent: Double?
    var pricePrevious: Double?
    var currency: String = "CNY"
    var shippingEstimateUSD: Double?

    // Origen y compra
    var originalURL: String = ""
    /// Clave normalizada del enlace para detectar duplicados.
    var normalizedURL: String = ""
    var platform: String = ""
    var agentLinksData: Data?
    var sellerName: String = ""
    /// Solo se rellena si el usuario introduce una valoración real comprobable.
    var sellerRating: Double?
    var sellerRatingSource: String = ""

    // Características
    var color: String = ""
    var size: String = ""
    var material: String = ""
    var attributesData: Data?
    /// Lo que afirma el vendedor ("1:1", "Top Quality"...). No es una garantía.
    var declaredQuality: String = ""
    /// Lo que el propio usuario ha comprobado (por ejemplo con fotos QC).
    var verifiedQuality: String = ""
    var includedAccessories: String = ""

    // Organización
    var notes: String = ""
    var isFavorite: Bool = false
    var priorityRaw: Int = 0
    var statusRaw: String = PurchaseStatus.researching.rawValue
    /// Productos de ejemplo, separados de los datos reales del usuario.
    var isDemo: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ProductImage.product)
    var images: [ProductImage] = []

    var collections: [ProductCollection] = []

    init(name: String = "", categoryKey: String = "otros") {
        self.id = UUID()
        self.name = name
        self.categoryKey = categoryKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension Product {
    var status: PurchaseStatus {
        get { PurchaseStatus(rawValue: statusRaw) ?? .researching }
        set { statusRaw = newValue.rawValue }
    }

    var priority: PriorityLevel {
        get { PriorityLevel(rawValue: priorityRaw) ?? .unset }
        set { priorityRaw = newValue.rawValue }
    }

    var attributes: [String: String] {
        get {
            guard let attributesData,
                  let value = try? JSONDecoder().decode([String: String].self, from: attributesData) else { return [:] }
            return value
        }
        set { attributesData = try? JSONEncoder().encode(newValue) }
    }

    var agentLinks: [AgentLink] {
        get {
            guard let agentLinksData,
                  let value = try? JSONDecoder().decode([AgentLink].self, from: agentLinksData) else { return [] }
            return value
        }
        set { agentLinksData = try? JSONEncoder().encode(newValue) }
    }

    /// Equivalente a `nombreAgente` / `urlAgente` de la especificación.
    var primaryAgent: AgentLink? { agentLinks.first }

    var orderedImages: [ProductImage] { images.sorted { $0.order < $1.order } }

    var coverImage: ProductImage? {
        let ordered = orderedImages
        return ordered.first(where: { $0.kind == .official }) ?? ordered.first
    }

    var displayName: String {
        let trimmed = name.trimmed
        return trimmed.isEmpty ? "Producto sin nombre" : trimmed
    }

    /// Solo se calcula cuando existe un precio anterior real mayor que el actual.
    var discountPercent: Int? {
        guard let current = priceCurrent, let previous = pricePrevious,
              current > 0, previous > current else { return nil }
        let pct = Int(((previous - current) / previous * 100).rounded())
        return pct > 0 ? pct : nil
    }

    var sourceLabel: String {
        if let agent = primaryAgent?.name, !agent.isEmpty { return agent }
        if !platform.isEmpty { return platform }
        if let host = URL(string: originalURL)?.host { return host.replacingOccurrences(of: "www.", with: "") }
        return ""
    }

    func touch() { updatedAt = Date() }
}

enum PurchaseStatus: String, CaseIterable, Identifiable, Codable {
    case researching, favorite, pending, ready, purchased, discarded

    var id: String { rawValue }

    var label: String {
        switch self {
        case .researching: return "Por investigar"
        case .favorite: return "Favorito"
        case .pending: return "Pendiente de comprar"
        case .ready: return "Listo para comprar"
        case .purchased: return "Comprado"
        case .discarded: return "Descartado"
        }
    }

    var symbol: String {
        switch self {
        case .researching: return "magnifyingglass"
        case .favorite: return "star"
        case .pending: return "clock"
        case .ready: return "cart"
        case .purchased: return "checkmark.seal"
        case .discarded: return "xmark.circle"
        }
    }
}

enum PriorityLevel: Int, CaseIterable, Identifiable {
    case unset = 0, low, medium, high

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .unset: return "Sin prioridad"
        case .low: return "Baja"
        case .medium: return "Media"
        case .high: return "Alta"
        }
    }
}
