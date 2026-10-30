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
    private func weidianPage(gallery: [String], variants: [(String, String)], prices: [String: Double] = [:]) -> String {
        let values = variants.enumerated().map { i, v in ["attr_id": 100 + i, "attr_value": v.0, "img": "https://si.geilicdn.com/\(v.1).jpg"] as [String: Any] }
        // Combinaciones modelo-talla con su precio, como en la página real ("attr_ids": "100-7").
        var skus: [String: Any] = [:]
        for (i, v) in variants.enumerated() {
            if let price = prices[v.0] { skus["\(i)"] = ["attr_ids": "\(100 + i)-7", "price": String(format: "%.2f", price)] }
        }
        let obj: [String: Any] = ["result": ["default_model": [
            "item_info": ["imgs": gallery.map { "https://si.geilicdn.com/\($0).jpg" }, "item_name": "GX Batch 4"],
            "sku_properties": ["attr_list": [["attr_title": "COLORS", "attr_values": values]], "sku": skus],
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

    func testNicknamesPriceAndCollabBreakTies() {
        // "Bred" es "Black and red" en la tienda (caso real de Repsun).
        let repsun = weidianPage(gallery: [], variants: [("FQ8138-600 Bull", "bull"), ("IX 8180-001 Black and red 2026", "bred26"),
                                                        ("308497-007 Cool Gray", "grey")])
        XCTAssertEqual(PhotoSources.weidianPhotos(html: repsun, productName: "Jordan 4 Bred 2026 — GX Batch"),
                       .photos([URL(string: "https://si.geilicdn.com/bred26.jpg?w=1080&h=1080&cp=1")!]))
        // Dos Black Cat en el mismo anuncio: decide el precio del producto.
        let cats = [PhotoSources.Variant(name: "2025 Black Cat", image: URL(string: "https://a/2025.jpg")!, price: 440),
                    PhotoSources.Variant(name: "Black Cat 2020", image: URL(string: "https://a/2020.jpg")!, price: 480),
                    PhotoSources.Variant(name: "Black Red", image: URL(string: "https://a/br.jpg")!, price: 440)]
        XCTAssertEqual(PhotoSources.bestVariant(for: "Jordan 4 Black Cat — GX Batch", price: 440, in: cats)?.name, "2025 Black Cat")
        // Sin precio ni año que los separe, no se elige ninguno.
        XCTAssertNil(PhotoSources.bestVariant(for: "Jordan 4 Black Cat", price: nil, in: cats))
        XCTAssertEqual(PhotoSources.bestVariant(for: "Jordan 4 Black Cat 2020", price: nil, in: cats)?.name, "Black Cat 2020")
        // "SB" desempata entre dos Navy; solo "SB" no identifica nada.
        let navies = [PhotoSources.Variant(name: "SB Navy", image: URL(string: "https://a/sb.jpg")!),
                      PhotoSources.Variant(name: "Midnight Navy", image: URL(string: "https://a/mn.jpg")!),
                      PhotoSources.Variant(name: "SB Pine Green", image: URL(string: "https://a/pine.jpg")!)]
        XCTAssertEqual(PhotoSources.bestVariant(for: "Air Jordan 4 SB Navy — GX Batch", price: nil, in: navies)?.name, "SB Navy")
        XCTAssertNil(PhotoSources.bestVariant(for: "Jordan 4 SB", price: nil, in: navies))
    }

    func testPriceMismatchAsksInsteadOfGuessing() {
        // Caso real de TMF: "Navy Blue" cuesta ¥500 y el producto se guardó a ¥450.
        let tmf = weidianPage(gallery: ["cover"], variants: [("GX AJ4 Navy Blue", "navy"), ("GX AJ4 Black Cat 2025", "cat")],
                              prices: ["GX AJ4 Navy Blue": 500, "GX AJ4 Black Cat 2025": 420])
        guard case .ambiguous(_, let choices) = PhotoSources.weidianPhotos(html: tmf, productName: "Jordan 4 SB Navy — GX Batch", price: 450) else {
            return XCTFail("Un modelo con otro precio no se pone sin confirmar")
        }
        XCTAssertEqual(choices.first?.name, "GX AJ4 Navy Blue")
        XCTAssertEqual(choices.first?.price, 500)
        // Con el precio correcto, o con el precio «desde» del anuncio, sí se pone.
        XCTAssertEqual(PhotoSources.weidianPhotos(html: tmf, productName: "Jordan 4 SB Navy", price: 500),
                       .photos([URL(string: "https://si.geilicdn.com/navy.jpg?w=1080&h=1080&cp=1")!]))
        XCTAssertEqual(PhotoSources.weidianPhotos(html: tmf, productName: "Jordan 4 SB Navy", price: 420),
                       .photos([URL(string: "https://si.geilicdn.com/navy.jpg?w=1080&h=1080&cp=1")!]))
    }

    func testModelNamedByChatGPTWins() {
        // Dos Black Cat al mismo precio: sin ayuda hay que preguntar; con el modelo que guardó ChatGPT, no.
        let gxmade = weidianPage(gallery: [], variants: [("2025 Black Cat（best-selling)", "cat25"), ("Black Cat 2020", "cat20"),
                                                         ("SB Navy", "navy")],
                                 prices: ["2025 Black Cat（best-selling)": 440, "Black Cat 2020": 440, "SB Navy": 440])
        guard case .ambiguous = PhotoSources.weidianPhotos(html: gxmade, productName: "Jordan 4 Black Cat — GX Batch", price: 440) else {
            return XCTFail("Sin el modelo indicado debe preguntar")
        }
        let cat25 = URL(string: "https://si.geilicdn.com/cat25.jpg?w=1080&h=1080&cp=1")!
        XCTAssertEqual(PhotoSources.weidianPhotos(html: gxmade, productName: "Jordan 4 Black Cat", price: 440,
                                                  listingModel: "2025 Black Cat（best-selling)"), .photos([cat25]))
        // Escrito de otra forma también vale si solo un modelo lo contiene.
        XCTAssertEqual(PhotoSources.weidianPhotos(html: gxmade, productName: "Jordan 4 Black Cat", price: 440,
                                                  listingModel: "black cat 2025"), .photos([cat25]))
        // Manda incluso si el precio guardado no cuadra.
        XCTAssertEqual(PhotoSources.weidianPhotos(html: gxmade, productName: "Jordan 4 SB Navy", price: 999, listingModel: "SB Navy"),
                       .photos([URL(string: "https://si.geilicdn.com/navy.jpg?w=1080&h=1080&cp=1")!]))
        // Un modelo que no existe en el anuncio no inventa nada: vuelve a las reglas normales.
        guard case .ambiguous = PhotoSources.weidianPhotos(html: gxmade, productName: "Jordan 4 Black Cat", price: 440, listingModel: "Cool Grey") else {
            return XCTFail("Modelo inexistente: no debe elegir")
        }
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
        let items: [(String, String, Double)] = [("7815143816", "Jordan 4 Black Cat — GX Batch", 440),
                                                  ("7242121077", "Jordan 4 Bred 2026 — GX Batch", 430),
                                                  ("7327048497", "Jordan 4 SB Navy — GX Batch", 450)]
        for (id, name, price) in items {
            let html = await LinkImportService.html(URL(string: "https://weidian.com/item.html?itemID=\(id)")!)
            let data = html.flatMap(PhotoSources.weidianData)
            let matching = data?.variants.filter { $0.name.lowercased().contains("cat") || $0.name.lowercased().contains("navy") || $0.name.lowercased().contains("red") }
            print("LIVE \(id): gallery=\(data?.gallery.count ?? -1) relevant=\(matching?.map { "\($0.name) ¥\($0.price ?? -1)" } ?? [])")
            print("LIVE \(id) → \(html.map { PhotoSources.weidianPhotos(html: $0, productName: name, price: price) } ?? .nothing)")
        }
    }
}
