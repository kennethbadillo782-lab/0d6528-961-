import SwiftUI
import Supabase
import UIKit

private struct CatalogAPIKey: Decodable, Identifiable {
    let id: String
    let label: String
    let key_prefix: String
    let scopes: [String]
    let revoked_at: String?
}
private struct CatalogAPISettings: Decodable { let enabled: Bool }
private struct CatalogAudit: Decodable, Identifiable { let id: Int; let operation: String; let created_at: String }
private struct CreateCatalogKey: Encodable { let p_label: String; let p_scopes: [String]; let p_days: Int }

struct ChatGPTAccessView: View {
    @ObservedObject private var account = CloudAccount.shared
    @State private var enabled = false
    @State private var loaded = false
    @State private var keys: [CatalogAPIKey] = []
    @State private var audit: [CatalogAudit] = []
    @State private var label = "ChatGPT guardar"
    @State private var scope = "create"
    @State private var newKey: String?
    @State private var revokeID: String?
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        AccountCard(title:"Acceso de ChatGPT",symbol:"key") {
            if account.email == nil {
                Text("Inicia sesión para configurar el acceso de ChatGPT.").font(.subheadline)
            } else {
                Toggle("Permitir acceso de ChatGPT",isOn:Binding(get:{enabled},set:{ value in Task { await setEnabled(value) } })).disabled(!loaded || busy)
                Text("Pausarlo bloquea las claves existentes sin borrarlas.").font(.caption).foregroundStyle(.secondary)
                ForEach(keys) { key in
                    VStack(alignment:.leading,spacing:6) {
                        Text(String(key.label.prefix(60)))
                        Text("\(key.key_prefix)… · \(key.scopes.joined(separator:", "))").font(.caption).foregroundStyle(.secondary)
                        if key.revoked_at == nil { Button("Revocar clave",role:.destructive) { revokeID = key.id }.disabled(busy) }
                        else { Text("Revocada").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                TextField("Nombre de la clave",text:$label)
                Picker("Permisos",selection:$scope) {
                    Text("Solo guardar").tag("create")
                    Text("Solo consultar").tag("read")
                    Text("Consultar y guardar").tag("read,create")
                    Text("Consultar y editar").tag("read,write")
                }
                Button("Crear clave (180 días)") { Task { await createKey() } }.buttonStyle(SecondaryButtonStyle()).disabled(busy || label.trimmingCharacters(in:.whitespaces).isEmpty)
                Text("Para mayor aislamiento usa dos GPTs: uno que guarda y otro que consulta. Ninguna clave permite borrar productos.").font(.caption).foregroundStyle(.secondary)
                if !audit.isEmpty {
                    Text("Últimas operaciones").font(.headline)
                    ForEach(audit.prefix(10)) { item in Text("\(String(item.operation.prefix(60))) · \(String(item.created_at.prefix(19)))").font(.caption) }
                }
                Button("Actualizar acceso e historial") { Task { await refresh() } }.disabled(busy)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id:account.email) { if account.email != nil { await refresh() } }
        .sheet(isPresented:Binding(get:{newKey != nil},set:{if !$0 { newKey = nil }})) {
            NavigationStack {
                VStack(alignment:.leading,spacing:20) {
                    Text("Guarda esta clave ahora. Se muestra una sola vez; el servidor conserva únicamente su huella.")
                    if let newKey { Text(newKey).font(.system(.caption,design:.monospaced)).textSelection(.enabled).privacySensitive() }
                    Button("Copiar clave") { if let newKey { UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic:newKey]],options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(120)]) } }
                    Text("Pégala solo en la autenticación de la acción de tu GPT, encabezado X-API-Key. No en una conversación.").font(.caption)
                    Spacer()
                }.padding().navigationTitle("Clave nueva").toolbar { Button("Listo") { newKey = nil } }
            }
        }
        .confirmationDialog("¿Revocar esta clave definitivamente?",isPresented:Binding(get:{revokeID != nil},set:{if !$0 {revokeID = nil}}),titleVisibility:.visible) {
            Button("Revocar",role:.destructive) { if let id = revokeID { Task { await revoke(id) } }; revokeID = nil }
            Button("Cancelar",role:.cancel) { revokeID = nil }
        }
    }
    @MainActor private func refresh() async {
        guard let client = account.client else { return }
        busy = true; defer { busy = false }
        do {
            let settings: [CatalogAPISettings] = try await client.from("api_settings").select("enabled").limit(1).execute().value
            enabled = settings.first?.enabled ?? false
            keys = try await client.from("api_keys").select("id,label,key_prefix,scopes,revoked_at").order("created_at",ascending:false).limit(20).execute().value
            audit = try await client.from("api_audit_log").select("id,operation,created_at").order("created_at",ascending:false).limit(10).execute().value
            loaded = true; message = ""
        } catch { message = "No se pudo consultar el acceso. Revisa la sesión y la conexión." }
    }
    @MainActor private func setEnabled(_ value: Bool) async {
        guard let client = account.client else { return }
        busy = true
        do { let session = try await client.auth.session; try await client.from("api_settings").update(["enabled":value]).eq("owner_id",value:session.user.id).execute(); enabled = value }
        catch { message = "No se pudo cambiar el acceso. El servidor conserva el estado anterior." }
        busy = false
    }
    @MainActor private func createKey() async {
        guard let client = account.client else { return }
        busy = true
        do { let key: String = try await client.rpc("create_api_key",params:CreateCatalogKey(p_label:String(label.prefix(60)),p_scopes:scope.split(separator:",").map(String.init),p_days:180)).execute().value; newKey = key; await refresh() }
        catch { message = "No se pudo crear la clave. Revisa la conexión; el máximo es 5 claves activas." }
        busy = false
    }
    @MainActor private func revoke(_ id: String) async {
        guard let client = account.client else { return }
        busy = true
        do { try await client.from("api_keys").update(["revoked_at":CloudMapping.stamp(Date())]).eq("id",value:id).execute(); await refresh() }
        catch { message = "No se pudo revocar. Comprueba internet y vuelve a intentarlo." }
        busy = false
    }
}
