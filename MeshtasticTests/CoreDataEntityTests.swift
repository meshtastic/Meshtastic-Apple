// CoreDataEntityTests.swift
// MeshtasticTests

import Testing
import Foundation
import CoreData
@testable import Meshtastic

// MARK: - In-Memory Core Data Helper

private func makeInMemoryContainer() -> NSPersistentContainer {
	let container = NSPersistentContainer(name: "Meshtastic")
	let description = NSPersistentStoreDescription()
	description.type = NSInMemoryStoreType
	container.persistentStoreDescriptions = [description]
	container.loadPersistentStores { _, error in
		if let error {
			fatalError("Failed to load in-memory store: \(error)")
		}
	}
	return container
}

// MARK: - createUser Tests

@Suite("createUser")
struct CreateUserTests {

	@Test func createUser_setsProperties() throws {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let user = try createUser(num: 12345, context: context)
		#expect(user.num == 12345)
		#expect(user.userId == Int64(12345).toHex())
		#expect(user.hwModel == "UNSET")
		#expect(user.unmessagable == false)
	}

	@Test func createUser_setsLongName() throws {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let user = try createUser(num: 0xABCDEF01, context: context)
		let last4 = String(user.userId!.suffix(4))
		#expect(user.longName == "Meshtastic \(last4)")
		#expect(user.shortName == last4)
	}

	@Test func createUser_negativeNum_throws() throws {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		#expect(throws: CoreDataError.self) {
			try createUser(num: -1, context: context)
		}
	}

	@Test func createUser_zero_succeeds() throws {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let user = try createUser(num: 0, context: context)
		#expect(user.num == 0)
	}
}

// MARK: - createNodeInfo Tests

@Suite("createNodeInfo")
struct CreateNodeInfoTests {

	@Test func createNodeInfo_setsProperties() {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let node = createNodeInfo(num: 98765, context: context)
		#expect(node.id == 98765)
		#expect(node.num == 98765)
		#expect(node.user != nil)
		#expect(node.user?.num == 98765)
		#expect(node.user?.hwModel == "UNSET")
	}

	@Test func createNodeInfo_userHasCorrectUserId() {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let node = createNodeInfo(num: 0xFF, context: context)
		let hex = Int64(0xFF).toHex()
		#expect(node.user?.userId == "!\(hex)")
	}

	@Test func createNodeInfo_userShortNameIsLast4() {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let node = createNodeInfo(num: 0xDEADBEEF, context: context)
		let hex = Int64(0xDEADBEEF).toHex()
		let last4 = String(hex.suffix(4))
		#expect(node.user?.shortName == last4)
	}
}

// MARK: - UserEntity.hardwareImage Tests

@Suite("UserEntity hardwareImage")
struct UserEntityHardwareImageTests {

	private func makeUser(hwModel: String?) -> UserEntity {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let user = UserEntity(context: context)
		user.num = 1
		user.hwModel = hwModel
		return user
	}

	@Test func nilHwModel_returnsNil() {
		let user = makeUser(hwModel: nil)
		#expect(user.hardwareImage == nil)
	}

	@Test func unsetModel_returnsUNSET() {
		let user = makeUser(hwModel: "UNSET")
		#expect(user.hardwareImage == "UNSET")
	}

	@Test func unknownModel_returnsUNSET() {
		let user = makeUser(hwModel: "SOMETHINGWEIRD")
		#expect(user.hardwareImage == "UNSET")
	}

	@Test func heltecV3() {
		let user = makeUser(hwModel: "HELTECV3")
		#expect(user.hardwareImage == "HELTECV3")
	}

	@Test func heltecV4() {
		let user = makeUser(hwModel: "HELTECV4")
		#expect(user.hardwareImage == "HELTECV4")
	}

	@Test func heltecHT62() {
		let user = makeUser(hwModel: "HELTECHT62")
		#expect(user.hardwareImage == "HELTECHT62")
	}

	@Test func heltecMeshNodeT114() {
		let user = makeUser(hwModel: "HELTECMESHNODET114")
		#expect(user.hardwareImage == "HELTECMESHNODET114")
	}

	@Test func heltecMeshPocket() {
		let user = makeUser(hwModel: "HELTECMESHPOCKET")
		#expect(user.hardwareImage == "HELTECMESHPOCKET")
	}

	@Test func heltecVisionMasterE213() {
		let user = makeUser(hwModel: "HELTECVISIONMASTERE213")
		#expect(user.hardwareImage == "HELTECVISIONMASTERE213")
	}

	@Test func heltecVisionMasterE290() {
		let user = makeUser(hwModel: "HELTECVISIONMASTERE290")
		#expect(user.hardwareImage == "HELTECVISIONMASTERE290")
	}

	@Test func heltecWirelessPaper() {
		let user = makeUser(hwModel: "HELTECWIRELESSPAPER")
		#expect(user.hardwareImage == "HELTECWIRELESSPAPER")
	}

	@Test func heltecWirelessPaperV10() {
		let user = makeUser(hwModel: "HELTECWIRELESSPAPERV10")
		#expect(user.hardwareImage == "HELTECWIRELESSPAPER")
	}

	@Test func heltecWirelessTracker() {
		let user = makeUser(hwModel: "HELTECWIRELESSTRACKER")
		#expect(user.hardwareImage == "HELTECWIRELESSTRACKER")
	}

	@Test func heltecWirelessTrackerV10() {
		let user = makeUser(hwModel: "HELTECWIRELESSTRACKERV10")
		#expect(user.hardwareImage == "HELTECWIRELESSTRACKER")
	}

	@Test func heltecWSLV3() {
		let user = makeUser(hwModel: "HELTECWSLV3")
		#expect(user.hardwareImage == "HELTECWSLV3")
	}

	@Test func tDeck() {
		let user = makeUser(hwModel: "TDECK")
		#expect(user.hardwareImage == "TDECK")
	}

	@Test func tEcho() {
		let user = makeUser(hwModel: "TECHO")
		#expect(user.hardwareImage == "TECHO")
	}

	@Test func tWatchS3() {
		let user = makeUser(hwModel: "TWATCHS3")
		#expect(user.hardwareImage == "TWATCHS3")
	}

	@Test func lilygoTBeamS3Core() {
		let user = makeUser(hwModel: "LILYGOTBEAMS3CORE")
		#expect(user.hardwareImage == "LILYGOTBEAMS3CORE")
	}

	@Test func tBeam() {
		let user = makeUser(hwModel: "TBEAM")
		#expect(user.hardwareImage == "TBEAM")
	}

	@Test func tBeamV0P7() {
		let user = makeUser(hwModel: "TBEAM_V0P7")
		#expect(user.hardwareImage == "TBEAM")
	}

	@Test func tLoraC6() {
		let user = makeUser(hwModel: "TLORAC6")
		#expect(user.hardwareImage == "TLORAC6")
	}

	@Test func tLoraT3S3Epaper() {
		let user = makeUser(hwModel: "TLORAT3S3EPAPER")
		#expect(user.hardwareImage == "TLORAT3S3EPAPER")
	}

	@Test func tLoraT3S3V1() {
		let user = makeUser(hwModel: "TLORAT3S3V1")
		#expect(user.hardwareImage == "TLORAT3S3V1")
	}

	@Test func tLoraT3S3() {
		let user = makeUser(hwModel: "TLORAT3S3")
		#expect(user.hardwareImage == "TLORAT3S3V1")
	}

	@Test func tLoraV211P6() {
		let user = makeUser(hwModel: "TLORAV211P6")
		#expect(user.hardwareImage == "TLORAV211P6")
	}

	@Test func tLoraV211P8() {
		let user = makeUser(hwModel: "TLORAV211P8")
		#expect(user.hardwareImage == "TLORAV211P8")
	}

	@Test func sensecapIndicator() {
		let user = makeUser(hwModel: "SENSECAPINDICATOR")
		#expect(user.hardwareImage == "SENSECAPINDICATOR")
	}

	@Test func trackerT1000E() {
		let user = makeUser(hwModel: "TRACKERT1000E")
		#expect(user.hardwareImage == "TRACKERT1000E")
	}

	@Test func seeedXiaoS3() {
		let user = makeUser(hwModel: "SEEEDXIAOS3")
		#expect(user.hardwareImage == "SEEEDXIAOS3")
	}

	@Test func wioWM1110() {
		let user = makeUser(hwModel: "WIOWM1110")
		#expect(user.hardwareImage == "WIOWM1110")
	}

	@Test func seeedSolarNode() {
		let user = makeUser(hwModel: "SEEEDSOLARNODE")
		#expect(user.hardwareImage == "SEEEDSOLARNODE")
	}

	@Test func seeedWioTrackerL1() {
		let user = makeUser(hwModel: "SEEEDWIOTRACKERL1")
		#expect(user.hardwareImage == "SEEEDWIOTRACKERL1")
	}

	@Test func rak4631() {
		let user = makeUser(hwModel: "RAK4631")
		#expect(user.hardwareImage == "RAK4631")
	}

	@Test func rak11310() {
		let user = makeUser(hwModel: "RAK11310")
		#expect(user.hardwareImage == "RAK11310")
	}

	@Test func wismeshTap() {
		let user = makeUser(hwModel: "WISMESHTAP")
		#expect(user.hardwareImage == "WISMESHTAP")
	}

	@Test func nanoG1() {
		let user = makeUser(hwModel: "NANOG1")
		#expect(user.hardwareImage == "NANOG1")
	}

	@Test func nanoG1Explorer() {
		let user = makeUser(hwModel: "NANOG1EXPLORER")
		#expect(user.hardwareImage == "NANOG1")
	}

	@Test func nanoG2Ultra() {
		let user = makeUser(hwModel: "NANOG2ULTRA")
		#expect(user.hardwareImage == "NANOG2ULTRA")
	}

	@Test func muziR1Neo() {
		let user = makeUser(hwModel: "MUZIR1NEO")
		#expect(user.hardwareImage == "MUZIR1NEO")
	}

	@Test func stationG2() {
		let user = makeUser(hwModel: "STATIONG2")
		#expect(user.hardwareImage == "STATIONG2")
	}

	@Test func thinkNodeM1() {
		let user = makeUser(hwModel: "THINKNODEM1")
		#expect(user.hardwareImage == "THINKNODEM1")
	}

	@Test func thinkNodeM2() {
		let user = makeUser(hwModel: "THINKNODEM2")
		#expect(user.hardwareImage == "THINKNODEM2")
	}

	@Test func thinkNodeM3() {
		let user = makeUser(hwModel: "THINKNODEM3")
		#expect(user.hardwareImage == "THINKNODEM3")
	}

	@Test func thinkNodeM4() {
		let user = makeUser(hwModel: "THINKNODEM4")
		#expect(user.hardwareImage == "THINKNODEM4")
	}

	@Test func rpiPico() {
		let user = makeUser(hwModel: "RPIPICO")
		#expect(user.hardwareImage == "RPIPICO")
	}
}

// MARK: - PositionEntity Computed Properties Tests

@Suite("PositionEntity Computed Properties")
struct PositionEntityComputedTests {

	private func makePosition(latI: Int32 = 0, lonI: Int32 = 0, precisionBits: Int32 = 32) -> PositionEntity {
		let container = makeInMemoryContainer()
		let context = container.viewContext
		let pos = PositionEntity(context: context)
		pos.latitudeI = latI
		pos.longitudeI = lonI
		pos.precisionBits = precisionBits
		return pos
	}

	@Test func latitude_zero_returnsZero() {
		let pos = makePosition(latI: 0)
		#expect(pos.latitude == 0)
	}

	@Test func latitude_positive() {
		let pos = makePosition(latI: 374_000_000) // ~37.4 degrees
		let lat = pos.latitude!
		#expect(abs(lat - 37.4) < 0.01)
	}

	@Test func longitude_zero_returnsZero() {
		let pos = makePosition(lonI: 0)
		#expect(pos.longitude == 0)
	}

	@Test func longitude_negative() {
		let pos = makePosition(lonI: -1_220_000_000) // ~-122 degrees
		let lon = pos.longitude!
		#expect(abs(lon - (-122.0)) < 0.01)
	}

	@Test func nodeCoordinate_bothZero_returnsNil() {
		let pos = makePosition(latI: 0, lonI: 0)
		#expect(pos.nodeCoordinate == nil)
	}

	@Test func nodeCoordinate_nonZero_returnsCoord() {
		let pos = makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let coord = pos.nodeCoordinate
		#expect(coord != nil)
		#expect(abs(coord!.latitude - 37.4) < 0.01)
		#expect(abs(coord!.longitude - (-122.0)) < 0.01)
	}

	@Test func nodeLocation_bothZero_returnsNil() {
		let pos = makePosition(latI: 0, lonI: 0)
		#expect(pos.nodeLocation == nil)
	}

	@Test func nodeLocation_nonZero_returnsLocation() {
		let pos = makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let loc = pos.nodeLocation
		#expect(loc != nil)
	}

	@Test func isPreciseLocation_32bits() {
		let pos = makePosition(precisionBits: 32)
		#expect(pos.isPreciseLocation == true)
	}

	@Test func isPreciseLocation_0bits() {
		let pos = makePosition(precisionBits: 0)
		#expect(pos.isPreciseLocation == true)
	}

	@Test func isPreciseLocation_16bits_notPrecise() {
		let pos = makePosition(precisionBits: 16)
		#expect(pos.isPreciseLocation == false)
	}

	@Test func annotation_returnsPointAnnotation() {
		let pos = makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let ann = pos.annotaton
		#expect(abs(ann.coordinate.latitude - 37.4) < 0.01)
	}

	@Test func fuzzedNodeCoordinate_bothZero_returnsNil() {
		let pos = makePosition(latI: 0, lonI: 0)
		#expect(pos.fuzzedNodeCoordinate == nil)
	}

	@Test func fuzzedNodeCoordinate_nonZero_slightlyOffset() {
		let pos = makePosition(latI: 374_000_000, lonI: -1_220_000_000)
		let fuzzed = pos.fuzzedNodeCoordinate
		#expect(fuzzed != nil)
		// Offset should be tiny — within ~0.001 degrees
		let latDiff = abs(fuzzed!.latitude - 37.4)
		#expect(latDiff < 0.001)
	}
}

// MARK: - MessageEntity Computed Properties Tests

@Suite("MessageEntity Computed Properties")
struct MessageEntityComputedTests {

	private func makeContainer() -> NSPersistentContainer {
		makeInMemoryContainer()
	}

	@Test func hasTranslatedPayload_nil_returnsFalse() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.messagePayloadTranslated = nil
		#expect(msg.hasTranslatedPayload == false)
	}

	@Test func hasTranslatedPayload_empty_returnsFalse() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.messagePayloadTranslated = "   "
		#expect(msg.hasTranslatedPayload == false)
	}

	@Test func hasTranslatedPayload_content_returnsTrue() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.messagePayloadTranslated = "Hola"
		#expect(msg.hasTranslatedPayload == true)
	}

	@Test func displayedPayload_noTranslation() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.messagePayload = "Hello"
		msg.messagePayloadTranslated = nil
		#expect(msg.displayedPayload == "Hello")
	}

	@Test func displayedPayload_nilPayload() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.messagePayload = nil
		#expect(msg.displayedPayload == "EMPTY MESSAGE")
	}

	@Test func timestamp_convertsCorrectly() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.messageTimestamp = 1700000000
		let ts = msg.timestamp
		#expect(ts == Date(timeIntervalSince1970: 1700000000))
	}

	@Test func canRetry_noError_false() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.ackError = 0 // NONE
		#expect(msg.canRetry == false)
	}

	@Test func displayTimestamp_firstMessage_returnsFalse() {
		let container = makeContainer()
		let msg = MessageEntity(context: container.viewContext)
		msg.messageTimestamp = 1700000000
		#expect(msg.displayTimestamp(aboveMessage: nil) == false)
	}

	@Test func displayTimestamp_withinHour_returnsFalse() {
		let container = makeContainer()
		let ctx = container.viewContext
		let above = MessageEntity(context: ctx)
		above.messageTimestamp = 1700000000
		let current = MessageEntity(context: ctx)
		current.messageTimestamp = 1700000000 + 1800 // 30 min later
		#expect(current.displayTimestamp(aboveMessage: above) == false)
	}

	@Test func displayTimestamp_overHour_returnsTrue() {
		let container = makeContainer()
		let ctx = container.viewContext
		let above = MessageEntity(context: ctx)
		above.messageTimestamp = 1700000000
		let current = MessageEntity(context: ctx)
		current.messageTimestamp = 1700000000 + 7200 // 2 hours later
		#expect(current.displayTimestamp(aboveMessage: above) == true)
	}
}

// MARK: - UserEntity.messagePredicate Tests

@Suite("UserEntity messagePredicate")
struct UserEntityMessagePredicateTests {

	@Test func messagePredicate_isNotNil() {
		let container = makeInMemoryContainer()
		let user = UserEntity(context: container.viewContext)
		user.num = 1
		let pred = user.messagePredicate
		#expect(pred.predicateFormat.contains("toUser"))
		#expect(pred.predicateFormat.contains("fromUser"))
	}

	@Test func messageFetchRequest_hasSortDescriptor() {
		let container = makeInMemoryContainer()
		let user = UserEntity(context: container.viewContext)
		user.num = 1
		let req = user.messageFetchRequest
		#expect(req.sortDescriptors?.count == 1)
		#expect(req.sortDescriptors?.first?.key == "messageTimestamp")
	}
}

// MARK: - NodeInfoEntity Computed Properties Tests

@Suite("NodeInfoEntity Computed Properties")
struct NodeInfoEntityComputedTests {

	@Test func latestPosition_noPositions_returnsNil() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.latestPosition == nil)
	}

	@Test func hasPositions_noPositions_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.hasPositions == false)
	}

	@Test func latestDeviceMetrics_noTelemetry_returnsNil() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.latestDeviceMetrics == nil)
	}

	@Test func latestEnvironmentMetrics_noTelemetry_returnsNil() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.latestEnvironmentMetrics == nil)
	}

	@Test func latestPowerMetrics_noTelemetry_returnsNil() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.latestPowerMetrics == nil)
	}

	@Test func hasDeviceMetrics_noTelemetry_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.hasDeviceMetrics == false)
	}

	@Test func hasEnvironmentMetrics_noTelemetry_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.hasEnvironmentMetrics == false)
	}

	@Test func hasPowerMetrics_noTelemetry_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.hasPowerMetrics == false)
	}

	@Test func hasPax_noPax_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.hasPax == false)
	}

	@Test func hasTraceRoutes_noRoutes_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.hasTraceRoutes == false)
	}

	@Test func isStoreForwardRouter_noConfig_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		#expect(node.isStoreForwardRouter == false)
	}

	@Test func isOnline_nullLastHeard_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		node.lastHeard = nil
		#expect(node.isOnline == false)
	}

	@Test func isOnline_recentHeard_returnsTrue() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		node.lastHeard = Date() // just now
		#expect(node.isOnline == true)
	}

	@Test func isOnline_oldHeard_returnsFalse() {
		let container = makeInMemoryContainer()
		let node = NodeInfoEntity(context: container.viewContext)
		node.lastHeard = Date().addingTimeInterval(-3 * 3600) // 3 hours ago
		#expect(node.isOnline == false)
	}
}
