import XCTest
import SwiftData
@testable import Meshtastic

final class ChannelEntityTests: XCTestCase {
    var modelContainer: ModelContainer!
    var context: ModelContext!

    @MainActor override func setUp() {
        super.setUp()
        modelContainer = sharedModelContainer
        context = ModelContext(modelContainer)
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    func testChannelEntityDefaultInit() {
        let channel = ChannelEntity()
        XCTAssertFalse(channel.downlinkEnabled)
        XCTAssertEqual(channel.id, 0)
        XCTAssertEqual(channel.index, 0)
        XCTAssertFalse(channel.mute)
        XCTAssertNil(channel.name)
        XCTAssertEqual(channel.positionPrecision, 32)
        XCTAssertNil(channel.psk)
        XCTAssertEqual(channel.role, 0)
        XCTAssertFalse(channel.uplinkEnabled)
        XCTAssertNil(channel.myInfoChannel)
    }

    func testChannelEntityInsertAndFetch() throws {
        let channel = ChannelEntity()
        channel.id = 42
        channel.name = "Test Channel"
        channel.uplinkEnabled = true
        context.insert(channel)
        try context.save()

        let descriptor = FetchDescriptor<ChannelEntity>(predicate: #Predicate { $0.id == 42 })
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Test Channel")
        XCTAssertTrue(fetched.first?.uplinkEnabled ?? false)
    }

	func testUnencryptedChannelAllowsPreciseLocationOnlyInHamMode() {
		XCTAssertFalse(ChannelPreciseLocationPolicy.canEnablePreciseLocation(
			channelKeySize: 0,
			channelRole: 1,
			isHamMode: false
		))
		XCTAssertTrue(ChannelPreciseLocationPolicy.canEnablePreciseLocation(
			channelKeySize: 0,
			channelRole: 1,
			isHamMode: true
		))
	}

	func testDefaultKeyChannelCannotEnablePreciseLocationInHamMode() {
		XCTAssertFalse(ChannelPreciseLocationPolicy.canEnablePreciseLocation(
			channelKeySize: -1,
			channelRole: 1,
			isHamMode: true
		))
	}

	func testDisabledChannelCannotEnablePreciseLocation() {
		XCTAssertFalse(ChannelPreciseLocationPolicy.canEnablePreciseLocation(
			channelKeySize: 16,
			channelRole: 0,
			isHamMode: true
		))
	}

	func testHamModeForcesAnEmptyChannelKey() {
		XCTAssertEqual(ChannelPreciseLocationPolicy.requiredChannelKeySize(
			currentKeySize: 16,
			isHamMode: true
		), 0)
		XCTAssertEqual(ChannelPreciseLocationPolicy.requiredChannelKeySize(
			currentKeySize: 16,
			isHamMode: false
		), 16)
	}

	func testEncryptedChannelAllowsPreciseLocationWithoutHamMode() {
		XCTAssertTrue(ChannelPreciseLocationPolicy.canEnablePreciseLocation(
			channelKeySize: 16,
			channelRole: 1,
			isHamMode: false
		))
	}

	func testUnencryptedHamChannelRequiresAcknowledgementBeforePreciseLocation() {
		XCTAssertTrue(ChannelPreciseLocationPolicy.requiresPrivacyAcknowledgement(
			channelKeySize: 0,
			isHamMode: true
		))
		XCTAssertFalse(ChannelPreciseLocationPolicy.requiresPrivacyAcknowledgement(
			channelKeySize: 0,
			isHamMode: false
		))
	}
}
