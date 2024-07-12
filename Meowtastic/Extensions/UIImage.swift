//
//  UIImage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation
import UIKit

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
