//
//  MultiRadioUnheardOnCurrentLoraTests.swift
//  MeshtasticTests
//
//  main's #2575 stores NodeInfo.heard_on_current_lora on the shared node rows, from the one
//  connected radio. Feature 021: only the only radio connected answers it, and a second radio
//  puts the answers back to unknown, so no window shows another radio's answers. Scripted radios
//  as in `MultiRadioConnectFlowTests`.
//

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@MainActor
@Suite("Unheard on current LoRa with several radios", .serialized, .timeLimit(.minutes(1)))
struct MultiRadioUnheardOnCurrentLoraTests {

	private typealias SavedDefaults = ConnectFlowSupport.SavedDefaults
	/// Firmware that sends NodeInfo.heard_on_current_lora (2.8.1+).
	private let reportingFirmware = "2.8.1.abcdef0"

	private func node(_ num: UInt32) -> NodeInfoEntity? {
		let context = ModelContext(PersistenceController.shared.container)
		let nodeNum = Int64(num)
		return try? context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })).first
	}

	private struct Radios {
		let manager: AccessoryManager
		let firstNum: UInt32
		let secondNum: UInt32
		let secondDevice: Device
	}

	/// The first radio connected and its node database saved; the second one ready to connect.
	private func connectFirst(firmware: String) async throws -> Radios {
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let secondNum = firstNum &+ 0x300
		let first = ScriptedRadio(nodeNum: firstNum, firmwareVersion: firmware, dumpNodes: [firstNum &+ 1])
		let second = ScriptedRadio(nodeNum: secondNum, firmwareVersion: reportingFirmware, dumpNodes: [secondNum &+ 1])
		let secondDevice = ConnectFlowSupport.device()
		let manager = ConnectFlowSupport.makeManager(ScriptedTransport(radio: first, radiosByIdentifier: [secondDevice.identifier: second]))
		try await manager.connect(to: ConnectFlowSupport.device())
		try await ConnectFlowSupport.waitUntil { manager.nodeDatabaseSavedAt != nil || !manager.reportsHeardOnCurrentLora }
		return Radios(manager: manager, firstNum: firstNum, secondNum: secondNum, secondDevice: secondDevice)
	}

	@Test("The only radio's answers are stored, as on main; a second radio puts them back to unknown")
	func secondRadioClearsTheAnswers() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: reportingFirmware)
		let manager = radios.manager
		let heardByFirst = radios.firstNum &+ 1

		#expect(manager.heardOnCurrentLoraSession === manager.activeConnection)
		#expect(manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)))
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.secondNum)))
		#expect(manager.nodeDatabaseSavedAt != nil)
		// The scripted dump leaves the field at its default, false: not heard on these settings.
		try await ConnectFlowSupport.waitUntil { node(heardByFirst)?.heardOnCurrentLora == false }
		#expect(node(heardByFirst)?.heardOnCurrentLora == false)

		try await manager.connectAdditionalRadio(radios.secondDevice)
		#expect(manager.soleConnectedSession == nil)
		#expect(manager.heardOnCurrentLoraSession == nil)
		#expect(!manager.reportsHeardOnCurrentLora)
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)), "no window offers the notice")
		#expect(manager.nodeDatabaseSavedAt == nil)
		try await ConnectFlowSupport.waitUntil { node(heardByFirst)?.heardOnCurrentLora == nil }
		#expect(node(heardByFirst)?.heardOnCurrentLora == nil, "the first radio's answer doesn't stand for the second's")
		#expect(node(radios.secondNum &+ 1)?.heardOnCurrentLora == nil, "the second radio's answers aren't stored")
	}

	@Test("A LoRa change asks for the node database again only from the only radio connected")
	func loraChangeRefreshOnlyForTheOnlyRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: reportingFirmware)
		let manager = radios.manager

		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: Int64(radios.secondNum))
		#expect(!manager.awaitingNodeDatabaseAfterLoRaChange, "not the radio whose answers are kept")
		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: Int64(radios.firstNum))
		#expect(manager.awaitingNodeDatabaseAfterLoRaChange, "the one radio, as on main")

		try await manager.connectAdditionalRadio(radios.secondDevice)
		#expect(!manager.awaitingNodeDatabaseAfterLoRaChange, "a second radio stands the wait down")
		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: Int64(radios.firstNum))
		#expect(!manager.awaitingNodeDatabaseAfterLoRaChange)
	}

	@Test("A radio whose firmware doesn't send the field answers nothing, alone or not")
	func olderFirmwareAnswersNothing() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: "2.7.15.567b8ea")
		let manager = radios.manager

		#expect(manager.soleConnectedSession === manager.activeConnection)
		#expect(manager.heardOnCurrentLoraSession == nil)
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)))
		#expect(node(radios.firstNum &+ 1)?.heardOnCurrentLora == nil)
	}
}
