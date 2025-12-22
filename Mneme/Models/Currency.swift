import Foundation

struct Currency: Identifiable, Hashable, Codable, Sendable {
    let code: String
    let symbol: String
    let name: String
    
    var id: String { code }
    
    nonisolated static let all: [Currency] = [
        Currency(code: "USD", symbol: "$", name: "US Dollar"),
        Currency(code: "EUR", symbol: "€", name: "Euro"),
        Currency(code: "TRY", symbol: "₺", name: "Turkish Lira"),
        Currency(code: "GBP", symbol: "£", name: "British Pound"),
        Currency(code: "JPY", symbol: "¥", name: "Japanese Yen"),
        Currency(code: "AUD", symbol: "A$", name: "Australian Dollar"),
        Currency(code: "CAD", symbol: "C$", name: "Canadian Dollar"),
        Currency(code: "CHF", symbol: "Fr", name: "Swiss Franc"),
        Currency(code: "CNY", symbol: "¥", name: "Chinese Yuan"),
        Currency(code: "SEK", symbol: "kr", name: "Swedish Krona"),
        Currency(code: "NZD", symbol: "NZ$", name: "New Zealand Dollar"),
        Currency(code: "MXN", symbol: "$", name: "Mexican Peso"),
        Currency(code: "SGD", symbol: "S$", name: "Singapore Dollar"),
        Currency(code: "HKD", symbol: "HK$", name: "Hong Kong Dollar"),
        Currency(code: "NOK", symbol: "kr", name: "Norwegian Krone"),
        Currency(code: "KRW", symbol: "₩", name: "South Korean Won"),
        Currency(code: "INR", symbol: "₹", name: "Indian Rupee"),
        Currency(code: "RUB", symbol: "₽", name: "Russian Ruble"),
        Currency(code: "BRL", symbol: "R$", name: "Brazilian Real"),
        Currency(code: "ZAR", symbol: "R", name: "South African Rand"),
        Currency(code: "DKK", symbol: "kr", name: "Danish Krone"),
        Currency(code: "PLN", symbol: "zł", name: "Polish Zloty"),
        Currency(code: "THB", symbol: "฿", name: "Thai Baht"),
        Currency(code: "IDR", symbol: "Rp", name: "Indonesian Rupiah"),
        Currency(code: "HUF", symbol: "Ft", name: "Hungarian Forint"),
        Currency(code: "CZK", symbol: "Kč", name: "Czech Koruna"),
        Currency(code: "ILS", symbol: "₪", name: "Israeli New Shekel"),
        Currency(code: "MYR", symbol: "RM", name: "Malaysian Ringgit"),
        Currency(code: "PHP", symbol: "₱", name: "Philippine Peso"),
        Currency(code: "RON", symbol: "lei", name: "Romanian Leu"),
        Currency(code: "BGN", symbol: "лв", name: "Bulgarian Lev"),
        Currency(code: "HRK", symbol: "kn", name: "Croatian Kuna"),
        Currency(code: "ISK", symbol: "kr", name: "Icelandic Króna")
    ]
    
    nonisolated static let supportedCodes: Set<String> = Set(all.map { $0.code })
    
    static func from(code: String) -> Currency? {
        // Case insensitive match
        let upper = code.uppercased()
        return all.first { $0.code == upper }
    }
}
