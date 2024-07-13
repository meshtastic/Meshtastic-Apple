import SwiftUI

struct Avatar: View {
    private let name: String?
    private let background: Color
	private let size: CGFloat

    var body: some View {
        ZStack {
			RoundedRectangle(cornerRadius: size / 4)
				.fill(background)
				.frame(width: size, height: size)

			if let name = name {
				Text(name)
					.frame(width: size * 0.9, height: size * 0.9, alignment: .center)
					.foregroundColor(background.isLight() ? .black : .white)
					.minimumScaleFactor(0.001)
					.font(.system(size: 1300))
			}
			else {
				Image(systemName: "questionmark")
					.frame(width: size * 0.9, height: size * 0.9, alignment: .center)
					.foregroundColor(background.isLight() ? .black : .white)
					.minimumScaleFactor(0.001)
					.font(.system(size: 1300))
			}
        }
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

private struct CircleText_Previews: PreviewProvider {
    static var previews: some View {
		VStack {
			HStack {
				Avatar("N1", background: Color.yellow, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("8", background: Color.purple, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("😝", background: Color.red, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("🍔", background: Color.brown, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}

			HStack {
				Avatar("👻", background: Color.orange, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("🤙", background: Color.orange, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("69", background: Color.green, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("WWWW", background: Color.cyan, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}

			HStack {
				Avatar("CW-A", background: Color.secondary)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("CW-A", background: Color.secondary, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("MOMO", background: Color.mint, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("IIII", background: Color.accentColor, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}

			HStack {
				Avatar("🚗", background: Color.orange)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("🔋", background: Color.indigo, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("🛢️", background: Color.orange, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
				Avatar("LCP", background: Color.indigo, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}

			HStack {
				Avatar("🤡", background: Color.red, size: 80)
					.previewLayout(.fixed(width: 300, height: 100))
			}
		}
    }
}
