//
//  NodeFilterParameters+UnheardOnCurrentLora.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftData
import SwiftUI

// MARK: - Not heard on current LoRa, per radio (feature 021)

/// One radio's NodeInfo.heard_on_current_lora answers, from its observations as saved.
///
/// Each radio answers for its own LoRa settings: after A moves from LongFast to LongTurbo, A
/// reports the nodes it heard on LongFast as not heard, while B, still on LongFast, doesn't. So a
/// window shows its own radio's answers, and the same node can carry the marker in A's window and
/// not in B's. Read through a fresh `ModelContext`: a long-lived one can hold values from before
/// another context's save (T382).
enum RadioLoraAnswers {
	struct Answer: Equatable {
		/// The radio's answer; nil when it gave none, or no longer has the node.
		let heard: Bool?
		/// The radio has the node over MQTT, which says nothing about its LoRa settings.
		let viaMqtt: Bool

		/// Not heard on the radio's current settings: a different claim from offline.
		var isUnheard: Bool { heard == false && !viaMqtt }
	}

	/// Every answer of radio `radioNum`'s, by node.
	static func answers(ofRadio radioNum: Int64, container: ModelContainer) -> [Int64: Answer] {
		guard radioNum != 0 else { return [:] }
		let descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == radioNum })
		let observations = (try? ModelContext(container).fetch(descriptor)) ?? []
		var answers: [Int64: Answer] = [:]
		for observation in observations {
			answers[observation.nodeNum] = Answer(heard: observation.heardOnCurrentLora, viaMqtt: observation.viaMqtt)
		}
		return answers
	}

	/// Radio `radioNum`'s answer for node `nodeNum`; nil when it has no observation of it.
	static func answer(of nodeNum: Int64, radioNum: Int64, container: ModelContainer) -> Answer? {
		let key = NodeObservationEntity.key(radioNum: radioNum, nodeNum: nodeNum)
		var descriptor = FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.key == key })
		descriptor.fetchLimit = 1
		guard let observation = (try? ModelContext(container).fetch(descriptor))?.first else { return nil }
		return Answer(heard: observation.heardOnCurrentLora, viaMqtt: observation.viaMqtt)
	}

	/// The nodes radio `radioNum` reports not heard on its current settings.
	static func unheardNodeNums(ofRadio radioNum: Int64, container: ModelContainer) -> Set<Int64> {
		Set(answers(ofRadio: radioNum, container: container).filter { $0.value.isUnheard }.keys)
	}
}

/// When a window looks its radio's answers up again: its radio changed, or that radio's node
/// database was saved.
struct RadioLoraAnswersKey: Equatable {
	let radioNum: Int64
	let savedAt: Date?
}

extension AccessoryManager {
	/// The radio whose answers `window` shows: its radio, also while it's disconnected, since the
	/// answers stay with its observations.
	func answeringRadioNum(for window: RadioWindow) -> Int64 {
		nodeNum(for: window) ?? radioNodeNum(for: window)
	}

	func radioLoraAnswersKey(for window: RadioWindow) -> RadioLoraAnswersKey {
		let radioNum = answeringRadioNum(for: window)
		return RadioLoraAnswersKey(radioNum: radioNum, savedAt: nodeDatabaseSavedAt[radioNum])
	}
}

/// Keeps `NodeFilterParameters.unheardOnCurrentLoraNodeNums` to the window's radio's answers, for
/// its node list, map and contacts: looked up when the window's radio changes, when its node
/// database is saved, and when an answer changes (`heardOnCurrentLoraDidChange`). Never while a
/// list or the map renders (T163).
struct UnheardOnCurrentLoraRefresh: ViewModifier {
	@Environment(\.modelContext) private var context
	@Environment(\.windowRadio) private var windowRadio
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@ObservedObject var filters: NodeFilterParameters

	func body(content: Content) -> some View {
		content
			.task(id: accessoryManager.radioLoraAnswersKey(for: windowRadio)) {
				refresh()
			}
			.onReceive(NotificationCenter.default.publisher(for: .heardOnCurrentLoraDidChange)) { _ in
				refresh()
			}
	}

	private func refresh() {
		let radioNum = accessoryManager.answeringRadioNum(for: windowRadio)
		filters.setUnheardOnCurrentLoraNodeNums(RadioLoraAnswers.unheardNodeNums(ofRadio: radioNum, container: context.container))
	}
}

extension View {
	func refreshesUnheardOnCurrentLora(_ filters: NodeFilterParameters) -> some View {
		modifier(UnheardOnCurrentLoraRefresh(filters: filters))
	}
}
