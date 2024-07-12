import Foundation
import SwiftUI

struct NodeListFilter: View {
	var filterTitle = "Node Filters"

	@Binding
	var isFavorite: Bool
	@Binding
	var isOnline: Bool
	@Binding
	var ignoreMQTT: Bool
	@State
	var editMode = EditMode.active

	@Environment(\.dismiss)
	private var dismiss

	var body: some View {
		NavigationStack {
			Form {
				Section(header: Text(filterTitle)) {
					Toggle(isOn: $isFavorite) {
						Label {
							Text("Favorites")
						} icon: {
							Image(systemName: "star.fill")
								.foregroundColor(.yellow)
								.symbolRenderingMode(.hierarchical)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $isOnline) {
						Label {
							Text("Online")
						} icon: {
							Image(systemName: "checkmark.circle.fill")
								.foregroundColor(.green)
								.symbolRenderingMode(.hierarchical)
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)

					Toggle(isOn: $ignoreMQTT) {
						Label {
							Text("Ignore MQTT")
						} icon: {
							Image(systemName: "dot.radiowaves.up.forward")
						}
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.listRowSeparator(.visible)
				}
			}
		}
		.presentationDetents([
			.fraction(0.65)
		])
		.presentationDragIndicator(.visible)
	}
}
