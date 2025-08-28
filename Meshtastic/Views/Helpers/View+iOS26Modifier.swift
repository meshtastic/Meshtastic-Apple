//
//  View+iOS26Modifier.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/29/25.
//

import Foundation
import SwiftUI

extension View {
	@ViewBuilder
	func iOS26Modifier(
		_ contentBuilder: (@escaping (Self) -> some View)
	) -> some View {
		if #available(iOS 26.0, macOS 26.0, *) {
			contentBuilder(self)
		} else {
			self
		}
	}
	
	@ViewBuilder
	func olderThaniOS26Modifier(
		_ contentBuilder: (@escaping (Self) -> some View)
	) -> some View {
		if #available(iOS 26.0, macOS 26.0, *) {
			self
		} else {
			contentBuilder(self)
		}
	}
}
