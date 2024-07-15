import SwiftUI

struct Avatar: View {
    private let name: String?
    private let background: Color
	private let size: CGFloat

	var body: some View {
		ZStack(alignment: .center) {
			if let name = name {
				Text(name)
					.font(.system(size: 128, weight: .heavy, design: .rounded))
					.foregroundColor(background.isLight() ? .black : .white)
					.minimumScaleFactor(0.1)
					.padding(.all, 8)
					.frame(width: size, height: size)
			}
			else {
				Image(systemName: "questionmark")
					.font(.system(size: 128, weight: .heavy, design: .rounded))
					.foregroundColor(background.isLight() ? .black : .white)
					.minimumScaleFactor(0.1)
					.padding(.all, 8)
					.frame(width: size, height: size)
			}
		}
		.background(background)
		.clipShape(
			RoundedRectangle(cornerRadius: size / 4)
		)
	}

	init(
		_ name: String?,
		background: Color,
		size: CGFloat = 45
	) {
		self.name = name
		self.background = background
		self.size = size
	}
}
