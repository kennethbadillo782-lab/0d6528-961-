import SwiftUI
import SwiftData

enum AppTab: Hashable {
    // "add" no es una pantalla: al tocarla se abre la hoja de agregar producto.
    case home, explore, add, saved, collections
}

struct AddProductRequest: Identifiable {
    let id = UUID()
    var prefillURL: String = ""
    var collectionID: PersistentIdentifier? = nil
}

final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var addRequest: AddProductRequest?
    @Published var toast: String?

    func presentAdd(url: String? = nil, collection: ProductCollection? = nil) {
        addRequest = AddProductRequest(prefillURL: url ?? "", collectionID: collection?.persistentModelID)
    }

    func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        let current = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard self?.toast == current else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
    }
}
