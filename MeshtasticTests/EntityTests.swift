// EntityTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftData
@testable import Meshtastic

// MARK: - In-Memory Persistence Helper

/// Shared test container that stays alive for the entire test process
@MainActor
final class TestContainerProvider {
	static let shared: ModelContainer = sharedModelContainer
}

@MainActor
private func makeTestContainer() throws -> ModelContainer {
	return sharedModelContainer
}

// MARK: - createUser Tests

@Suite("createUser")
struct CreateUserTests {

	@Test @MainActor func createUser_setsProperties() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let user = try createUser(num: 12345, context: context)
		#expect(user.num == 12345)
		#expect(user.userId == Int64(12345).toHex())
		#expect(user.hwModel == "UNSET")
		#expect(user.unmessagable == false)
	}

	@Test @MainActor func createUser_setsLongName() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let user = try createUser(num: 0xABCDEF01, context: context)
		let last4 = String(user.userId!.suffix(4))
		#expect(user.longName == "Meshtastic \(last4)")
		#expect(user.shortName == last4)
	}

	@Test @MainActor func createUser_negativeNum_throws() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		#expect(throws: PersistenceError.self) {
			try createUser(num: -1, context: context)
		}
	}

	@Test @MainActor func createUser_zero_succeeds() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let user = try createUser(num: 0, context: context)
		#expect(user.num == 0)
	}
}

// MARK: - createNodeInfo Tests

@Suite("createNodeInfo")
struct CreateNodeInfoTests {

	@Test @MainActor func createNodeInfo_setsProperties() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let node = createNodeInfo(num: 98765, context: context)
		#expect(node.id == 98765)
		#expect(node.num == 98765)
		#expect(node.user != nil)
		#expect(node.user?.num == 98765)
		#expect(node.user?.hwModel == "UNSET")
	}

	@Test @MainActor func createNodeInfo_userHasCorrectUserId() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let node = createNodeInfo(num: 0xFF, context: context)
		let hex = Int64(0xFF).toHex()
		#expect(node.user?.userId == "!\(hex)")
	}

	@Test @MainActor func createNodeInfo_userShortNameIsLast4() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let node = createNodeInfo(num: 0xDEADBEEF, context: context)
		let hex = Int64(0xDEADBEEF).toHex()
		let last4 = String(hex.suffix(4))
		#expect(node.user?.shortName == last4)
	}
}

// MARK: - UserEntity.hardwareImage Tests

@Suite("UserEntity hardwareImage", .serialized)
struct UserEntityHardwareImageTests {

	@MainActor
	private func makeUser(hwModel: String?) throws -> UserEntity {
		let context = TestContainerProvider.shared.mainContext
		let user = UserEntity()
		user.num = Int64.random(in: 1...Int64.max)
		user.hwModel = hwModel
		context.insert(user)
		return user
	}

	@Test @MainActor func nilHwModel_returnsNil() throws {
		let user = try makeUser(hwModel: nil)
		#expect(user.hardwareImage == nil)
	}

	@Test @MainActor func unsetModel_returnsUNSET() throws {
		let user = try makeUser(hwModel: "UNSET")
		#expect(user.hardwareImage == "UNSET")
	}

	@Test @MainActor func unknownModel_returnsUNSET() throws {
		let user = try makeUser(hwModel: "SOMETHINGWEIRD")
		#expect(user.hardwareImage == "UNSET")
	}

	@Test @MainActor func heltecV3() throws {
		let user = try makeUser(hwModel: "HELTECV3")
		#expect(user.hardwareImage == "HELTECV3")
	}

	@Test @MainActor func heltecV4() throws {
		let user = try makeUser(hwModel: "HELTECV4")
		#expect(user.hardwareImage == "HELTECV4")
	}

	@Test @MainActor func heltecHT62() throws {
		let user = try makeUser(hwModel: "HELTECHT62")
		#expect(user.hardwareImage == "HELTECHT62")
	}

	@Test @MainActor func heltecMeshNodeT114() throws {
		let user = try makeUser(hwModel: "HELTECMESHNODET114")
		#expect(user.hardwareImage == "HELTECMESHNODET114")
	}

	@Test @MainActor func heltecMeshPocket() throws {
		let user = try makeUser(hwModel: "HELTECMESHPOCKET")
		#expect(user.hardwareImage == "HELTECMESHPOCKET")
	}

	@Test @MainActor func heltecVisionMasterE213() throws {
		let user = try makeUser(hwModel: "HELTECVISIONMASTERE213")
		#expect(user.hardwareImage == "HELTECVISIONMASTERE213")
	}

	@Test @MainActor func heltecVisionMasterE290() throws {
		let user = try makeUser(hwModel: "HELTECVISIONMASTERE290")
		#expect(user.hardwareImage == "HELTECVISIONMASTERE290")
	}

	@Test @MainActor func heltecWirelessPaper() throws {
		let user = try makeUser(hwModel: "HELTECWIRELESSPAPER")
		#expect(user.hardwareImage == "HELTECWIRELESSPAPER")
	}

	@Test @MainActor func heltecWirelessPaperV10() throws {
		let user = try makeUser(hwModel: "HELTECWIRELESSPAPERV10")
		#expect(user.hardwareImage == "HELTECWIRELESSPAPER")
	}

	@Test @MainActor func heltecWirelessTracker() throws {
		let user = try makeUser(hwModel: "HELTECWIRELESSTRACKER")
		#expect(user.hardwareImage == "HELTECWIRELESSTRACKER")
	}

	@Test @MainActor func heltecWirelessTrackerV10() throws {
		let user = try makeUser(hwModel: "HELTECWIRELESSTRACKERV10")
		#expect(user.hardwareImage == "HELTECWIRELESSTRACKER")
	}

	@Test @MainActor func heltecWSLV3() throws {
		let user = try makeUser(hwModel: "HELTECWSLV3")
		#expect(user.hardwareImage == "HELTECWSLV3")
	}

	@Test @MainActor func tDeck() throws {
		let user = try makeUser(hwModel: "TDECK")
		#expect(user.hardwareImage == "TDECK")
	}

	@Test @MainActor func tEcho() throws {
		let user = try makeUser(hwModel: "TECHO")
		#expect(user.hardwareImage == "TECHO")
	}

	@Test @MainActor func tWatchS3() throws {
		let user = try makeUser(hwModel: "TWATCHS3")
		#expect(user.hardwareImage == "TWATCHS3")
	}

	@Test @MainActor func lilygoTBeamS3Core() throws {
		let user = try makeUser(hwModel: "LILYGOTBEAMS3CORE")
		#expect(user.hardwareImage == "LILYGOTBEAMS3CORE")
	}

	@Test @MainActor func tBeam() throws {
		let user = try makeUser(hwModel: "TBEAM")
		#expect(user.hardwareImage == "TBEAM")
	}

	@Test @MainActor func tBeamV0P7() throws {
		let user = try makeUser(hwModel: "TBEAM_V0P7")
		#expect(user.hardwareImage == "TBEAM")
	}

	@Test @MainActor func tLoraC6() throws {
		let user = try makeUser(hwModel: "TLORAC6")
		#expect(user.hardwareImage == "TLORAC6")
	}

	@Test @MainActor func tLoraT3S3Epaper() throws {
		let user = try makeUser(hwModel: "TLORAT3S3EPAPER")
		#expect(user.hardwareImage == "TLORAT3S3EPAPER")
	}

	@Test @MainActor func tLoraT3S3V1() throws {
		let user = try makeUser(hwModel: "TLORAT3S3V1")
		#expect(user.hardwareImage == "TLORAT3S3V1")
	}

	@Test @MainActor func tLoraT3S3() throws {
		let user = try makeUser(hwModel: "TLORAT3S3")
		#expect(user.hardwareImage == "TLORAT3S3V1")
	}

	@Test @MainActor func tLoraV211P6() throws {
		let user = try makeUser(hwModel: "TLORAV211P6")
		#expect(user.hardwareImage == "TLORAV211P6")
	}

	@Test @MainActor func tLoraV211P8() throws {
		let user = try makeUser(hwModel: "TLORAV211P8")
		#expect(user.hardwareImage == "TLORAV211P8")
	}

	@Test @MainActor func sensecapIndicator() throws {
		let user = try makeUser(hwModel: "SENSECAPINDICATOR")
		#expect(user.hardwareImage == "SENSECAPINDICATOR")
	}

	@Test @MainActor func trackerT1000E() throws {
		let user = try makeUser(hwModel: "TRACKERT1000E")
		#expect(user.hardwareImage == "TRACKERT1000E")
	}

	@Test @MainActor func seeedXiaoS3() throws {
		let user = try makeUser(hwModel: "SEEEDXIAOS3")
		#expect(user.hardwareImage == "SEEEDXIAOS3")
	}

	@Test @MainActor func wioWM1110() throws {
		let user = try makeUser(hwModel: "WIOWM1110")
		#expect(user.hardwareImage == "WIOWM1110")
	}

	@Test @MainActor func seeedSolarNode() throws {
		let user = try makeUser(hwModel: "SEEEDSOLARNODE")
		#expect(user.hardwareImage == "SEEEDSOLARNODE")
	}

	@Test @MainActor func seeedWioTrackerL1() throws {
		let user = try makeUser(hwModel: "SEEEDWIOTRACKERL1")
		#expect(user.hardwareImage == "SEEEDWIOTRACKERL1")
	}

	@Test @MainActor func rak4631() throws {
		let user = try makeUser(hwModel: "RAK4631")
		#expect(user.hardwareImage == "RAK4631")
	}

	@Test @MainActor func rak11310() throws {
		let user = try makeUser(hwModel: "RAK11310")
		#expect(user.hardwareImage == "RAK11310")
	}

	@Test @MainActor func wismeshTap() throws {
		let user = try makeUser(hwModel: "WISMESHTAP")
		#expect(user.hardwareImage == "WISMESHTAP")
	}

	@Test @MainActor func nanoG1() throws {
		let user = try makeUser(hwModel: "NANOG1")
		#expect(user.hardwareImage == "NANOG1")
	}

	@Test @MainActor func nanoG1Explorer() throws {
		let user = try makeUser(hwModel: "NANOG1EXPLORER")
		#expect(user.hardwareImage == "NANOG1")
	}

	@Test @MainActor func nanoG2Ultra() throws {
		let user = try makeUser(hwModel: "NANOG2ULTRA")
		#expect(user.hardwareImage == "NANOG2ULTRA")
	}

	@Test @MainActor func muziR1Neo() throws {
		let user = try makeUser(hwModel: "MUZIR1NEO")
		#expect(user.hardwareImage == "MUZIR1NEO")
	}

	@Test @MainActor func stationG2() throws {
		let user = try makeUser(hwModel: "STATIONG2")
		#expect(user.hardwareImage == "STATIONG2")
	}

	@Test @MainActor func thinkNodeM1() throws {
		let user = try makeUser(hwModel: "THINKNODEM1")
		#expect(user.hardwareImage == "THINKNODEM1")
	}

	@Test @MainActor func thinkNodeM2() throws {
		let user = try makeUser(hwModel: "THINKNODEM2")
		#expect(user.hardwareImage == "THINKNODEM2")
	}

	@Test @MainActor func thinkNodeM3() throws {
		let user = try makeUser(hwModel: "THINKNODEM3")
		#expect(user.hardwareImage == "THINKNODEM3")
	}

	@Test @MainActor func thinkNodeM4() throws {
		let user = try makeUser(hwModel: "THINKNODEM4")
		#expect(user.hardwareImage == "THINKNODEM4")
	}

	@Test @MainActor func rpiPico() throws {
		let user = try makeUser(hwModel: "RPIPICO")
		#expect(user.hardwareImage == "RPIPICO")
	}
}

// MARK: - PositionEntity Computed Properties Tests

@Suite("PositionEntity Computed Properties", .serialized)
struct PositionEntityComputedTests {

	@MainActor
	private func makePosition(latI: Int32 = 0, lonI: Int32 = 0, precisionBits: Int32 = 32) throws -> PositionEntity {
		let context = TestContainerProvider.shared.mainContext
		let pos = PositionEntity()
		pos.latitudeI = latI
		pos.longitudeI = lonI
		pos.precisionBits = precisionBits
		context.insert(pos)
		return pos
	}

	@Test @MainActor func latitude_zero_returnsZero() throws {
		let pos = try makePosition(latI: 0)
		#expect(pos.latitude == 0)
	}

	@Test @MainActor func latitude_positive() throws {
		let pos = try makePosition(latI: 374_000_000) // ~37.4 degrees
		let lat = pos.latitude!
		#expect(abs(lat - 37.4) < 0.01)
	}

	@Test @MainActor func longitude_zero_returnsZero() throws {
		let pos = try makePosition(lonI: 0)
		#expect(pos.longitude == 0)
	}

	@Test @MainActor func longitude_negative() throws {
		let pos = try makePosition(lonI: -1_220_000_000) // ~-122 degrees
		let lon = pos.longitude!
		#expect(abs(lon - (-122.0)) < 0.01)
	}

	@Test @MainActor func nodeCoordinate_bothZero_returnsNil() throws {
		let pos = try makePosition(latI: 0, lonI: 0)
		#expect(pos.nodeCoordinate == nil)
	}

	@Test @MainActor func nodeCoordinate_nonZero_returnsCoord() throws {
		let pos = try makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let coord = pos.nodeCoordinate
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37.4) < 0.01)
		#expect(abs(coord!.longitude - (-122.0)) < 0.01)
	}

	@Test @MainActor func nodeLocation_bothZero_returnsNil() throws {
		let pos = try makePosition(latI: 0, lonI: 0)
		#expect(pos.nodeLocation == nil)
	}

	@Test @MainActor func nodeLocation_nonZero_returnsLocation() throws {
		let pos = try makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let loc = pos.nodeLocation
		#expect(loc != nil)
	}

	@Test @MainActor func isPreciseLocation_32bits() throws {
		let pos = try makePosition(precisionBits: 32)
		#expect(pos.isPreciseLocation == true)
	}

	@Test @MainActor func isPreciseLocation_0bits() throws {
		let pos = try makePosition(precisionBits: 0)
		#expect(pos.isPreciseLocation == true)
	}

	@Test @MainActor func isPreciseLocation_16bits_notPrecise() throws {
		let pos = try makePosition(precisionBits: 16)
		#expect(pos.isPreciseLocation == false)
	}

	@Test @MainActor func annotation_returnsPointAnnotation() throws {
		let pos = try makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let ann = pos.annotaton
		#expect(abs(ann.coordinate.latitude - 37.4) < 0.01)
	}

	@Test @MainActor func fuzzedNodeCoordinate_bothZero_returnsNil() throws {
		let pos = try makePosition(latI: 0, lonI: 0)
		#expect(pos.fuzzedNodeCoordinate == nil)
	}

	@Test @MainActor func fuzzedNodeCoordinate_nonZero_slightlyOffset() throws {
		let pos = try makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let fuzzed = pos.fuzzedNodeCoordinate
		#expect(fuzzed != nil)
		let latDiff = abs(fuzzed!.latitude - 37.4)
		#expect(latDiff < 0.001)
	}
}

// MARK: - MessageEntity Computed Properties Tests

@Suite("MessageEntity Computed Properties", .serialized)
struct MessageEntityComputedTests {

	@MainActor
	private func makeMessage() throws -> (ModelContext, MessageEntity) {
		let context = TestContainerProvider.shared.mainContext
		let msg = MessageEntity()
		context.insert(msg)
		return (context, msg)
	}

	@Test @MainActor func hasTranslatedPayload_nil_returnsFalse() throws {
		let (_, msg) = try makeMessage()
		msg.messagePayloadTranslated = nil
		#expect(msg.hasTranslatedPayload == false)
	}

	@Test @MainActor func hasTranslatedPayload_empty_returnsFalse() throws {
		let (_, msg) = try makeMessage()
		msg.messagePayloadTranslated = "   "
		#expect(msg.hasTranslatedPayload == false)
	}

	@Test @MainActor func hasTranslatedPayload_content_returnsTrue() throws {
		let (_, msg) = try makeMessage()
		msg.messagePayloadTranslated = "Hola"
		#expect(msg.hasTranslatedPayload == true)
	}

	@Test @MainActor func displayedPayload_noTranslation() throws {
		let (_, msg) = try makeMessage()
		msg.messagePayload = "Hello"
		msg.messagePayloadTranslated = nil
		#expect(msg.displayedPayload == "Hello")
	}

	@Test @MainActor func displayedPayload_nilPayload() throws {
		let (_, msg) = try makeMessage()
		msg.messagePayload = nil
		#expect(msg.displayedPayload == "EMPTY MESSAGE")
	}

	@Test @MainActor func timestamp_convertsCorrectly() throws {
		let (_, msg) = try makeMessage()
		msg.messageTimestamp = 1700000000
		let ts = msg.timestamp
		#expect(ts == Date(timeIntervalSince1970: 1700000000))
	}

	@Test @MainActor func canRetry_noError_false() throws {
		let (_, msg) = try makeMessage()
		msg.ackError = 0 // NONE
		#expect(msg.canRetry == false)
	}

	@Test @MainActor func displayTimestamp_firstMessage_returnsFalse() throws {
		let (_, msg) = try makeMessage()
		msg.messageTimestamp = 1700000000
		#expect(msg.displayTimestamp(aboveMessage: nil) == false)
	}

	@Test @MainActor func displayTimestamp_withinHour_returnsFalse() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let above = MessageEntity()
		above.messageTimestamp = 1700000000
		context.insert(above)
		let current = MessageEntity()
		current.messageTimestamp = 1700000000 + 1800 // 30 min later
		context.insert(current)
		#expect(current.displayTimestamp(aboveMessage: above) == false)
	}

	@Test @MainActor func displayTimestamp_overHour_returnsTrue() throws {
		let container = try makeTestContainer()
		let context = container.mainContext
		let above = MessageEntity()
		above.messageTimestamp = 1700000000
		context.insert(above)
		let current = MessageEntity()
		current.messageTimestamp = 1700000000 + 7200 // 2 hours later
		context.insert(current)
		#expect(current.displayTimestamp(aboveMessage: above) == true)
	}
}

// MARK: - NodeInfoEntity Computed Properties Tests

@Suite("NodeInfoEntity Computed Properties")
struct NodeInfoEntityComputedTests {

	@MainActor
	private func makeNode() throws -> NodeInfoEntity {
		let container = try makeTestContainer()
		let context = container.mainContext
		let node = NodeInfoEntity()
		context.insert(node)
		return node
	}

	@Test @MainActor func latestPosition_noPositions_returnsNil() throws {
		let node = try makeNode()
		#expect(node.latestPosition == nil)
	}

	@Test @MainActor func hasPositions_noPositions_returnsFalse() throws {
		let node = try makeNode()
		#expect(node.hasPositions == false)
	}

	@Test @MainActor func latestDeviceMetrics_noTelemetry_returnsNil() throws {
		let node = try makeNode()
		#expect(node.latestDeviceMetrics == nil)
	}

	@Test @MainActor func latestEnvironmentMetrics_noTelemetry_returnsNil() throws {
		let node = try makeNode()
		#expect(node.latestEnvironmentMetrics == nil)
	}

	@Test @MainActor func latestPowerMetrics_noTelemetry_returnsNil() throws {
		let node = try makeNode()
		#expect(node.latestPowerMetrics == nil)
	}

	@Test @MainActor func hasDeviceMetrics_noTelemetry_returnsFalse() throws {
		let node = try makeNode()
		#expect(node.hasDeviceMetrics == false)
	}

	@Test @MainActor func hasEnvironmentMetrics_noTelemetry_returnsFalse() throws {
		let node = try makeNode()
		#expect(node.hasEnvironmentMetrics == false)
	}

	@Test @MainActor func hasPowerMetrics_noTelemetry_returnsFalse() throws {
		let node = try makeNode()
		#expect(node.hasPowerMetrics == false)
	}

	@Test @MainActor func hasPax_noPax_returnsFalse() throws {
		let node = try makeNode()
		#expect(node.hasPax == false)
	}

	@Test @MainActor func hasTraceRoutes_noRoutes_returnsFalse() throws {
		let node = try makeNode()
		#expect(node.hasTraceRoutes == false)
	}

	@Test @MainActor func isStoreForwardRouter_noConfig_returnsFalse() throws {
		let node = try makeNode()
		#expect(node.isStoreForwardRouter == false)
	}

	@Test @MainActor func isOnline_nullLastHeard_returnsFalse() throws {
		let node = try makeNode()
		node.lastHeard = nil
		#expect(node.isOnline == false)
	}

	@Test @MainActor func isOnline_recentHeard_returnsTrue() throws {
		let node = try makeNode()
		node.lastHeard = Date()
		#expect(node.isOnline == true)
	}

	@Test @MainActor func isOnline_oldHeard_returnsFalse() throws {
		let node = try makeNode()
		node.lastHeard = Date().addingTimeInterval(-3 * 3600) // 3 hours ago
		#expect(node.isOnline == false)
	}
}
