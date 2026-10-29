import XCTest
import SwiftData
import Supabase
import UIKit
@testable import MiCatalogo

final class CloudLiveTests: XCTestCase {
    @MainActor
    func testNativeAppAndChatGPTAPIExchangeDataWithRealSupabase() async throws {
        guard let file = Bundle(for:Self.self).url(forResource:"NativeSecrets",withExtension:"json"),
              let secrets = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:String],
              let token = secrets["MC_NATIVE_TOKEN_HASH"], !token.isEmpty,
              let key = secrets["MC_NATIVE_API_KEY"], !key.isEmpty else { throw XCTSkip("Sin credencial efímera para integración remota") }
        let account = CloudAccount.shared
        let client = try XCTUnwrap(account.client)
        let response = try await client.auth.verifyOTP(tokenHash:token,type:.magiclink)
        let session = try XCTUnwrap(response.session)
        let owner = session.user.id.uuidString.lowercased()
        let restoredClient = CloudAccount()
        let restoredSession = try await XCTUnwrap(restoredClient.client).auth.session
        XCTAssertEqual(restoredSession.user.id,session.user.id)
        account.email = session.user.email
        UserDefaults.standard.removeObject(forKey:"catalog.cloud.owner")
        let schema = Schema([Product.self, ProductImage.self, ProductCollection.self, CatalogCategory.self, CloudSyncEntry.self, CloudRemoteCache.self])
        let container = try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
        let c = container.mainContext; let transport = SupabaseCatalogTransport(account:account,owner:owner); let sync = CatalogSync()
        let suffix = UUID().uuidString
        let p = Product(name:"Prueba nativa offline \(suffix)"); c.insert(p)
        let localID = p.id
        let image = ProductImage(data:try XCTUnwrap(UIImage(systemName:"tshirt")?.pngData())); c.insert(image); p.images = [image]
        try c.save(); try sync.capturePending(context:c,owner:owner)
        var apiProductID: UUID?
        var step = "inicio"
        do {
            step = "sync inicial"
            try await sync.sync(context:c,transport:transport)
            step = "fetch"
            let first = try await transport.fetch("products")
            XCTAssertTrue(first.contains { ($0["id"] as? String) == localID.uuidString.lowercased() && ($0["name"] as? String) == p.name })
            XCTAssertFalse(image.cloudPath.isEmpty)
            step = "api chatgpt"
            var request = URLRequest(url:try XCTUnwrap(account.base?.appendingPathComponent("functions/v1/catalog-api/products")))
            request.httpMethod = "POST"; request.setValue(key,forHTTPHeaderField:"X-API-Key"); request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject:["name":"Desde ChatGPT API \(suffix)","original_url":"https://example.com/native-test/\(suffix)","category_key":"otros","images":[["url":"https://cdn.shopify.com/static/shopify-favicon.png"]]])
            let (data,result) = try await NetworkSafety.data(for:request,maxBytes:2_000_000)
            XCTAssertEqual((result as? HTTPURLResponse)?.statusCode,201)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? CloudRow)
            let row = try XCTUnwrap(json["product"] as? CloudRow)
            apiProductID = UUID(uuidString:row["id"] as? String ?? "")
            step = "sync tras api"
            try await sync.sync(context:c,transport:transport)
            let pulled = try XCTUnwrap(c.fetch(FetchDescriptor<Product>()).first { $0.id == apiProductID })
            XCTAssertTrue(pulled.name.hasPrefix("Desde ChatGPT API"))
            XCTAssertNotNil(pulled.images.first?.data)
            pulled.notes = "Editado en Swift ñ"; pulled.touch(); try c.save()
            try await sync.sync(context:c,transport:transport)
            let rows = try await transport.fetch("products")
            XCTAssertTrue(rows.contains { ($0["id"] as? String) == pulled.id.uuidString.lowercased() && ($0["notes"] as? String) == "Editado en Swift ñ" })
            step = "segunda cache"
            // Otra caché SwiftData descarga fotos privadas y ve ambos productos.
            let second = try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
            try await CatalogSync().sync(context:second.mainContext,transport:transport)
            let photoProduct = try XCTUnwrap(second.mainContext.fetch(FetchDescriptor<Product>()).first { $0.id == localID })
            XCTAssertNotNil(photoProduct.images.first?.data)
            step = "borrado"
            c.delete(p); c.delete(pulled); try c.save(); try await sync.sync(context:c,transport:transport)
            let deleted = try await transport.fetch("products")
            XCTAssertTrue(deleted.contains { ($0["id"] as? String) == localID.uuidString.lowercased() && $0["deleted_at"] is String })
            step = "signOut"
            try await client.auth.signOut(); account.email = nil
            XCTAssertNil(client.auth.currentSession)
            XCTAssertNil(try CatalogKeychain().retrieve(key:"sb-ddppztnamwmryhamezwy-auth-token"))
        } catch {
            // Limpieza acotada a los ids ficticios creados por esta prueba.
            for id in [localID,apiProductID].compactMap({ $0 }) {
                if let row = try? await transport.fetch("products").first(where: { $0["id"] as? String == id.uuidString.lowercased() }) {
                    _ = try? await transport.write("products",row:["id":id.uuidString.lowercased(),"deleted_at":CloudMapping.stamp(Date())],previous:row["updated_at"] as? String)
                }
            }
            try? await client.auth.signOut(); account.email = nil
            XCTFail("paso fallido: \(step)")
            throw error
        }
        UserDefaults.standard.removeObject(forKey:"catalog.cloud.owner")
    }
}
