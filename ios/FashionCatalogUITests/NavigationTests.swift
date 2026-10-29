import XCTest

final class NavigationTests: XCTestCase {
    func testAllFiveTabsOpenAndAppRelaunches() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launch()
        for title in ["Inicio", "Explorar", "Guardados", "Colecciones", "Cuenta"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 15), "Falta pestaña \(title)")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "No se abrió \(title)")
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = title
            capture.lifetime = .keepAlways
            add(capture)
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Inicio"].waitForExistence(timeout: 15))
    }
}
