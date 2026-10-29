import SwiftUI
import SwiftData

/// Panel de la campana: lo que está listo para comprar, pendiente y lo agregado recientemente.
struct ActivityView: View {
    @Environment(\.dismiss) var dismiss
    @Query(sort: \Product.updatedAt, order: .reverse) var products: [Product]

    private var ready: [Product] { products.filter { $0.status == .ready } }
    private var pending: [Product] { products.filter { $0.status == .pending } }
    private var recent: [Product] { Array(products.sorted { $0.createdAt > $1.createdAt }.prefix(8)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if products.isEmpty {
                        EmptyStateView(symbol: "bell", title: "Sin actividad",
                                       message: "Aquí verás los productos listos para comprar y lo último que agregaste.")
                    } else {
                        section("Listos para comprar", ready)
                        section("Pendientes de comprar", pending)
                        section("Agregados recientemente", recent)
                        Text("Los avisos automáticos de bajadas de precio llegarán cuando se active la sincronización con una fuente de precios.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(Theme.hPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Actividad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(Theme.blue)
                }
            }
            .withAppRoutes()
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Product]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: title)
                ForEach(items) { p in
                    NavigationLink(value: AppRoute.product(p)) {
                        SavedRow(product: p)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
