import Foundation
import WebKit

/// Abre una página en un navegador invisible (ejecuta su JavaScript) y lee solo la galería principal:
/// las fotos grandes de la parte superior. Comparte las cookies de "Abrir página", así que si la tienda
/// pide iniciar sesión basta con hacerlo una vez desde la ficha del producto.
@MainActor
final class PageRenderer: NSObject, WKNavigationDelegate {
    struct Result { var images: [URL]; var needsLogin: Bool; var blocked: Bool; var finalURL: URL? }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Never>?

    static func render(_ url: URL, wait: Duration = .seconds(4)) async -> Result {
        let renderer = PageRenderer()
        return await renderer.run(url, wait: wait)
    }

    private func run(_ url: URL, wait: Duration) async -> Result {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        web.customUserAgent = LinkImportService.userAgent
        web.navigationDelegate = self
        webView = web
        defer { web.stopLoading(); web.navigationDelegate = nil; webView = nil }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuation = c
            web.load(URLRequest(url: url, timeoutInterval: 20))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.finish()
            }
        }
        // Tiempo para que el JavaScript de la tienda pinte la galería.
        try? await Task.sleep(for: wait)
        let final = web.url
        let text = (try? await web.evaluateJavaScript("document.body ? document.body.innerText.slice(0, 4000) : ''") as? String) ?? ""
        let path = (final?.absoluteString ?? "").lowercased()
        let needsLogin = path.contains("login") || path.contains("passport") || text.contains("请登录") || text.contains("登录后")
            || text.localizedCaseInsensitiveContains("sign in to")
        let blocked = text.contains("验证") && text.contains("滑块") || text.localizedCaseInsensitiveContains("unusual traffic")
            || text.localizedCaseInsensitiveContains("just a moment")
        let raw = (try? await web.evaluateJavaScript(Self.galleryScript) as? [String]) ?? []
        let images = PhotoSources.unique(raw.compactMap { URL(string: $0) }.filter { NetworkSafety.isPublic($0) })
        return Result(images: images, needsLogin: needsLogin, blocked: blocked, finalURL: final)
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish() }
    }

    /// Galería principal: imágenes anchas (≥ 60 % de la pantalla) cuyo borde superior está en la primera
    /// pantalla. Los carruseles colocan sus fotos a la misma altura aunque estén fuera por los lados;
    /// las recomendaciones de otros productos quedan más abajo y se descartan.
    static let galleryScript = """
    (() => {
      const vw = window.innerWidth, vh = window.innerHeight, out = [];
      const add = (u) => { if (u && /^https?:/.test(u) && !out.includes(u)) out.push(u); };
      document.querySelectorAll('img').forEach((img) => {
        const r = img.getBoundingClientRect();
        if (r.width < vw * 0.6 || r.top > vh * 0.9 || r.bottom < 0) return;
        add(img.currentSrc || img.src || img.getAttribute('data-src'));
      });
      document.querySelectorAll('[style*="background-image"]').forEach((el) => {
        const r = el.getBoundingClientRect();
        if (r.width < vw * 0.6 || r.top > vh * 0.9 || r.bottom < 0) return;
        const m = (el.style.backgroundImage || '').match(/url\\(["']?([^"')]+)/);
        if (m) add(new URL(m[1], location.href).href);
      });
      return out.slice(0, 12);
    })()
    """
}
