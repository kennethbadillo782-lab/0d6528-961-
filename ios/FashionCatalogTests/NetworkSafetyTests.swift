import XCTest
@testable import MiCatalogo

/// Pruebas de las reglas de red de la app. Añade un target de pruebas unitarias
/// ("MiCatalogoTests", host: MiCatalogo) que incluya esta carpeta y ejecútalas con ⌘U.
final class NetworkSafetyTests: XCTestCase {

    func testOnlyWebLinksCanBeOpened() {
        for ok in ["https://item.taobao.com/item.htm?id=1", "http://weidian.com/item.html?itemID=7", "https://www.hipobuy.com/p?url=x"] {
            XCTAssertNotNil(NetworkSafety.webURL(ok), ok)
        }
        for bad in ["javascript:alert(1)", "data:text/html,<b>x</b>", "file:///etc/passwd", "tel:5555555",
                    "shortcuts://run-shortcut?name=x", "httpfalso://x.com", "https-evil://x.com",
                    "https://item.taobao.com@evil.com/login", "https://user:pass@x.com/", "https://localhost", "",
                    String(repeating: "a", count: 3000)] {
            XCTAssertNil(NetworkSafety.webURL(bad), bad)
        }
    }

    func testNoDownloadsToLocalNetwork() {
        let blocked = ["http://127.0.0.1/x.png", "http://localhost/x.png", "http://localhost./x.png", "http://[::1]/",
                       "http://[::ffff:127.0.0.1]/", "http://[::ffff:a9fe:a9fe]/", "http://[64:ff9b::a9fe:a9fe]/",
                       "http://[2002:a9fe:a9fe::]/", "http://[fe80::1]/", "http://[fd00::1]/",
                       "http://169.254.169.254/latest", "http://10.0.0.1/", "http://192.168.1.1/router.png",
                       "http://172.16.5.4/", "http://100.64.0.1/", "http://0.0.0.0/", "http://2130706433/",
                       "http://0x7f.1/", "http://017700000001/", "http://router/", "http://printer.local/x.png",
                       "http://nas.lan/", "http://cdn.x.com:8080/a.png", "http://cdn.x.com:22/a.png"]
        for s in blocked {
            guard let url = URL(string: s) else { continue } // si iOS ni siquiera la acepta, tampoco se descarga
            XCTAssertFalse(NetworkSafety.isPublic(url), s)
        }
        for s in ["https://img.alicdn.com/x.jpg", "https://si.geilicdn.com/a.webp", "http://8.8.8.8/x.png",
                  "https://[2a00:1450:4001:80b::200e]/x.png", "https://cdn.x.com:443/a.png"] {
            XCTAssertTrue(NetworkSafety.isPublic(URL(string: s)!), s)
        }
    }

    func testNamesThatResolveToLocalNetworkAreRejected() {
        XCTAssertFalse(NetworkSafety.resolvesOnlyToPublic("localhost"))
        XCTAssertFalse(NetworkSafety.resolvesOnlyToPublic("127.0.0.1"))
        XCTAssertFalse(NetworkSafety.resolvesOnlyToPublic("192.168.1.1"))
        XCTAssertFalse(NetworkSafety.resolvesOnlyToPublic("no-existe-de-verdad.invalid"))
        // Con red: XCTAssertTrue(NetworkSafety.resolvesOnlyToPublic("apple.com"))
        // y XCTAssertFalse(NetworkSafety.resolvesOnlyToPublic("192-168-1-1.nip.io"))
    }

    func testNAT64MobileNetworksStillWork() {
        var a = in6_addr()
        XCTAssertEqual(inet_pton(AF_INET6, "64:ff9b::808:808", &a), 1)   // 8.8.8.8 vía NAT64
        XCTAssertTrue(NetworkSafety.isPublicIPv6(a))
        XCTAssertEqual(inet_pton(AF_INET6, "64:ff9b::c0a8:101", &a), 1)  // 192.168.1.1 vía NAT64
        XCTAssertFalse(NetworkSafety.isPublicIPv6(a))
    }

    func testDownloadRefusesLocalHostsBeforeConnecting() async {
        let request = URLRequest(url: URL(string: "http://192.168.1.1/x.png")!)
        do {
            _ = try await NetworkSafety.data(for: request, maxBytes: 1000)
            XCTFail("No debía conectar")
        } catch {
            XCTAssertTrue(error is NetworkSafety.SafetyError)
        }
    }
}
