import Foundation

/// Reglas de red compartidas por toda la app.
/// - Solo se abren o descargan enlaces http(s) sin usuario/contraseña.
/// - Las descargas automáticas (fotos, lectura de páginas) nunca van a la red local
///   (router, impresoras, 192.168.x.x, localhost...) ni siguen redirecciones hacia ella:
///   se comprueba el nombre y también las IPs a las que resuelve. Queda un margen teórico
///   (DNS que cambia entre la comprobación y la conexión) que cubre el aviso de "Red local" de iOS.
/// - Las descargas tienen un tamaño máximo y no se cargan enteras en memoria antes de comprobarlo.
enum NetworkSafety {

    // MARK: Enlaces

    /// Devuelve la URL solo si es http/https real. Evita esquemas como `javascript:`,
    /// `tel:`, `shortcuts:` o "httpfalso://", y enlaces tipo https://taobao.com@web-falsa.com.
    static func webURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 2048, let url = URL(string: s),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              let host = url.host, !host.isEmpty, host.contains(".") || host.contains(":") else { return nil }
        return url
    }

    /// true si la app puede descargar algo de esta URL automáticamente.
    static func isPublic(_ url: URL) -> Bool {
        guard webURL(url.absoluteString) != nil, let host = url.host else { return false }
        if let port = url.port, port != 80, port != 443 { return false }
        return isPublicHost(host)
    }

    static func isPublicHost(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }

        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 { return isPublicIPv4(UInt32(bigEndian: v4.s_addr)) }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 { return isPublicIPv6(v6) }

        // Formas numéricas raras (2130706433, 0x7f.1...) y nombres sin dominio ("router").
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let numericLabel: (Substring) -> Bool = { label in
            let l = label.lowercased()
            if l.hasPrefix("0x") { return l.dropFirst(2).allSatisfy { $0.isHexDigit } }
            return !l.isEmpty && l.allSatisfy { $0.isASCII && $0.isNumber }
        }
        if labels.count <= 4 && labels.allSatisfy(numericLabel) { return false }
        guard host.contains(".") else { return false }
        // Solo nombres ASCII normalizados (evita dígitos de ancho completo y trucos Unicode).
        guard host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return false }
        let blockedSuffixes = [".localhost", ".local", ".internal", ".home.arpa", ".lan", ".intranet",
                               ".corp", ".localdomain", ".arpa"]
        if host == "localhost" || blockedSuffixes.contains(where: { host.hasSuffix($0) }) { return false }
        return true
    }

    private static let privateV4: [(base: UInt32, bits: UInt32)] = [
        (0x0000_0000, 8), (0x0A00_0000, 8), (0x6440_0000, 10), (0x7F00_0000, 8), (0xA9FE_0000, 16),
        (0xAC10_0000, 12), (0xC000_0000, 24), (0xC000_0200, 24), (0xC058_6300, 24), (0xC0A8_0000, 16),
        (0xC612_0000, 15), (0xC633_6400, 24), (0xCB00_7100, 24), (0xE000_0000, 4), (0xF000_0000, 4),
    ]

    static func isPublicIPv4(_ n: UInt32) -> Bool {
        !privateV4.contains { range in
            let mask: UInt32 = range.bits == 0 ? 0 : ~UInt32(0) << (32 - range.bits)
            return n & mask == range.base
        }
    }

    static func isPublicIPv6(_ addr: in6_addr) -> Bool {
        let b: [UInt8] = withUnsafeBytes(of: addr) { Array($0) }
        guard b.count == 16 else { return false }
        var g = [UInt16](repeating: 0, count: 8)
        for i in 0..<8 { g[i] = (UInt16(b[2 * i]) << 8) | UInt16(b[2 * i + 1]) }
        func v4(_ i: Int) -> UInt32 { (UInt32(g[i]) << 16) | UInt32(g[i + 1]) }
        if g[0] == 0 && g[1] == 0 && g[2] == 0 && g[3] == 0 && g[4] == 0 {
            if g[5] == 0xFFFF { return isPublicIPv4(v4(6)) }   // ::ffff:a.b.c.d
            if g[5] == 0 { return false }                      // ::, ::1, ::a.b.c.d
        }
        if g[0] == 0x0064 && g[1] == 0xFF9B {                  // NAT64 (redes móviles solo IPv6)
            if g[2] == 0 && g[3] == 0 && g[4] == 0 && g[5] == 0 { return isPublicIPv4(v4(6)) }
            return false
        }
        if g[0] == 0x2002 { return isPublicIPv4(v4(1)) }       // 6to4
        if g[0] == 0x2001 && (g[1] < 0x0200 || g[1] == 0x0DB8) { return false }
        return (g[0] & 0xE000) == 0x2000                       // solo unicast global
    }

    // MARK: DNS

    /// Resuelve el nombre y exige que TODAS sus direcciones sean públicas
    /// (evita nombres como 192-168-1-1.nip.io que apuntan a tu red de casa).
    /// Es bloqueante: llámalo fuera del hilo principal.
    static func resolvesOnlyToPublic(_ rawHost: String) -> Bool {
        var host = rawHost
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }
        var sawAddress = false
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            if let sa = info.pointee.ai_addr {
                if info.pointee.ai_family == AF_INET {
                    let ok = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        isPublicIPv4(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
                    }
                    if !ok { return false }
                    sawAddress = true
                } else if info.pointee.ai_family == AF_INET6 {
                    let ok = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { isPublicIPv6($0.pointee.sin6_addr) }
                    if !ok { return false }
                    sawAddress = true
                }
            }
            cursor = info.pointee.ai_next
        }
        return sawAddress
    }

    // MARK: Descargas

    enum SafetyError: LocalizedError {
        case blockedHost, tooLarge
        var errorDescription: String? {
            switch self {
            case .blockedHost: return "Por seguridad, la app no descarga de direcciones de tu red local."
            case .tooLarge: return "El archivo es demasiado grande."
            }
        }
    }

    /// Descarga con límite de tamaño y sin redirecciones hacia la red local.
    static func data(for request: URLRequest, maxBytes: Int) async throws -> (Data, URLResponse) {
        guard let url = request.url, isPublic(url), let host = url.host else { throw SafetyError.blockedHost }
        let resolvesOK = await Task.detached(priority: .utility) { NetworkSafety.resolvesOnlyToPublic(host) }.value
        guard resolvesOK else { throw SafetyError.blockedHost }
        let (bytes, response) = try await URLSession.shared.bytes(for: request, delegate: SafeRedirects.shared)
        if response.expectedContentLength > Int64(maxBytes) {
            bytes.task.cancel()
            throw SafetyError.tooLarge
        }
        var data = Data()
        data.reserveCapacity(Int(min(max(response.expectedContentLength, 0), Int64(maxBytes))))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes {
                bytes.task.cancel()
                throw SafetyError.tooLarge
            }
        }
        return (data, response)
    }
}

/// Rechaza redirecciones que salgan de http(s) o apunten a la red local.
final class SafeRedirects: NSObject, URLSessionTaskDelegate {
    static let shared = SafeRedirects()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, NetworkSafety.isPublic(url),
           let host = url.host, NetworkSafety.resolvesOnlyToPublic(host) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
