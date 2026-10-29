import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddProductView: View {
    let request: AddProductRequest

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @EnvironmentObject var appState: AppState
    @Query(sort: \ProductCollection.sortOrder) var collections: [ProductCollection]
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @Query(sort: \Product.createdAt, order: .reverse) var products: [Product]

    enum Mode: String, CaseIterable, Identifiable {
        case link = "Pegar enlace"
        case photos = "Subir fotos"
        case search = "Búsqueda"
        var id: String { rawValue }
    }

    enum DetectStatus: Equatable {
        case idle, working
        case success(String)
        case warning(String)
        case error(String)
    }

    @State var mode: Mode = .link
    @State var draft = ProductDraft()
    @State var linkText = ""
    @State var status: DetectStatus = .idle
    @State var saveToCollection = true
    @State var showDetails = false
    @State var duplicate: Product?
    @State var showCollectionPicker = false
    @State var searchText = ""
    @State var didPrefill = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modeSelector
                    switch mode {
                    case .link: linkSection
                    case .photos: photosSection
                    case .search: searchSection
                    }
                    if mode != .search {
                        collectionSection
                        notesSection
                        detailsSection
                    }
                }
                .padding(Theme.hPadding)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Agregar producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(.white)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if mode != .search {
                    Button("Guardar producto") { attemptSave() }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: canSave))
                        .disabled(!canSave)
                        .padding(.horizontal, Theme.hPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .background(Theme.background.opacity(0.96))
                }
            }
            .withAppRoutes()
            .alert("Producto duplicado", isPresented: Binding(
                get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }
            ), presenting: duplicate) { existing in
                Button("Guardar de todos modos") { save() }
                Button("Cancelar", role: .cancel) {}
            } message: { existing in
                Text("Ya guardaste “\(existing.displayName)” con este mismo enlace el \(DateText.short(existing.createdAt)).")
            }
            .sheet(isPresented: $showCollectionPicker) {
                CollectionMultiPicker(selection: $draft.collectionIDs)
            }
        }
        .interactiveDismissDisabled(draft.hasContent)
        .onAppear(perform: prefill)
    }

    private var canSave: Bool { draft.hasContent && status != .working }

    // MARK: Selector de método

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(mode == m ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(mode == m ? Color.white : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
        .sensoryFeedback(.selection, trigger: mode)
    }

    // MARK: Método 1 — enlace

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: $linkText,
                          prompt: Text("Pega el link de Taobao, Weidian, 1688, Yupoo, Hipobuy…\nhttps://...")
                            .foregroundColor(Theme.textSecondary.opacity(0.7)),
                          axis: .vertical)
                    .lineLimit(2...5)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .font(.system(size: 15))
                HStack {
                    Spacer()
                    Button {
                        if let s = UIPasteboard.general.string { linkText = s }
                    } label: {
                        Label("Pegar", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Theme.search, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                detect()
            } label: {
                HStack(spacing: 8) {
                    if status == .working { ProgressView().tint(.white) }
                    Text(status == .working ? "Detectando…" : "Detectar información")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(linkText.trimmed.isEmpty || status == .working)

            statusMessage
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch status {
        case .idle, .working:
            EmptyView()
        case .success(let message):
            messageRow(message, symbol: "checkmark.circle.fill", color: Theme.green)
        case .warning(let message):
            messageRow(message, symbol: "exclamationmark.triangle.fill", color: .orange)
        case .error(let message):
            messageRow(message, symbol: "xmark.octagon.fill", color: Theme.red)
        }
    }

    private func messageRow(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Método 2 — fotos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Elige capturas o fotos de tu galería. Puedes guardar el producto aunque todavía no tenga enlace.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            DraftImagesEditor(images: $draft.images, defaultKind: .manual)
            FormTextField(label: "Nombre", text: $draft.name, placeholder: "Ej. Chaqueta que vi en TikTok")
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Método 3 — búsqueda en lo guardado

    private var searchSection: some View {
        let results = searchText.trimmed.isEmpty ? [] : products.filter { SearchMatcher.matches($0, query: searchText) }
        return VStack(alignment: .leading, spacing: 12) {
            SearchBar(text: $searchText, placeholder: "Buscar en tus productos guardados…")
            Text("Por ahora la búsqueda funciona sobre tu catálogo. La búsqueda en tiendas externas se añadirá cuando haya un servicio compatible.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            if !searchText.trimmed.isEmpty && results.isEmpty {
                EmptyStateView(symbol: "magnifyingglass", title: "Sin resultados",
                               message: "No tienes productos guardados que coincidan.")
            }
            ForEach(results.prefix(50)) { p in
                NavigationLink(value: AppRoute.product(p)) { SavedRow(product: p) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Colección, notas y detalles

    private var selectedCollectionNames: String {
        let names = collections.filter { draft.collectionIDs.contains($0.persistentModelID) }.map(\.name)
        return names.isEmpty ? "Elegir colección" : names.joined(separator: ", ")
    }

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $saveToCollection) {
                Text("Guardar en colección")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .tint(Theme.blue)
            if saveToCollection {
                Button { showCollectionPicker = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 34, height: 34)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
                        Text(selectedCollectionNames)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(10)
                    .background(Theme.search, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesSection: some View {
        FormTextField(label: "Notas (opcional)", text: $draft.notes,
                      placeholder: "Añade notas, tallas, colores, etc...", multiline: true)
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
            } label: {
                HStack {
                    Text("Detalles del producto")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(showDetails ? "Ocultar" : "Editar")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.blue)
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.blue)
                }
            }
            .buttonStyle(.plain)

            if !showDetails {
                Text(detailsSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ProductFormFields(draft: $draft, categories: categories, showsNotes: false,
                                  showsPhotos: mode != .photos)
            }
        }
    }

    private var detailsSummary: String {
        var parts: [String] = []
        if !draft.name.trimmed.isEmpty { parts.append(draft.name) }
        if let price = draft.priceText.parsedNumber { parts.append(Money.format(price, code: draft.currency)) }
        if !draft.categoryKey.isEmpty { parts.append(CategoryCatalog.name(draft.categoryKey, in: categories)) }
        if !draft.images.isEmpty { parts.append("\(draft.images.count) foto\(draft.images.count == 1 ? "" : "s")") }
        return parts.isEmpty
            ? "Nombre, marca, categoría, precio, vendedor, talla, color, material y estado."
            : parts.joined(separator: " · ")
    }

    // MARK: Acciones

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        if let id = request.collectionID {
            draft.collectionIDs = [id]
        } else if let first = collections.first {
            draft.collectionIDs = [first.persistentModelID]
        }
        if !request.prefillURL.trimmed.isEmpty {
            linkText = request.prefillURL
            detect()
        }
    }

    @MainActor
    private func detect() {
        guard let url = LinkImportService.cleanURL(linkText) else {
            status = .error("Ese enlace no parece válido. Revisa que empiece por https://")
            return
        }
        linkText = url.absoluteString
        if let agent = LinkImportService.agentName(for: url) {
            if !draft.agentLinks.contains(where: { $0.url == url.absoluteString }) {
                draft.agentLinks.insert(AgentLink(name: agent, url: url.absoluteString), at: 0)
            }
            if let original = LinkImportService.embeddedOriginalURL(url) { draft.originalURL = original.absoluteString }
        } else {
            draft.originalURL = url.absoluteString
        }
        draft.platform = draft.platform.trimmed.isEmpty ? LinkImportService.platformName(for: url) : draft.platform
        status = .working

        Task { @MainActor in
            do {
                let info = try await LinkImportService.fetch(url)
                let images = await LinkImportService.downloadImages(info.imageURLs)
                draft.apply(info, images: images)
                if info.foundSomething {
                    status = .success("Información detectada. Revisa los datos antes de guardar.")
                } else {
                    status = .warning("La página no compartió nombre, precio ni fotos. Completa los datos manualmente.")
                }
            } catch {
                status = .warning("No se pudo leer la página (\(error.localizedDescription)). Puedes completar los datos manualmente.")
            }
            if draft.categoryKey.isEmpty, let guess = CategoryCatalog.guessKey(from: draft.name) {
                draft.categoryKey = guess
            }
            withAnimation { showDetails = true }
        }
    }

    private func attemptSave() {
        let key = draft.duplicateKey
        if !key.isEmpty, let existing = products.first(where: { $0.normalizedURL == key }) {
            duplicate = existing
            return
        }
        save()
    }

    private func save() {
        var final = draft
        if final.categoryKey.isEmpty { final.categoryKey = "otros" }
        if !saveToCollection { final.collectionIDs = [] }
        let product = Product()
        context.insert(product)
        final.write(to: product, context: context, collections: collections)
        do {
            try context.save()
            appState.showToast("Producto guardado")
            dismiss()
        } catch {
            status = .error("No se pudo guardar: \(error.localizedDescription)")
        }
    }
}

/// Selección múltiple de colecciones para un producto nuevo.
struct CollectionMultiPicker: View {
    @Binding var selection: Set<PersistentIdentifier>
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @Query(sort: \ProductCollection.sortOrder) var collections: [ProductCollection]
    @State var showCreate = false
    @State var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections) { c in
                    let id = c.persistentModelID
                    Button {
                        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                    } label: {
                        HStack {
                            Text(c.name).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection.contains(id) ? Theme.blue : Theme.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Label("Nueva colección", systemImage: "plus").foregroundStyle(Theme.blue)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Colecciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }.foregroundStyle(Theme.blue)
                }
            }
            .alert("Nueva colección", isPresented: $showCreate) {
                TextField("Nombre", text: $newName)
                Button("Crear") {
                    let name = newName.trimmed
                    guard !name.isEmpty else { return }
                    let c = ProductCollection(name: name, sortOrder: (collections.map(\.sortOrder).max() ?? 0) + 1)
                    context.insert(c)
                    try? context.save()
                    selection.insert(c.persistentModelID)
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }
}
