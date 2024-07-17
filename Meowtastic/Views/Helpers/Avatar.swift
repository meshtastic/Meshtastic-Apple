import SwiftUI

struct Avatar: View {
    private let name: String?
    private let background: Color
	private let size: CGFloat
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
					.minimumScaleFactor(0.1)
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
		}
		.background(background)
		.clipShape(
			UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
		)
	}

	init(
		_ name: String?,
		background: Color,
		size: CGFloat = 45,
		corners: (Bool, Bool, Bool, Bool)? = nil
	) {
		self.name = name
		self.background = background
		self.size = size
		self.corners = corners
	}
}
