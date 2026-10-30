import SwiftUI
import SwiftData
import PhotosUI

struct CollectionsView: View {
    @Environment(\.modelContext) var context
    @EnvironmentObject var appState: AppState
    @Query(sort: \ProductCollection.sortOrder) var collections: [ProductCollection]
    @Query(filter: #Predicate<Product> { $0.isFavorite == true }, sort: \Product.updatedAt, order: .reverse)
    var favorites: [Product]

    @State var tab = 0
    @State var showCreate = false
    @State var newName = ""
    @State var renaming: ProductCollection?
    @State var renameText = ""
    @State var deleting: ProductCollection?
    @State var coverEditing: ProductCollection?

    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                segmented
                if tab == 0 {
                    if collections.isEmpty {
                        EmptyStateView(symbol: "folder", title: "Sin colecciones",
                                       message: "Agrupa tus productos, por ejemplo: Lista principal, Verano o Regalos.",
                                       actionTitle: "Crear colección", action: { newName = ""; showCreate = true })
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(collections) { collection in
                                NavigationLink(value: AppRoute.collection(collection)) {
                                    CollectionCard(collection: collection)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { menu(for: collection) }
                            }
                        }
                    }
                } else {
                    if favorites.isEmpty {
                        EmptyStateView(symbol: "heart", title: "Sin favoritos",
                                       message: "Toca el corazón de cualquier producto para verlo aquí.")
                    } else {
                        ProductGrid(products: favorites)
                    }
                }
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Sin barra de título: desenfoque progresivo detrás de la hora para que el contenido no choque con ella.
        .overlay(alignment: .top) { StatusBarBlur() }
        .alert("Nueva colección", isPresented: $showCreate) {
            TextField("Nombre", text: $newName)
            Button("Crear", action: create)
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Renombrar colección", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                let name = renameText.trimmed
                if let renaming, !name.isEmpty {
                    renaming.name = name
                    try? context.save()
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Eliminar colección?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { collection in
            Button("Eliminar solo la colección", role: .destructive) {
                context.delete(collection)
                try? context.save()
            }
            if !collection.products.isEmpty {
                Button("Eliminar la colección y sus \(collection.products.count) productos", role: .destructive) {
                    for p in collection.products { context.delete(p) }
                    context.delete(collection)
                    try? context.save()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Si eliges solo la colección, los productos se conservan en Guardados y en sus otras colecciones.")
        }
        .sheet(item: $coverEditing) { CoverEditorSheet(collection: $0) }
    }

    private var header: some View {
        HStack {
            Text("Colecciones")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button { newName = ""; showCreate = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Crear colección")
        }
        .padding(.top, 6)
    }

    private var segmented: some View {
        HStack(spacing: 4) {
            ForEach(Array(["Mis colecciones", "Favoritos"].enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = index }
                } label: {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tab == index ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(tab == index ? Color.white : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.card, in: Capsule())
    }

    @ViewBuilder
    private func menu(for collection: ProductCollection) -> some View {
        Button {
            renameText = collection.name
            renaming = collection
        } label: { Label("Renombrar", systemImage: "pencil") }
        Button { coverEditing = collection } label: { Label("Cambiar portada", systemImage: "photo") }
        Button { move(collection, by: -1) } label: { Label("Mover antes", systemImage: "arrow.left") }
            .disabled(collections.first?.persistentModelID == collection.persistentModelID)
        Button { move(collection, by: 1) } label: { Label("Mover después", systemImage: "arrow.right") }
            .disabled(collections.last?.persistentModelID == collection.persistentModelID)
        Divider()
        Button(role: .destructive) { deleting = collection } label: { Label("Eliminar", systemImage: "trash") }
    }

    private func create() {
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        context.insert(ProductCollection(name: name, sortOrder: (collections.map(\.sortOrder).max() ?? -1) + 1))
        try? context.save()
    }

    private func move(_ collection: ProductCollection, by delta: Int) {
        var ordered = collections
        guard let index = ordered.firstIndex(where: { $0.persistentModelID == collection.persistentModelID }) else { return }
        let target = index + delta
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        for (i, c) in ordered.enumerated() { c.sortOrder = i }
        try? context.save()
    }
}

struct CollectionCard: View {
    let collection: ProductCollection

    var body: some View {
        Color.clear
            .aspectRatio(1.12, contentMode: .fit)
            .overlay { cover }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(collection.products.count) producto\(collection.products.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var cover: some View {
        if let data = collection.coverData {
            ImageLoaderView(cacheKey: "cover-\(collection.id.uuidString)-\(data.count)",
                            dataProvider: { data }, maxPixel: 600, placeholderSymbol: "folder")
        } else if let image = collection.automaticCover {
            CatalogImage(image: image, maxPixel: 600, placeholderSymbol: "folder")
        } else {
            ImagePlaceholder(symbol: "folder")
        }
    }
}

struct CoverEditorSheet: View {
    let collection: ProductCollection
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @State var pickerItem: PhotosPickerItem?

    let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Elegir foto de la galería", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        collection.coverData = nil
                        try? context.save()
                        dismiss()
                    } label: {
                        Label("Usar automáticamente el último producto", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    let images = collection.products.compactMap(\.coverImage)
                    if !images.isEmpty {
                        SectionTitle(title: "O elige un producto de la colección")
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(images) { image in
                                Button {
                                    collection.coverData = image.data
                                    try? context.save()
                                    dismiss()
                                } label: {
                                    CatalogImage(image: image, maxPixel: 300)
                                        .frame(height: 90)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(Theme.hPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Portada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    let datas = await ImageService.loadPickerItems([item])
                    if let data = datas.first {
                        collection.coverData = data
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CollectionDetailView: View {
    let collection: ProductCollection
    @EnvironmentObject var appState: AppState
    @State var search = ""
    @State var sort: ProductSort = .recent
    @State var showPicker = false

    var body: some View {
        let items = sort.apply(collection.products.filter { SearchMatcher.matches($0, query: search) })
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SearchBar(text: $search, placeholder: "Buscar en \(collection.name)...")
                if collection.products.isEmpty {
                    EmptyStateView(symbol: "folder", title: "Colección vacía",
                                   message: "Añade productos que ya tienes guardados o agrega uno nuevo.",
                                   actionTitle: "Añadir productos", action: { showPicker = true })
                } else if items.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "Sin resultados",
                                   message: "Ningún producto de esta colección coincide.")
                } else {
                    Text("\(collection.products.count) productos")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    ProductGrid(products: items, collection: collection)
                }
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SortMenu(sort: $sort)
                Menu {
                    Button { showPicker = true } label: { Label("Añadir productos guardados", systemImage: "checklist") }
                    Button { appState.presentAdd(collection: collection) } label: {
                        Label("Agregar producto nuevo", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showPicker) { ProductMultiPicker(collection: collection) }
    }
}

/// Añadir o quitar varios productos guardados de una colección.
struct ProductMultiPicker: View {
    let collection: ProductCollection
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @Query(sort: \Product.createdAt, order: .reverse) var products: [Product]
    @State var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(products.filter { SearchMatcher.matches($0, query: search) }) { product in
                    let isIn = collection.products.contains { $0.persistentModelID == product.persistentModelID }
                    Button {
                        if isIn {
                            product.collections.removeAll { $0.persistentModelID == collection.persistentModelID }
                        } else {
                            product.collections.append(collection)
                        }
                        product.touch()
                    } label: {
                        HStack(spacing: 12) {
                            CatalogImage(image: product.coverImage, maxPixel: 160)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(product.displayName).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isIn ? Theme.blue : Theme.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $search, prompt: "Buscar productos")
            .navigationTitle("Añadir a \(collection.name)")
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
        }
    }
}
