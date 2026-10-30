import SwiftUI
import UIKit
import ImageIO
import PhotosUI

/// Caché en memoria + reducción de tamaño para que las cuadrículas con miles de fotos sigan fluidas.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

enum ImageService {
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Guarda las fotos con un tamaño razonable (máx. 2048 px) para no llenar el iPhone.
    static func prepareForStorage(_ data: Data, maxPixel: CGFloat = 2048) -> Data? {
        downsample(data, maxPixel: maxPixel)?.jpegData(compressionQuality: 0.85)
    }

    static func loadPickerItems(_ items: [PhotosPickerItem]) async -> [Data] {
        var result: [Data] = []
        for item in items {
            if let raw = try? await item.loadTransferable(type: Data.self) {
                let prepared = await Task.detached(priority: .userInitiated) {
                    ImageService.prepareForStorage(raw)
                }.value
                if let prepared { result.append(prepared) }
            }
        }
        return result
    }

    static func download(_ url: URL, referer: String? = nil, maxBytes: Int = 12_000_000) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(LinkImportService.userAgent, forHTTPHeaderField: "User-Agent")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        } else if let host = url.host {
            request.setValue("https://\(host)/", forHTTPHeaderField: "Referer")
        }
        guard let (data, response) = try? await NetworkSafety.data(for: request, maxBytes: maxBytes),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return await Task.detached(priority: .utility) { ImageService.prepareForStorage(data) }.value
    }
}

// MARK: - Vistas de imagen

struct ImagePlaceholder: View {
    var symbol: String = "photo"
    var caption: String?

    var body: some View {
        ZStack {
            Theme.card
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// Imagen de un producto guardado (datos locales o, si no hay, su URL remota).
struct CatalogImage: View {
    let image: ProductImage?
    var maxPixel: CGFloat = 600
    var placeholderSymbol: String = "photo"
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image {
            ImageLoaderView(
                cacheKey: "\(image.id.uuidString)-\(Int(maxPixel))",
                dataProvider: { image.data },
                remoteURL: image.remoteURL,
                maxPixel: maxPixel,
                placeholderSymbol: placeholderSymbol,
                contentMode: contentMode
            )
        } else {
            ImagePlaceholder(symbol: placeholderSymbol)
        }
    }
}

struct ImageLoaderView: View {
    let cacheKey: String
    let dataProvider: () -> Data?
    var remoteURL: String = ""
    var maxPixel: CGFloat = 600
    var placeholderSymbol: String = "photo"
    var contentMode: ContentMode = .fill

    @State var uiImage: UIImage?
    @State var failed = false

    var body: some View {
        ZStack {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ImagePlaceholder(
                    symbol: failed ? "exclamationmark.triangle" : placeholderSymbol,
                    caption: failed ? "No se pudo cargar" : nil
                )
            }
        }
        .task(id: cacheKey) { await load() }
    }

    @MainActor
    private func load() async {
        if let cached = ImageCache.shared.image(forKey: cacheKey) {
            uiImage = cached
            return
        }
        let px = maxPixel
        var loaded: UIImage?
        if let data = dataProvider() {
            loaded = await Task.detached(priority: .userInitiated) {
                ImageService.downsample(data, maxPixel: px)
            }.value
        } else if let url = NetworkSafety.webURL(remoteURL) {
            if let data = await ImageService.download(url) {
                loaded = await Task.detached(priority: .userInitiated) {
                    ImageService.downsample(data, maxPixel: px)
                }.value
            }
        } else {
            return
        }
        if let loaded {
            ImageCache.shared.set(loaded, forKey: cacheKey)
            uiImage = loaded
        } else {
            failed = true
        }
    }
}
