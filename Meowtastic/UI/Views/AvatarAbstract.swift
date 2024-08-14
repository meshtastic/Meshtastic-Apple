import SwiftUI

struct AvatarAbstract: View {
	private let name: String?
	private let icon: String
	private let color: Color?
	private let size: CGFloat

	// swiftlint:disable:next large_tuple
	private let corners: (Bool, Bool, Bool, Bool)?

	private var background: Color {
		if let color {
			return color
		}
		else {
			return .accentColor
		}
	}
	private var foreground: Color {
		background.isLight() ? .black : .white
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
			if let name, !name.isEmpty {
				Text(name)
					.font(.system(size: 128, weight: .heavy, design: .rounded))
					.foregroundColor(foreground)
					.lineLimit(1)
					.minimumScaleFactor(0.01)
					.padding(.all, size / 8)
					.frame(width: size, height: size)
			}
			else {
				Image(systemName: icon)
					.resizable()
					.scaledToFit()
					.foregroundColor(foreground.opacity(0.5))
					.padding(.all, size / 8)
					.frame(width: size, height: size)
			}
		}
		.background(background)
		.clipShape(
			UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
		)
	}

	init(
		_ name: String? = nil,
		icon: String = "person.fill.questionmark",
		color: Color? = nil,
		size: CGFloat = 45,
		// swiftlint:disable:next large_tuple
		corners: (Bool, Bool, Bool, Bool)? = nil
	) {
		self.name = name
		self.icon = icon
		self.color = color
		self.size = size
		self.corners = corners
	}
}
