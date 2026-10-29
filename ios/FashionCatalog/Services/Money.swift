import Foundation

/// Precios en su moneda original con conversión opcional a USD.
/// Las tasas se guardan con su fecha; si no existe tasa, nunca se inventa una conversión.
enum Money {
    static let supported = ["USD", "CNY", "EUR", "GBP", "JPY", "KRW", "HKD", "MXN", "CAD"]

    static func symbol(for code: String) -> String {
        switch code {
        case "USD": return "$"
        case "CNY", "JPY": return "¥"
        case "EUR": return "€"
        case "GBP": return "£"
        case "KRW": return "₩"
        case "HKD": return "HK$"
        case "MXN": return "MX$"
        case "CAD": return "CA$"
        default: return code + " "
        }
    }

    static func name(for code: String) -> String {
        switch code {
        case "USD": return "Dólar estadounidense"
        case "CNY": return "Yuan chino"
        case "EUR": return "Euro"
        case "GBP": return "Libra esterlina"
        case "JPY": return "Yen japonés"
        case "KRW": return "Won surcoreano"
        case "HKD": return "Dólar de Hong Kong"
        case "MXN": return "Peso mexicano"
        case "CAD": return "Dólar canadiense"
        default: return code
        }
    }

    static func format(_ amount: Double, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        let isWhole = amount.rounded() == amount
        f.minimumFractionDigits = isWhole ? 0 : 2
        f.maximumFractionDigits = 2
        let number = f.string(from: NSNumber(value: amount)) ?? String(amount)
        let sym = symbol(for: code)
        return code == "USD" ? sym + number : sym + " " + number
    }

    // MARK: Tasas (USD por 1 unidad de la moneda)

    static func rate(for code: String) -> (value: Double, updated: Date)? {
        if code == "USD" { return (1, Date()) }
        let defaults = UserDefaults.standard
        let value = defaults.double(forKey: "rate.\(code)")
        guard value > 0 else { return nil }
        let time = defaults.double(forKey: "rateDate.\(code)")
        return (value, Date(timeIntervalSince1970: time))
    }

    static func setRate(_ value: Double?, for code: String, date: Date = Date()) {
        let defaults = UserDefaults.standard
        if let value, value > 0 {
            defaults.set(value, forKey: "rate.\(code)")
            defaults.set(date.timeIntervalSince1970, forKey: "rateDate.\(code)")
        } else {
            defaults.removeObject(forKey: "rate.\(code)")
            defaults.removeObject(forKey: "rateDate.\(code)")
        }
        defaults.set(defaults.integer(forKey: SettingsKeys.ratesVersion) + 1, forKey: SettingsKeys.ratesVersion)
    }

    static func toUSD(_ amount: Double, code: String) -> Double? {
        guard let r = rate(for: code) else { return nil }
        return amount * r.value
    }

    /// Valor usado para ordenar y filtrar: USD si hay tasa, si no el precio original.
    static func comparableAmount(_ product: Product) -> Double? {
        guard let price = product.priceCurrent else { return nil }
        return toUSD(price, code: product.currency) ?? price
    }

    static var showUSDEquivalent: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.showUSD)
    }

    // MARK: Actualización en línea

    private struct RatesResponse: Decodable {
        let date: String
        let rates: [String: Double]
    }

    enum RatesError: LocalizedError {
        case badResponse
        var errorDescription: String? { "El servicio de tasas no respondió correctamente." }
    }

    /// Usa Frankfurter (tasas de referencia del Banco Central Europeo, gratuito y sin clave).
    @discardableResult
    static func fetchRates() async throws -> Date {
        let codes = supported.filter { $0 != "USD" }.joined(separator: ",")
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=\(codes)") else {
            throw RatesError.badResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RatesError.badResponse
        }
        let decoded = try JSONDecoder().decode(RatesResponse.self, from: data)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let date = df.date(from: decoded.date) ?? Date()
        for (code, perUSD) in decoded.rates where perUSD > 0 {
            setRate(1 / perUSD, for: code, date: date)
        }
        return date
    }
}
