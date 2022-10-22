import Foundation
import SwiftUI

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

extension Int {

	func numberOfDigits() -> Int {
		if abs(self) < 10 {
			return 1
		} else {
			return 1 + (self/10).numberOfDigits()
		}
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
