//
//  NodeFilterParameters+HeardBy.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftData
import SwiftUI

// MARK: - Heard-by filter (feature 021, T087)

extension NodeFilterParameters {

	/// Looks up the nodes the chosen radio has heard, for `matches(…, heardByNodeNums:)`. Nil
	/// when the filter is off, or when the chosen radio is no longer one of the user's radios,
	/// so a stale choice never empties the lists. Only assigned when it changed.
	func refreshHeardByNodeNums(in context: ModelContext) {
		let nodeNums = heardByRadio == 0 ? nil : Self.nodeNums(heardBy: heardByRadio, in: context)
		if nodeNums != heardByNodeNums {
			setHeardByNodeNums(nodeNums)
		}
	}

	/// Every node `radioNum` has an observation of, plus the radio itself. Nil when `radioNum`
	/// isn't one of the user's radios (no `MyInfoEntity`).
	static func nodeNums(heardBy radioNum: Int64, in context: ModelContext) -> Set<Int64>? {
		let radioDescriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum })
		guard ((try? context.fetchCount(radioDescriptor)) ?? 0) > 0 else { return nil }
		var descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == radioNum })
		descriptor.propertiesToFetch = [\.nodeNum]
		var nodeNums = Set(((try? context.fetch(descriptor)) ?? []).map(\.nodeNum))
		nodeNums.insert(radioNum)
		return nodeNums
	}
}

/// Keeps `NodeFilterParameters.heardByNodeNums` current for a list or map: looked up when the
/// chosen radio changes and every 15 s while the filter is on, as the radio hears more nodes.
struct HeardByRefresh: ViewModifier {
	@Environment(\.modelContext) private var context
	@ObservedObject var filters: NodeFilterParameters

	func body(content: Content) -> some View {
		content.task(id: filters.heardByRadio) {
			while !Task.isCancelled {
				filters.refreshHeardByNodeNums(in: context)
				guard filters.heardByRadio != 0 else { return }
				try? await Task.sleep(for: .seconds(15))
			}
		}
	}
}

extension View {
	func refreshesHeardBy(_ filters: NodeFilterParameters) -> some View {
		modifier(HeardByRefresh(filters: filters))
	}
}

/// "Heard By" picker for the node, map and contact filters. Only shown once the user has more
/// than one radio; with one, every node is heard by it.
struct NodeHeardByFilterPicker: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@ObservedObject var filters: NodeFilterParameters
	@Query(sort: \MyInfoEntity.myNodeNum) private var radios: [MyInfoEntity]

	var body: some View {
		let radioNums = radios.map(\.myNodeNum).filter { $0 != 0 }
		if radioNums.count > 1 {
			Picker(selection: $filters.heardByRadio) {
				Text("Any Radio").tag(Int64(0))
				ForEach(radioNums, id: \.self) { radioNum in
					Text(radioName(radioNum)).tag(radioNum)
				}
			} label: {
				Label("Heard By", systemImage: "antenna.radiowaves.left.and.right")
			}
			.listRowSeparator(.visible)
			.onAppear {
				// A radio the user has since removed would otherwise stay selected, unlisted.
				if filters.heardByRadio != 0 && !radioNums.contains(filters.heardByRadio) {
					filters.heardByRadio = 0
				}
			}
		}
	}

	/// From the queried radios' relationships, not a fetch: this runs while the picker renders.
	private func radioName(_ radioNum: Int64) -> String {
		if let device = accessoryManager.connectedSession(forRadio: radioNum)?.device {
			return device.shortName ?? device.longName ?? device.name
		}
		let user = radios.first { $0.myNodeNum == radioNum }?.myInfoNode?.user
		return user?.longName ?? user?.shortName ?? radioNum.toHex()
	}
}
