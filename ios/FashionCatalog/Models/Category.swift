import Foundation
import SwiftData

/// Grupos de acceso rápido de la pantalla Inicio.
enum QuickGroup: String, CaseIterable, Identifiable, Hashable, Codable {
    case all, clothing, shoes, bags, accessories

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Todo"
        case .clothing: return "Ropa"
        case .shoes: return "Zapatos"
        case .bags: return "Carteras"
        case .accessories: return "Accesorios"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .clothing: return "tshirt"
        case .shoes: return "shoe.2"
        case .bags: return "handbag"
        case .accessories: return "sparkles"
        }
    }
}

/// Categoría persistente: las del sistema se crean al primer arranque y el usuario puede añadir más.
@Model
final class CatalogCategory {
    var key: String = ""
    var name: String = ""
    var symbol: String = "square.grid.2x2"
    var groupRaw: String = QuickGroup.accessories.rawValue
    var subcategories: [String] = []
    var sortOrder: Int = 0
    var isBuiltIn: Bool = false
    var showOnHome: Bool = true

    init(key: String, name: String, symbol: String, group: QuickGroup, subcategories: [String],
         sortOrder: Int, isBuiltIn: Bool, showOnHome: Bool = true) {
        self.key = key
        self.name = name
        self.symbol = symbol
        self.groupRaw = group.rawValue
        self.subcategories = subcategories
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
        self.showOnHome = showOnHome
    }

    var group: QuickGroup {
        get { QuickGroup(rawValue: groupRaw) ?? .accessories }
        set { groupRaw = newValue.rawValue }
    }
}

struct BuiltInCategory {
    let key: String
    let name: String
    let symbol: String
    let group: QuickGroup
    let subcategories: [String]
}

enum CategoryCatalog {
    /// El orden define cómo aparecen en Inicio (las 7 primeras + "Más").
    static let builtIns: [BuiltInCategory] = [
        BuiltInCategory(key: "camisas", name: "Camisas", symbol: "tshirt", group: .clothing,
                        subcategories: ["T-Shirts", "Polo", "Manga larga", "Manga corta", "Botones", "Oversize"]),
        BuiltInCategory(key: "pantalones", name: "Pantalones", symbol: "figure.walk", group: .clothing,
                        subcategories: ["Jeans", "Cargo", "Shorts", "Joggers", "Chinos", "Formales", "Deportivos", "Técnicos"]),
        BuiltInCategory(key: "carteras", name: "Carteras", symbol: "handbag", group: .bags,
                        subcategories: ["Crossbody", "Backpack", "Billetera", "Tote", "Shoulder Bag", "Messenger", "Camera Bag"]),
        BuiltInCategory(key: "zapatos", name: "Zapatos", symbol: "shoe.2", group: .shoes,
                        subcategories: ["Sneakers", "Botas", "Sandalias", "Formales"]),
        BuiltInCategory(key: "pantallas", name: "Pantallas", symbol: "sparkle", group: .accessories,
                        subcategories: ["Redondas", "Cuadradas", "Halo", "Cluster", "Solitarias", "Iced Out"]),
        BuiltInCategory(key: "gorras", name: "Gorras", symbol: "baseball", group: .accessories,
                        subcategories: ["Baseball", "Trucker", "Fitted", "Snapback"]),
        BuiltInCategory(key: "relojes", name: "Relojes", symbol: "clock", group: .accessories,
                        subcategories: ["Deportivos", "Clásicos", "Digitales"]),
        BuiltInCategory(key: "abrigos", name: "Abrigos", symbol: "wind", group: .clothing,
                        subcategories: ["Hoodies", "Chaquetas", "Suéteres", "Rompevientos"]),
        BuiltInCategory(key: "joyeria", name: "Joyería", symbol: "sparkles", group: .accessories,
                        subcategories: ["Cadenas", "Collares", "Pulseras", "Anillos"]),
        BuiltInCategory(key: "gafas", name: "Gafas", symbol: "eyeglasses", group: .accessories,
                        subcategories: ["Sol", "Ópticas", "Deportivas"]),
        BuiltInCategory(key: "otros", name: "Otros", symbol: "square.grid.2x2", group: .accessories,
                        subcategories: ["Correas", "Accesorios", "Personalizados"])
    ]

    static func category(_ key: String, in categories: [CatalogCategory]) -> CatalogCategory? {
        categories.first { $0.key == key }
    }

    static func name(_ key: String, in categories: [CatalogCategory]) -> String {
        if let c = category(key, in: categories) { return c.name }
        return builtIns.first { $0.key == key }?.name ?? key.capitalized
    }

    static func symbol(_ key: String, in categories: [CatalogCategory]) -> String {
        if let c = category(key, in: categories) { return c.symbol }
        return builtIns.first { $0.key == key }?.symbol ?? "photo"
    }

    static func makeKey(from name: String, existing: [CatalogCategory]) -> String {
        let base = name.loose
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let root = base.isEmpty ? "categoria" : base
        var key = root
        var n = 2
        let keys = Set(existing.map(\.key))
        while keys.contains(key) {
            key = "\(root)-\(n)"
            n += 1
        }
        return key
    }

    /// Sugerencia de categoría a partir del título detectado (solo si el usuario no eligió una).
    static func guessKey(from text: String) -> String? {
        let t = text.loose
        let rules: [(String, [String])] = [
            ("pantallas", ["earring", "stud", "耳钉", "耳环", "arete", "pantalla"]),
            ("carteras", ["bag", "wallet", "backpack", "tote", "crossbody", "messenger", "包", "钱包", "cartera", "bolso", "mochila"]),
            ("zapatos", ["shoe", "sneaker", "boot", "sandal", "trainer", "鞋", "zapato", "tenis"]),
            ("gorras", ["cap", "hat", "beanie", "帽", "gorra"]),
            ("relojes", ["watch", "手表", "腕表", "reloj"]),
            ("gafas", ["sunglass", "glasses", "eyewear", "眼镜", "gafas", "lentes"]),
            ("joyeria", ["necklace", "chain", "bracelet", "ring", "pendant", "项链", "手链", "戒指", "cadena", "collar", "pulsera", "anillo"]),
            ("abrigos", ["hoodie", "jacket", "sweater", "coat", "windbreaker", "卫衣", "外套", "夹克", "sudadera", "chaqueta", "abrigo"]),
            ("pantalones", ["jeans", "pants", "trousers", "shorts", "cargo", "jogger", "裤", "pantalon"]),
            ("camisas", ["t-shirt", "tshirt", "tee", "shirt", "polo", "t恤", "衬衫", "camisa", "camiseta"])
        ]
        for (key, words) in rules where words.contains(where: { t.contains($0) }) {
            return key
        }
        return nil
    }
}
