//
//  MapButtons.swift
//  Meshtastic
//
//  Copyright © Garth Vander Houwen 4/23/23.
//

import SwiftUI

struct MapButtons: View {
	let buttonWidth: CGFloat = 22
	let width: CGFloat = 45
	@Binding var tracking: UserTrackingModes
	@Binding var isPresentingInfoSheet: Bool
	var body: some View {
		VStack {
			let impactLight = UIImpactFeedbackGenerator(style: .light)
			Button(action: {
				self.isPresentingInfoSheet.toggle()
			}) {
				Image(systemName: isPresentingInfoSheet ? "info.circle.fill" : "info.circle")
					.resizable()
					.frame(width: buttonWidth, height: buttonWidth, alignment: .center)
					.offset(y: -2)
			}
			Divider()
			Button(action: {
				switch self.tracking {
				case .none:
					self.tracking = .follow
				case .follow:
					self.tracking = .followWithHeading
				case .followWithHeading:
					self.tracking = .none
				}
				impactLight.impactOccurred()
			}) {
				Image(systemName: tracking.icon)
					.frame(width: buttonWidth, height: buttonWidth, alignment: .center)
					.offset(y: 3)
			}
		}
		.frame(width: width, height: width*2, alignment: .center)
		.background(Color(UIColor.systemBackground))
		.cornerRadius(8)
		.shadow(radius: 1)
		.offset(x: 3, y: 25)
	}
}

// MARK: Previews
struct MapControl_Previews: PreviewProvider {
	@State static var tracking: UserTrackingModes = .none
	@State static var isPresentingInfoSheet = false
	static var previews: some View {
		Group {
			MapButtons(tracking: $tracking, isPresentingInfoSheet: $isPresentingInfoSheet)
				.environment(\.colorScheme, .light)
			MapButtons(tracking: $tracking, isPresentingInfoSheet: $isPresentingInfoSheet)
				.environment(\.colorScheme, .dark)
		}
		.previewLayout(.fixed(width: 60, height: 100))
	}
}
