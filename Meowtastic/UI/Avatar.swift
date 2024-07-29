import SwiftUI

struct Avatar: View {
	private let name: String?
	private let temperature: Double?
	private let background: Color
	private let size: CGFloat

	// swiftlint:disable:next large_tuple
	private let corners: (Bool, Bool, Bool, Bool)?

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
					.foregroundColor(background.isLight() ? .black : .white)
					.lineLimit(1)
					.minimumScaleFactor(0.01)
					.padding(.all, size / 8)
					.frame(width: size, height: size)
			}
			else {
				Image(systemName: "questionmark")
					.resizable()
					.scaledToFit()
					.foregroundColor(background.isLight() ? .black : .white)
					.padding(.all, size / 8)
					.frame(width: size, height: size)
			}

			if let temperature {
				let tempFormatted = String(format: "%.0f", temperature)

				HStack(alignment: .center, spacing: 2) {
					Text(tempFormatted)
						.font(.system(size: 10, weight: .semibold, design: .rounded))
						.foregroundColor(
							(background.isLight() ? Color.black : Color.white)
								.opacity(0.8)
						)
						.lineLimit(1)

					Image(systemName: "thermometer.variable")
						.font(.system(size: 7, weight: .semibold, design: .rounded))
						.foregroundColor(
							(background.isLight() ? Color.black : Color.white)
								.opacity(0.8)
						)
				}
				.padding(.horizontal, 6)
				.padding(.vertical, 2)
				.frame(width: size, height: size, alignment: .bottomTrailing)
			}
		}
		.background(background)
		.clipShape(
			UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
		)
	}

	init(
		_ name: String?,
		temperature: Double? = nil,
		background: Color,
		size: CGFloat = 45,
		// swiftlint:disable:next large_tuple
		corners: (Bool, Bool, Bool, Bool)? = nil
	) {
		self.name = name
		self.temperature = temperature
		self.background = background
		self.size = size
		self.corners = corners
	}
}
