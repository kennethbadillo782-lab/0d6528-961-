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
    @State var showAccount = false

    private var visibleProducts: [Product] {
        hideDiscarded ? products.filter { $0.status != .discarded } : products
    }

    private var trimmedSearch: String { search.trimmed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                SearchBar(text: $search, placeholder: "Buscar productos...") {
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
        .sheet(isPresented: $showAccount) {
            NavigationStack { AccountView().withAppRoutes() }
        }
    }

    // MARK: Encabezado

    private var header: some View {
        HStack {
            Text("Inicio")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button { showAccount = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Cuenta")
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

    /// Accesos grandes con foto: la portada es el último producto guardado de ese tipo.
    private struct QuickTile: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let route: AppRoute
        let matches: (Product) -> Bool
    }

    private var quickTiles: [QuickTile] {
        let groupOf = Dictionary(categories.map { ($0.key, $0.groupRaw) }, uniquingKeysWith: { a, _ in a })
        return [
            QuickTile(id: "ropa", title: "Ropa", symbol: "tshirt", route: .group(.clothing),
                      matches: { groupOf[$0.categoryKey] == QuickGroup.clothing.rawValue }),
            QuickTile(id: "zapatos", title: "Zapatos", symbol: "shoe.2", route: .category(key: "zapatos", subcategory: nil),
                      matches: { $0.categoryKey == "zapatos" }),
            QuickTile(id: "carteras", title: "Carteras", symbol: "handbag", route: .category(key: "carteras", subcategory: nil),
                      matches: { $0.categoryKey == "carteras" }),
            QuickTile(id: "relojes", title: "Relojes", symbol: "clock", route: .category(key: "relojes", subcategory: nil),
                      matches: { $0.categoryKey == "relojes" }),
        ]
    }

    private var quickAccessRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(quickTiles) { tile in
                NavigationLink(value: tile.route) {
                    PhotoTile(title: tile.title, subtitle: nil,
                              image: visibleProducts.first(where: tile.matches)?.coverImage,
                              symbol: tile.symbol, aspect: 0.72)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Marcas

    /// Solo las marcas que ya tienes guardadas: aparecen a medida que guardas productos de cada una.
    private var brands: [String] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for p in visibleProducts where !p.brand.trimmed.isEmpty {
            let key = BrandLibrary.key(p.brand)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
            if display[key] == nil { display[key] = p.brand.trimmed }
        }
        let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return sorted.compactMap { display[$0.key] }
    }

    @ViewBuilder
    private var brandsSection: some View {
        let list = brands
        if !list.isEmpty {
            brandsRow(list)
        }
    }

    private func brandsRow(_ brands: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Marcas")
                Spacer()
                Text("\(brands.count) en tu lista")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
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
        Array(categories.filter(\.showOnHome).prefix(6))
    }

    private var countByCategory: [String: Int] {
        visibleProducts.reduce(into: [:]) { $0[$1.categoryKey, default: 0] += 1 }
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
        let counts = countByCategory
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Categorías")
                Spacer()
                NavigationLink(value: AppRoute.allCategories) {
                    HStack(spacing: 3) {
                        Text("Ver todas")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(homeCategories) { category in
                    let n = counts[category.key] ?? 0
                    NavigationLink(value: AppRoute.category(key: category.key, subcategory: nil)) {
                        PhotoTile(title: category.name, subtitle: "\(n) producto\(n == 1 ? "" : "s")",
                                  image: covers[category.key], symbol: category.symbol, aspect: 1.45)
                    }
                    .buttonStyle(.plain)
                }
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

    /// Como la referencia: tarjetas cuadradas oscuras, todas iguales, con el logo en blanco
    /// (los logos de color se muestran tal cual) o el nombre de la marca como logotipo.
    var body: some View {
        let shown = BrandLibrary.displayName(name)
        Group {
            if let logo = BrandLibrary.logo(name) {
                Image(uiImage: logo)
                    .renderingMode(BrandLibrary.logoHasColor(name) ? .original : .template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(14)
            } else {
                Text(shown)
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(shown.contains(" ") ? 2 : 1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
            }
        }
        .frame(width: 68, height: 68)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
        .accessibilityLabel(shown)
    }
}

/// Tarjeta con foto a sangre, degradado y texto abajo a la izquierda.
struct PhotoTile: View {
    let title: String
    var subtitle: String?
    var image: ProductImage?
    var symbol: String = "photo"
    var aspect: CGFloat = 1

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image {
                    CatalogImage(image: image, maxPixel: 600, placeholderSymbol: symbol)
                } else {
                    ZStack {
                        LinearGradient(colors: [Theme.card, Theme.chip], startPoint: .top, endPoint: .bottom)
                        Image(systemName: symbol)
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                            .offset(y: -10)
                    }
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: subtitle == nil ? 13 : 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
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
