import SwiftUI

struct Avatar: View {
    private let name: String?
    private let background: Color
	private let size: CGFloat

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
			RoundedRectangle(cornerRadius: size / 4, style: .continuous)
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
