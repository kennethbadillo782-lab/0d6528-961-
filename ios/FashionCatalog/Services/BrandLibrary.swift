import Foundation
import UIKit

/// Biblioteca de marcas incluida en la app (brands.json): nombre, alias y si hay logo verificado.
/// Los logos son marcas registradas de sus titulares; aquí solo identifican marcas de tu propia lista.
enum BrandLibrary {
    private struct Entry: Decodable {
        let id: String
        let name: String
        let aliases: [String]
        let logo: Bool
        /// Logo con colores propios (no se tiñe de blanco). Por defecto, monocromo.
        var logoColor: Bool? = nil
    }

    private static let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "brands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }()

    private static let byKey: [String: Entry] = {
        var map: [String: Entry] = [:]
        for e in entries {
            for name in [e.name] + e.aliases where !key(name).isEmpty {
                if map[key(name)] == nil { map[key(name)] = e }
            }
        }
        return map
    }()

    /// Igual que el descargador: sin acentos, minúsculas, solo letras y números ("H&M" → "handm").
    static func key(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en"))
            .replacingOccurrences(of: "&", with: " and ")
        return String(folded.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
    }

    /// Nombre oficial de la marca si se reconoce (por nombre o alias), si no el texto guardado.
    static func displayName(_ brand: String) -> String {
        byKey[key(brand)]?.name ?? brand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func logoHasColor(_ brand: String) -> Bool { byKey[key(brand)]?.logoColor ?? false }

    /// Logo verificado incluido en la app, si existe para esa marca.
    static func logo(_ brand: String) -> UIImage? {
        guard let entry = byKey[key(brand)], entry.logo else { return nil }
        return UIImage(named: "brand-\(entry.id)")
    }
}
