import XCTest
import SwiftData
@testable import MiCatalogo

final class CatalogPersistenceTests: XCTestCase {
    @MainActor
    private func store() throws -> ModelContainer {
        let schema = Schema([Product.self, ProductImage.self, ProductCollection.self, CatalogCategory.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @MainActor
    func testBackupRoundTripPreservesPhotosCollectionsAndSkipsDuplicates() throws {
        let source = try store()
        let context = source.mainContext
        let collection = ProductCollection(name: "Prueba colección")
        context.insert(collection)
        let product = Product(name: "Camisa ñ & prueba", categoryKey: "otros")
        context.insert(product)
        product.originalURL = "https://item.taobao.com/item.htm?id=1"
        product.notes = "Notas especiales á <>"
        product.isFavorite = true
        product.collections = [collection]
        let image = ProductImage(data: Data([1, 2, 3, 4]), kind: .manual, order: 0)
        context.insert(image)
        product.images = [image]
        let demo = Product(name: "Ejemplo excluido")
        demo.isDemo = true
        context.insert(demo)
        try context.save()
        let backup = try BackupService.makeBackup(context: context)
        let target = try store()
        let restored = try BackupService.restore(backup, context: target.mainContext)
        XCTAssertEqual(restored.added, 1)
        let products = try target.mainContext.fetch(FetchDescriptor<Product>())
        let actual = try XCTUnwrap(products.first)
        XCTAssertEqual(actual.id, product.id)
        XCTAssertEqual(actual.name, product.name)
        XCTAssertEqual(actual.notes, product.notes)
        XCTAssertTrue(actual.isFavorite)
        XCTAssertEqual(actual.images.first?.data, image.data)
        XCTAssertEqual(actual.collections.first?.id, collection.id)
        let repeated = try BackupService.restore(backup, context: target.mainContext)
        XCTAssertEqual(repeated.added, 0)
        XCTAssertEqual(repeated.skipped, 1)
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<Product>()), 1)
    }

    @MainActor
    func testMaliciousBackupLinksAreRemovedAndInvalidJSONDoesNotChangeStore() throws {
        let source = try store()
        let product = Product(name: String(repeating: "x", count: 1000))
        source.mainContext.insert(product)
        product.originalURL = "javascript:alert(1)"
        product.agentLinks = [AgentLink(name: "Malicioso", url: "shortcuts://run-shortcut")]
        let image = ProductImage(data: nil, remoteURL: "file:///etc/passwd", kind: .manual, order: 0)
        source.mainContext.insert(image)
        product.images = [image]
        try source.mainContext.save()
        let target = try store()
        _ = try BackupService.restore(BackupService.makeBackup(context: source.mainContext), context: target.mainContext)
        let actual = try XCTUnwrap(target.mainContext.fetch(FetchDescriptor<Product>()).first)
        XCTAssertEqual(actual.name.count, 300)
        XCTAssertEqual(actual.originalURL, "")
        XCTAssertTrue(actual.agentLinks.isEmpty)
        XCTAssertEqual(actual.images.first?.remoteURL, "")
        XCTAssertThrowsError(try BackupService.restore(Data("{invalid".utf8), context: target.mainContext))
        XCTAssertEqual(try target.mainContext.fetchCount(FetchDescriptor<Product>()), 1)
    }

    @MainActor
    func testDeleteProductCascadesImagesAndKeepsCollection() throws {
        let container = try store()
        let context = container.mainContext
        let collection = ProductCollection(name: "Conservar")
        context.insert(collection)
        let product = Product(name: "Eliminar")
        context.insert(product)
        let image = ProductImage(data: Data([1]), kind: .manual, order: 0)
        context.insert(image)
        product.images = [image]
        product.collections = [collection]
        try context.save()
        context.delete(product)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Product>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductImage>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProductCollection>()), 1)
    }
}
