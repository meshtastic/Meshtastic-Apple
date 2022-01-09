import Foundation
import SwiftUI

extension Data {
    var hexDescription: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
	var macAddressString: String {
		let mac: String = reduce("") {$0 + String(format: "%02x:", $1)}
		return String(mac.dropLast())
	}
}

extension Date {
    static var currentTimeStamp: Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}

extension String {

    /// Create `Data` from hexadecimal string representation
    ///
    /// This creates a `Data` object from hex string. Note, if the string has any spaces or non-hex characters (e.g. starts with '<' and with a '>'), those are ignored and only hex characters are processed.
    ///
    /// - returns: Data represented by this hexadecimal string.

    var hexadecimal: Data? {
        var data = Data(capacity: count / 2)

        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, range: NSRange(startIndex..., in: self)) { match, _, _ in
            let byteString = (self as NSString).substring(with: match!.range)
            let num = UInt8(byteString, radix: 16)!
            data.append(num)
        }

        guard data.count > 0 else { return nil }

        return data
    }
	
	func image(fontSize:CGFloat = 40, bgColor:UIColor = UIColor.clear, imageSize:CGSize? = nil) -> UIImage?
	{
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

}

typealias NodeColor = Int

extension NodeColor {
  // a color to represent an individual meshtastic device
	var color: Color {
		switch self {
		case 0:
			return Color(.red)
		case 1:
			return Color(.blue)
		case 2:
			return Color(.yellow)
		case 3:
			return Color(.green)
		case 4:
			return Color(.purple)
		case 5:
			return Color(.systemPink)
		case 6:
			return Color(.systemTeal)
		case 7:
			return Color(.black)
		case 8:
			return Color(.gray)
		case 9:
			return Color(.brown)
		case 10:
			return Color(.magenta)
		case 11:
			return Color(.orange)
		case 12:
			return Color(.cyan)
		default:
			return Color(.blue)
		}
	}
}
