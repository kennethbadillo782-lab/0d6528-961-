import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) var context
    @Query(sort: \Product.createdAt, order: .reverse) var products: [Product]
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @AppStorage(SettingsKeys.hideDiscarded) var hideDiscarded = false

    @State var search = ""
    @State var showActivity = false

    private var visibleProducts: [Product] {
        hideDiscarded ? products.filter { $0.status != .discarded } : products
    }

    private var trimmedSearch: String { search.trimmed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                SearchBar(text: $search, placeholder: "Buscar productos, marcas o links...") {
                    if LinkImportService.looksLikeURL(search) { appState.presentAdd(url: search) }
                }
                if trimmedSearch.isEmpty {
                    quickAccessRow
                    brandsSection
                    categoriesSection
                    if products.isEmpty { emptyCatalog }
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showActivity) { ActivityView() }
    }

    // MARK: Encabezado

    private var header: some View {
        HStack {
            Text("Inicio")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button { showActivity = true } label: {
                Image(systemName: "bell")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if readyCount > 0 {
                            Circle().fill(Theme.heart).frame(width: 8, height: 8).offset(x: -9, y: 9)
                        }
                    }
            }
            .accessibilityLabel("Actividad")
        }
        .padding(.top, 6)
    }

    private var readyCount: Int { products.filter { $0.status == .ready }.count }

    // MARK: Accesos rápidos

    private var quickAccessRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(QuickGroup.allCases) { group in
                    NavigationLink(value: route(for: group)) {
                        VStack(spacing: 6) {
                            Image(systemName: group.symbol)
                                .font(.system(size: 19, weight: .regular))
                                .foregroundStyle(group == .all ? .black : .white)
                                .frame(width: 54, height: 46)
                                .background(group == .all ? Color.white : Theme.card,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(group.label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(minWidth: 62)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.hPadding)
        }
        .padding(.horizontal, -Theme.hPadding)
    }

    private func route(for group: QuickGroup) -> AppRoute {
        switch group {
        case .all: return .allProducts
        case .clothing, .accessories: return .group(group)
        case .shoes: return .category(key: "zapatos", subcategory: nil)
        case .bags: return .category(key: "carteras", subcategory: nil)
        }
    }

    // MARK: Marcas

    /// Marcas presentes en el catálogo (son filtros personales, no conexiones oficiales).
    private var brands: [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for p in products where !p.brand.trimmed.isEmpty {
            let key = p.brand.loose
            counts[key, default: 0] += 1
            if display[key] == nil { display[key] = p.brand.trimmed }
        }
        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let found = sorted.compactMap { display[$0.key] }
        return found.isEmpty ? ["Louis Vuitton", "Gucci", "Dior", "Coach", "Nike"] : found
    }

    private var brandsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Marcas populares")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(brands, id: \.self) { brand in
                        NavigationLink(value: AppRoute.brand(brand)) {
                            BrandTile(name: brand)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.hPadding)
            }
            .padding(.horizontal, -Theme.hPadding)
        }
    }

    // MARK: Categorías

    private var homeCategories: [CatalogCategory] {
        Array(categories.filter(\.showOnHome).prefix(7))
    }

    private var coverByCategory: [String: ProductImage] {
        var result: [String: ProductImage] = [:]
        for p in products where result[p.categoryKey] == nil {
            if let image = p.coverImage { result[p.categoryKey] = image }
        }
        return result
    }

    private var categoriesSection: some View {
        let covers = coverByCategory
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Categorías")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(homeCategories) { category in
                    NavigationLink(value: AppRoute.category(key: category.key, subcategory: nil)) {
                        CategoryTile(title: category.name, image: covers[category.key], symbol: category.symbol)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: AppRoute.allCategories) {
                    ZStack {
                        Theme.card
                        VStack(spacing: 6) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Más").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white)
                    }
                    .aspectRatio(0.78, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Estados

    private var emptyCatalog: some View {
        VStack(spacing: 0) {
            EmptyStateView(
                symbol: "tshirt",
                title: "Tu catálogo está vacío",
                message: "Pega un enlace de Taobao, Weidian, Yupoo o un agente, o sube capturas de TikTok e Instagram.",
                actionTitle: "Agregar producto",
                action: { appState.presentAdd() }
            )
            Button("Cargar productos de ejemplo") {
                DemoData.insert(into: context)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
        }
        .background(Theme.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        let results = visibleProducts.filter { SearchMatcher.matches($0, query: trimmedSearch) }
        let isLink = LinkImportService.looksLikeURL(trimmedSearch)
        let key = isLink ? LinkImportService.duplicateKey(trimmedSearch) : ""
        let existing = key.isEmpty ? nil : products.first { $0.normalizedURL == key }

        return VStack(alignment: .leading, spacing: 14) {
            if isLink {
                LinkDetectedBanner(existing: existing) {
                    appState.presentAdd(url: trimmedSearch)
                }
            }
            if results.isEmpty && !isLink {
                EmptyStateView(symbol: "magnifyingglass", title: "Sin resultados",
                               message: "No hay productos guardados que coincidan con “\(trimmedSearch)”.")
            } else if !results.isEmpty {
                Text("\(results.count) resultado\(results.count == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                ProductGrid(products: results)
            }
        }
    }
}

struct BrandTile: View {
    let name: String

    /// Iniciales en texto neutro: no se reproducen logotipos de las marcas.
    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(initials)
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .frame(width: 60, height: 52)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 64)
        }
    }
}

struct LinkDetectedBanner: View {
    let existing: Product?
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(Theme.blue)
                Text(existing == nil ? "Enlace detectado" : "Ya tienes este producto guardado")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if let existing {
                NavigationLink(value: AppRoute.product(existing)) {
                    HStack {
                        Text(existing.displayName).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Button(existing == nil ? "Agregar producto con este enlace" : "Agregar de todos modos", action: onAdd)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
