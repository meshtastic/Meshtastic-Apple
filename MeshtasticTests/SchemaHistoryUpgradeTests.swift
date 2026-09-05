import CoreData
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Meshtastic

private struct SchemaHistoryManifest: Decodable {
	let formatVersion: Int
	let tags: [SchemaHistoryFixture]
	let xcode: SchemaHistoryXcode
}

private struct SchemaHistoryFixture: Decodable, Hashable {
	let checksum: String
	let commit: String
	let fixture: String
	let sourceTag: String
	let tag: String
}

private struct SchemaHistoryXcode: Decodable {
	let build: String
	let version: String
}

private struct SchemaHistoryMetadata: Decodable {
	let checksum: String
	let sourceTag: String
}

private final class SchemaHistoryBundleMarker: NSObject {}

@Suite("SwiftData schema history", .serialized)
struct SchemaHistoryUpgradeTests {
	private static let expectedTags = [
		"v2.7.13",
		"v2.7.14",
		"v2.7.15",
		"v2.7.16",
		"v2.7.17",
		"v2.7.18",
		"v2.7.19",
		"v2.7.20",
		"v2.7.21"
	]

	// Never update this value. A mismatch means V1 was edited instead of adding a new schema.
	private static let expectedV1Checksum = "e6b2a95d7a2ffdcd3c17579191161532a2025a8cf5af8f315bf6331f385117f0"
	// Update this only when a new current schema and migration stage are added.
	private static let expectedCurrentChecksum = "e6b2a95d7a2ffdcd3c17579191161532a2025a8cf5af8f315bf6331f385117f0"

	@Test func fixtureInventoryCoversEverySwiftDataRelease() throws {
		let (manifest, root) = try loadManifest()
		#expect(manifest.formatVersion == 1)
		#expect(manifest.tags.map(\.tag) == Self.expectedTags)
		#expect(manifest.tags.allSatisfy { $0.commit.count == 40 })
		#expect(!manifest.xcode.version.isEmpty)
		#expect(!manifest.xcode.build.isEmpty)

		let fixtures = Dictionary(grouping: manifest.tags, by: \.checksum)
		#expect(fixtures.count == 8)
		for (checksum, entries) in fixtures {
			let fixture = try #require(entries.first)
			#expect(entries.allSatisfy { $0.fixture == fixture.fixture })
			#expect(entries.allSatisfy { $0.sourceTag == fixture.sourceTag })
			#expect(fixture.fixture == "\(checksum)/Meshtastic.store")
			#expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(fixture.fixture).path))

			let metadataURL = root.appendingPathComponent(checksum).appendingPathComponent("metadata.json")
			let metadata = try JSONDecoder().decode(SchemaHistoryMetadata.self, from: Data(contentsOf: metadataURL))
			#expect(metadata.checksum == checksum)
			#expect(metadata.sourceTag == fixture.sourceTag)
		}
	}

	@Test @MainActor func everyHistoricalStoreOpensWithoutReplacement() throws {
		let (manifest, root) = try loadManifest()
		let fixtures = Dictionary(grouping: manifest.tags, by: \.checksum)
			.values
			.compactMap(\.first)
			.sorted { $0.sourceTag < $1.sourceTag }

		for fixture in fixtures {
			do {
				try validateUpgrade(of: fixture, from: root)
			} catch {
				Issue.record("\(fixture.sourceTag) fixture \(fixture.checksum) failed to open: \(error)")
			}
		}
	}

	@Test @MainActor func effectiveV1SchemaHasNotChanged() throws {
		let temporaryDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("MeshtasticV1Schema-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
		let storeURL = temporaryDirectory.appendingPathComponent("Meshtastic.store")
		let schema = Schema(versionedSchema: MeshtasticSchemaV1.self)
		let configuration = ModelConfiguration("Meshtastic", schema: schema, url: storeURL, allowsSave: true)
		do {
			let container = try ModelContainer(for: schema, configurations: configuration)
			try container.mainContext.save()
		}

		let checksum = try schemaChecksum(at: storeURL)
		#expect(
			checksum == Self.expectedV1Checksum,
			"MeshtasticSchemaV1 changed. Add a new versioned schema instead of editing V1. Actual checksum: \(checksum)"
		)
	}

	private func loadManifest() throws -> (SchemaHistoryManifest, URL) {
		let bundle = Bundle(for: SchemaHistoryBundleMarker.self)
		let root = try #require(
			bundle.resourceURL?.appendingPathComponent("swiftdata-schema-history", isDirectory: true)
		)
		let manifestURL = root.appendingPathComponent("manifest.json")
		let manifest = try JSONDecoder().decode(SchemaHistoryManifest.self, from: Data(contentsOf: manifestURL))
		return (manifest, root)
	}

	@MainActor
	private func validateUpgrade(of fixture: SchemaHistoryFixture, from resourceRoot: URL) throws {
		let sourceStore = resourceRoot.appendingPathComponent(fixture.fixture)
		let storeName = "SchemaHistory-\(fixture.sourceTag)-\(UUID().uuidString)"
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: false, allowsSave: true)
		let storeURL = configuration.url
		try FileManager.default.createDirectory(
			at: storeURL.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try FileManager.default.copyItem(at: sourceStore, to: storeURL)
		defer { removeStoreFiles(startingWith: storeURL) }
		#expect(try schemaChecksum(at: storeURL) == fixture.checksum)

		try autoreleasepool {
			let controller = PersistenceController(inMemory: false, storeName: storeName)
			let context = controller.context
			let patch = try #require(Int(fixture.sourceTag.split(separator: ".").last ?? ""))
			let fixtureBase = Int64(2_700_000 + patch * 1_000)
			let senderNumber = fixtureBase + 1
			let receiverNumber = fixtureBase + 2
			let messageID = fixtureBase + Int64(patch)

			let nodes = try context.fetch(FetchDescriptor<NodeInfoEntity>())
			let users = try context.fetch(FetchDescriptor<UserEntity>())
			let messages = try context.fetch(FetchDescriptor<MessageEntity>())
			let positions = try context.fetch(FetchDescriptor<PositionEntity>())
			let node = try #require(nodes.first)
			let message = try #require(messages.first)
			#expect(nodes.count == 1)
			#expect(users.count == 2)
			#expect(messages.count == 1)
			#expect(positions.count == 1)
			#expect(node.num == senderNumber)
			#expect(node.favorite)
			#expect(node.bleName == "fixture-\(fixture.sourceTag)")
			#expect(node.user?.num == senderNumber)
			#expect(node.user?.longName == "Schema fixture sender \(fixture.sourceTag)")
			#expect(node.positions.count == 1)
			#expect(node.positions.first?.nodePosition === node)
			#expect(message.messageId == messageID)
			#expect(message.messagePayload == "schema-history-\(fixture.sourceTag)")
			#expect(message.fromUser?.num == senderNumber)
			#expect(message.toUser?.num == receiverNumber)
			#expect(message.fromUser?.sentMessages.contains { $0.messageId == messageID } == true)
			#expect(message.toUser?.receivedMessages.contains { $0.messageId == messageID } == true)
		}

		let directoryContents = try FileManager.default.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().path)
		let brokenPrefix = storeURL.lastPathComponent + "-broken-"
		#expect(directoryContents.allSatisfy { !$0.hasPrefix(brokenPrefix) })
		#expect(try schemaChecksum(at: storeURL) == Self.expectedCurrentChecksum)
	}

	private func removeStoreFiles(startingWith storeURL: URL) {
		let fileManager = FileManager.default
		let directory = storeURL.deletingLastPathComponent()
		let storeFileName = storeURL.lastPathComponent
		guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
		for name in names where name == storeFileName || name.hasPrefix(storeFileName + "-") {
			try? fileManager.removeItem(at: directory.appendingPathComponent(name))
		}
	}

	private func schemaChecksum(at storeURL: URL) throws -> String {
		let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
			ofType: NSSQLiteStoreType,
			at: storeURL,
			options: nil
		)
		let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:]
		let canonicalHashes = hashes.keys.sorted().map { key in
			"\(key)=\(hashes[key]!.base64EncodedString())"
		}.joined(separator: "\n")
		return SHA256.hash(data: Data(canonicalHashes.utf8))
			.map { String(format: "%02x", $0) }
			.joined()
	}
}
