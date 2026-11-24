//
//  NodeMapWidgetIntent.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/21/26.
//
//  The Node Map widget's configuration: which nodes the map shows, and, on
//  the small size, whether the counts sit over the map. The app renders a map
//  for each node choice a widget on a screen uses.
//

import AppIntents

enum NodeMapFilter: String, AppEnum, CaseIterable {
	case all
	case online
	case favorites

	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Nodes")
	static let caseDisplayRepresentations: [NodeMapFilter: DisplayRepresentation] = [
		.all: "All",
		.online: "Online",
		.favorites: "Favorites"
	]

	/// Whether the map shows `node`. The connected radio is always shown, ringed.
	func includes(_ node: NodeSnapshot, radioNum: Int64?) -> Bool {
		if node.num == radioNum { return true }
		switch self {
		case .all: return true
		case .online: return node.isOnline
		case .favorites: return node.isFavorite
		}
	}
}

struct NodeMapWidgetIntent: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Node Map"
	static let description = IntentDescription("Pick the nodes the map shows.")

	@Parameter(title: "Nodes", default: .all)
	var filter: NodeMapFilter

	/// The small size only; the larger sizes lay their details beside the map.
	@Parameter(title: "Show Labels", default: true)
	var showsLabels: Bool

	init() {}

	static var parameterSummary: some ParameterSummary {
		Switch(.widgetFamily) {
			Case(.systemSmall) {
				Summary {
					\.$filter
					\.$showsLabels
				}
			}
			DefaultCase {
				Summary {
					\.$filter
				}
			}
		}
	}
}
