import SwiftUI
import SwiftData

@main
struct FashionCatalogApp: App {
    let container: ModelContainer
    @StateObject var appState = AppState()

    init() {
        AppearanceConfigurator.configure()
        UserDefaults.standard.register(defaults: [
            SettingsKeys.showUSD: true,
            SettingsKeys.hideDiscarded: false
        ])
        do {
            container = try ModelContainer(
                for: Product.self, ProductImage.self, ProductCollection.self, CatalogCategory.self, CloudSyncEntry.self, CloudRemoteCache.self
            )
        } catch {
            fatalError("No se pudo abrir la base de datos local: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

enum SettingsKeys {
    static let showUSD = "showUSD"
    static let hideDiscarded = "hideDiscarded"
    static let ratesVersion = "ratesVersion"
}
