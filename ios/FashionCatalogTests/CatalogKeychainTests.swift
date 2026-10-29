import XCTest
import Security
@testable import MiCatalogo

final class CatalogKeychainTests: XCTestCase {
    func testSessionStorageUsesDeviceOnlyAccessibilityAndRemovesValue() throws {
        let key = "regression-" + UUID().uuidString
        let storage = CatalogKeychain()
        defer { try? storage.remove(key:key) }
        try storage.store(key:key,value:Data("fixture-one".utf8))
        XCTAssertEqual(try storage.retrieve(key:key),Data("fixture-one".utf8))
        try storage.store(key:key,value:Data("fixture-two".utf8))
        XCTAssertEqual(try storage.retrieve(key:key),Data("fixture-two".utf8))
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.micatalogo.moda.auth",kSecAttrAccount as String:key,kSecReturnAttributes as String:true]
        var attributes: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary,&attributes),errSecSuccess)
        XCTAssertEqual((attributes as? [String:Any])?[kSecAttrAccessible as String] as? String,kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        try storage.remove(key:key)
        XCTAssertNil(try storage.retrieve(key:key))
    }
}
