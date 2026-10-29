import SwiftUI
import SwiftData

/// "Más": todas las categorías disponibles.
struct AllCategoriesView: View {
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @Query(sort: \Product.createdAt, order: .reverse) var products: [Product]

    var body: some View {
        let counts = Dictionary(grouping: products, by: \.categoryKey).mapValues(\.count)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(categories) { category in
                        NavigationLink(value: AppRoute.category(key: category.key, subcategory: nil)) {
                            VStack(alignment: .leading, spacing: 4) {
                                CategoryTile(
                                    title: category.name,
                                    image: products.first { $0.categoryKey == category.key && $0.coverImage != nil }?.coverImage,
                                    symbol: category.symbol,
                                    aspect: 0.9
                                )
                                Text("\(counts[category.key] ?? 0) productos")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                NavigationLink(value: AppRoute.categoriesManager) {
                    Label("Administrar categorías", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Theme.hPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Categorías")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Crear, editar y ocultar categorías. Las del sistema no se borran, pero se pueden ampliar.
struct CategoriesManagerView: View {
    @Environment(\.modelContext) var context
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @Query var products: [Product]

    @State var showCreate = false
    @State var newName = ""
    @State var newGroup: QuickGroup = .accessories
    @State var pendingDelete: CatalogCategory?

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    NavigationLink(value: AppRoute.categoryEditor(category)) {
                        HStack(spacing: 12) {
                            Image(systemName: category.symbol)
                                .frame(width: 28)
                                .foregroundStyle(Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name).foregroundStyle(.white)
                                Text("\(category.group.label) · \(category.subcategories.count) subcategorías")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if !category.showOnHome {
                                Image(systemName: "eye.slash").foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)
                    .swipeActions {
                        if !category.isBuiltIn {
                            Button(role: .destructive) { pendingDelete = category } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove { from, to in
                    var ordered = categories
                    ordered.move(fromOffsets: from, toOffset: to)
                    for (i, c) in ordered.enumerated() { c.sortOrder = i }
                    try? context.save()
                }
            } footer: {
                Text("Las 7 primeras categorías visibles aparecen en Inicio. Mantén pulsado y arrastra para reordenar.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Categorías")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().foregroundStyle(Theme.blue) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = ""; showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                Form {
                    TextField("Nombre (por ejemplo, Perfumes)", text: $newName)
                    Picker("Grupo", selection: $newGroup) {
                        ForEach(QuickGroup.allCases.filter { $0 != .all }) { Text($0.label).tag($0) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .navigationTitle("Nueva categoría")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { showCreate = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Crear") { create() }.disabled(newName.trimmed.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("¿Eliminar categoría?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { category in
            Button("Eliminar y mover sus productos a Otros", role: .destructive) {
                for p in products where p.categoryKey == category.key { p.categoryKey = "otros" }
                context.delete(category)
                try? context.save()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func create() {
        let name = newName.trimmed
        guard !name.isEmpty else { return }
        let key = CategoryCatalog.makeKey(from: name, existing: categories)
        context.insert(CatalogCategory(
            key: key, name: name, symbol: "tag", group: newGroup, subcategories: [],
            sortOrder: (categories.map(\.sortOrder).max() ?? 0) + 1, isBuiltIn: false
        ))
        try? context.save()
        showCreate = false
    }
}

struct CategoryEditView: View {
    @Bindable var category: CatalogCategory
    @Environment(\.modelContext) var context
    @State var newSub = ""

    let symbols = ["tag", "tshirt", "handbag", "bag", "shoe.2", "sparkle", "sparkles", "clock",
                           "eyeglasses", "baseball", "wind", "crown", "gift", "drop", "star", "heart",
                           "square.grid.2x2", "figure.walk"]

    var body: some View {
        Form {
            Section("General") {
                if category.isBuiltIn {
                    LabeledContent("Nombre", value: category.name)
                } else {
                    TextField("Nombre", text: $category.name)
                }
                Picker("Grupo", selection: Binding(get: { category.group }, set: { category.group = $0 })) {
                    ForEach(QuickGroup.allCases.filter { $0 != .all }) { Text($0.label).tag($0) }
                }
                Toggle("Mostrar en Inicio", isOn: $category.showOnHome)
                Picker("Icono", selection: $category.symbol) {
                    ForEach(symbols, id: \.self) { s in
                        Label(s, systemImage: s).labelStyle(.iconOnly).tag(s)
                    }
                }
            }
            .listRowBackground(Theme.card)

            Section("Subcategorías") {
                ForEach(category.subcategories, id: \.self) { sub in
                    Text(sub)
                }
                .onDelete { category.subcategories.remove(atOffsets: $0) }
                .onMove { category.subcategories.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("Nueva subcategoría", text: $newSub)
                        .onSubmit(addSub)
                    Button("Añadir", action: addSub)
                        .disabled(newSub.trimmed.isEmpty)
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear { try? context.save() }
    }

    private func addSub() {
        let s = newSub.trimmed
        guard !s.isEmpty, !category.subcategories.contains(where: { $0.equalsLoose(s) }) else { return }
        category.subcategories.append(s)
        newSub = ""
    }
}
