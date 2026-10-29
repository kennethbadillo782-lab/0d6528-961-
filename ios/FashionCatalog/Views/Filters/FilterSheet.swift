import SwiftUI

/// Panel de filtros avanzados. Cada categoría muestra solo las opciones que tienen sentido.
struct FilterSheet: View {
    let title: String
    let schema: CategorySchema
    let products: [Product]
    var subcategories: [String] = []
    @Binding var state: FilterState

    @Environment(\.dismiss) var dismiss
    @State var draft = FilterState()
    @State var price: ClosedRange<Double> = 0...1
    @State var didLoad = false

    // MARK: Valores derivados de los productos reales

    private func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map(\.trimmed).filter { !$0.isEmpty && seen.insert($0.loose).inserted }.sorted()
    }

    private var brands: [String] { distinct(products.map(\.brand)) }
    private var materials: [String] { distinct(products.map(\.material)) }
    private var sellers: [String] { distinct(products.map(\.sellerName)) }
    private var agents: [String] { distinct(products.flatMap { $0.agentLinks.map(\.name) }) }

    private var sizes: [String] {
        var options = schema.sizeOptions
        let present = distinct(products.flatMap { $0.size.sizeTokens })
        for s in present where !options.contains(where: { $0.equalsLoose(s) }) { options.append(s) }
        return options
    }

    private var priceBounds: ClosedRange<Double>? {
        let values = products.compactMap { Money.comparableAmount($0) }
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let lower = lo.rounded(.down)
        let upper = max(hi.rounded(.up), lower + 1)
        return lower...upper
    }

    private var priceUnit: String {
        let priced = products.filter { $0.priceCurrent != nil }
        let allConvertible = priced.allSatisfy { Money.toUSD($0.priceCurrent ?? 0, code: $0.currency) != nil }
        if allConvertible { return "$" }
        let currencies = Set(priced.map(\.currency))
        return currencies.count == 1 ? Money.symbol(for: currencies.first ?? "") : ""
    }

    private func attributeOptions(_ def: AttributeDef) -> [String] {
        if def.kind == .text {
            return distinct(products.compactMap { $0.attributes[def.key] })
        }
        var options = def.options
        if def.kind == .options {
            let present = distinct(products.compactMap { $0.attributes[def.key] })
            for v in present where !options.contains(where: { $0.equalsLoose(v) }) { options.append(v) }
        }
        return options
    }

    // MARK: Vista

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !schema.filterTypeCards.isEmpty {
                        typeCardsSection
                    } else if !subcategories.isEmpty {
                        section("Tipo") {
                            chips(subcategories, isOn: { draft.subcategory == $0 }) { value in
                                draft.subcategory = draft.subcategory == value ? nil : value
                            }
                        }
                    }

                    if !brands.isEmpty {
                        section("Marca") { brandTiles }
                    }

                    if schema.sizeMode != .noSizes && !sizes.isEmpty {
                        section("Talla") {
                            chips(sizes, isOn: { draft.sizes.contains($0) }) { FilterState.toggle($0, in: &draft.sizes) }
                        }
                    }

                    section("Color") { colorRow }

                    ForEach(schema.attributes.filter(\.filterable)) { def in
                        let options = attributeOptions(def)
                        if !options.isEmpty {
                            section(def.label) {
                                chips(options, isOn: { draft.hasAttribute(def.key, $0) }) {
                                    draft.toggleAttribute(def.key, $0)
                                }
                            }
                        }
                    }

                    if schema.usesMaterialField && !materials.isEmpty {
                        section("Material") {
                            chips(materials, isOn: { draft.materials.contains($0) }) {
                                FilterState.toggle($0, in: &draft.materials)
                            }
                        }
                    }

                    if !sellers.isEmpty {
                        section("Vendedor") {
                            chips(sellers, isOn: { draft.sellers.contains($0) }) { FilterState.toggle($0, in: &draft.sellers) }
                        }
                    }

                    if !agents.isEmpty {
                        section("Agente de compra") {
                            chips(agents, isOn: { draft.agents.contains($0) }) { FilterState.toggle($0, in: &draft.agents) }
                        }
                    }

                    section("Estado") {
                        chips(PurchaseStatus.allCases.map(\.label), isOn: { label in
                            PurchaseStatus.allCases.first { $0.label == label }.map { draft.statuses.contains($0.rawValue) } ?? false
                        }) { label in
                            if let s = PurchaseStatus.allCases.first(where: { $0.label == label }) {
                                FilterState.toggle(s.rawValue, in: &draft.statuses)
                            }
                        }
                    }

                    if let bounds = priceBounds {
                        section("Precio") {
                            VStack(spacing: 6) {
                                RangeSlider(range: $price, bounds: bounds)
                                HStack {
                                    Text(priceText(price.lowerBound))
                                    Spacer()
                                    Text(price.upperBound >= bounds.upperBound
                                         ? priceText(bounds.upperBound) + "+" : priceText(price.upperBound))
                                }
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                if priceUnit != "$" {
                                    Text("Configura las tasas de cambio en Cuenta para comparar todos los precios en USD.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                                }
                            }
                        }
                    }

                    Button("Limpiar filtros") {
                        draft = FilterState()
                        draft.subcategory = state.subcategory
                        if let bounds = priceBounds { price = bounds }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
                }
                .padding(Theme.hPadding)
                .padding(.bottom, 20)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !didLoad else { return }
            draft = state
            if let bounds = priceBounds {
                if let saved = state.priceRange {
                    let lo = min(max(saved.lowerBound, bounds.lowerBound), bounds.upperBound)
                    let hi = max(min(saved.upperBound, bounds.upperBound), lo)
                    price = lo...hi
                } else {
                    price = bounds
                }
            }
            didLoad = true
        }
    }

    private var header: some View {
        HStack {
            Button("Cancelar") { dismiss() }
                .foregroundStyle(.white)
            Spacer()
            Text("Filtros (\(title))")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button("Aplicar") { apply() }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.blue)
        }
        .font(.system(size: 16))
        .padding(.horizontal, Theme.hPadding)
        .frame(height: 56)
    }

    private func apply() {
        var result = draft
        if let bounds = priceBounds, price != bounds {
            result.priceRange = price.lowerBound...(price.upperBound >= bounds.upperBound ? .greatestFiniteMagnitude : price.upperBound)
        } else {
            result.priceRange = nil
        }
        state = result
        dismiss()
    }

    private func priceText(_ value: Double) -> String {
        let unit = priceUnit
        return unit == "$" ? "$\(Int(value))" : (unit.isEmpty ? "\(Int(value))" : "\(unit) \(Int(value))")
    }

    // MARK: Secciones

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            content()
        }
    }

    private func chips(_ options: [String], isOn: @escaping (String) -> Bool,
                       toggle: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                FilterChip(title: option, isSelected: isOn(option), accent: .blue) { toggle(option) }
            }
        }
    }

    private var typeCardsSection: some View {
        section("Tipo") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(schema.filterTypeCards) { card in
                    Button {
                        FilterState.toggle(card.title, in: &draft.styleCards)
                    } label: {
                        StyleCardView(card: card,
                                      image: products.first(where: { card.matches($0) })?.coverImage,
                                      isSelected: draft.styleCards.contains(card.title),
                                      width: 54)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var brandTiles: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(brands, id: \.self) { brand in
                    Button {
                        FilterState.toggle(brand, in: &draft.brands)
                    } label: {
                        Text(brand)
                            .font(.system(size: 12, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 66, height: 46)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(draft.brands.contains(brand) ? Theme.blue : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.hPadding)
        }
        .padding(.horizontal, -Theme.hPadding)
    }

    private var colorRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(schema.palette) { swatch in
                Button {
                    FilterState.toggle(swatch.name, in: &draft.colors)
                } label: {
                    ColorDot(swatch: swatch, isSelected: draft.colors.contains(swatch.name), size: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
