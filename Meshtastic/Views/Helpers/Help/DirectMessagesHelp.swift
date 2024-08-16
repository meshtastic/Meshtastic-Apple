//
//  DirectMessagesHelp.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen on 8/15/24.
//

import SwiftUI

struct DirectMessagesHelp: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		ScrollView {
			Text("Direct Message Help")
				.font(.title)
				.padding(.vertical)
			VStack(alignment: .leading) {
				HStack {
					Image(systemName: "star.fill")
						.foregroundColor(.yellow)
						.padding(.bottom)
					Text("Favorites and nodes with recent messages show up at the top of the contact list.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
				HStack {
					Image(systemName: "hand.tap")
						.padding(.bottom)
					Text("Long press to favorite or mute the contact or delete a conversation.")
						.fixedSize(horizontal: false, vertical: true)
						.padding(.bottom)
				}
			}
			if idiom == .phone {
				VStack(alignment: .leading) {
					LockLegend()
					AckErrors()
				}
			} else {
				HStack(alignment: .top) {
					LockLegend()
					AckErrors()
						.padding(.trailing)
				}
			}
#if targetEnvironment(macCatalyst)
		Spacer()
		Button {
			dismiss()
		} label: {
			Label("close", systemImage: "xmark")
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.controlSize(.large)
		.padding(.bottom)
#endif
		}
		.frame(minHeight: 0, maxHeight: .infinity, alignment: .leading)
		.padding()
		.presentationDetents([.large])
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}

struct DirectMessagesHelpPreviews: PreviewProvider {
	static var previews: some View {
		VStack {
			AckErrors()
		}
	}
}
