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

	/// The nodes the chosen radio has heard, for `matches(…, heardByNodeNums:)`. Nil when the
	/// filter is off, or when the chosen radio is no longer one of the user's radios, so a stale
	/// choice never empties the lists.
	func heardByNodeNums(in context: ModelContext) -> Set<Int64>? {
		guard heardByRadio != 0 else { return nil }
		return Self.nodeNums(heardBy: heardByRadio, in: context)
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

/// "Heard By" picker for the node, map and contact filters. Only shown once the user has more
/// than one radio; with one, every node is heard by it.
struct NodeHeardByFilterPicker: View {
	@Environment(\.modelContext) private var context
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

	private func radioName(_ radioNum: Int64) -> String {
		if let device = accessoryManager.connectedSession(forRadio: radioNum)?.device {
			return device.shortName ?? device.longName ?? device.name
		}
		let user = getNodeInfo(id: radioNum, context: context)?.user
		return user?.longName ?? user?.shortName ?? radioNum.toHex()
	}
}
