import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AccountView: View {
    @Environment(\.modelContext) var context
    @EnvironmentObject var appState: AppState
    @Query var products: [Product]
    @Query var collections: [ProductCollection]

    @AppStorage(SettingsKeys.showUSD) var showUSD = true
    @AppStorage(SettingsKeys.hideDiscarded) var hideDiscarded = false
    @AppStorage(SettingsKeys.ratesVersion) var ratesVersion = 0

    @State var updatingRates = false
    @State var ratesMessage: String?
    @State var editingCurrency: String?
    @State var rateText = ""
    @State var exportDocument: BackupDocument?
    @State var showExporter = false
    @State var showImporter = false
    @State var backupMessage: String?
    @State var confirmRemoveDemo = false

    private var userProducts: [Product] { products.filter { !$0.isDemo } }
    private var demoCount: Int { products.count - userProducts.count }
    private var usedCurrencies: [String] {
        let used = Set(products.map(\.currency)).subtracting(["USD"])
        let base = ["CNY"] + used.sorted().filter { $0 != "CNY" }
        return base
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Cuenta")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 6)

                summary
                currencyCard
                catalogCard
                displayCard
                backupCard
                syncCard
                ChatGPTAccessView()
                aboutCard
            }
            .padding(.horizontal, Theme.hPadding)
            .padding(.bottom, 28)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("Tasa \(editingCurrency ?? "") → USD", isPresented: Binding(
            get: { editingCurrency != nil }, set: { if !$0 { editingCurrency = nil } }
        )) {
            TextField("USD por 1 \(editingCurrency ?? "")", text: $rateText)
                .keyboardType(.decimalPad)
            Button("Guardar") {
                if let code = editingCurrency { Money.setRate(rateText.parsedNumber, for: code) }
            }
            Button("Quitar tasa", role: .destructive) {
                if let code = editingCurrency { Money.setRate(nil, for: code) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ejemplo: si 1 \(editingCurrency ?? "") equivale a 0.14 USD, escribe 0.14.")
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: "MiCatalogo-\(DateText.short(Date()).replacingOccurrences(of: " ", with: "-"))") { result in
            switch result {
            case .success: backupMessage = "Copia exportada correctamente."
            case .failure(let error): backupMessage = "No se pudo exportar: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .confirmationDialog("¿Quitar los productos de ejemplo?", isPresented: $confirmRemoveDemo,
                            titleVisibility: .visible) {
            Button("Quitar \(demoCount) ejemplos", role: .destructive) { DemoData.remove(from: context) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Tus productos reales no se tocan.")
        }
    }

    // MARK: Tarjetas

    private var summary: some View {
        HStack(spacing: 10) {
            stat("\(userProducts.count)", "Productos")
            stat("\(collections.count)", "Colecciones")
            stat("\(userProducts.filter { $0.status == .purchased }.count)", "Comprados")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var currencyCard: some View {
        AccountCard(title: "Moneda", symbol: "dollarsign.circle") {
            row("Moneda principal", value: "USD ($)")
            Toggle(isOn: $showUSD) {
                Text("Mostrar equivalente en USD").foregroundStyle(.white).font(.system(size: 15))
            }
            .tint(Theme.blue)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tasas de cambio")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(usedCurrencies, id: \.self) { code in
                    Button {
                        rateText = Money.rate(for: code).map { String(format: "%.4f", $0.value) } ?? ""
                        editingCurrency = code
                    } label: {
                        HStack {
                            Text("\(Money.symbol(for: code).trimmed) \(code)")
                                .foregroundStyle(.white)
                            Spacer()
                            if let rate = Money.rate(for: code) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("1 \(code) = $\(String(format: "%.4f", rate.value))")
                                        .foregroundStyle(.white)
                                    Text("Actualizada el \(DateText.short(rate.updated))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            } else {
                                Text("Sin tasa").foregroundStyle(Theme.textSecondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(.system(size: 14))
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .id(ratesVersion)
            }

            Button {
                updateRates()
            } label: {
                HStack(spacing: 8) {
                    if updatingRates { ProgressView().tint(.white) }
                    Text(updatingRates ? "Actualizando…" : "Actualizar tasas en línea")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(updatingRates)

            note(ratesMessage ?? "Tasas de referencia del Banco Central Europeo (frankfurter.dev). Si no hay tasa, se muestra solo el precio original.")
        }
    }

    private var catalogCard: some View {
        AccountCard(title: "Catálogo", symbol: "square.grid.2x2") {
            NavigationLink(value: AppRoute.categoriesManager) {
                row("Categorías y subcategorías", value: "", chevron: true)
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.border)
            if demoCount > 0 {
                Button { confirmRemoveDemo = true } label: {
                    row("Quitar productos de ejemplo", value: "\(demoCount)", chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    DemoData.insert(into: context)
                    appState.showToast("Ejemplos cargados")
                } label: {
                    row("Cargar productos de ejemplo", value: "", chevron: true)
                }
                .buttonStyle(.plain)
            }
            note("Los ejemplos llevan la etiqueta “Ejemplo”, no se exportan y se pueden quitar en cualquier momento.")
        }
    }

    private var displayCard: some View {
        AccountCard(title: "Visualización", symbol: "eye") {
            row("Apariencia", value: "Oscura")
            Toggle(isOn: $hideDiscarded) {
                Text("Ocultar descartados en el catálogo").foregroundStyle(.white).font(.system(size: 15))
            }
            .tint(Theme.blue)
            note("Los descartados siguen visibles en Guardados.")
        }
    }

    private var backupCard: some View {
        AccountCard(title: "Copia de seguridad", symbol: "externaldrive") {
            Button("Exportar productos (JSON)") { exportBackup() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Importar productos") { showImporter = true }
                .buttonStyle(SecondaryButtonStyle())
            note(backupMessage ?? "Incluye fotos, colecciones y categorías. Al importar, los productos que ya tienes no se duplican.")
        }
    }

    private var syncCard: some View { CloudAccountView() }

    private var aboutCard: some View {
        AccountCard(title: "Acerca de", symbol: "info.circle") {
            row("Versión", value: appVersion)
            note("Mi Catálogo de Moda es un catálogo personal: no vende productos ni procesa pagos. Las marcas se usan solo como filtros de tu propio catálogo y las calidades que indican los vendedores no están verificadas por la app.")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: Piezas

    private func row(_ label: String, value: String, chevron: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.white)
            Spacer()
            Text(value).foregroundStyle(Theme.textSecondary)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 15))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Acciones

    private func updateRates() {
        updatingRates = true
        Task { @MainActor in
            do {
                let date = try await Money.fetchRates()
                ratesMessage = "Tasas actualizadas (referencia del \(DateText.short(date)))."
            } catch {
                ratesMessage = "No se pudieron actualizar las tasas: \(error.localizedDescription). Puedes introducirlas a mano tocando cada moneda."
            }
            updatingRates = false
        }
    }

    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.makeBackup(context: context))
            showExporter = true
        } catch {
            backupMessage = "No se pudo preparar la copia: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            backupMessage = "No se pudo abrir el archivo: \(error.localizedDescription)"
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= 300_000_000 else {
                    backupMessage = "El archivo es demasiado grande para ser una copia de Mi Catálogo."
                    return
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let outcome = try BackupService.restore(data, context: context)
                backupMessage = "Importados \(outcome.added) productos. \(outcome.skipped) ya existían y se omitieron."
            } catch {
                // Una importación fallida no deja el catálogo a medias.
                context.rollback()
                backupMessage = "El archivo no es una copia válida de Mi Catálogo."
            }
        }
    }
}

struct AccountCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
