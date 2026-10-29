import SwiftUI

// MARK: - Esquema de filtros y atributos por categoría

enum SizeMode {
    case letters, lettersAndNumbers, numbers, noSizes
}

enum AttributeKind: Equatable {
    case options
    case text
    case number(String)
    case millimeters
}

struct AttributeDef: Identifiable {
    let key: String
    let label: String
    var options: [String] = []
    var kind: AttributeKind = .options
    var filterable: Bool = true
    var id: String { key }
}

/// Tarjeta visual de estilo (por ejemplo "Largos", "Cargo"). Puede filtrar por subcategoría o por atributo.
struct StyleCard: Identifiable, Hashable {
    enum Match: Hashable {
        case subcategory(String)
        case attribute(String, String)
    }

    let title: String
    let match: Match
    var symbol: String = "photo"
    var id: String { title }

    func matches(_ product: Product) -> Bool {
        switch match {
        case .subcategory(let sub):
            return product.subcategory.equalsLoose(sub)
        case .attribute(let key, let value):
            return (product.attributes[key] ?? "").equalsLoose(value)
        }
    }
}

struct InlineOption: Hashable {
    let label: String
    let attributeKey: String
}

struct ColorSwatch: Identifiable, Hashable {
    let name: String
    let hex: UInt32
    var id: String { name }
    var color: Color { Color(hex: hex) }

    static let clothing: [ColorSwatch] = [
        ColorSwatch(name: "Negro", hex: 0x0E0F11),
        ColorSwatch(name: "Gris", hex: 0x4A4F57),
        ColorSwatch(name: "Blanco", hex: 0xF2F2F2),
        ColorSwatch(name: "Beige", hex: 0xE9D8BE),
        ColorSwatch(name: "Marrón", hex: 0x7A5230),
        ColorSwatch(name: "Verde", hex: 0x2F7A57),
        ColorSwatch(name: "Azul", hex: 0x2C6BED),
        ColorSwatch(name: "Rojo", hex: 0xD7385E),
        ColorSwatch(name: "Rosa", hex: 0xF2A6C2),
        ColorSwatch(name: "Morado", hex: 0x7B4FD1),
        ColorSwatch(name: "Amarillo", hex: 0xF2C94C),
        ColorSwatch(name: "Naranja", hex: 0xF2994A)
    ]

    static let jewelry: [ColorSwatch] = [
        ColorSwatch(name: "Plateado", hex: 0xD9DCE1),
        ColorSwatch(name: "Dorado", hex: 0xE5B84B),
        ColorSwatch(name: "Rosa", hex: 0xF2A6C2),
        ColorSwatch(name: "Azul", hex: 0x1F4FE0),
        ColorSwatch(name: "Verde", hex: 0x1F9D63),
        ColorSwatch(name: "Negro", hex: 0x0E0F11)
    ]

    static func swatch(named name: String) -> ColorSwatch? {
        (clothing + jewelry).first { $0.name.equalsLoose(name) }
    }
}

struct CategorySchema {
    var allLabel = "Todos"
    /// Fila visual bajo la búsqueda (pantalla de la categoría).
    var styleCards: [StyleCard] = []
    /// Tarjetas "Tipo" del panel de filtros avanzados.
    var filterTypeCards: [StyleCard] = []
    var attributes: [AttributeDef] = []
    var sizeMode: SizeMode = .letters
    var numericSizes: [String] = []
    var palette: [ColorSwatch] = ColorSwatch.clothing
    var inlineMillimeters = false
    var inlineColors = false
    var inlineMaterials: [InlineOption] = []
    var usesMaterialField = true

    static let letterSizes = ["XS", "S", "M", "L", "XL", "XXL"]
    static let millimeterBuckets = ["3 mm", "5 mm", "6 mm", "8 mm", "10 mm+"]

    func attribute(_ key: String) -> AttributeDef? { attributes.first { $0.key == key } }

    var sizeOptions: [String] {
        switch sizeMode {
        case .letters: return Self.letterSizes
        case .lettersAndNumbers: return Self.letterSizes + numericSizes
        case .numbers: return numericSizes
        case .noSizes: return []
        }
    }

    /// Permite guardar medidas intermedias (6.5, 7, 9 mm) y agruparlas en los botones de tamaño.
    static func bucketMatches(_ bucket: String, value: Double) -> Bool {
        switch bucket {
        case "3 mm": return value < 4.5
        case "5 mm": return value >= 4.5 && value < 5.5
        case "6 mm": return value >= 5.5 && value < 7
        case "8 mm": return value >= 7 && value < 9.5
        case "10 mm+": return value >= 9.5
        default: return false
        }
    }

    static func forCategory(_ key: String) -> CategorySchema {
        var s = CategorySchema()
        switch key {
        case "camisas":
            s.allLabel = "Todas"
            s.attributes = [
                AttributeDef(key: "corte", label: "Corte", options: ["Regular", "Slim", "Oversize", "Boxy"]),
                AttributeDef(key: "cuello", label: "Cuello", options: ["Redondo", "V", "Polo", "Camisa"])
            ]

        case "pantalones":
            s.allLabel = "Todos"
            s.styleCards = [
                StyleCard(title: "Largos", match: .attribute("largo", "Largo"), symbol: "figure.walk"),
                StyleCard(title: "Cortos", match: .attribute("largo", "Corto"), symbol: "figure.run"),
                StyleCard(title: "Cargo", match: .subcategory("Cargo"), symbol: "shippingbox"),
                StyleCard(title: "Jeans", match: .subcategory("Jeans"), symbol: "figure.stand")
            ]
            s.filterTypeCards = s.styleCards + [
                StyleCard(title: "Jogger", match: .subcategory("Joggers"), symbol: "figure.run"),
                StyleCard(title: "Rectos", match: .attribute("corte", "Straight"), symbol: "line.3.horizontal"),
                StyleCard(title: "Anchos", match: .attribute("corte", "Wide-leg"), symbol: "arrow.left.and.right"),
                StyleCard(title: "Técnicos", match: .subcategory("Técnicos"), symbol: "gearshape")
            ]
            s.attributes = [
                AttributeDef(key: "largo", label: "Largo", options: ["Largo", "Corto", "Capri", "Bermuda"]),
                AttributeDef(key: "corte", label: "Corte",
                             options: ["Skinny", "Slim", "Regular", "Straight", "Relaxed", "Baggy", "Wide-leg"]),
                AttributeDef(key: "cintura", label: "Cintura", kind: .text)
            ]
            s.sizeMode = .lettersAndNumbers
            s.numericSizes = ["28", "29", "30", "31", "32", "33", "34", "36", "38"]

        case "abrigos":
            s.allLabel = "Todos"
            s.attributes = [
                AttributeDef(key: "corte", label: "Corte", options: ["Regular", "Oversize", "Cropped", "Slim"]),
                AttributeDef(key: "capucha", label: "Capucha", options: ["Con capucha", "Sin capucha"])
            ]

        case "zapatos":
            s.allLabel = "Todos"
            s.sizeMode = .numbers
            s.numericSizes = ["6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10", "10.5", "11", "12", "13"]
            s.attributes = [
                AttributeDef(key: "cana", label: "Caña", options: ["Baja", "Media", "Alta"]),
                AttributeDef(key: "sistemaTalla", label: "Sistema de talla", options: ["US", "EU", "UK", "CM"])
            ]

        case "carteras":
            s.allLabel = "Todas"
            s.sizeMode = .noSizes
            s.attributes = [
                AttributeDef(key: "tamano", label: "Tamaño", options: ["Mini", "Pequeña", "Mediana", "Grande"]),
                AttributeDef(key: "compartimentos", label: "Compartimentos", options: ["1", "2", "3", "4+"]),
                AttributeDef(key: "ancho", label: "Ancho", kind: .number("cm"), filterable: false),
                AttributeDef(key: "alto", label: "Alto", kind: .number("cm"), filterable: false),
                AttributeDef(key: "profundidad", label: "Profundidad", kind: .number("cm"), filterable: false)
            ]

        case "pantallas":
            s.allLabel = "Todas"
            s.sizeMode = .noSizes
            s.palette = ColorSwatch.jewelry
            s.inlineMillimeters = true
            s.inlineColors = true
            s.usesMaterialField = false
            s.inlineMaterials = [
                InlineOption(label: "Moissanita", attributeKey: "piedra"),
                InlineOption(label: "Plata 925", attributeKey: "metal"),
                InlineOption(label: "Oro", attributeKey: "metal")
            ]
            s.attributes = [
                AttributeDef(key: "tamanoMM", label: "Tamaño / diámetro", options: millimeterBuckets, kind: .millimeters),
                AttributeDef(key: "piedra", label: "Piedra",
                             options: ["Moissanita", "Zirconia cúbica", "Diamante", "Otra", "Sin piedra"]),
                AttributeDef(key: "metal", label: "Metal de la montura",
                             options: ["Plata 925", "Oro", "Oro 14k", "Oro 18k", "Acero inoxidable", "Otro"]),
                AttributeDef(key: "cierre", label: "Tipo de cierre",
                             options: ["Rosca", "Presión", "Mariposa", "Huggie", "Otro"]),
                AttributeDef(key: "piedras", label: "Piedras", options: ["Piedra central", "Múltiples piedras"]),
                AttributeDef(key: "forma", label: "Forma",
                             options: ["Redonda", "Cuadrada", "Princesa", "Corazón", "Otra"])
            ]

        case "joyeria":
            s.allLabel = "Todo"
            s.sizeMode = .noSizes
            s.palette = ColorSwatch.jewelry
            s.usesMaterialField = false
            s.attributes = [
                AttributeDef(key: "metal", label: "Metal",
                             options: ["Plata 925", "Oro", "Oro 14k", "Oro 18k", "Acero inoxidable", "Otro"]),
                AttributeDef(key: "piedra", label: "Piedra",
                             options: ["Moissanita", "Zirconia cúbica", "Diamante", "Otra", "Sin piedra"]),
                AttributeDef(key: "largoCM", label: "Largo", kind: .number("cm"), filterable: false),
                AttributeDef(key: "grosorMM", label: "Grosor", kind: .number("mm"), filterable: false)
            ]

        case "gorras":
            s.allLabel = "Todas"
            s.sizeMode = .noSizes
            s.attributes = [
                AttributeDef(key: "ajuste", label: "Ajuste", options: ["Ajustable", "Talla fija"])
            ]

        case "relojes":
            s.allLabel = "Todos"
            s.sizeMode = .noSizes
            s.palette = ColorSwatch.jewelry
            s.attributes = [
                AttributeDef(key: "movimiento", label: "Movimiento", options: ["Automático", "Cuarzo", "Digital"]),
                AttributeDef(key: "diametroMM", label: "Diámetro", kind: .number("mm"), filterable: false)
            ]

        case "gafas":
            s.allLabel = "Todas"
            s.sizeMode = .noSizes

        default:
            s.allLabel = "Todos"
        }
        return s
    }
}

// MARK: - Estado de filtros

struct FilterState: Equatable {
    var subcategory: String?
    var styleCards: Set<String> = []
    var brands: Set<String> = []
    var colors: Set<String> = []
    var sizes: Set<String> = []
    var materials: Set<String> = []
    var sellers: Set<String> = []
    var agents: Set<String> = []
    var statuses: Set<String> = []
    var attributes: [String: Set<String>] = [:]
    var priceRange: ClosedRange<Double>?

    /// Número de filtros avanzados activos (sin contar la subcategoría rápida).
    var activeCount: Int {
        var n = styleCards.count + brands.count + colors.count + sizes.count + materials.count
            + sellers.count + agents.count + statuses.count
        n += attributes.values.reduce(0) { $0 + $1.count }
        if priceRange != nil { n += 1 }
        return n
    }

    var isEmpty: Bool { activeCount == 0 && subcategory == nil }

    static func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    mutating func toggleAttribute(_ key: String, _ value: String) {
        var current = attributes[key] ?? []
        Self.toggle(value, in: &current)
        attributes[key] = current.isEmpty ? nil : current
    }

    func hasAttribute(_ key: String, _ value: String) -> Bool {
        attributes[key]?.contains(value) ?? false
    }

    /// Todos los filtros se combinan con Y entre secciones y con O dentro de cada sección.
    func matches(_ p: Product, schema: CategorySchema) -> Bool {
        if let subcategory, !p.subcategory.equalsLoose(subcategory) { return false }

        if !styleCards.isEmpty {
            let cards = (schema.filterTypeCards + schema.styleCards).filter { styleCards.contains($0.title) }
            if !cards.isEmpty && !cards.contains(where: { $0.matches(p) }) { return false }
        }
        if !brands.isEmpty && !brands.contains(where: { $0.equalsLoose(p.brand) }) { return false }
        if !colors.isEmpty && !colors.contains(where: { p.color.containsLoose($0) }) { return false }
        if !sizes.isEmpty {
            let tokens = p.size.sizeTokens
            if !sizes.contains(where: { s in tokens.contains { $0.equalsLoose(s) } }) { return false }
        }
        if !materials.isEmpty && !materials.contains(where: { p.material.containsLoose($0) }) { return false }
        if !sellers.isEmpty && !sellers.contains(where: { $0.equalsLoose(p.sellerName) }) { return false }
        if !agents.isEmpty {
            let names = p.agentLinks.map(\.name)
            if !agents.contains(where: { a in names.contains { $0.equalsLoose(a) } }) { return false }
        }
        if !statuses.isEmpty && !statuses.contains(p.statusRaw) { return false }

        let attrs = p.attributes
        for (key, values) in attributes where !values.isEmpty {
            let raw = attrs[key] ?? ""
            if schema.attribute(key)?.kind == .millimeters {
                guard let v = raw.parsedNumber,
                      values.contains(where: { CategorySchema.bucketMatches($0, value: v) }) else { return false }
            } else if !values.contains(where: { $0.equalsLoose(raw) }) {
                return false
            }
        }

        if let range = priceRange {
            guard let amount = Money.comparableAmount(p), range.contains(amount) else { return false }
        }
        return true
    }
}

// MARK: - Búsqueda y orden

enum SearchMatcher {
    static func matches(_ p: Product, query: String) -> Bool {
        let q = query.loose
        guard !q.isEmpty else { return true }
        let haystack = [
            p.name, p.brand, p.categoryKey, p.subcategory, p.sellerName, p.platform, p.material,
            p.color, p.notes, p.originalURL, p.productDescription, p.agentLinks.map(\.name).joined(separator: " ")
        ].joined(separator: " ").loose
        return q.split(separator: " ").allSatisfy { haystack.contains($0) }
    }
}

enum ProductSort: String, CaseIterable, Identifiable {
    case recent, oldest, priceLow, priceHigh, priority, pending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Más recientes"
        case .oldest: return "Más antiguos"
        case .priceLow: return "Precio menor"
        case .priceHigh: return "Precio mayor"
        case .priority: return "Prioridad"
        case .pending: return "Pendientes de comprar"
        }
    }

    func apply(_ products: [Product]) -> [Product] {
        switch self {
        case .recent:
            return products.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return products.sorted { $0.createdAt < $1.createdAt }
        case .priceLow, .priceHigh:
            let ascending = self == .priceLow
            return products.sorted { a, b in
                switch (Money.comparableAmount(a), Money.comparableAmount(b)) {
                case let (x?, y?): return ascending ? x < y : x > y
                case (.some, .none): return true
                case (.none, .some): return false
                default: return a.createdAt > b.createdAt
                }
            }
        case .priority:
            return products.sorted {
                $0.priorityRaw != $1.priorityRaw ? $0.priorityRaw > $1.priorityRaw : $0.createdAt > $1.createdAt
            }
        case .pending:
            func rank(_ s: PurchaseStatus) -> Int {
                switch s {
                case .ready: return 0
                case .pending: return 1
                case .favorite: return 2
                case .researching: return 3
                case .purchased: return 4
                case .discarded: return 5
                }
            }
            return products.sorted {
                rank($0.status) != rank($1.status) ? rank($0.status) < rank($1.status) : $0.createdAt > $1.createdAt
            }
        }
    }
}

// MARK: - Utilidades de texto

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Texto normalizado para comparar sin mayúsculas ni acentos.
    var loose: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func equalsLoose(_ other: String) -> Bool { loose == other.loose }

    func containsLoose(_ other: String) -> Bool {
        let o = other.loose
        return !o.isEmpty && loose.contains(o)
    }

    var parsedNumber: Double? {
        let cleaned = trimmed.replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }

    var sizeTokens: [String] {
        components(separatedBy: CharacterSet(charactersIn: ",/;| "))
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
    }
}
