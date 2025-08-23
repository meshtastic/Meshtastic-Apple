//
//  AppIconButton.swift
//  Meshtastic
//
//  Created by Chase Christiansen on 7/21/25.
//

import SwiftUI

struct AppIconButton: View {
	@Binding var iconDescription: String
	@Binding var iconName: String?
	@Binding var isPresenting: Bool
	@State var errorDetails: String?
	@State var didError = false

	@Environment(\.colorScheme) var colorScheme

    var body: some View {
		Button {
			UIApplication.shared.setAlternateIconName(iconName) { error in
				if let error = error {
					errorDetails = error.localizedDescription
					didError = true
				} else {
					self.isPresenting = false
				}
			}
		} label: {
			HStack(alignment: .center) {
				let imageName = colorScheme == .dark ? "\(iconName ?? "AppIcon")_Dark_Thumb" : "\(iconName ?? "AppIcon")_Thumb"

				if let image = UIImage(named: imageName) {
					Image(uiImage: image)
						.resizable()
						.aspectRatio(contentMode: .fill)
						.background(.thickMaterial)
						.frame(width: 50, height: 50)
						.clipShape(RoundedRectangle(cornerRadius: 8))
				}

				VStack(alignment: .leading) {
					Text(iconDescription)
				}
			}
		}
	}
}

#Preview {
	List {
		AppIconButton(iconDescription: .constant("Default"), iconName: .constant("AppIcon"), isPresenting: .constant(true))
	}
}
