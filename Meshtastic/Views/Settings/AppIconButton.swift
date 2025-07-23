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
	@State var errorDetails: String?
	@State var didError = false

    var body: some View {
		Button {
			UIApplication.shared.setAlternateIconName(iconName) { error in
				if let error = error {
					errorDetails = error.localizedDescription
					didError = true
				}
			}
		} label: {
			HStack(alignment: .center) {
				let imageName = "\(iconName ?? "AppIcon")_Thumb"
				if let image = UIImage(named: imageName) {
					Image(uiImage: image)
						.resizable()
						.aspectRatio(contentMode: .fill)
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
		AppIconButton(iconDescription: .constant("Default"), iconName: .constant("AppIcon"))
	}
}
