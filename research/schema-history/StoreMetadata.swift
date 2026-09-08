#!/usr/bin/env swift

import CoreData
import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4 else {
	fputs("usage: StoreMetadata.swift <store> <tag> <output-json>\n", stderr)
	exit(64)
}

let storeURL = URL(fileURLWithPath: CommandLine.arguments[1])
let tag = CommandLine.arguments[2]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
	ofType: NSSQLiteStoreType,
	at: storeURL,
	options: nil
)
let entityVersionHashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] ?? [:]
let encodedHashes = entityVersionHashes.mapValues { $0.base64EncodedString() }
let canonicalHashes = encodedHashes.keys.sorted().map { key in
	"\(key)=\(encodedHashes[key]!)"
}.joined(separator: "\n")
let checksum = SHA256.hash(data: Data(canonicalHashes.utf8))
	.map { String(format: "%02x", $0) }
	.joined()
let versionIdentifiers = (metadata[NSStoreModelVersionIdentifiersKey] as? Set<AnyHashable> ?? [])
	.map(String.init(describing:))
	.sorted()
let output: [String: Any] = [
	"checksum": checksum,
	"entityCount": encodedHashes.count,
	"entityVersionHashes": encodedHashes,
	"sourceTag": tag,
	"versionIdentifiers": versionIdentifiers
]
let outputData = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
try outputData.write(to: outputURL, options: .atomic)
print(checksum)
