//
//  EditNodeDisplayNameView.swift
//  Meshtastic
//
//  Sheet to set or clear a local display name for a node.
//

import SwiftUI
import CoreData

struct EditNodeDisplayNameView: View {
	@Environment(\.dismiss) private var dismiss
	let node: NodeInfoEntity
	@State private var displayName: String = ""
	@State private var hasChanges: Bool = false

	var body: some View {
		NavigationStack {
			Form {
				Section {
					TextField("Display name", text: $displayName)
						.autocorrectionDisabled(true)
						.onChange(of: displayName) { _, _ in hasChanges = true }
				} footer: {
					Text("This name is only shown on this device. The node’s real name is unchanged for sharing and export.")
				}
				if NodeDisplayNameStore.displayName(for: node.num) != nil {
					Section {
						Button(role: .destructive) {
							displayName = ""
							hasChanges = true
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
					.disabled(!hasChanges)
				}
			}
			.onAppear {
				displayName = NodeDisplayNameStore.displayName(for: node.num) ?? ""
			}
		}
	}
}
