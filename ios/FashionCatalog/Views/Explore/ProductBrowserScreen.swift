import SwiftUI
import SwiftData

/// Explorar, "Todo" y filtros por marca.
struct ProductBrowserScreen: View {
    enum Scope: Hashable {
        case all
        case brand(String)
    }

    let title: String
    let scope: Scope

    @Query(sort: \Product.createdAt, order: .reverse) var allProducts: [Product]
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @AppStorage(SettingsKeys.hideDiscarded) var hideDiscarded = false
    @EnvironmentObject var appState: AppState

    @State var search = ""
    @State var categoryKey: String?
    @State var filter = FilterState()
    @State var sort: ProductSort = .recent
    @State var showFilters = false

    private var scoped: [Product] {
        allProducts.filter { p in
            if hideDiscarded && p.status == .discarded { return false }
            switch scope {
            case .all: return true
            case .brand(let brand): return p.brand.equalsLoose(brand)
            }
        }
    }

    private var base: [Product] {
        guard let categoryKey else { return scoped }
        return scoped.filter { $0.categoryKey == categoryKey }
    }

    private var schema: CategorySchema { CategorySchema.forCategory(categoryKey ?? "") }

    private var categoryNames: [String] {
        let present = Set(scoped.map(\.categoryKey))
        return categories.filter { present.contains($0.key) }.map(\.name)
    }

    private var selectedName: Binding<String?> {
        Binding(
            get: { categoryKey.map { CategoryCatalog.name($0, in: categories) } },
            set: { name in
                categoryKey = name.flatMap { n in categories.first { $0.name == n }?.key }
                filter = FilterState()
            }
        )
    }

    var body: some View {
        let s = schema
        let items = sort.apply(base.filter { filter.matches($0, schema: s) && SearchMatcher.matches($0, query: search) })
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SearchBar(text: $search, placeholder: "Buscar productos, marcas o vendedores...")
                if !categoryNames.isEmpty {
                    ChipRow(options: categoryNames, allLabel: "Todo", selection: selectedName)
                }
                if filter.activeCount > 0 {
                    ActiveFiltersBar(count: filter.activeCount) { filter = FilterState() }
                }
                if items.isEmpty {
                    if scoped.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass",
                                       title: scopeEmptyTitle,
                                       message: "Cuando guardes productos podrás explorarlos y filtrarlos aquí.",
                                       actionTitle: "Agregar producto",
                                       action: { appState.presentAdd() })
                    } else {
                        EmptyStateView(symbol: "magnifyingglass", title: "Sin resultados",
                                       message: "Prueba con otra búsqueda o quita algunos filtros.",
                                       actionTitle: "Limpiar filtros",
                                       action: { filter = FilterState(); search = "" })
                    }
                } else {
                    Text("\(items.count) producto\(items.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    ProductGrid(products: items)
                }
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SortMenu(sort: $sort)
                FilterToolbarButton(count: filter.activeCount) { showFilters = true }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(title: categoryKey.map { CategoryCatalog.name($0, in: categories) } ?? title,
                        schema: s, products: base,
                        subcategories: categoryKey.flatMap { CategoryCatalog.category($0, in: categories)?.subcategories } ?? [],
                        state: $filter)
        }
    }

    private var scopeEmptyTitle: String {
        switch scope {
        case .all: return "Nada que explorar todavía"
        case .brand(let brand): return "No tienes productos de \(brand)"
        }
    }
}
