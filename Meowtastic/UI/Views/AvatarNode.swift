import SwiftUI

struct AvatarNode: View {
	private let size: CGFloat
	private let ignoreOffline: Bool
	private let showTemperature: Bool

	// swiftlint:disable:next large_tuple
	private let corners: (Bool, Bool, Bool, Bool)?

	@ObservedObject
	private var node: NodeInfoEntity

	private var name: String? {
		node.user?.shortName
	}

	private var background: Color {
		if node.isOnline || ignoreOffline {
			return Color(
				UIColor(hex: UInt32(node.num))
			)
		}
		else {
			return Color.gray.opacity(0.7)
		}
	}

	private var foreground: Color {
		background.isLight() ? .black : .white
	}

	private var temperature: Double? {
		let nodeEnvironment = node
			.telemetries?
			.filtered(
				using: NSPredicate(format: "metricsType == 1")
			)
			.lastObject as? TelemetryEntity

		guard let temperature = nodeEnvironment?.temperature else {
			return nil
		}

		return Double(temperature)
	}

	private var radii: RectangleCornerRadii {
		let radius = size / 4

		if let corners {
			return RectangleCornerRadii(
				topLeading: corners.0 ? radius : 0,
				bottomLeading: corners.1 ? radius : 0,
				bottomTrailing: corners.2 ? radius : 0,
				topTrailing: corners.3 ? radius : 0
			)
		}
		else {
			return RectangleCornerRadii(
				topLeading: radius,
				bottomLeading: radius,
				bottomTrailing: radius,
				topTrailing: radius
			)
		}
	}

	var body: some View {
		ZStack(alignment: .center) {
			if let name = name, !name.isEmpty {
				Text(name)
					.font(.system(size: 128, weight: .heavy, design: .rounded))
					.foregroundColor(foreground)
					.lineLimit(1)
					.minimumScaleFactor(0.01)
					.padding(.all, size / 8)
					.frame(width: size, height: size)
			}
			else {
				Image(systemName: "questionmark")
					.resizable()
					.scaledToFit()
					.foregroundColor(foreground)
					.padding(.all, size / 8)
					.frame(width: size, height: size)
			}

			if showTemperature, node.isOnline, let temperature {
				let tempFormatted = String(format: "%.0f", temperature)

				HStack(alignment: .center, spacing: 2) {
					Text(tempFormatted)
						.font(.system(size: size / 6, weight: .semibold, design: .rounded))
						.foregroundColor(
							background // inverted colors
								.opacity(0.8)
						)
						.lineLimit(1)

					Image(systemName: "thermometer.variable")
						.font(.system(size: size / 8, weight: .semibold, design: .rounded))
						.foregroundColor(
							background // inverted colors
								.opacity(0.8)
						)
				}
				.padding(.horizontal, size / 6)
				.padding(.vertical, size / 32)
				.background(foreground) // inverted colors
				.clipShape(
					UnevenRoundedRectangle(
						cornerRadii: RectangleCornerRadii(topLeading: 4)
					)
				)
				.frame(width: size, height: size, alignment: .bottomTrailing)
			}
		}
		.background(background)
		.clipShape(
			UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
		)
	}

	init(
		_ node: NodeInfoEntity,
		ignoreOffline: Bool = false,
		showTemperature: Bool = false,
		size: CGFloat = 45,
		// swiftlint:disable:next large_tuple
		corners: (Bool, Bool, Bool, Bool)? = nil
	) {
		self.node = node
		self.ignoreOffline = ignoreOffline
		self.showTemperature = showTemperature
		self.size = size
		self.corners = corners
	}
}
