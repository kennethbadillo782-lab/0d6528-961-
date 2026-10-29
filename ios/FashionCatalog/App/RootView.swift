import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) var context

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack { HomeView().withAppRoutes() }
                .tabItem { Label("Inicio", systemImage: "house.fill") }
                .tag(AppTab.home)

            NavigationStack { ProductBrowserScreen(title: "Explorar", scope: .all).withAppRoutes() }
                .tabItem { Label("Explorar", systemImage: "magnifyingglass") }
                .tag(AppTab.explore)

            NavigationStack { SavedView().withAppRoutes() }
                .tabItem { Label("Guardados", systemImage: "bookmark") }
                .tag(AppTab.saved)

            NavigationStack { CollectionsView().withAppRoutes() }
                .tabItem { Label("Colecciones", systemImage: "folder") }
                .tag(AppTab.collections)

            NavigationStack { AccountView().withAppRoutes() }
                .tabItem { Label("Cuenta", systemImage: "person") }
                .tag(AppTab.account)
        }
        .tint(Theme.blue)
        .sheet(item: $appState.addRequest) { request in
            AddProductView(request: request)
        }
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                ToastView(message: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task { SeedService.seedIfNeeded(context) }
    }
}

enum AppRoute: Hashable {
    case product(Product)
    case category(key: String, subcategory: String?)
    case group(QuickGroup)
    case brand(String)
    case allProducts
    case allCategories
    case collection(ProductCollection)
    case categoriesManager
    case categoryEditor(CatalogCategory)
}

extension View {
    func withAppRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .product(let product):
                ProductDetailView(product: product)
            case .category(let key, let subcategory):
                CategoryScreen(categoryKey: key, initialSubcategory: subcategory)
            case .group(let group):
                GroupScreen(group: group)
            case .brand(let brand):
                ProductBrowserScreen(title: brand, scope: .brand(brand))
            case .allProducts:
                ProductBrowserScreen(title: "Todo", scope: .all)
            case .allCategories:
                AllCategoriesView()
            case .collection(let collection):
                CollectionDetailView(collection: collection)
            case .categoriesManager:
                CategoriesManagerView()
            case .categoryEditor(let category):
                CategoryEditView(category: category)
            }
        }
    }
}
