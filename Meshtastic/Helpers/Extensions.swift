import Foundation
import SwiftUI
import MapKit

extension Character {
	var isEmoji: Bool {
		guard let scalar = unicodeScalars.first else { return false }
		return scalar.properties.isEmoji && (scalar.value >= 0x203C || unicodeScalars.count > 1)
	}
}

extension CLLocationCoordinate2D {
	/// Returns distance from coordianate in meters.
	/// - Parameter from: coordinate which will be used as end point.
	/// - Returns: distance in meters.
	func distance(from: CLLocationCoordinate2D) -> CLLocationDistance {
		let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
		let to = CLLocation(latitude: self.latitude, longitude: self.longitude)
		return from.distance(from: to)
	}
}

extension Color {
	///  Returns a boolean for a SwiftUI Color to determine what color of text to use
	/// - Returns: true if the color is light
	func isLight() -> Bool {
		guard let components = cgColor?.components, components.count > 2 else {return false}
		let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
		return (brightness > 0.5)
	}
}

extension UIColor {
	
	///  Returns a boolean indicating if a color is light
	/// - Returns: true if the color is light
	func isLight() -> Bool {
		guard let components = cgColor.components, components.count > 2 else {return false}
		let brightness = ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
		return (brightness > 0.5)
	}
	
	///  Returns a UInt32 from a UIColor
	/// - Returns: UInt32
	var hex: UInt32 {
		   var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		   getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		   var value: UInt32 = 0
		   value += UInt32(1.0 * 255) << 24
		   value += UInt32(red   * 255) << 16
		   value += UInt32(green * 255) << 8
		   value += UInt32(blue  * 255)
		   return value
	}
	
	///  Returns a UIColor from a UInt32 value
	/// - Parameter hex: UInt32 value  to convert to a color
	/// - Returns: UIColor
	convenience init(hex: UInt32) {
		let red = CGFloat((hex & 0xFF0000) >> 16)
		let green = CGFloat((hex & 0x00FF00) >> 8)
		let blue = CGFloat((hex & 0x0000FF))
		//print("\(red) - \(green) - \(blue)")
		self.init(red: red/255.0, green: green/255.0, blue: blue/255.0, alpha: 1.0)
	}
}

extension Data {
	var macAddressString: String {
		let mac: String = reduce("") {$0 + String(format: "%02x:", $1)}
		return String(mac.dropLast())
	}
	var hexDescription: String {
		return reduce("") {$0 + String(format: "%02x", $1)}
	}
}

extension Date {
    static var currentTimeStamp: Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

	func formattedDate(format: String) -> String {
		let dateformat = DateFormatter()
		dateformat.dateFormat = format
		return dateformat.string(from: self)
	}
}

extension Float {

	func formattedTemperature() -> String {
		let temperature = Measurement<UnitTemperature>(value: Double(self), unit: .celsius)
		return temperature.formatted(.measurement(width: .abbreviated, usage: .weather))
	}
	func localeTemperature() -> Double {
		let temperature = Measurement<UnitTemperature>(value: Double(self), unit: .celsius)
		let locale = NSLocale.current as NSLocale
		let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
		var format: UnitTemperature = .celsius

		if localeUnit! as? String == "Fahrenheit" {
			format = .fahrenheit
		}
		return temperature.converted(to: format).value
	}
}

extension Int {

	func numberOfDigits() -> Int {
		if abs(self) < 10 {
			return 1
		} else {
			return 1 + (self/10).numberOfDigits()
		}
	}
}

extension UIImage {
	func rotate(radians: Float) -> UIImage? {
		var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
		newSize.width = floor(newSize.width)
		newSize.height = floor(newSize.height)
		UIGraphicsBeginImageContextWithOptions(newSize, false, self.scale)
		let context = UIGraphicsGetCurrentContext()!
		context.translateBy(x: newSize.width/2, y: newSize.height/2)
		context.rotate(by: CGFloat(radians))
		self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))
		let newImage = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()

		return newImage
	}
}

extension String {

	func base64urlToBase64() -> String {
		var base64 = self
			.replacingOccurrences(of: "-", with: "+")
			.replacingOccurrences(of: "_", with: "/")
		if base64.count % 4 != 0 {
			base64.append(String(repeating: "==", count: 4 - base64.count % 4))
		}
		return base64
	}

	func base64ToBase64url() -> String {
		let base64url = self
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
		return base64url
	}

	func onlyEmojis() -> Bool {
		return count > 0 && !contains { !$0.isEmoji }
	}

	func image(fontSize: CGFloat = 40, bgColor: UIColor = UIColor.clear, imageSize: CGSize? = nil) -> UIImage? {
		let font = UIFont.systemFont(ofSize: fontSize)
		let attributes = [NSAttributedString.Key.font: font]
		let imageSize = imageSize ?? self.size(withAttributes: attributes)
		UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
		bgColor.set()
		let rect = CGRect(origin: .zero, size: imageSize)
		UIRectFill(rect)
		self.draw(in: rect, withAttributes: [.font: font])
		let image = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		return image
	}

	func camelCaseToWords() -> String {
		return unicodeScalars.dropFirst().reduce(String(prefix(1))) {
			return CharacterSet.uppercaseLetters.contains($1)
				? $0 + " " + String($1)
				: $0 + String($1)
		}
	}
}

extension UserDefaults {

	enum Keys: String, CaseIterable {
		case meshtasticUsername
		case preferredPeripheralId
		case provideLocation
		case provideLocationInterval
		case keyboardType
		case meshMapType
		case meshMapCenteringMode
		case meshMapRecentering
		case meshMapCustomTileServer
		case meshMapUserTrackingMode
		case meshMapShowNodeHistory
		case meshMapShowRouteLines
	}

	func reset() {
		Keys.allCases.forEach { removeObject(forKey: $0.rawValue) }
	}
}
