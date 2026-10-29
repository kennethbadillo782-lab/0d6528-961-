import SwiftUI
import SwiftData

struct SavedView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) var context
    @Query(sort: \Product.createdAt, order: .reverse) var products: [Product]
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]

    @State var categoryName: String?
    @State var statusFilter: PurchaseStatus?
    @State var sort: ProductSort = .recent
    @State var pendingDelete: Product?
    @State var collectionTarget: Product?

    private var categoryNames: [String] {
        let present = Set(products.map(\.categoryKey))
        return categories.filter { present.contains($0.key) }.map(\.name)
    }

    private var filtered: [Product] {
        let key = categoryName.flatMap { n in categories.first { $0.name == n }?.key }
        let list = products.filter { p in
            (key == nil || p.categoryKey == key) && (statusFilter == nil || p.status == statusFilter)
        }
        return sort.apply(list)
    }

    var body: some View {
        let items = filtered
        VStack(spacing: 10) {
            if !categoryNames.isEmpty {
                ChipRow(options: categoryNames, allLabel: "Todos", selection: $categoryName)
                    .padding(.horizontal, Theme.hPadding)
            }
            controls
                .padding(.horizontal, Theme.hPadding)

            if products.isEmpty {
                Spacer()
                EmptyStateView(symbol: "bookmark", title: "Aún no has guardado productos",
                               message: "Todo lo que guardes aparecerá aquí con su fecha, precio y tienda.",
                               actionTitle: "Agregar producto", action: { appState.presentAdd() })
                Spacer()
            } else if items.isEmpty {
                Spacer()
                EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "Nada con estos filtros",
                               message: "Cambia la categoría o el estado para ver más productos.",
                               actionTitle: "Ver todos",
                               action: { categoryName = nil; statusFilter = nil })
                Spacer()
            } else {
                List {
                    ForEach(items) { product in
                        SavedRow(product: product)
                            .background(
                                NavigationLink(value: AppRoute.product(product)) { EmptyView() }.opacity(0)
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: Theme.hPadding, bottom: 5, trailing: Theme.hPadding))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { pendingDelete = product } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                                Button {
                                    product.status = product.status == .purchased ? .pending : .purchased
                                    product.touch()
                                } label: {
                                    Label(product.status == .purchased ? "Pendiente" : "Comprado",
                                          systemImage: product.status == .purchased ? "clock" : "checkmark")
                                }
                                .tint(Theme.blue)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    product.isFavorite.toggle()
                                    product.touch()
                                } label: {
                                    Label("Favorito", systemImage: product.isFavorite ? "heart.slash" : "heart")
                                }
                                .tint(Theme.heart)
                            }
                            .contextMenu {
                                ProductActionsMenu(product: product, collection: nil,
                                                   onAddToCollection: { collectionTarget = product },
                                                   onDelete: { pendingDelete = product })
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.top, 4)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Guardados")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { appState.presentAdd() } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                }
                .accessibilityLabel("Agregar producto")
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
            Text("Se borrarán sus fotos y enlaces. Si ya lo compraste, puedes marcarlo como Comprado para conservarlo en el historial.")
        }
        .sheet(item: $collectionTarget) { CollectionPickerSheet(product: $0) }
    }

    private var controls: some View {
        HStack {
            Menu {
                Button("Todos los estados") { statusFilter = nil }
                ForEach(PurchaseStatus.allCases) { s in
                    Button { statusFilter = s } label: { Label(s.label, systemImage: s.symbol) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag")
                    Text(statusFilter?.label ?? "Todos los estados")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusFilter == nil ? Theme.textSecondary : Theme.blue)
            }
            Spacer()
            Menu {
                Picker("Ordenar", selection: $sort) {
                    ForEach(ProductSort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sort.label)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Fila compacta: miniatura, nombre, precio, plataforma/agente, fecha y favorito.
struct SavedRow: View {
    let product: Product
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CatalogImage(image: product.coverImage, maxPixel: 220,
                         placeholderSymbol: CategoryCatalog.symbol(product.categoryKey, in: categories))
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(product.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    HeartButton(isOn: product.isFavorite, size: 15) {
                        product.isFavorite.toggle()
                        product.touch()
                    }
                    .frame(width: 24, height: 20)
                }
                PriceLabel(product: product, font: .system(size: 13, weight: .medium), color: .white)
                HStack(spacing: 6) {
                    if !product.sourceLabel.isEmpty {
                        SourceBadge(name: product.sourceLabel)
                    }
                    if product.isDemo {
                        DemoBadge()
                    } else if product.status != .researching {
                        Text(product.status.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(product.status == .ready ? Theme.blue : Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(DateText.short(product.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct SourceBadge: View {
    let name: String

    private var tint: Color {
        let palette: [Color] = [Theme.blue, Theme.green, Theme.heart, .orange, .purple, .teal]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(tint, in: RoundedRectangle(cornerRadius: 4))
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
