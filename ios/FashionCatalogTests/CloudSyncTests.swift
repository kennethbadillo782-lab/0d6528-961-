import XCTest
import SwiftData
import UIKit
@testable import MiCatalogo

@MainActor
final class MemoryCloud: CatalogCloudTransport {
    let owner = "e042b902-68c2-4d7a-a2c9-228f59141ac2"
    var rows: [String:[CloudRow]] = [:]
    var files: [String:Data] = [:]
    var offline = false
    var afterWrite: (() -> Void)?
    func fetch(_ table: String) async throws -> [CloudRow] { if offline { throw URLError(.notConnectedToInternet) }; return rows[table] ?? [] }
    func write(_ table: String, row: CloudRow, previous: String?) async throws -> CloudRow {
        if offline { throw URLError(.notConnectedToInternet) }
        let key = CloudMapping.key(row,table:table)
        if let previous, let old = rows[table]?.first(where: { CloudMapping.key($0,table:table) == key }), old["updated_at"] as? String != previous { throw CloudError.conflict }
        var value = row; value.removeValue(forKey:"local_data_hash"); value["owner_id"] = owner; value["updated_at"] = CloudMapping.stamp(Date().addingTimeInterval(-100))
        rows[table,default:[]].removeAll { CloudMapping.key($0,table:table) == key }; rows[table,default:[]].append(value)
        let action = afterWrite; afterWrite = nil; action?()
        return value
    }
    func upload(_ data: Data,path: String) async throws { files[path] = data }
    func download(_ path: String) async throws -> Data { guard let data = files[path] else { throw CloudError.invalidData }; return data }
}

final class CloudSyncTests: XCTestCase {
    @MainActor private func store() throws -> ModelContainer {
        UserDefaults.standard.removeObject(forKey:"catalog.cloud.owner")
        let schema = Schema([Product.self, ProductImage.self, ProductCollection.self, CatalogCategory.self, CloudSyncEntry.self])
        return try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
    }
    @MainActor
    func testOfflineCreateEditAndDeleteReachCloudAfterRetry() async throws {
        let container = try store(); let c = container.mainContext; let transport = MemoryCloud(); let sync = CatalogSync()
        let p = Product(name:"Creado sin conexión"); c.insert(p); try c.save()
        transport.offline = true
        do { try await sync.sync(context:c,transport:transport); XCTFail("Debía fallar offline") } catch {}
        XCTAssertEqual(try c.fetch(FetchDescriptor<CloudSyncEntry>()).filter { $0.pendingSince != nil }.count,1)
        transport.offline = false; try await sync.sync(context:c,transport:transport)
        XCTAssertEqual(transport.rows["products"]?.first?["name"] as? String,p.name)
        p.name = "Editado ñ"; p.touch(); try c.save(); try await sync.sync(context:c,transport:transport)
        XCTAssertEqual(transport.rows["products"]?.first?["name"] as? String,"Editado ñ")
        c.delete(p); try c.save(); try await sync.sync(context:c,transport:transport)
        XCTAssertNotNil(transport.rows["products"]?.first?["deleted_at"] as? String)
        try await sync.sync(context:c,transport:transport)
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<Product>()),0)
    }
    @MainActor
    func testAPIRowIsPulledSanitizedAndRemoteDeleteDoesNotResurrect() async throws {
        let container = try store(); let c = container.mainContext; let t = MemoryCloud(); let sync = CatalogSync()
        let id = UUID().uuidString.lowercased()
        t.rows["products"] = [["id":id,"name":"Desde API","original_url":"javascript:alert(1)","agent_links":[["name":"x","url":"file:///etc/passwd"]],"updated_at":CloudMapping.stamp(Date()),"created_at":CloudMapping.stamp(Date())]]
        try await sync.sync(context:c,transport:t)
        let p = try XCTUnwrap(c.fetch(FetchDescriptor<Product>()).first)
        XCTAssertEqual(p.name,"Desde API"); XCTAssertEqual(p.originalURL,""); XCTAssertTrue(p.agentLinks.isEmpty)
        t.rows["products"]![0]["deleted_at"] = CloudMapping.stamp(Date())
        try await sync.sync(context:c,transport:t); try await sync.sync(context:c,transport:t)
        XCTAssertEqual(try c.fetchCount(FetchDescriptor<Product>()),0)
        XCTAssertNotNil(t.rows["products"]![0]["deleted_at"])
    }
    @MainActor
    func testNewerRemoteWinsConflictAndEditDuringUploadRemainsPending() async throws {
        let container = try store(); let c = container.mainContext; let t = MemoryCloud(); let sync = CatalogSync()
        let p = Product(name:"Inicial"); c.insert(p); try c.save(); try await sync.sync(context:c,transport:t)
        p.name = "Local viejo"; p.updatedAt = Date().addingTimeInterval(-60)
        t.rows["products"]![0]["name"] = "Remoto nuevo"; t.rows["products"]![0]["updated_at"] = CloudMapping.stamp(Date())
        try await sync.sync(context:c,transport:t); XCTAssertEqual(p.name,"Remoto nuevo")
        p.name = "Enviando"; p.updatedAt = Date().addingTimeInterval(1)
        t.afterWrite = { p.name = "Editado mientras enviaba"; p.updatedAt = Date().addingTimeInterval(2) }
        try await sync.sync(context:c,transport:t)
        XCTAssertEqual(p.name,"Editado mientras enviaba")
        try await sync.sync(context:c,transport:t)
        XCTAssertEqual(t.rows["products"]?.first?["name"] as? String,"Editado mientras enviaba")
    }
    @MainActor
    func testCollectionsMembershipAndPrivatePhotoRoundTrip() async throws {
        let source = try store(); let c = source.mainContext; let t = MemoryCloud(); let sync = CatalogSync()
        let collection = ProductCollection(name:"Pruebas"); c.insert(collection)
        let p = Product(name:"Foto privada"); c.insert(p); p.collections = [collection]
        let data = try XCTUnwrap(UIImage(systemName:"tshirt")?.pngData())
        let image = ProductImage(data:data); c.insert(image); p.images = [image]; try c.save()
        try await sync.sync(context:c,transport:t)
        XCTAssertEqual(t.files.count,1); XCTAssertEqual(t.rows["product_collections"]?.count,1)
        let target = try store(); try await CatalogSync().sync(context:target.mainContext,transport:t)
        let actual = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<Product>()).first)
        XCTAssertEqual(actual.collections.first?.name,"Pruebas"); XCTAssertNotNil(actual.images.first?.data)
        XCTAssertTrue(actual.images.first?.cloudPath.hasPrefix(t.owner+"/") ?? false)
        let count = t.files.count; try await CatalogSync().sync(context:target.mainContext,transport:t); XCTAssertEqual(t.files.count,count)
    }
    @MainActor
    func testSeedCollectionReusesServerIDAndAccountCannotBeMixed() async throws {
        let container = try store(); let c = container.mainContext; let t = MemoryCloud(); let sync = CatalogSync()
        let collection = ProductCollection(name:"Lista principal"); c.insert(collection)
        let remoteID = UUID().uuidString.lowercased()
        t.rows["collections"] = [["id":remoteID,"name":"Lista principal","sort_order":0,"updated_at":CloudMapping.stamp(Date())]]
        try await sync.sync(context:c,transport:t)
        XCTAssertEqual(collection.id.uuidString.lowercased(),remoteID); XCTAssertEqual(t.rows["collections"]?.count,1)
        UserDefaults.standard.set("otra-cuenta",forKey:"catalog.cloud.owner")
        do { try await sync.sync(context:c,transport:t); XCTFail("No debe mezclar cuentas") } catch CloudError.accountMismatch {} catch { XCTFail("Error inesperado") }
        UserDefaults.standard.removeObject(forKey:"catalog.cloud.owner")
    }
}
