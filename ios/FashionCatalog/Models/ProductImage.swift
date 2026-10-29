import Foundation
import SwiftData

enum ImageKind: String, CaseIterable, Identifiable, Codable {
    case official, qc, buyer, worn, manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .official: return "Anuncio"
        case .qc: return "QC"
        case .buyer: return "Comprador"
        case .worn: return "Puesto"
        case .manual: return "Manual"
        }
    }

    var longLabel: String {
        switch self {
        case .official: return "Foto oficial del anuncio"
        case .qc: return "Foto QC (inspección)"
        case .buyer: return "Foto de comprador"
        case .worn: return "Producto puesto"
        case .manual: return "Subida manualmente"
        }
    }
}

@Model
final class ProductImage {
    var id: UUID = UUID()
    /// La imagen se guarda en el dispositivo para que no dependa de que la tienda mantenga el enlace.
    @Attribute(.externalStorage) var data: Data?
    var cloudPath: String = ""
    var cloudUploadedHash: String = ""
    var remoteURL: String = ""
    var kindRaw: String = ImageKind.official.rawValue
    var order: Int = 0
    var createdAt: Date = Date()
    var product: Product?

    init(data: Data?, remoteURL: String = "", kind: ImageKind = .official, order: Int = 0) {
        self.id = UUID()
        self.data = data
        self.remoteURL = remoteURL
        self.kindRaw = kind.rawValue
        self.order = order
        self.createdAt = Date()
    }

    var kind: ImageKind {
        get { ImageKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }
}
