//
//  EditNodeDisplayNameView.swift
//  Meshtastic
//
//  Sheet to set or clear a local display name for a node.
//

import SwiftUI

struct EditNodeDisplayNameView: View {
	@Environment(\.dismiss) private var dismiss
	let node: NodeInfoEntity
	@State private var displayName: String = ""
	/// The value loaded in `onAppear`, so Save is only enabled on a real edit — comparing against
	/// a plain "did anything change" flag would also fire when `onAppear` assigns `displayName` from
	/// the store, enabling Save (and letting a no-op tap re-save the same value and re-post
	/// `didChangeNotification`) the instant the sheet opens for a node that already has a name.
	@State private var initialDisplayName: String = ""

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Display name", text: $displayName)
						.autocorrectionDisabled(true)
				} footer: {
					Text("This name is only shown on this device. The node's real name is unchanged for sharing and export.")
				}
				if NodeDisplayNameStore.displayName(for: node.num) != nil {
					Section {
						Button(role: .destructive) {
							displayName = ""
						} label: {
							Label("Remove custom name", systemImage: "trash")
						}
					}
				}
			}
			.navigationTitle("Display name")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						dismiss()
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
						NodeDisplayNameStore.setDisplayName(trimmed.isEmpty ? nil : trimmed, for: node.num)
						dismiss()
					}
					.disabled(displayName == initialDisplayName)
				}
			}
			.onAppear {
				let current = NodeDisplayNameStore.displayName(for: node.num) ?? ""
				displayName = current
				initialDisplayName = current
			}
		}
	}
}
