import XCTest
@testable import MiCatalogo

/// Reglas para encontrar las fotos del anuncio del producto exacto.
final class PhotoSourcesTests: XCTestCase {

    func testAgentLinksPointToTheOriginalStore() {
        let cases: [(String, String)] = [
            ("https://www.hipobuy.com/product/weidian/7815143816", "https://weidian.com/item.html?itemID=7815143816"),
            ("https://www.kakobuy.com/item/details?url=https%3A%2F%2Fweidian.com%2Fitem.html%3FitemID%3D7242121077", "https://weidian.com/item.html?itemID=7242121077"),
            ("https://www.cssbuy.com/item-micro-7327048497.html", "https://weidian.com/item.html?itemID=7327048497"),
            ("https://www.cssbuy.com/item-1688-735474104361.html", "https://detail.1688.com/offer/735474104361.html"),
            ("https://www.cssbuy.com/item-711566484587.html", "https://item.taobao.com/item.htm?id=711566484587"),
            ("https://www.sugargoo.com/#/home/productDetail?productLink=https%3A%2F%2Fweidian.com%2Fitem.html%3FitemID%3D7815143816", "https://weidian.com/item.html?itemID=7815143816"),
            ("https://cnfans.com/product?shop_type=taobao&id=711566484587", "https://item.taobao.com/item.htm?id=711566484587"),
        ]
        for (agent, store) in cases {
            XCTAssertEqual(PhotoSources.storeURL(fromAgent: URL(string: agent)!)?.absoluteString, store, agent)
        }
        XCTAssertNil(PhotoSources.storeURL(fromAgent: URL(string: "https://www.hipobuy.com/")!))
    }

    /// Página de Weidian con el formato real: JSON dentro de data-obj con entidades HTML.
    private func weidianPage(gallery: [String], variants: [(String, String)]) -> String {
        let values = variants.map { ["attr_value": $0.0, "img": "https://si.geilicdn.com/\($0.1).jpg"] }
        let obj: [String: Any] = ["result": ["default_model": [
            "item_info": ["imgs": gallery.map { "https://si.geilicdn.com/\($0).jpg" }, "item_name": "GX Batch 4"],
            "sku_properties": ["attr_list": [["attr_title": "COLORS", "attr_values": values]]],
        ]]]
        let json = String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
        let encoded = json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&#34;")
        return "<html><script crossorigin=\"anonymous\" id=\"__rocker-render-inject__\" data-obj=\"\(encoded)\"></script></html>"
    }

    func testMultiModelListingPicksOnlyTheMatchingModel() {
        let html = weidianPage(gallery: ["cover"], variants: [
            ("GX AJ4 Military Blue", "blue"), ("GX AJ4 black red 2.0 leather", "blackred"),
            ("GX AJ4 Black Cat", "blackcat"), ("GX AJ4 SB Navy", "sbnavy"), ("SB Pine Green", "pine"),
            ("2026 Bred（New Arrive）", "bred"),
        ])
        XCTAssertEqual(PhotoSources.weidianPhotos(html: html, productName: "Air Jordan 4 Black Cat — GX Batch"),
                       .photos([URL(string: "https://si.geilicdn.com/blackcat.jpg?w=1080&h=1080&cp=1")!]))
        XCTAssertEqual(PhotoSources.weidianPhotos(html: html, productName: "Air Jordan 4 SB Navy — GX Batch"),
                       .photos([URL(string: "https://si.geilicdn.com/sbnavy.jpg?w=1080&h=1080&cp=1")!]))
        XCTAssertEqual(PhotoSources.weidianPhotos(html: html, productName: "Air Jordan 4 Bred 2026 — GX Batch"),
                       .photos([URL(string: "https://si.geilicdn.com/bred.jpg?w=1080&h=1080&cp=1")!]))
    }

    func testUnknownModelInMultiModelListingStaysPending() {
        let html = weidianPage(gallery: ["cover"], variants: [("GX AJ4 Military Blue", "blue"), ("GX AJ4 Cool Grey", "grey")])
        guard case .ambiguous = PhotoSources.weidianPhotos(html: html, productName: "Air Jordan 4 Black Cat — GX Batch") else {
            return XCTFail("Un modelo que no aparece no debe recibir la foto de otro")
        }
        // Coincidencia parcial ("Black" de Black Red) tampoco basta.
        let partial = weidianPage(gallery: [], variants: [("Black Red", "br"), ("White Cement", "wc")])
        guard case .ambiguous = PhotoSources.weidianPhotos(html: partial, productName: "Jordan 4 Black Cat") else {
            return XCTFail("Una coincidencia parcial no identifica el modelo")
        }
    }

    func testSingleModelListingUsesTheWholeGallery() {
        let html = weidianPage(gallery: ["a", "b", "c"], variants: [("Black", "a")])
        XCTAssertEqual(PhotoSources.weidianPhotos(html: html, productName: "Graham bag"),
                       .photos(["a", "b", "c"].map { URL(string: "https://si.geilicdn.com/\($0).jpg?w=1080&h=1080&cp=1")! }))
        XCTAssertEqual(PhotoSources.weidianPhotos(html: "<html></html>", productName: "x"), .nothing)
    }

    func testYupooAlbumPhotos() {
        let html = #"<img src="//photo.yupoo.com/gxshop/1a2b3c4d/medium.jpg"><img data-src="https:\/\/photo.yupoo.com\/gxshop\/9f8e7d6c\/big.jpg">"#
        XCTAssertEqual(PhotoSources.yupooPhotos(html: html).map(\.absoluteString),
                       ["https://photo.yupoo.com/gxshop/1a2b3c4d/big.jpg", "https://photo.yupoo.com/gxshop/9f8e7d6c/big.jpg"])
    }

    /// Con TEST_RUNNER_PHOTO_LIVE=1: las tres Jordan reales de Weidian.
    func testLiveWeidianJordans() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PHOTO_LIVE"] == "1", "Solo con red y PHOTO_LIVE=1")
        let items = [("7815143816", "Jordan 4 Black Cat — GX Batch"), ("7242121077", "Jordan 4 Bred 2026 — GX Batch"),
                     ("7327048497", "Jordan 4 SB Navy — GX Batch")]
        for (id, name) in items {
            let html = await LinkImportService.html(URL(string: "https://weidian.com/item.html?itemID=\(id)")!)
            let data = html.flatMap(PhotoSources.weidianData)
            print("LIVE \(id): gallery=\(data?.gallery.count ?? -1) variants=\(data?.variants.map(\.name) ?? [])")
            print("LIVE \(id) → \(html.map { PhotoSources.weidianPhotos(html: $0, productName: name) } ?? .nothing)")
        }
    }
}
