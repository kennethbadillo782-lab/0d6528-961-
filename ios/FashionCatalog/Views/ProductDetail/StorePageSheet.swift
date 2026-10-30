import SwiftUI
import WebKit

/// Página de la tienda dentro de Wearlist. Comparte cookies con la búsqueda automática de fotos:
/// si la tienda pide iniciar sesión o una verificación, se hace aquí una vez.
struct StorePageSheet: View {
    let url: URL
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            StoreWebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host ?? "Tienda")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Listo, buscar fotos") { onDone() } }
                }
        }
    }
}

private struct StoreWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = LinkImportService.userAgent
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
