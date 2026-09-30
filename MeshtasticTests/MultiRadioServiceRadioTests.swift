//
//  MultiRadioServiceRadioTests.swift
//  MeshtasticTests
//
//  Feature 021, T102–T105: the radio TAK, CarPlay & Siri and the Watch use.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

private actor IdleConnection: Connection {
	let type: TransportType = .tcp
	var isConnected = true

	func send(_ data: ToRadio) async throws {}
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("Multi-radio service radios", .serialized)
struct MultiRadioServiceRadioTests {

	private let firstNum: Int64 = 0x0A0A
	private let extraNum: Int64 = 0x0B0B
	private let offlineNum: Int64 = 0x0C0C

	private func makeStore() -> UserDefaults {
		let name = "ServiceRadio-\(UUID().uuidString)"
		let store = UserDefaults(suiteName: name)!
		store.removePersistentDomain(forName: name)
		return store
	}

	private struct Radios {
		let manager: AccessoryManager
		let first: RadioSession
		let extra: RadioSession
	}

	private func makeManager() -> Radios {
		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		var firstDevice = Device(id: UUID(), name: "First", transportType: .tcp, identifier: "a.local:4403")
		firstDevice.num = firstNum
		let first = RadioSession(device: firstDevice, connection: IdleConnection())
		manager.activeConnection = first
		var extraDevice = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		extraDevice.num = extraNum
		let extra = RadioSession(device: extraDevice, connection: IdleConnection())
		manager.additionalRadios[extraDevice.id] = extra
		return Radios(manager: manager, first: first, extra: extra)
	}

	@Test("A choice is saved per service; 0 clears it")
	func choicePersistence() {
		let store = makeStore()
		#expect(UserDefaults.serviceRadio(.tak, in: store) == 0)
		UserDefaults.setServiceRadio(extraNum, for: .tak, in: store)
		#expect(UserDefaults.serviceRadio(.tak, in: store) == extraNum)
		#expect(UserDefaults.serviceRadio(.carPlay, in: store) == 0)
		#expect(UserDefaults.serviceRadio(.watch, in: store) == 0)
		UserDefaults.setServiceRadio(0, for: .tak, in: store)
		#expect(UserDefaults.serviceRadio(.tak, in: store) == 0)
	}

	/// The two radios as known: connected with this version.
	private func knowBoth(_ manager: AccessoryManager) {
		manager.knownRadios = [StoredRadio(nodeNum: firstNum, name: "First"), StoredRadio(nodeNum: extraNum, name: "Extra")]
	}

	@Test("With one radio known every service uses the connected radio, as on main")
	func oneRadioUsesIt() {
		let store = makeStore()
		let radios = makeManager()
		let manager = radios.manager
		manager.knownRadios = [StoredRadio(nodeNum: firstNum, name: "First")]
		UserDefaults.setServiceRadio(extraNum, for: .tak, in: store)
		#expect(manager.session(for: .tak, store: store) === radios.first)
		#expect(manager.servicesNeedingRadio(store: store, inUse: { _ in true }).isEmpty, "nothing to choose")
		#expect(manager.intentRadio(nil, store: store) == .radio(firstNum))
	}

	@Test("With several radios known a service uses only its chosen radio, waits while it's off, and needs one when in use")
	func severalRadiosNeedAChoice() {
		let store = makeStore()
		let radios = makeManager()
		let manager = radios.manager
		knowBoth(manager)

		#expect(manager.session(for: .tak, store: store) == nil, "none chosen: nothing is guessed")
		#expect(manager.servicesNeedingRadio(store: store, inUse: { $0 != .tak }) == [.carPlay, .watch], "TAK off: not needed")

		UserDefaults.setServiceRadio(extraNum, for: .carPlay, in: store)
		#expect(manager.session(for: .carPlay, store: store) === radios.extra)
		#expect(manager.servicesNeedingRadio(store: store, inUse: { $0 == .carPlay }).isEmpty)

		// Off: waited for, never another radio (W-15).
		manager.additionalRadios = [:]
		#expect(manager.radioNum(for: .carPlay, store: store) == extraNum, "CarPlay still lists its conversations")
		#expect(manager.session(for: .carPlay, store: store) == nil)

		// Removed: the choice goes, and a service in use asks again.
		manager.clearServiceRadios(pointingAt: extraNum, store: store)
		#expect(UserDefaults.serviceRadio(.carPlay, in: store) == 0)
		#expect(manager.servicesNeedingRadio(store: store, inUse: { $0 == .carPlay }) == [.carPlay])

		// A choice of a radio that isn't one of the known ones doesn't count.
		UserDefaults.setServiceRadio(offlineNum, for: .carPlay, in: store)
		#expect(manager.radioNum(for: .carPlay, store: store) == nil)
	}

	@Test("The choice sheet lists the connected radios first")
	func connectedRadiosFirst() {
		let manager = makeManager().manager
		manager.knownRadios = [StoredRadio(nodeNum: offlineNum, name: "Offline"), StoredRadio(nodeNum: firstNum, name: "First"), StoredRadio(nodeNum: extraNum, name: "Extra")]
		#expect(manager.knownRadiosConnectedFirst.map(\.nodeNum) == [firstNum, extraNum, offlineNum])
	}

	@Test("A Siri or Shortcuts command uses the radio it names or the CarPlay & Siri radio, never another; with none chosen it asks")
	func intentRadio() throws {
		let store = makeStore()
		let manager = makeManager().manager
		knowBoth(manager)
		#expect(manager.intentRadio(nil, store: store) == .needsChoice, "several radios and none chosen")
		UserDefaults.setServiceRadio(extraNum, for: .carPlay, in: store)
		#expect(manager.intentRadio(nil, store: store) == .radio(extraNum))
		#expect(manager.intentRadio(firstNum, store: store) == .radio(firstNum))
		#expect(manager.intentRadio(offlineNum, store: store) == .notConnected, "never sent from another radio")

		manager.additionalRadios = [:]
		#expect(manager.intentRadio(nil, store: store) == .notConnected, "the chosen radio is off: not swapped")
		manager.activeConnection = nil
		#expect(manager.intentRadio(nil, store: store) == .noRadio)
		// Each case throws its own error: a radio that's off is said to be off, not asked for again.
		struct Off: Error {}
		struct Ask: Error {}
		#expect(throws: AppIntentErrors.AppIntentError.self) {
			try IntentRadioChoice.noRadio.radioNum(noRadio: AppIntentErrors.AppIntentError.notConnected, notConnected: Off(), needsValue: Ask())
		}
		#expect(throws: Off.self) {
			try IntentRadioChoice.notConnected.radioNum(noRadio: AppIntentErrors.AppIntentError.notConnected, notConnected: Off(), needsValue: Ask())
		}
		#expect(throws: Ask.self) {
			try IntentRadioChoice.needsChoice.radioNum(noRadio: AppIntentErrors.AppIntentError.notConnected, notConnected: Off(), needsValue: Ask())
		}
		#expect(try IntentRadioChoice.radio(7).radioNum(noRadio: Off(), notConnected: Off(), needsValue: Ask()) == 7)
	}

	// MARK: - Datadog (T107)

	@Test("The connect event reports each radio's own firmware, from its metadata when the device has none yet")
	func reportedFirmwareVersion() throws {
		let manager = makeManager().manager
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("ServiceRadio-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		manager.context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = extraNum
		let metadata = DeviceMetadataEntity()
		metadata.firmwareVersion = "2.6.11.60ec05e"
		node.metadata = metadata
		manager.context.insert(metadata)
		manager.context.insert(node)

		var device = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		device.num = extraNum
		#expect(manager.reportedFirmwareVersion(for: device) == "2.6.11", "stored metadata, build suffix dropped")
		device.firmwareVersion = "2.7.15.567b8ea"
		#expect(manager.reportedFirmwareVersion(for: device) == "2.7.15")
		device.num = offlineNum
		device.firmwareVersion = nil
		#expect(manager.reportedFirmwareVersion(for: device) == nil)
	}

	// MARK: - Watch (T105)

	private func seedWatchStore() throws -> ModelContainer {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = ModelContext(container)
		for num in [Int64(1), 2] {
			let node = NodeInfoEntity()
			node.num = num
			node.lastHeard = Date()
			node.snr = 7.5
			let user = UserEntity()
			user.num = num
			user.longName = "Node \(num)"
			user.shortName = "N\(num)"
			node.user = user
			context.insert(user)
			context.insert(node)
			let position = PositionEntity()
			position.latitudeI = 480_000_000
			position.longitudeI = -1_220_000_000
			position.time = Date()
			position.nodePosition = node
			context.insert(position)
			node.latestPositionCache = position
		}
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = extraNum
		context.insert(myInfo)
		let observation = NodeObservationEntity(radioNum: extraNum, nodeNum: 1)
		observation.snr = 3
		observation.lastHeard = Date(timeIntervalSince1970: 1_800_000_000)
		context.insert(observation)
		try context.save()
		return container
	}

	@Test("With a radio picked for the Watch, it shows the nodes that radio heard, as it heard them")
	func watchHeardBy() async throws {
		let mesh = MeshPackets(modelContainer: try seedWatchStore())
		let all = await mesh.watchNodeSnapshot(userLatitude: 48, userLongitude: -122, maxDistanceMeters: 804.672)
		#expect(Set(all.map(\.num)) == [1, 2])

		let heard = await mesh.watchNodeSnapshot(userLatitude: 48, userLongitude: -122, maxDistanceMeters: 804.672, heardBy: extraNum)
		#expect(heard.map(\.num) == [1])
		#expect(heard.first?.snr == 3)
		#expect(heard.first?.lastHeard == Date(timeIntervalSince1970: 1_800_000_000))
	}

	@Test("A Watch radio that's no longer one of the user's radios shows every node")
	func watchStaleRadio() async throws {
		let mesh = MeshPackets(modelContainer: try seedWatchStore())
		let nodes = await mesh.watchNodeSnapshot(userLatitude: 48, userLongitude: -122, maxDistanceMeters: 804.672, heardBy: offlineNum)
		#expect(Set(nodes.map(\.num)) == [1, 2])
	}

	@Test("The TAK channel picker lists only the TAK radio's channels")
	func takChannelsAreTheTAKRadios() throws {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("TAKChannels-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let context = ModelContext(try ModelContainer(for: schema, configurations: config))
		var all: [ChannelEntity] = []
		for (radio, names) in [(firstNum, ["Primary", "Team"]), (extraNum, ["Primary", "Family"])] {
			let myInfo = MyInfoEntity()
			myInfo.myNodeNum = radio
			context.insert(myInfo)
			for (index, name) in names.enumerated() {
				let channel = ChannelEntity()
				channel.index = Int32(index)
				channel.name = name
				channel.myInfoChannel = myInfo
				context.insert(channel)
				all.append(channel)
			}
		}
		try context.save()

		let extraChannels = TAKServerConfig.channels(all, ofRadio: extraNum)
		#expect(extraChannels.map(\.name) == ["Primary", "Family"])
		#expect(Set(extraChannels.map(\.index)).count == extraChannels.count, "one row per slot")
		#expect(TAKServerConfig.channels(all, ofRadio: nil).isEmpty)
	}
}
