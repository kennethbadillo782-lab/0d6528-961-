import SwiftUI
import SwiftData
import UIKit

struct ProductDetailView: View {
    @Bindable var product: Product

    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @EnvironmentObject var appState: AppState
    @Query(sort: \CatalogCategory.sortOrder) var categories: [CatalogCategory]
    @AppStorage(SettingsKeys.ratesVersion) var ratesVersion = 0

    @State var selectedIndex = 0
    @State var showViewer = false
    @State var showEditor = false
    @State var showCollections = false
    @State var confirmDelete = false

    private var images: [ProductImage] { product.orderedImages }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery
                VStack(alignment: .leading, spacing: 16) {
                    titleAndPrice
                    tags
                    costSummary
                    sellerCard
                    agentsCard
                    personalCard
                    if !product.productDescription.trimmed.isEmpty { descriptionCard }
                    attributesCard
                    footer
                }
                .padding(.horizontal, Theme.hPadding)
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Producto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                HeartButton(isOn: product.isFavorite, size: 18) {
                    product.isFavorite.toggle()
                    product.touch()
                }
                Menu {
                    Button { showEditor = true } label: { Label("Editar producto", systemImage: "pencil") }
                    Button { showCollections = true } label: { Label("Colecciones", systemImage: "folder") }
                    if let url = validURL(product.originalURL) {
                        ShareLink(item: url) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Eliminar producto", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.white)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $showEditor) { ProductEditorView(product: product) }
        .sheet(isPresented: $showCollections) { CollectionPickerSheet(product: product) }
        .fullScreenCover(isPresented: $showViewer) {
            ImageViewer(images: images, index: $selectedIndex)
        }
        .confirmationDialog("¿Eliminar este producto?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar producto", role: .destructive) { deleteProduct() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrarán sus fotos, enlaces y notas. Esta acción no se puede deshacer.")
        }
        .onChange(of: product.statusRaw) { _, _ in product.touch() }
        .onChange(of: product.priorityRaw) { _, _ in product.touch() }
    }

    // MARK: Galería

    private var gallery: some View {
        ZStack(alignment: .bottom) {
            Group {
                if images.isEmpty {
                    ImagePlaceholder(symbol: CategoryCatalog.symbol(product.categoryKey, in: categories),
                                     caption: "Sin fotos todavía")
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                            CatalogImage(image: image, maxPixel: 1400)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture { showViewer = true }
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .frame(height: 360)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                if images.indices.contains(selectedIndex), images[selectedIndex].kind != .official {
                    Text(images[selectedIndex].kind.longLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .padding(12)
                }
            }
            .overlay(alignment: .topTrailing) {
                if product.isDemo { DemoBadge().padding(12) }
            }

            if images.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedIndex = index }
                            } label: {
                                CatalogImage(image: image, maxPixel: 180)
                                    .frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(index == selectedIndex ? Color.white : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: Información principal

    private var titleAndPrice: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !product.brand.trimmed.isEmpty {
                Text(product.brand.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(product.displayName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let price = product.priceCurrent {
                    Text(Money.format(price, code: product.currency))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    if let previous = product.pricePrevious, product.discountPercent != nil {
                        Text(Money.format(previous, code: product.currency))
                            .font(.system(size: 14))
                            .strikethrough()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let pct = product.discountPercent {
                        Text("-\(pct)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text("Sin precio guardado")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var tags: some View {
        let hasQuality = !product.declaredQuality.trimmed.isEmpty
        let others = [product.material, product.color, product.size.isEmpty ? "" : "Talla \(product.size)",
                      product.includedAccessories, product.subcategory].map(\.trimmed).filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            if hasQuality || !others.isEmpty || !product.verifiedQuality.trimmed.isEmpty {
                FlowLayout(spacing: 8) {
                    if hasQuality {
                        TagChip(text: product.declaredQuality, tint: Theme.green, filled: true)
                    }
                    if !product.verifiedQuality.trimmed.isEmpty {
                        TagChip(text: "✓ " + product.verifiedQuality, tint: Theme.blue, filled: true)
                    }
                    ForEach(others, id: \.self) { TagChip(text: $0) }
                }
            }
            if hasQuality {
                Text("La calidad en verde es lo que declara el vendedor; la app no la garantiza.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private var costSummary: some View {
        let _ = ratesVersion
        if let price = product.priceCurrent {
            let usd = Money.toUSD(price, code: product.currency)
            let rate = Money.rate(for: product.currency)
            let shipping = product.shippingEstimateUSD
            if product.currency != "USD" || shipping != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if product.currency != "USD" {
                        if let usd, let rate {
                            infoRow("Equivalente", "≈ " + Money.format(usd, code: "USD"))
                            Text("Tasa \(product.currency)→USD actualizada el \(DateText.short(rate.updated))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        } else {
                            Text("No hay tasa de cambio para \(product.currency). Puedes añadirla en Cuenta › Moneda.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if let shipping {
                        infoRow("Envío estimado", Money.format(shipping, code: "USD"))
                        if let usd {
                            infoRow("Costo final estimado", "≈ " + Money.format(usd + shipping, code: "USD"), bold: true)
                        }
                    }
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var sellerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Vendedor")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(product.sellerName.trimmed.isEmpty ? "Sin especificar" : product.sellerName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if !product.platform.trimmed.isEmpty {
                        Text(product.platform)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if let rating = product.sellerRating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating)).foregroundStyle(.white)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.leading, 8)
                }
            }
            if product.sellerRating != nil, !product.sellerRatingSource.trimmed.isEmpty {
                Text("Valoración según: \(product.sellerRatingSource)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var agentsCard: some View {
        let links = product.agentLinks.filter { validURL($0.url) != nil }
        let original = validURL(product.originalURL)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Abrir en\nagente")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 54, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(links) { link in
                            AgentButton(title: link.name, symbol: "bag") {
                                if let url = validURL(link.url) { openURL(url) }
                            }
                        }
                        if let original {
                            AgentButton(title: "Original", symbol: "safari") { openURL(original) }
                        }
                        AgentButton(title: "Copiar", symbol: "doc.on.doc") {
                            UIPasteboard.general.string = original?.absoluteString ?? links.first?.url ?? ""
                            appState.showToast("Enlace copiado")
                        }
                        .disabled(original == nil && links.isEmpty)
                        .opacity(original == nil && links.isEmpty ? 0.4 : 1)
                    }
                }
            }
            if links.isEmpty {
                Text(original == nil
                     ? "Este producto no tiene enlaces guardados. Puedes añadirlos en Editar."
                     : "Sin enlaces de agente guardados. Añádelos en Editar cuando tengas uno.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var personalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Menu {
                Picker("Estado", selection: $product.statusRaw) {
                    ForEach(PurchaseStatus.allCases) { s in
                        Label(s.label, systemImage: s.symbol).tag(s.rawValue)
                    }
                }
            } label: {
                menuRow("Estado", product.status.label)
            }
            Divider().overlay(Theme.border)
            Menu {
                Picker("Prioridad", selection: $product.priorityRaw) {
                    ForEach(PriorityLevel.allCases) { p in Text(p.label).tag(p.rawValue) }
                }
            } label: {
                menuRow("Prioridad", product.priority.label)
            }
            Divider().overlay(Theme.border)
            Button { showEditor = true } label: {
                menuRow("Talla y color", [product.size, product.color].map(\.trimmed).filter { !$0.isEmpty }
                    .joined(separator: " · ").ifEmpty("Sin definir"))
            }
            Divider().overlay(Theme.border)
            Button { showEditor = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Notas personales").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    Text(product.notes.trimmed.isEmpty ? "Añade notas sobre tallas, colores o calidad…" : product.notes)
                        .font(.system(size: 14))
                        .foregroundStyle(product.notes.trimmed.isEmpty ? Theme.textSecondary.opacity(0.7) : .white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Descripción").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text(product.productDescription)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var attributesCard: some View {
        let schema = CategorySchema.forCategory(product.categoryKey)
        let attrs = product.attributes
        let rows: [(String, String)] = attrs.keys.sorted().compactMap { key in
            guard let value = attrs[key], !value.isEmpty else { return nil }
            let def = schema.attribute(key)
            var display = value
            switch def?.kind {
            case .number(let unit): display = "\(value) \(unit)"
            case .millimeters: display = "\(value) mm"
            default: break
            }
            return (def?.label ?? key, display)
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Características").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                ForEach(rows.indices, id: \.self) { i in infoRow(rows[i].0, rows[i].1) }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Categoría: \(CategoryCatalog.name(product.categoryKey, in: categories))"
                 + (product.subcategory.isEmpty ? "" : " › \(product.subcategory)"))
            Text("Guardado el \(DateText.long(product.createdAt))")
            Text("Actualizado el \(DateText.long(product.updatedAt))")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.textSecondary.opacity(0.8))
    }

    private var bottomBar: some View {
        let count = product.collections.count
        return Button {
            showCollections = true
        } label: {
            HStack(spacing: 8) {
                if count > 0 { Image(systemName: "checkmark") }
                Text(count == 0 ? "Guardar en colección"
                     : "Guardado en \(count) colección\(count == 1 ? "" : "es")")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, Theme.hPadding)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.background.opacity(0.96))
    }

    // MARK: Utilidades

    private func infoRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(bold ? .semibold : .regular)
        }
        .font(.system(size: 14))
    }

    private func menuRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func validURL(_ raw: String) -> URL? {
        NetworkSafety.webURL(raw)
    }

    private func deleteProduct() {
        let target = product
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            context.delete(target)
            try? context.save()
        }
    }
}

struct AgentButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 50)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Visor a pantalla completa con zoom

struct ImageViewer: View {
    let images: [ProductImage]
    @Binding var index: Int
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.element.id) { i, image in
                    ZoomableImage(image: image).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Cerrar")
        }
        .statusBarHidden()
    }
}

struct ZoomableImage: View {
    let image: ProductImage
    @State var scale: CGFloat = 1
    @State var lastScale: CGFloat = 1
    @State var offset: CGSize = .zero
    @State var lastOffset: CGSize = .zero

    var body: some View {
        CatalogImage(image: image, maxPixel: 2400, contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 5) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { reset() }
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset },
                including: scale > 1 ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                }
            }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
