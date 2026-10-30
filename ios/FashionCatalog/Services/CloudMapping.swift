import Foundation
import SwiftData
import CryptoKit

@Model
final class CloudSyncEntry {
    var owner: String = ""
    var table: String = ""
    var rowKey: String = ""
    var fingerprint: String = ""
    var observedFingerprint: String = ""
    var remoteStamp: String = ""
    var pendingSince: Date?
    var isDeleted: Bool = false
    init(owner: String, table: String, key: String) { self.owner = owner; self.table = table; self.rowKey = key }
}

@Model
final class CloudRemoteCache {
    var owner: String = ""
    var table: String = ""
    var rowsData: Data = Data()
    var cursor: String?
    init(owner: String, table: String) { self.owner = owner; self.table = table }
}

typealias CloudRow = [String: Any]
struct CloudSnapshot {
    let table: String
    let key: String
    var row: CloudRow
    var modified: Date?
    var fingerprint: String {
        let data = (try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum CloudMapping {
    static let tables = ["categories", "collections", "products", "product_images", "product_collections"]
    static func key(_ row: CloudRow, table: String) -> String {
        if table == "categories" { return row["key"] as? String ?? "" }
        if table == "product_collections" { return (row["product_id"] as? String ?? "") + "/" + (row["collection_id"] as? String ?? "") }
        return (row["id"] as? String ?? "").lowercased()
    }
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    static func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func text(_ row: CloudRow, _ key: String, _ max: Int = 5000) -> String { String((row[key] as? String ?? "").prefix(max)) }
    static func link(_ row: CloudRow, _ key: String) -> String { NetworkSafety.webURL(text(row,key,2048))?.absoluteString ?? "" }
    @MainActor
    /// Huella de la foto. Una foto subida o descargada no cambia (solo se añaden o se borran), así que se
    /// reutiliza la guardada en vez de leer y resumir la imagen del disco en cada sincronización.
    static func localHash(_ i: ProductImage) -> String {
        if !i.cloudPath.isEmpty && !i.cloudUploadedHash.isEmpty { return i.cloudUploadedHash }
        return i.data.map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() } ?? ""
    }
    static func snapshots(_ context: ModelContext) throws -> [CloudSnapshot] {
        var result: [CloudSnapshot] = []
        let products = try context.fetch(FetchDescriptor<Product>()).filter { !$0.isDemo }
        for c in try context.fetch(FetchDescriptor<CatalogCategory>()) {
            result.append(.init(table:"categories",key:c.key,row:["key":c.key,"name":c.name,"symbol":c.symbol,"group_key":c.groupRaw == "all" ? "accessories" : c.groupRaw,"subcategories":c.subcategories,"sort_order":c.sortOrder,"show_on_home":c.showOnHome,"is_builtin":c.isBuiltIn]))
        }
        for c in try context.fetch(FetchDescriptor<ProductCollection>()) {
            result.append(.init(table:"collections",key:c.id.uuidString.lowercased(),row:["id":c.id.uuidString.lowercased(),"name":c.name,"sort_order":c.sortOrder,"cover_path":c.cloudCoverPath as Any? ?? NSNull()]))
        }
        for p in products {
            var row: CloudRow = ["id":p.id.uuidString.lowercased(),"name":p.name.isEmpty ? p.displayName : p.name,"brand":p.brand,"category_key":p.categoryKey,"subcategory":p.subcategory,"description":p.productDescription,"currency":p.currency,"original_url":p.originalURL,"normalized_url":p.normalizedURL,"platform":p.platform,"seller_name":p.sellerName,"seller_rating_source":p.sellerRatingSource,"color":p.color,"size":p.size,"material":p.material,"attributes":p.attributes,"declared_quality":p.declaredQuality,"verified_quality":p.verifiedQuality,"included_accessories":p.includedAccessories,"notes":p.notes,"is_favorite":p.isFavorite,"priority":p.priorityRaw,"status":p.statusRaw]
            row["price_current"] = p.priceCurrent as Any? ?? NSNull(); row["price_previous"] = p.pricePrevious as Any? ?? NSNull()
            row["shipping_estimate_usd"] = p.shippingEstimateUSD as Any? ?? NSNull(); row["seller_rating"] = p.sellerRating as Any? ?? NSNull()
            row["agent_links"] = p.agentLinks.map { ["name":$0.name,"url":$0.url] }
            result.append(.init(table:"products",key:p.id.uuidString.lowercased(),row:row,modified:p.updatedAt))
            for i in p.images {
                result.append(.init(table:"product_images",key:i.id.uuidString.lowercased(),row:["id":i.id.uuidString.lowercased(),"product_id":p.id.uuidString.lowercased(),"source_url":i.remoteURL,"storage_path":i.cloudPath,"kind":i.kindRaw,"position":i.order,"content_type":"image/jpeg","local_data_hash":localHash(i)]))
            }
            for c in p.collections {
                let row = ["product_id":p.id.uuidString.lowercased(),"collection_id":c.id.uuidString.lowercased()]
                result.append(.init(table:"product_collections",key:key(row,table:"product_collections"),row:row))
            }
        }
        return result
    }
    @MainActor
    static func apply(_ r: CloudRow, table: String, context: ModelContext) throws {
        let key = key(r,table:table)
        let deleted = r["deleted_at"] is String
        if table == "categories" {
            let existing = try context.fetch(FetchDescriptor<CatalogCategory>()).first { $0.key == key }
            if deleted { if let existing { context.delete(existing) }; return }
            guard !key.isEmpty, key.count <= 40, key.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }) else { throw CloudError.invalidData }
            let c = existing ?? CatalogCategory(key:key,name:"",symbol:"tag",group:.accessories,subcategories:[],sortOrder:0,isBuiltIn:false)
            if existing == nil { context.insert(c) }
            c.name = text(r,"name",60); c.symbol = text(r,"symbol",60); c.groupRaw = QuickGroup(rawValue:text(r,"group_key"))?.rawValue ?? "accessories"
            c.subcategories = (r["subcategories"] as? [String] ?? []).prefix(40).map { String($0.prefix(60)) }
            c.sortOrder = r["sort_order"] as? Int ?? 0; c.showOnHome = r["show_on_home"] as? Bool ?? true; c.isBuiltIn = r["is_builtin"] as? Bool ?? false
        } else if table == "collections" {
            guard let id = UUID(uuidString:key) else { throw CloudError.invalidData }
            let existing = try context.fetch(FetchDescriptor<ProductCollection>()).first { $0.id == id }
            if deleted { if let existing { context.delete(existing) }; return }
            let c = existing ?? ProductCollection(name:""); if existing == nil { c.id = id; context.insert(c) }
            c.name = text(r,"name",80); c.sortOrder = r["sort_order"] as? Int ?? 0; let path = r["cover_path"] as? String
            if c.cloudCoverPath != path { c.coverData = nil; c.cloudCoverHash = ""; c.cloudCoverPath = path }
        } else if table == "products" {
            guard let id = UUID(uuidString:key) else { throw CloudError.invalidData }
            let existing = try context.fetch(FetchDescriptor<Product>()).first { $0.id == id }
            if deleted { if let existing { context.delete(existing) }; return }
            let p = existing ?? Product(); if existing == nil { p.id = id; context.insert(p) }
            p.name = text(r,"name",300); p.brand = text(r,"brand",120); p.categoryKey = text(r,"category_key",40); p.subcategory = text(r,"subcategory",60)
            p.productDescription = text(r,"description"); p.currency = text(r,"currency",3); p.originalURL = link(r,"original_url"); p.normalizedURL = text(r,"normalized_url",2048)
            p.platform = text(r,"platform",60); p.sellerName = text(r,"seller_name",120); p.sellerRatingSource = text(r,"seller_rating_source",120)
            p.color = text(r,"color",60); p.size = text(r,"size",60); p.material = text(r,"material",120); p.declaredQuality = text(r,"declared_quality",120); p.verifiedQuality = text(r,"verified_quality",120)
            p.includedAccessories = text(r,"included_accessories",200); p.notes = text(r,"notes"); p.isFavorite = r["is_favorite"] as? Bool ?? false
            p.priorityRaw = min(3,max(0,r["priority"] as? Int ?? 0)); p.statusRaw = PurchaseStatus(rawValue:text(r,"status"))?.rawValue ?? PurchaseStatus.researching.rawValue
            func money(_ k: String) -> Double? { guard let n = r[k] as? NSNumber, n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }; return n.doubleValue }
            p.priceCurrent = money("price_current"); p.pricePrevious = money("price_previous"); p.shippingEstimateUSD = money("shipping_estimate_usd"); p.sellerRating = money("seller_rating").flatMap { $0 <= 5 ? $0 : nil }
            p.attributes = Dictionary((r["attributes"] as? [String:String] ?? [:]).prefix(30).map { (String($0.key.prefix(40)),String($0.value.prefix(120))) },uniquingKeysWith: { a,_ in a })
            p.agentLinks = (r["agent_links"] as? [CloudRow] ?? []).prefix(10).compactMap { row in let url = link(row,"url"); return url.isEmpty ? nil : AgentLink(name:text(row,"name",40),url:url) }
            p.createdAt = date(r["created_at"]) ?? p.createdAt; p.updatedAt = date(r["updated_at"]) ?? p.updatedAt
        } else if table == "product_images" {
            guard let id = UUID(uuidString:key) else { throw CloudError.invalidData }
            let existing = try context.fetch(FetchDescriptor<ProductImage>()).first { $0.id == id }
            if deleted { if let existing { context.delete(existing) }; return }
            guard let pid = UUID(uuidString:text(r,"product_id")), let product = try context.fetch(FetchDescriptor<Product>()).first(where: { $0.id == pid }) else { return }
            let i = existing ?? ProductImage(data:nil); if existing == nil { i.id = id; context.insert(i); product.images.append(i) }
            i.remoteURL = link(r,"source_url"); i.kindRaw = ImageKind(rawValue:text(r,"kind"))?.rawValue ?? "manual"; i.order = r["position"] as? Int ?? 0
            let path = text(r,"storage_path",400)
            if i.cloudPath != path { i.data = nil; i.cloudPath = path; i.cloudUploadedHash = "" }
        } else if table == "product_collections" {
            guard let pid = UUID(uuidString:text(r,"product_id")), let cid = UUID(uuidString:text(r,"collection_id")), let p = try context.fetch(FetchDescriptor<Product>()).first(where: { $0.id == pid }) else { return }
            if deleted { p.collections.removeAll { $0.id == cid } }
            else if let c = try context.fetch(FetchDescriptor<ProductCollection>()).first(where: { $0.id == cid }), !p.collections.contains(where: { $0.id == cid }) { p.collections.append(c) }
        }
    }
}
