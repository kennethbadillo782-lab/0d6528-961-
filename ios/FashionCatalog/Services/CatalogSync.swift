import Foundation
import SwiftData
import UIKit
import CryptoKit
import Supabase

@MainActor
protocol CatalogCloudTransport {
    var owner: String { get }
    func fetch(_ table: String) async throws -> [CloudRow]
    func fetchChanges(_ table: String, since: String?) async throws -> [CloudRow]
    func write(_ table: String, row: CloudRow, previous: String?) async throws -> CloudRow
    func upload(_ data: Data, path: String) async throws
    func download(_ path: String) async throws -> Data
}

extension CatalogCloudTransport {
    func fetchChanges(_ table: String, since: String?) async throws -> [CloudRow] { try await fetch(table) }
}

@MainActor
final class SupabaseCatalogTransport: CatalogCloudTransport {
    let owner: String
    private let account: CloudAccount
    init(account: CloudAccount, owner: String) { self.account = account; self.owner = owner }
    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, content: String = "application/json", prefer: String? = nil, max: Int = 8_000_000) async throws -> Data {
        guard let base = account.base, let client = account.client else { throw CloudError.configuration }
        let session = try await client.auth.session
        guard session.user.id.uuidString.lowercased() == owner else { throw CloudError.accountMismatch }
        var components = URLComponents(url:base.appendingPathComponent(path),resolvingAgainstBaseURL:false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url:components.url!); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.setValue(account.publicKey,forHTTPHeaderField:"apikey"); request.setValue("Bearer \(session.accessToken)",forHTTPHeaderField:"Authorization")
        request.setValue(content,forHTTPHeaderField:"Content-Type"); if let prefer { request.setValue(prefer,forHTTPHeaderField:"Prefer") }
        let (data,response) = try await NetworkSafety.data(for:request,maxBytes:max)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw CloudError.rejected((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return data
    }
    func fetch(_ table: String) async throws -> [CloudRow] { try await fetchChanges(table,since:nil) }
    func fetchChanges(_ table: String, since: String?) async throws -> [CloudRow] {
        guard CloudMapping.tables.contains(table) else { throw CloudError.invalidData }
        var rows: [CloudRow] = []; var offset = 0
        while true {
            var q = [URLQueryItem(name:"select",value:"*"),URLQueryItem(name:"owner_id",value:"eq.\(owner)"),URLQueryItem(name:"order",value:table == "categories" ? "key.asc" : table == "product_collections" ? "product_id.asc,collection_id.asc" : "id.asc"),URLQueryItem(name:"limit",value:"200"),URLQueryItem(name:"offset",value:String(offset))]
            if let since { q.append(.init(name:"updated_at",value:"gte.\(since)")) }
            let data = try await request("rest/v1/\(table)",query:q)
            guard let page = try JSONSerialization.jsonObject(with:data) as? [CloudRow] else { throw CloudError.invalidData }
            rows += page; if page.count < 200 { return rows }; offset += 200
            guard offset <= 100_000 else { throw CloudError.invalidData }
        }
    }
    func write(_ table: String, row: CloudRow, previous: String?) async throws -> CloudRow {
        var body = row; body["owner_id"] = owner; body.removeValue(forKey:"local_data_hash")
        let identity = table == "categories" ? ["key"] : table == "product_collections" ? ["product_id","collection_id"] : ["id"]
        var q = identity.map { URLQueryItem(name:$0,value:"eq.\(row[$0] as? String ?? "")") }
        q.append(.init(name:"owner_id",value:"eq.\(owner)"))
        if let previous { q.append(.init(name:"updated_at",value:"eq.\(previous)")) }
        let data = try await request("rest/v1/\(table)",method:previous == nil ? "POST" : "PATCH",query:previous == nil ? [] : q,body:JSONSerialization.data(withJSONObject:body),prefer:"return=representation")
        guard let rows = try JSONSerialization.jsonObject(with:data) as? [CloudRow], let first = rows.first else { throw CloudError.conflict }
        return first
    }
    func upload(_ data: Data, path: String) async throws {
        guard validPath(path), data.count <= 5_000_000 else { throw CloudError.invalidData }
        _ = try await request("storage/v1/object/product-images/\(path)",method:"POST",body:data,content:"image/jpeg")
    }
    func download(_ path: String) async throws -> Data {
        guard validPath(path) else { throw CloudError.invalidData }
        return try await request("storage/v1/object/authenticated/product-images/\(path)",max:15_000_000)
    }
    private func validPath(_ path: String) -> Bool {
        path.hasPrefix(owner+"/") && path.count <= 400 && !path.contains("..") && path.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_/ .".contains($0)) } && !path.contains(" ")
    }
}

@MainActor
final class CatalogSync: ObservableObject {
    static let shared = CatalogSync()
    @Published var status = "Sincronización pendiente"
    @Published var isSyncing = false
    @Published var lastSync: Date?
    private var busy = false

    func run(context: ModelContext) async {
        if let bound = UserDefaults.standard.string(forKey:"catalog.cloud.owner") { try? capturePending(context:context,owner:bound) }
        let account = CloudAccount.shared
        guard let client = account.client, account.email != nil else { return }
        do {
            let session = try await client.auth.session
            try await sync(context:context,transport:SupabaseCatalogTransport(account:account,owner:session.user.id.uuidString.lowercased()))
        } catch { status = "Sin conexión o sesión vencida. Los cambios locales se conservan para reintentar." }
    }
    // Público internamente para pruebas con transporte determinista y con el servidor real.
    func sync(context: ModelContext, transport: CatalogCloudTransport) async throws {
        guard !busy else { return }
        busy = true; isSyncing = true; defer { busy = false; isSyncing = false }
        status = "Sincronizando…"
        let owner = transport.owner
        let allEntries = try context.fetch(FetchDescriptor<CloudSyncEntry>())
        guard !allEntries.contains(where: { $0.owner != owner }) else { throw CloudError.accountMismatch }
        // Identidad de cuenta duradera: tampoco se mezcla una caché tras cerrar sesión.
        let binding = UserDefaults.standard.string(forKey:"catalog.cloud.owner")
        guard binding == nil || binding == owner else { throw CloudError.accountMismatch }
        UserDefaults.standard.set(owner,forKey:"catalog.cloud.owner")
        try capturePending(context:context,owner:owner)
        var remote: [String:[CloudRow]] = [:]
        var caches = try context.fetch(FetchDescriptor<CloudRemoteCache>()).filter { $0.owner == owner }
        for table in CloudMapping.tables {
            let cache = caches.first { $0.table == table } ?? CloudRemoteCache(owner:owner,table:table)
            if !caches.contains(where: { $0.table == table }) { context.insert(cache); caches.append(cache) }
            let previous = cache.rowsData.isEmpty ? [] : ((try JSONSerialization.jsonObject(with:cache.rowsData)) as? [CloudRow] ?? [])
            let overlap = CloudMapping.date(cache.cursor).map { CloudMapping.stamp($0.addingTimeInterval(-2)) }
            let changes = try await transport.fetchChanges(table,since:overlap)
            var combined = Dictionary(previous.map { (CloudMapping.key($0,table:table),$0) },uniquingKeysWith: { _,b in b })
            for row in changes { combined[CloudMapping.key(row,table:table)] = row }
            remote[table] = Array(combined.values)
            cache.rowsData = try JSONSerialization.data(withJSONObject:Array(combined.values))
            if let newest = changes.compactMap({ CloudMapping.date($0["updated_at"]) }).max() { cache.cursor = CloudMapping.stamp(newest) }
        }
        try context.save()
        // Fusionar por nombre la colección sembrada al primer login; nunca crear dos "Lista principal".
        for c in try context.fetch(FetchDescriptor<ProductCollection>()) {
            if !allEntries.contains(where: { $0.table == "collections" && $0.rowKey == c.id.uuidString.lowercased() && !$0.remoteStamp.isEmpty }),
               let r = remote["collections"]?.first(where: { ($0["name"] as? String)?.lowercased() == c.name.lowercased() && !($0["deleted_at"] is String) }), let id = UUID(uuidString:r["id"] as? String ?? "") { c.id = id }
        }
        // Solo sube contenido binario nuevo; rutas aleatorias evitan sobreescribir una foto remota.
        for p in try context.fetch(FetchDescriptor<Product>()) where !p.isDemo {
            for image in p.images {
                guard let data = image.data else { continue }
                let hash = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
                if image.cloudUploadedHash == hash && !image.cloudPath.isEmpty { continue }
                guard let jpeg = ImageService.downsample(data,maxPixel:1600)?.jpegData(compressionQuality:0.78), jpeg.count <= 5_000_000 else { throw CloudError.invalidData }
                let path = "\(owner)/\(p.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                try await transport.upload(jpeg,path:path)
                // Si se editó mientras subía, la nueva imagen quedará pendiente en el siguiente ciclo.
                if image.data == data { image.cloudPath = path; image.cloudUploadedHash = hash }
            }
        }
        for collection in try context.fetch(FetchDescriptor<ProductCollection>()) {
            if let data = collection.coverData {
                let hash = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
                if collection.cloudCoverHash != hash || collection.cloudCoverPath == nil {
                    guard let jpeg = ImageService.downsample(data,maxPixel:1600)?.jpegData(compressionQuality:0.78) else { throw CloudError.invalidData }
                    let path = "\(owner)/\(collection.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
                    try await transport.upload(jpeg,path:path)
                    if collection.coverData == data { collection.cloudCoverPath = path; collection.cloudCoverHash = hash }
                }
            } else if !collection.cloudCoverHash.isEmpty { collection.cloudCoverPath = nil; collection.cloudCoverHash = "" }
        }
        let local = try CloudMapping.snapshots(context)
        var entries = try context.fetch(FetchDescriptor<CloudSyncEntry>())
        for e in entries where e.remoteStamp.isEmpty && e.table == "collections" && !local.contains(where: { $0.table == e.table && $0.key == e.rowKey }) { context.delete(e) }
        entries = entries.filter { e in !(e.remoteStamp.isEmpty && e.table == "collections" && !local.contains(where: { $0.table == e.table && $0.key == e.rowKey })) }
        for snapshot in local {
            if let e = entries.first(where: { $0.table == snapshot.table && $0.rowKey == snapshot.key }) {
                if e.fingerprint != snapshot.fingerprint && e.pendingSince == nil { e.pendingSince = snapshot.modified ?? Date() }
            } else {
                let e = CloudSyncEntry(owner:owner,table:snapshot.table,key:snapshot.key); e.pendingSince = snapshot.modified ?? Date(); context.insert(e); entries.append(e)
            }
        }
        for e in entries where !e.isDeleted && !local.contains(where: { $0.table == e.table && $0.key == e.rowKey }) {
            if e.pendingSince == nil { e.pendingSince = Date() }
        }
        try context.save() // Persistir la cola ANTES de los envíos; sobrevive a fallos y cierre.
        for table in CloudMapping.tables {
            var keys = Set((remote[table] ?? []).map { CloudMapping.key($0,table:table) })
            keys.formUnion(entries.filter { $0.table == table }.map(\.rowKey))
            for key in keys.sorted() {
                let r = remote[table]?.first { CloudMapping.key($0,table:table) == key }
                let snapshot = local.first { $0.table == table && $0.key == key }
                var entry = entries.first { $0.table == table && $0.rowKey == key }
                let dirty = entry?.pendingSince != nil
                let remoteDate = CloudMapping.date(r?["updated_at"])
                // El servidor gana cuando su fecha es posterior al cambio local pendiente.
                let remoteWins = !dirty || (remoteDate != nil && entry?.pendingSince != nil && remoteDate! > entry!.pendingSince!)
                if let r, remoteWins {
                    let current = try CloudMapping.snapshots(context).first { $0.table == table && $0.key == key }
                    guard current?.fingerprint == snapshot?.fingerprint else { continue }
                    try CloudMapping.apply(r,table:table,context:context)
                    if entry == nil { let e = CloudSyncEntry(owner:owner,table:table,key:key); context.insert(e); entries.append(e); entry = e }
                } else if dirty {
                    var row = snapshot?.row ?? identity(table:table,key:key)
                    if snapshot == nil { row["deleted_at"] = CloudMapping.stamp(entry!.pendingSince!) }
                    else { row["deleted_at"] = NSNull() }
                    // Eliminación local de una fila que nunca llegó al servidor: no insertar un fantasma.
                    if snapshot == nil && r == nil { entry?.isDeleted = true; entry?.pendingSince = nil; continue }
                    let written = try await transport.write(table,row:row,previous:r?["updated_at"] as? String)
                    entry?.remoteStamp = written["updated_at"] as? String ?? ""
                    if let cache = caches.first(where: { $0.table == table }) {
                        var cached = remote[table] ?? []; cached.removeAll { CloudMapping.key($0,table:table) == key }; cached.append(written)
                        remote[table] = cached; cache.rowsData = try JSONSerialization.data(withJSONObject:cached)
                    }
                } else { continue }
                // Guardar la huella exacta del estado recibido/enviado, sin absorber ediciones concurrentes.
                let current = try CloudMapping.snapshots(context).first { $0.table == table && $0.key == key }
                entry?.fingerprint = remoteWins ? (current?.fingerprint ?? "") : (snapshot?.fingerprint ?? "")
                entry?.isDeleted = remoteWins ? (r?["deleted_at"] is String) : snapshot == nil
                entry?.pendingSince = nil
                if remoteWins { entry?.remoteStamp = r?["updated_at"] as? String ?? "" }
                try context.save()
            }
        }
        // Fotos privadas: ninguna URL firmada persistida ni token en los modelos.
        for image in try context.fetch(FetchDescriptor<ProductImage>()) where image.data == nil && !image.cloudPath.isEmpty {
            let path = image.cloudPath
            let data = try await transport.download(path)
            guard let decoded = ImageService.downsample(data,maxPixel:1600), let jpeg = decoded.jpegData(compressionQuality:0.85) else { throw CloudError.invalidData }
            if image.cloudPath == path { image.data = jpeg; image.cloudUploadedHash = SHA256.hash(data:jpeg).map { String(format:"%02x",$0) }.joined() }
        }
        for collection in try context.fetch(FetchDescriptor<ProductCollection>()) where collection.coverData == nil {
            if let path = collection.cloudCoverPath {
                let data = try await transport.download(path)
                guard let decoded = ImageService.downsample(data,maxPixel:1600), let jpeg = decoded.jpegData(compressionQuality:0.85) else { throw CloudError.invalidData }
                if collection.cloudCoverPath == path { collection.coverData = jpeg; collection.cloudCoverHash = SHA256.hash(data:jpeg).map { String(format:"%02x",$0) }.joined() }
            }
        }
        // La descarga de caché no es una modificación de la foto del usuario.
        let after = try CloudMapping.snapshots(context)
        for e in entries where e.table == "product_images" && e.pendingSince == nil {
            if let s = after.first(where: { $0.table == e.table && $0.key == e.rowKey }) { e.fingerprint = s.fingerprint }
        }
        try context.save(); lastSync = Date(); status = "Sincronizado"
    }
    func capturePending(context: ModelContext, owner: String) throws {
        let snapshots = try CloudMapping.snapshots(context)
        var entries = try context.fetch(FetchDescriptor<CloudSyncEntry>()).filter { $0.owner == owner }
        for s in snapshots {
            if let e = entries.first(where: { $0.table == s.table && $0.rowKey == s.key }) {
                if e.fingerprint != s.fingerprint && e.pendingSince == nil { e.pendingSince = s.modified ?? Date() }
            } else {
                let e = CloudSyncEntry(owner:owner,table:s.table,key:s.key); e.pendingSince = s.modified ?? Date(); context.insert(e); entries.append(e)
            }
        }
        for e in entries where !e.isDeleted && !snapshots.contains(where: { $0.table == e.table && $0.key == e.rowKey }) {
            if e.pendingSince == nil { e.pendingSince = Date() }
        }
        try context.save()
    }
    private func identity(table: String, key: String) -> CloudRow {
        if table == "categories" { return ["key":key] }
        if table == "product_collections" { let p = key.split(separator:"/"); return ["product_id":String(p.first ?? ""),"collection_id":String(p.last ?? "")] }
        return ["id":key]
    }
}
