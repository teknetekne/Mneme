import Foundation

extension Double {
    /// Returns a string representation of the double.
    /// If the double has no fractional part (e.g. 15.0), returns it as an integer ("15").
    /// Otherwise returns the original double string.
    var clean: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
    
    /// Returns a formatted string with optional maximum fraction digits.
    /// If the value is an integer, it returns it without decimals.
    /// If it has decimals, it respects the maxDecimals parameter.
    func clean(maxDecimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxDecimals
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
