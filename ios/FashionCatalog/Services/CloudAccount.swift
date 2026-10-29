import Foundation
import Security
import Supabase

struct CatalogKeychain: AuthLocalStorage {
    private let service = "com.micatalogo.moda.auth"
    func store(key: String, value: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        let changes: [String: Any] = [kSecValueData as String: value, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CloudError.keychain }
        } else if status != errSecSuccess { throw CloudError.keychain }
    }
    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CloudError.keychain }
        return item as? Data
    }
    func remove(key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudError.keychain }
    }
}

enum CloudError: Error { case keychain, configuration, rejected(Int), invalidData, accountMismatch, conflict }

@MainActor
final class CloudAccount: ObservableObject {
    static let shared = CloudAccount()
    @Published var email: String?
    @Published var message = "Sin sesión. Tus datos siguen disponibles sin conexión."
    @Published var busy = false
    let client: SupabaseClient?
    let base: URL?
    let publicKey: String
    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let raw = info["SUPABASE_URL"] as? String ?? ""
        publicKey = info["SUPABASE_ANON_KEY"] as? String ?? ""
        if let url = URL(string: raw), url.scheme == "https", url.host == "ddppztnamwmryhamezwy.supabase.co", !publicKey.isEmpty, !publicKey.contains("$(") {
            base = url
            client = SupabaseClient(supabaseURL: url, supabaseKey: publicKey, options: .init(auth: .init(storage: CatalogKeychain(), redirectToURL: URL(string: "micatalogo://auth-callback"))))
        } else { base = nil; client = nil }
    }
    func restore() async {
        guard let client else { message = "Esta compilación no tiene servidor configurado."; return }
        if let session = try? await client.auth.session { email = session.user.email; message = "Sesión recuperada." }
    }
    func sendLink(_ address: String) async {
        guard let client else { return }
        busy = true; defer { busy = false }
        do {
            try await client.auth.signInWithOTP(email: address.trimmingCharacters(in: .whitespacesAndNewlines), redirectTo: URL(string: "micatalogo://auth-callback"), shouldCreateUser: false)
            message = "Si el correo corresponde a tu cuenta, recibirás un enlace. En Appetize puedes pegar el enlace completo aquí."
        } catch { message = "No se pudo enviar el enlace. Revisa el correo y la conexión; espera un minuto antes de reintentar." }
    }
    func acceptLink(_ raw: String) async {
        guard let client, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              (url.scheme == "micatalogo" && url.host == "auth-callback") || (url.scheme == "https" && url.host == base?.host && url.path == "/auth/v1/verify") else { message = "Enlace de acceso no válido."; return }
        busy = true; defer { busy = false }
        do {
            var callback = url
            if url.scheme == "https" {
                // Solo el host fijo de Auth. No sigue redirecciones a destinos arbitrarios.
                callback = try await AuthLinkResolver.resolve(url)
            }
            let session = try await client.auth.session(from: callback)
            email = session.user.email; message = "Sesión iniciada."
        } catch { message = "El enlace venció, ya se usó o pertenece a otro dispositivo. Solicita uno nuevo desde esta app." }
    }
    func signOut() async {
        guard let client else { return }
        do { try await client.auth.signOut(); email = nil; message = "Sesión cerrada. La copia local permanece en este dispositivo." }
        catch { message = "No se pudo cerrar la sesión en el servidor. Revisa internet y vuelve a intentarlo." }
    }
}

// Captura únicamente el callback PKCE esperado; nunca abre una URL recibida en la red.
final class AuthLinkResolver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var callback: URL?
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url, url.scheme == "micatalogo", url.host == "auth-callback" { callback = url }
        completionHandler(nil)
    }
    static func resolve(_ url: URL) async throws -> URL {
        let delegate = AuthLinkResolver()
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        _ = try await session.data(from: url)
        guard let callback = delegate.callback else { throw CloudError.invalidData }
        return callback
    }
}
