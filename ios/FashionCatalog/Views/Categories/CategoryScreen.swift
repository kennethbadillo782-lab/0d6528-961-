import SwiftUI
import SwiftData

/// Pantalla de una categoría (Pantalones, Carteras, Pantallas…). Los filtros se adaptan a la categoría.
struct CategoryScreen: View {
    let categoryKey: String

    @Query(sort: \Product.createdAt, order: .reverse) var allProducts: [Product]
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @AppStorage(SettingsKeys.hideDiscarded) var hideDiscarded = false
    @EnvironmentObject var appState: AppState

    @State var search = ""
    @State var filter: FilterState
    @State var sort: ProductSort = .recent
    @State var showFilters = false

    init(categoryKey: String, initialSubcategory: String? = nil) {
        self.categoryKey = categoryKey
        var state = FilterState()
        state.subcategory = initialSubcategory
        _filter = State(initialValue: state)
    }

    private var category: CatalogCategory? { CategoryCatalog.category(categoryKey, in: categories) }
    private var name: String { CategoryCatalog.name(categoryKey, in: categories) }
    private var schema: CategorySchema { CategorySchema.forCategory(categoryKey) }
    private var subcategories: [String] { category?.subcategories ?? [] }

    private var base: [Product] {
        allProducts.filter { $0.categoryKey == categoryKey && (!hideDiscarded || $0.status != .discarded) }
    }

    private var results: [Product] {
        let s = schema
        return sort.apply(base.filter { filter.matches($0, schema: s) && SearchMatcher.matches($0, query: search) })
    }

    var body: some View {
        let s = schema
        let items = results
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SearchBar(text: $search, placeholder: "Buscar \(name.lowercased())...")

                if !s.styleCards.isEmpty {
                    StyleCardRow(cards: s.styleCards, products: base, selection: $filter.styleCards)
                }

                if !subcategories.isEmpty {
                    ChipRow(options: subcategories, allLabel: s.allLabel, selection: $filter.subcategory)
                }

                if s.inlineMillimeters || s.inlineColors || !s.inlineMaterials.isEmpty {
                    InlineFilters(schema: s, filter: $filter, showMore: { showFilters = true })
                }

                if filter.activeCount > 0 {
                    ActiveFiltersBar(count: filter.activeCount) {
                        let sub = filter.subcategory
                        filter = FilterState()
                        filter.subcategory = sub
                    }
                }

                if items.isEmpty {
                    if base.isEmpty {
                        EmptyStateView(symbol: category?.symbol ?? "tray",
                                       title: "Aún no hay \(name.lowercased())",
                                       message: "Los productos que guardes en esta categoría aparecerán aquí.",
                                       actionTitle: "Agregar producto",
                                       action: { appState.presentAdd() })
                    } else {
                        EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "Sin resultados",
                                       message: "Ningún producto cumple todos los filtros seleccionados.",
                                       actionTitle: "Limpiar filtros",
                                       action: { filter = FilterState() })
                    }
                } else {
                    ProductGrid(products: items)
                }
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SortMenu(sort: $sort)
                FilterToolbarButton(count: filter.activeCount) { showFilters = true }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(title: name, schema: s, products: base, subcategories: [], state: $filter)
        }
    }
}

// MARK: - Piezas compartidas por las pantallas de catálogo

struct StyleCardRow: View {
    let cards: [StyleCard]
    let products: [Product]
    @Binding var selection: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cards) { card in
                    Button {
                        FilterState.toggle(card.title, in: &selection)
                    } label: {
                        StyleCardView(card: card, image: products.first(where: { card.matches($0) })?.coverImage,
                                      isSelected: selection.contains(card.title), width: 62)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.hPadding)
        }
        .padding(.horizontal, -Theme.hPadding)
    }
}

struct StyleCardView: View {
    let card: StyleCard
    let image: ProductImage?
    var isSelected: Bool
    var width: CGFloat = 62

    var body: some View {
        VStack(spacing: 4) {
            Color.clear
                .frame(width: width, height: width * 1.05)
                .overlay {
                    CatalogImage(image: image, maxPixel: 240, placeholderSymbol: card.symbol)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(card.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Theme.blue : .clear, lineWidth: 2)
        )
    }
}

/// Filtros visibles directamente en la pantalla (por ejemplo, en Pantallas).
struct InlineFilters: View {
    let schema: CategorySchema
    @Binding var filter: FilterState
    var showMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if schema.inlineMillimeters {
                VStack(alignment: .leading, spacing: 8) {
                    label("Tamaño")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CategorySchema.millimeterBuckets, id: \.self) { bucket in
                                FilterChip(title: bucket, isSelected: filter.hasAttribute("tamanoMM", bucket)) {
                                    filter.toggleAttribute("tamanoMM", bucket)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.hPadding)
                    }
                    .padding(.horizontal, -Theme.hPadding)
                }
            }
            if schema.inlineColors {
                VStack(alignment: .leading, spacing: 8) {
                    label("Color")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(schema.palette) { swatch in
                                Button {
                                    FilterState.toggle(swatch.name, in: &filter.colors)
                                } label: {
                                    ColorDot(swatch: swatch, isSelected: filter.colors.contains(swatch.name), size: 32)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.hPadding)
                    }
                    .padding(.horizontal, -Theme.hPadding)
                }
            }
            if !schema.inlineMaterials.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    label("Material")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(schema.inlineMaterials, id: \.self) { option in
                                FilterChip(title: option.label,
                                           isSelected: filter.hasAttribute(option.attributeKey, option.label)) {
                                    filter.toggleAttribute(option.attributeKey, option.label)
                                }
                            }
                            FilterChip(title: "Más", isSelected: false, action: showMore)
                        }
                        .padding(.horizontal, Theme.hPadding)
                    }
                    .padding(.horizontal, -Theme.hPadding)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
    }
}

struct FilterToolbarButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 18))
                .foregroundStyle(count > 0 ? Theme.blue : .white)
        }
        .accessibilityLabel("Filtros")
    }
}

struct SortMenu: View {
    @Binding var sort: ProductSort

    var body: some View {
        Menu {
            Picker("Ordenar", selection: $sort) {
                ForEach(ProductSort.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Ordenar")
    }
}

struct ActiveFiltersBar: View {
    let count: Int
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text("\(count) filtro\(count == 1 ? "" : "s") activo\(count == 1 ? "" : "s")")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Limpiar", action: onClear)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.blue)
        }
    }
}
