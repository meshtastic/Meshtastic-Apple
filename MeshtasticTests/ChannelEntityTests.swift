import XCTest
import SwiftData
@testable import Meshtastic

final class ChannelEntityTests: XCTestCase {
    var modelContainer: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let schema = Schema([ChannelEntity.self])
        modelContainer = try! ModelContainer(for: schema, configurations: [])
        context = ModelContext(modelContainer)
    }

    override func tearDown() {
        modelContainer = nil
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
}
