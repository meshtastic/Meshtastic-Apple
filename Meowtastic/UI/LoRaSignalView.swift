import Foundation
import SwiftUI

struct LoRaSignalView: View {
	let signalStrength: LoRaSignalStrength

	@ViewBuilder
	var body: some View {
		HStack {
			ForEach(0..<3) { bar in
				RoundedRectangle(cornerRadius: 3)
					.divided(amount: (CGFloat(bar) + 1) / CGFloat(3))
					.fill(
						getColor(signalStrength: signalStrength)
							.opacity(bar <= signalStrength.rawValue ? 1 : 0.3)
					)
					.frame(width: 8, height: 40)
			}
		}
	}

	private func getColor(signalStrength: LoRaSignalStrength) -> Color {
		switch signalStrength {
		case .none:
			return Color.red
		case .bad:
			return Color.orange
		case .fair:
			return Color.yellow
		case .good:
			return Color.green
		}
	}
}
