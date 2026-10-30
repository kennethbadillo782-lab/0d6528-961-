import SwiftUI
import SwiftData

/// Todas las marcas de tu lista ("Ver todas" desde Inicio), de la que más productos tiene a la que menos.
struct AllBrandsView: View {
    @Query(sort: \Product.createdAt, order: .reverse) var products: [Product]
    @AppStorage(SettingsKeys.hideDiscarded) var hideDiscarded = false

    var body: some View {
        let visible = hideDiscarded ? products.filter { $0.status != .discarded } : products
        let brands = BrandLibrary.ranked(in: visible)
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                ForEach(brands, id: \.name) { brand in
                    NavigationLink(value: AppRoute.brand(brand.name)) {
                        VStack(spacing: 5) {
                            BrandTile(name: brand.name)
                            Text(BrandLibrary.displayName(brand.name))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(brand.count) producto\(brand.count == 1 ? "" : "s")")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.hPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Marcas")
        .navigationBarTitleDisplayMode(.inline)
    }
}
