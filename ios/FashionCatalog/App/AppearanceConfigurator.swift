import UIKit

/// Configura la barra de navegación y la barra de pestañas para que coincidan con el diseño oscuro.
enum AppearanceConfigurator {
    static func configure() {
        let background = UIColor(red: 8 / 255, green: 11 / 255, blue: 14 / 255, alpha: 1)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = background
        nav.shadowColor = .clear
        nav.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 19, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = .white

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        // Más oscura que el contenido y con borde visible: la barra no se mezcla con lo de detrás.
        tab.backgroundColor = UIColor(red: 10 / 255, green: 10 / 255, blue: 12 / 255, alpha: 1)
        tab.shadowColor = UIColor(white: 1, alpha: 0.09)
        let normal = UIColor(red: 0.62, green: 0.64, blue: 0.68, alpha: 1)
        let selected = UIColor(red: 139 / 255, green: 124 / 255, blue: 246 / 255, alpha: 1)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [
                .foregroundColor: normal,
                .font: UIFont.systemFont(ofSize: 10, weight: .medium)
            ]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [
                .foregroundColor: selected,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
