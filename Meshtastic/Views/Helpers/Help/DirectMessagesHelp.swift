//
//  DirectMessagesHelp.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen on 8/15/24.
//

import SwiftUI

struct DirectMessagesHelp: View {
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				Section {
					HelpItem(
						symbol: AnyView(
							Image(systemName: "star.fill")
								.font(.title3)
								.foregroundColor(.yellow)
						),
						title: String(localized: "Favorites"),
						subtitle: String(localized: "Favorites and nodes with recent messages show up at the top of the contact list.")
					)
					HelpItem(
						symbol: AnyView(
							Image(systemName: "hand.tap")
								.font(.title3)
								.foregroundColor(.primary)
						),
						title: String(localized: "Long Press Actions"),
						subtitle: String(localized: "Long press to favorite or mute the contact or delete a conversation.")
					)
				} header: {
					Text("Contacts")
				}
				LockLegend()
				AckErrors()
			}
			.navigationTitle("Direct Messages Help")
			.navigationBarTitleDisplayMode(.inline)
#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("Close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.large])
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .large))
	}
}

struct DirectMessagesHelpPreviews: PreviewProvider {
	static var previews: some View {
		DirectMessagesHelp()
	}
}
