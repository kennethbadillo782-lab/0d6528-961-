import SwiftUI
import SwiftData

/// Pantalla de grupo, por ejemplo "Ropa": Camisas, Pantalones, Hoodies, Chaquetas…
struct GroupScreen: View {
    let group: QuickGroup

    @Query(sort: \Product.createdAt, order: .reverse) var allProducts: [Product]
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @AppStorage(SettingsKeys.hideDiscarded) var hideDiscarded = false
    @EnvironmentObject var appState: AppState

    @State var search = ""
    @State var selectedChip: GroupChip?
    @State var subcategory: String?
    @State var filter = FilterState()
    @State var sort: ProductSort = .recent
    @State var showFilters = false

    struct GroupChip: Hashable {
        let title: String
        let categoryKey: String
        let fixedSubcategory: String?
    }

    /// En Ropa, los abrigos se muestran como Hoodies, Chaquetas, etc., igual que en el diseño.
    private var chips: [GroupChip] {
        var result: [GroupChip] = []
        for c in categories where c.group == group {
            if group == .clothing && c.key == "abrigos" {
                result += c.subcategories.map { GroupChip(title: $0, categoryKey: c.key, fixedSubcategory: $0) }
            } else {
                result.append(GroupChip(title: c.name, categoryKey: c.key, fixedSubcategory: nil))
            }
        }
        return result
    }

    private var activeChip: GroupChip? { selectedChip ?? chips.first }

    private var activeCategory: CatalogCategory? {
        activeChip.flatMap { CategoryCatalog.category($0.categoryKey, in: categories) }
    }

    private var schema: CategorySchema { CategorySchema.forCategory(activeChip?.categoryKey ?? "") }

    private var base: [Product] {
        guard let chip = activeChip else { return [] }
        return allProducts.filter { p in
            p.categoryKey == chip.categoryKey
                && (chip.fixedSubcategory == nil || p.subcategory.equalsLoose(chip.fixedSubcategory!))
                && (!hideDiscarded || p.status != .discarded)
        }
    }

    private var results: [Product] {
        let s = schema
        return sort.apply(base.filter { p in
            (subcategory == nil || p.subcategory.equalsLoose(subcategory!))
                && filter.matches(p, schema: s)
                && SearchMatcher.matches(p, query: search)
        })
    }

    var body: some View {
        let items = results
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SearchBar(text: $search, placeholder: "Buscar en \(group.label.lowercased())...")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            FilterChip(title: chip.title, isSelected: chip == activeChip) {
                                selectedChip = chip
                                subcategory = nil
                                filter = FilterState()
                            }
                        }
                    }
                    .padding(.horizontal, Theme.hPadding)
                }
                .padding(.horizontal, -Theme.hPadding)

                if let chip = activeChip, chip.fixedSubcategory == nil,
                   let subs = activeCategory?.subcategories, !subs.isEmpty {
                    ChipRow(options: subs, allLabel: schema.allLabel, selection: $subcategory)
                }

                if filter.activeCount > 0 {
                    ActiveFiltersBar(count: filter.activeCount) { filter = FilterState() }
                }

                if chips.isEmpty {
                    EmptyStateView(symbol: group.symbol, title: "Sin categorías",
                                   message: "Crea una categoría para este grupo desde Cuenta › Categorías.")
                } else if items.isEmpty {
                    EmptyStateView(symbol: activeCategory?.symbol ?? "tray",
                                   title: base.isEmpty ? "Aún no hay productos aquí" : "Sin resultados",
                                   message: base.isEmpty
                                       ? "Guarda productos en \(activeChip?.title ?? "esta sección") para verlos aquí."
                                       : "Prueba con otra búsqueda o quita algunos filtros.",
                                   actionTitle: base.isEmpty ? "Agregar producto" : "Limpiar filtros",
                                   action: {
                                       if base.isEmpty { appState.presentAdd() } else {
                                           filter = FilterState()
                                           subcategory = nil
                                           search = ""
                                       }
                                   })
                } else {
                    ProductGrid(products: items)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(group.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SortMenu(sort: $sort)
                FilterToolbarButton(count: filter.activeCount) { showFilters = true }
            }
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(title: activeChip?.title ?? group.label, schema: schema, products: base,
                        subcategories: [], state: $filter)
        }
    }
}
