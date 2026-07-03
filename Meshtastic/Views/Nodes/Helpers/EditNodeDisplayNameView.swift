//
//  EditNodeDisplayNameView.swift
//  Meshtastic
//
//  Alert-based prompt to set or clear a local display name for a node.
//

import SwiftUI

extension View {
	/// Presents a native alert with a text field to set/clear a node's local display name.
	/// Driven by `node`: assign a node to present the alert for it, `nil` (or Cancel/Save) dismisses it.
	func displayNameAlert(node: Binding<NodeInfoEntity?>) -> some View {
		modifier(DisplayNameAlertModifier(node: node))
	}
}

private struct DisplayNameAlertModifier: ViewModifier {
	@Binding var node: NodeInfoEntity?
	@State private var displayName = ""
	/// The value loaded when the alert appeared, so Save is only enabled on a real edit -- comparing
	/// against a plain "did anything change" flag would also fire the moment the alert opens for a
	/// node that already has a name (see the load in `onChange(of: node?.num)` below).
	@State private var initialDisplayName = ""

	/// Matches the Long Name field's byte cap in UserConfig.swift (the protobuf User.long_name max),
	/// so a local nickname can't grow larger than a node's real long name could. Purely a consistency
	/// choice -- the nickname itself is local-only and never touches the mesh.
	private static let maxBytes = 36

	func body(content: Content) -> some View {
		content
			.alert(
				"Display Name",
				isPresented: Binding(get: { node != nil }, set: { isPresented in if !isPresented { node = nil } }),
				presenting: node
			) { presentedNode in
				TextField("Display name", text: $displayName)
					.autocorrectionDisabled(true)
					.onChange(of: displayName) { _, newValue in
						var clamped = newValue.withoutVariationSelectors
						while clamped.utf8.count > Self.maxBytes {
							clamped = String(clamped.dropLast())
						}
						if clamped != newValue { displayName = clamped }
					}
				Button("Cancel", role: .cancel) {
					node = nil
				}
				Button("Save") {
					let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
					NodeDisplayNameStore.setDisplayName(trimmed.isEmpty ? nil : trimmed, for: presentedNode.num)
					node = nil
				}
				.disabled(displayName == initialDisplayName)
			} message: { _ in
				Text("This name is only shown on this device. The node's real name is unchanged for sharing and export.")
			}
			.onChange(of: node?.num) { _, newNum in
				let current = newNum.flatMap { NodeDisplayNameStore.displayName(for: $0) } ?? ""
				displayName = current
				initialDisplayName = current
			}
	}
}
