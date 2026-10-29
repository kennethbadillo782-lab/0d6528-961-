import SwiftUI
import SwiftData

struct CloudAccountView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var account = CloudAccount.shared
    @ObservedObject private var sync = CatalogSync.shared
    @State private var email = ""
    @State private var link = ""
    var body: some View {
        AccountCard(title:"Sincronización",symbol:"arrow.triangle.2.circlepath") {
            if let address = account.email {
                Text(address).font(.subheadline).foregroundStyle(.secondary)
                Text(sync.status).accessibilityIdentifier("cloud.sync.status")
                if let date = sync.lastSync { Text(date,style:.time).font(.caption).foregroundStyle(.secondary) }
                Button(sync.isSyncing ? "Sincronizando…" : "Sincronizar ahora") { Task { await sync.run(context:context) } }
                    .buttonStyle(SecondaryButtonStyle()).disabled(sync.isSyncing)
                Button("Cerrar sesión") { Task { await account.signOut() } }.disabled(sync.isSyncing)
            } else {
                Text("Entra con tu correo para conectar este catálogo. Sin conexión puedes seguir editando.").font(.subheadline)
                TextField("Tu correo",text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.emailAddress)
                    .accessibilityIdentifier("cloud.email")
                Button("Enviar enlace de acceso") { Task { await account.sendLink(email) } }.buttonStyle(SecondaryButtonStyle()).disabled(account.busy || email.isEmpty)
                TextField("Pega aquí el enlace recibido (Appetize)",text:$link).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Button("Entrar con el enlace") { let value = link; link = ""; Task { await account.acceptLink(value); await sync.run(context:context) } }
                    .buttonStyle(SecondaryButtonStyle()).disabled(account.busy || link.isEmpty)
            }
            Text(account.message).font(.caption).foregroundStyle(.secondary)
            Text("Solo tu cuenta puede acceder. Las fotos se guardan en almacenamiento privado. Cerrar sesión conserva la copia local en este dispositivo.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
