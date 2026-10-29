import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Campos de formulario con el estilo oscuro

struct FormTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var multiline = false
    var suffix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            HStack {
                TextField("", text: $text,
                          prompt: Text(placeholder).foregroundColor(Theme.textSecondary.opacity(0.6)),
                          axis: multiline ? .vertical : .horizontal)
                    .lineLimit(multiline ? 3...8 : 1...1)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                    .autocorrectionDisabled(keyboard == .URL || keyboard == .decimalPad)
                    .foregroundStyle(.white)
                    .font(.system(size: 15))
                if let suffix {
                    Text(suffix).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.search, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct FormMenuField<Content: View>: View {
    let label: String
    let value: String
    var placeholder = "Seleccionar"
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Menu {
                content()
            } label: {
                HStack {
                    Text(value.isEmpty ? placeholder : value)
                        .foregroundStyle(value.isEmpty ? Theme.textSecondary.opacity(0.6) : .white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.search, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            content()
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Fotos del borrador

struct DraftImagesEditor: View {
    @Binding var images: [DraftImage]
    @State var pickerItems: [PhotosPickerItem] = []
    @State var isLoading = false
    var defaultKind: ImageKind = .manual

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                        VStack(spacing: 6) {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                            }
                            Text("Fotos").font(.system(size: 11))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Theme.search, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }

                    ForEach($images) { $image in
                        DraftThumbnail(image: $image) {
                            images.removeAll { $0.id == image.id }
                        } moveFirst: {
                            if let idx = images.firstIndex(where: { $0.id == image.id }) {
                                let item = images.remove(at: idx)
                                images.insert(item, at: 0)
                            }
                        }
                    }
                }
            }
            if !images.isEmpty {
                Text("Toca una foto para indicar si es oficial, QC, de comprador o puesta. La primera es la portada.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            isLoading = true
            Task {
                let datas = await ImageService.loadPickerItems(items)
                for data in datas { images.append(DraftImage(data: data, kind: defaultKind)) }
                pickerItems = []
                isLoading = false
            }
        }
    }
}

struct DraftThumbnail: View {
    @Binding var image: DraftImage
    var onDelete: () -> Void
    var moveFirst: () -> Void

    var body: some View {
        Menu {
            Picker("Tipo de foto", selection: $image.kind) {
                ForEach(ImageKind.allCases) { Text($0.longLabel).tag($0) }
            }
            Button { moveFirst() } label: { Label("Usar como portada", systemImage: "star") }
            Button(role: .destructive, action: onDelete) { Label("Quitar foto", systemImage: "trash") }
        } label: {
            thumbnail
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(image.kind.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .padding(5)
                }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let existing = image.existing {
            CatalogImage(image: existing, maxPixel: 260)
        } else {
            let data = image.data
            ImageLoaderView(cacheKey: "draft-\(image.id.uuidString)", dataProvider: { data },
                            remoteURL: image.remoteURL, maxPixel: 260)
        }
    }
}

// MARK: - Formulario completo del producto

struct ProductFormFields: View {
    @Binding var draft: ProductDraft
    let categories: [CatalogCategory]
    var showsNotes = true
    var showsPhotos = true

    private var schema: CategorySchema { CategorySchema.forCategory(draft.categoryKey) }
    private var category: CatalogCategory? { CategoryCatalog.category(draft.categoryKey, in: categories) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsPhotos {
                FormSection(title: "Fotos") {
                    DraftImagesEditor(images: $draft.images)
                }
            }

            FormSection(title: "Información") {
                FormTextField(label: "Nombre", text: $draft.name, placeholder: "Ej. Crossbody negra")
                FormTextField(label: "Marca", text: $draft.brand, placeholder: "Opcional")
                HStack(spacing: 10) {
                    FormMenuField(label: "Categoría",
                                  value: draft.categoryKey.isEmpty ? "" : CategoryCatalog.name(draft.categoryKey, in: categories)) {
                        ForEach(categories) { c in
                            Button(c.name) {
                                if draft.categoryKey != c.key {
                                    draft.categoryKey = c.key
                                    draft.subcategory = ""
                                }
                            }
                        }
                    }
                    FormMenuField(label: "Subcategoría", value: draft.subcategory) {
                        Button("Ninguna") { draft.subcategory = "" }
                        ForEach(category?.subcategories ?? [], id: \.self) { sub in
                            Button(sub) { draft.subcategory = sub }
                        }
                    }
                }
                FormTextField(label: "Descripción", text: $draft.productDescription,
                              placeholder: "Opcional", multiline: true)
            }

            FormSection(title: "Precio") {
                HStack(alignment: .bottom, spacing: 10) {
                    FormTextField(label: "Precio actual", text: $draft.priceText, placeholder: "0",
                                  keyboard: .decimalPad)
                    FormMenuField(label: "Moneda", value: draft.currency) {
                        ForEach(Money.supported, id: \.self) { code in
                            Button("\(code) · \(Money.name(for: code))") { draft.currency = code }
                        }
                    }
                    .frame(width: 110)
                }
                FormTextField(label: "Precio anterior (solo si es real)", text: $draft.previousPriceText,
                              placeholder: "Opcional", keyboard: .decimalPad)
                FormTextField(label: "Envío estimado", text: $draft.shippingText, placeholder: "Opcional",
                              keyboard: .decimalPad, suffix: "USD")
            }

            FormSection(title: "Dónde comprarlo") {
                FormTextField(label: "Enlace original", text: $draft.originalURL, placeholder: "https://...",
                              keyboard: .URL)
                FormTextField(label: "Plataforma", text: $draft.platform, placeholder: "Taobao, Weidian, Yupoo…")
                AgentLinksEditor(links: $draft.agentLinks)
            }

            FormSection(title: "Vendedor") {
                FormTextField(label: "Nombre del vendedor", text: $draft.sellerName, placeholder: "Opcional")
                HStack(spacing: 10) {
                    FormTextField(label: "Valoración real", text: $draft.sellerRatingText, placeholder: "Ej. 4.8",
                                  keyboard: .decimalPad)
                    FormTextField(label: "Fuente", text: $draft.sellerRatingSource, placeholder: "Ej. Taobao")
                }
                Text("Deja la valoración vacía si no la has comprobado.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            FormSection(title: "Características") {
                if schema.sizeMode != .noSizes {
                    FormTextField(label: "Talla", text: $draft.size, placeholder: schema.sizeOptions.prefix(4).joined(separator: ", "))
                }
                ColorField(color: $draft.color, palette: schema.palette)
                if schema.usesMaterialField {
                    FormTextField(label: "Material", text: $draft.material, placeholder: "Algodón, cuero…")
                }
                ForEach(schema.attributes) { def in
                    AttributeField(def: def, value: Binding(
                        get: { draft.attributes[def.key] ?? "" },
                        set: { draft.attributes[def.key] = $0 }
                    ))
                }
            }

            FormSection(title: "Calidad") {
                FormTextField(label: "Calidad que declara el vendedor", text: $draft.declaredQuality,
                              placeholder: "Ej. 1:1, Top Quality")
                FormTextField(label: "Calidad que comprobaste tú", text: $draft.verifiedQuality,
                              placeholder: "Ej. QC revisado, costuras bien")
                FormTextField(label: "Accesorios incluidos", text: $draft.includedAccessories,
                              placeholder: "Ej. caja, dust bag, logo")
            }

            FormSection(title: "Organización") {
                HStack(spacing: 10) {
                    FormMenuField(label: "Estado", value: draft.status.label) {
                        ForEach(PurchaseStatus.allCases) { s in
                            Button(s.label) { draft.status = s }
                        }
                    }
                    FormMenuField(label: "Prioridad", value: draft.priority.label) {
                        ForEach(PriorityLevel.allCases) { p in
                            Button(p.label) { draft.priority = p }
                        }
                    }
                }
                Toggle(isOn: $draft.isFavorite) {
                    Text("Favorito").foregroundStyle(.white)
                }
                .tint(Theme.heart)
                if showsNotes {
                    FormTextField(label: "Notas", text: $draft.notes,
                                  placeholder: "Añade notas, tallas, colores, etc...", multiline: true)
                }
            }
        }
    }
}

struct ColorField: View {
    @Binding var color: String
    let palette: [ColorSwatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormTextField(label: "Color", text: $color, placeholder: "Elige abajo o escríbelo")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(palette) { swatch in
                        Button {
                            color = color.equalsLoose(swatch.name) ? "" : swatch.name
                        } label: {
                            ColorDot(swatch: swatch, isSelected: color.equalsLoose(swatch.name), size: 26)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct AttributeField: View {
    let def: AttributeDef
    @Binding var value: String

    var body: some View {
        switch def.kind {
        case .options:
            FormMenuField(label: def.label, value: value) {
                Button("Sin especificar") { value = "" }
                ForEach(def.options, id: \.self) { option in
                    Button(option) { value = option }
                }
            }
        case .text:
            FormTextField(label: def.label, text: $value, placeholder: "Opcional")
        case .number(let unit):
            FormTextField(label: def.label, text: $value, placeholder: "0", keyboard: .decimalPad, suffix: unit)
        case .millimeters:
            FormTextField(label: def.label, text: $value, placeholder: "Ej. 6.5", keyboard: .decimalPad, suffix: "mm")
        }
    }
}

struct AgentLinksEditor: View {
    @Binding var links: [AgentLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enlaces de agente")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            ForEach($links) { $link in
                HStack(spacing: 8) {
                    Menu {
                        ForEach(LinkImportService.agentNames, id: \.self) { name in
                            Button(name) { link.name = name }
                        }
                        Button("Otro") { link.name = "Agente" }
                    } label: {
                        Text(link.name.isEmpty ? "Agente" : link.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(width: 86, height: 40)
                            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    TextField("", text: $link.url, prompt: Text("Enlace del agente").foregroundColor(Theme.textSecondary.opacity(0.6)))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                        .font(.system(size: 14))
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .background(Theme.search, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button {
                        links.removeAll { $0.id == link.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                links.append(AgentLink(name: "Hipobuy", url: ""))
            } label: {
                Label("Añadir enlace de agente", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.blue)
            }
            .buttonStyle(.plain)
            Text("Pega el enlace real que te da cada agente. La app no genera enlaces por su cuenta.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Edición de un producto existente

struct ProductEditorView: View {
    let product: Product
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @EnvironmentObject var appState: AppState
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @Query(sort: \ProductCollection.sortOrder) var collections: [ProductCollection]
    @State var draft = ProductDraft()
    @State var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ProductFormFields(draft: $draft, categories: categories)
                    .padding(Theme.hPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Editar producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        draft.write(to: product, context: context, collections: collections)
                        try? context.save()
                        appState.showToast("Cambios guardados")
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.blue)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !loaded else { return }
            draft = ProductDraft(product: product)
            loaded = true
        }
    }
}
