import Foundation

enum FixedFractionNumberFormatter {
	static func format<Value: BinaryFloatingPoint>(
		_ value: Value,
		fractionDigits: Int,
		locale: Locale = .autoupdatingCurrent
	) -> String {
		let formatter = NumberFormatter()
		formatter.locale = locale
		formatter.numberStyle = .decimal
		formatter.minimumFractionDigits = fractionDigits
		formatter.maximumFractionDigits = fractionDigits
		formatter.roundingMode = .halfEven

		return formatter.string(from: NSNumber(value: Double(value)))
			?? String(format: "%.\(fractionDigits)f", locale: locale, Double(value))
	}
}
