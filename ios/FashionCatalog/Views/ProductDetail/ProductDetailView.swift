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
    @State var pageToOpen: URL?
    @ObservedObject private var backfill = PhotoBackfill.shared

    private var images: [ProductImage] { product.orderedImages }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery
                VStack(alignment: .leading, spacing: 16) {
                    if PhotoBackfill.needsPhotos(product), !PhotoBackfill.pages(for: product).isEmpty { photoStatusCard }
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
        .sheet(item: $pageToOpen) { url in
            StorePageSheet(url: url) {
                pageToOpen = nil
                Task { await backfill.retryNow(product, context: context) }
            }
        }
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

    // MARK: Fotos pendientes

    /// Estado de la búsqueda automática de fotos del anuncio (solo si el producto aún no tiene ninguna).
    private var photoStatusCard: some View {
        let state = backfill.state(for: product)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if state?.working == true { ProgressView().tint(.white) } else { Image(systemName: "photo.badge.arrow.down") }
                Text(state?.working == true ? "Buscando fotos del anuncio…" : "Fotos del anuncio pendientes")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            if let state, !state.working {
                if !state.reason.isEmpty {
                    Text(state.reason).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                Text("Nuevo intento automático \(state.nextTry.formatted(.relative(presentation: .named))).")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            } else if state == nil {
                Text("Wearlist las buscará en la página de la tienda en unos segundos.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            if let choices = state?.choices, !choices.isEmpty, state?.working != true {
                Text("¿Cuál es tu modelo?").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(choices) { choice in
                            Button { Task { await backfill.choose(choice, for: product, context: context) } } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    AsyncImage(url: choice.image) { $0.resizable().scaledToFill() } placeholder: { Theme.background }
                                        .frame(width: 96, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(choice.name).font(.system(size: 11)).foregroundStyle(.white).lineLimit(2)
                                    if let price = choice.price {
                                        Text(Money.format(price, code: "CNY")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .frame(width: 96, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Reintentar") { Task { await backfill.retryNow(product, context: context) } }
                    .disabled(state?.working == true)
                if let page = PhotoBackfill.pages(for: product).first {
                    Button("Abrir página") { pageToOpen = page }
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.blue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Información principal

    private var titleAndPrice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let price = product.priceCurrent {
                    Text(Money.format(price, code: product.currency))
                        .font(.system(size: 26, weight: .bold))
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
                    Text("Precio no disponible")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if let rating = product.sellerRating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(Theme.star)
                        Text(String(format: "%.1f", rating)).foregroundStyle(.white)
                    }
                    .font(.system(size: 14, weight: .medium))
                }
            }
            if let price = product.priceCurrent, product.currency != "USD" {
                let _ = ratesVersion
                if let usd = Money.toUSD(price, code: product.currency) {
                    Text("≈ " + Money.format(usd, code: "USD") + " USD")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, -4)
                }
            }
            Text(product.displayName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !product.brand.trimmed.isEmpty {
                Text(product.brand.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Tienda de origen para "Comprar": el enlace original y, si falta, el primer agente.
    private var buyURL: URL? {
        validURL(product.originalURL) ?? product.agentLinks.lazy.compactMap { validURL($0.url) }.first
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
        let seller = product.sellerName.trimmed
        let shown = seller.isEmpty ? (product.platform.trimmed.isEmpty ? "Sin especificar" : product.platform) : seller
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Vendedor")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Text(String(shown.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent.opacity(0.35), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(shown)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !seller.isEmpty, !product.platform.trimmed.isEmpty {
                        Text(product.platform)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 4)
                if let url = buyURL {
                    Button { openURL(url) } label: {
                        HStack(spacing: 3) {
                            Text("Visitar")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(links) { link in
                        AgentButton(title: link.name, symbol: "bag.fill") {
                            if let url = validURL(link.url) { openURL(url) }
                        }
                    }
                    AgentButton(title: "Copiar enlace", symbol: "doc.on.doc") {
                        UIPasteboard.general.string = original?.absoluteString ?? links.first?.url ?? ""
                        appState.showToast("Enlace copiado")
                    }
                    .disabled(original == nil && links.isEmpty)
                    .opacity(original == nil && links.isEmpty ? 0.4 : 1)
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
        let url = buyURL
        return HStack(spacing: 10) {
            Button {
                if let url { openURL(url) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bag")
                    Text(url == nil ? "Sin enlace de tienda" : "Comprar")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: url != nil))
            .disabled(url == nil)

            Button { showCollections = true } label: {
                Image(systemName: count > 0 ? "folder.fill" : "folder.badge.plus")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(count == 0 ? "Guardar en colección" : "En \(count) colecciones")

            if let share = validURL(product.originalURL) {
                ShareLink(item: share) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
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
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 96, minHeight: 40)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
