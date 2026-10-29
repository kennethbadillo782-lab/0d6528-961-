import SwiftUI
import SwiftData

struct PriceLabel: View {
    let product: Product
    var font: Font = .system(size: 13, weight: .medium)
    var color: Color = Theme.textSecondary
    var showEquivalent = true

    @AppStorage(SettingsKeys.ratesVersion) var ratesVersion = 0
    @AppStorage(SettingsKeys.showUSD) var showUSD = true

    var body: some View {
        if let price = product.priceCurrent {
            HStack(spacing: 5) {
                Text(Money.format(price, code: product.currency))
                    .font(font)
                    .foregroundStyle(color)
                if showEquivalent, showUSD, product.currency != "USD",
                   let usd = Money.toUSD(price, code: product.currency) {
                    Text("≈ " + Money.format(usd, code: "USD"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.textSecondary.opacity(0.75))
                }
            }
            .lineLimit(1)
            .id(ratesVersion)
        } else {
            Text("Sin precio")
                .font(font)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
    }
}

struct ProductCard: View {
    let product: Product
    var categorySymbol: String = "photo"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CatalogImage(image: product.coverImage, maxPixel: 600, placeholderSymbol: categorySymbol)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    HeartButton(isOn: product.isFavorite) {
                        product.isFavorite.toggle()
                        product.touch()
                    }
                    .padding(4)
                }
                .overlay(alignment: .topLeading) {
                    if product.isDemo {
                        DemoBadge().padding(8)
                    } else if product.status == .purchased || product.status == .ready {
                        Text(product.status.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(product.status == .ready ? Theme.blue : Color.black.opacity(0.6),
                                        in: Capsule())
                            .padding(8)
                    }
                }

            Text(product.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            PriceLabel(product: product)
        }
        .contentShape(Rectangle())
    }
}

/// Cuadrícula de dos columnas reutilizada por todas las categorías.
struct ProductGrid: View {
    let products: [Product]
    var collection: ProductCollection?

    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @Environment(\.modelContext) var context
    @State var pendingDelete: Product?
    @State var collectionTarget: Product?

    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(products) { product in
                NavigationLink(value: AppRoute.product(product)) {
                    ProductCard(product: product,
                                categorySymbol: CategoryCatalog.symbol(product.categoryKey, in: categories))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ProductActionsMenu(
                        product: product,
                        collection: collection,
                        onAddToCollection: { collectionTarget = product },
                        onDelete: { pendingDelete = product }
                    )
                }
            }
        }
        .confirmationDialog(
            "¿Eliminar este producto?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { product in
            Button("Eliminar producto", role: .destructive) {
                context.delete(product)
                try? context.save()
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Se borrarán sus fotos y enlaces. Esta acción no se puede deshacer.")
        }
        .sheet(item: $collectionTarget) { product in
            CollectionPickerSheet(product: product)
        }
    }
}

/// Menú de acciones al mantener pulsado un producto.
struct ProductActionsMenu: View {
    let product: Product
    var collection: ProductCollection?
    var onAddToCollection: () -> Void
    var onDelete: () -> Void

    @Environment(\.openURL) var openURL

    var body: some View {
        Button {
            product.isFavorite.toggle()
            product.touch()
        } label: {
            Label(product.isFavorite ? "Quitar de favoritos" : "Marcar favorito",
                  systemImage: product.isFavorite ? "heart.slash" : "heart")
        }

        Menu {
            ForEach(PurchaseStatus.allCases) { status in
                Button {
                    product.status = status
                    product.touch()
                } label: {
                    if product.status == status {
                        Label(status.label, systemImage: "checkmark")
                    } else {
                        Text(status.label)
                    }
                }
            }
        } label: {
            Label("Cambiar estado", systemImage: "flag")
        }

        Button(action: onAddToCollection) {
            Label("Guardar en colección", systemImage: "folder.badge.plus")
        }

        if let collection {
            Button {
                product.collections.removeAll { $0.persistentModelID == collection.persistentModelID }
                product.touch()
            } label: {
                Label("Quitar de \(collection.name)", systemImage: "folder.badge.minus")
            }
        }

        if let url = NetworkSafety.webURL(product.originalURL) {
            Button { openURL(url) } label: { Label("Abrir enlace original", systemImage: "safari") }
        }

        Divider()

        Button(role: .destructive, action: onDelete) {
            Label("Eliminar", systemImage: "trash")
        }
    }
}

struct CategoryTile: View {
    let title: String
    var image: ProductImage?
    var symbol: String = "photo"
    var aspect: CGFloat = 0.78

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image {
                    CatalogImage(image: image, maxPixel: 400, placeholderSymbol: symbol)
                } else {
                    ZStack {
                        Theme.card
                        Image(systemName: symbol)
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Theme.textSecondary.opacity(0.8))
                            .offset(y: -8)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottom) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// Selección de colecciones de un producto (un producto puede estar en varias).
struct CollectionPickerSheet: View {
    let product: Product
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @Query(sort: \ProductCollection.sortOrder) var collections: [ProductCollection]
    @State var showCreate = false
    @State var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections) { collection in
                    let isIn = product.collections.contains { $0.persistentModelID == collection.persistentModelID }
                    Button {
                        if isIn {
                            product.collections.removeAll { $0.persistentModelID == collection.persistentModelID }
                        } else {
                            product.collections.append(collection)
                        }
                        product.touch()
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(Theme.textSecondary)
                            Text(collection.name).foregroundStyle(.white)
                            Spacer()
                            Text("\(collection.products.count)")
                                .foregroundStyle(Theme.textSecondary)
                            Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isIn ? Theme.blue : Theme.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Label("Nueva colección", systemImage: "plus")
                        .foregroundStyle(Theme.blue)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Guardar en colección")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        try? context.save()
                        dismiss()
                    }
                    .foregroundStyle(Theme.blue)
                }
            }
            .alert("Nueva colección", isPresented: $showCreate) {
                TextField("Nombre", text: $newName)
                Button("Crear") {
                    let name = newName.trimmed
                    guard !name.isEmpty else { return }
                    let c = ProductCollection(name: name, sortOrder: (collections.map(\.sortOrder).max() ?? 0) + 1)
                    context.insert(c)
                    product.collections.append(c)
                    product.touch()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}
