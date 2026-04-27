//
//  Image.swift
//  Meshtastic
//
//  Created by jake on 12/5/25.
//

import SwiftUI

extension Image {
	// Initializer taking a URL
//	init?(svgURL: URL, maxSize: CGSize? = nil) {
//		guard let svg = SVGKImage(contentsOf: svgURL) else { return nil }
//		self.init(svgkImage: svg, maxSize: maxSize)
//	}
//	
//	// Initializer taking Data
//	init?(svgData: Data, maxSize: CGSize? = nil) {
//		guard let svg = SVGKImage(data: svgData) else { return nil }
//		self.init(svgkImage: svg, maxSize: maxSize)
//	}
//	
//	// MARK: - Private Shared Logic
//	
////	private init?(svgkImage svg: SVGKImage, maxSize: CGSize?) {
////		guard let root = svg.domDocument?.rootElement as? SVGSVGElement else { return nil }
////		
////		// Calculate the intrinsic size, handling missing width/height attributes
////		// by falling back to the viewBox if necessary.
////		let intrinsicSize: CGSize = {
////			if let w = root.width, w.valueInSpecifiedUnits > 0,
////			   let h = root.height, h.valueInSpecifiedUnits > 0 {
////				return CGSize(width: CGFloat(root.width.valueInSpecifiedUnits),
////							  height: CGFloat(root.height.valueInSpecifiedUnits))
////			} else if root.hasAttribute("viewBox") {
////				let viewBox = root.viewBox
////				if viewBox.width > 0, viewBox.height > 0 {
////					return CGSize(width: CGFloat(viewBox.width),
////								  height: CGFloat(viewBox.height))
////				}
////			}
////			return svg.size // Fallback
////		}()
////		
////		guard intrinsicSize.width > 0, intrinsicSize.height > 0 else { return nil }
////		
////		// Apply scaling if maxSize is provided
////		if let maxSize {
////			let scale = min(maxSize.width / intrinsicSize.width,
////							maxSize.height / intrinsicSize.height)
////			svg.size = CGSize(width: intrinsicSize.width * scale,
////							  height: intrinsicSize.height * scale)
////		} else {
////			svg.size = intrinsicSize
////		}
////		
////		guard let uiImage = svg.uiImage else { return nil }
////		self.init(uiImage: uiImage)
////	}
}
