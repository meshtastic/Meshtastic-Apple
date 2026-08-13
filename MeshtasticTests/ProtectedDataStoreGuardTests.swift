//
//  ProtectedDataStoreGuardTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/11/26.
//
//  Locks down the probe that keeps a data-protection-locked store from being destroyed by the
//  corruption-recovery path (#2243). When the app is relaunched in the background before the
//  phone's first unlock (Bluetooth state restoration after a reboot), the store file exists but
//  cannot be opened; treating that as corruption renamed the user's database aside and started
//  an empty one. The probe must say "unreadable" for an exists-but-unopenable file, and
//  "readable" for anything the corruption path should still handle.
//
//  The simulator cannot reproduce the real pre-unlock data-protection state, so the
//  exists-but-unopenable condition is stood in for with POSIX permissions — the probe is a
//  plain open(2) check, so the two are equivalent at the layer under test.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Protected-data store guard")
struct ProtectedDataStoreGuardTests {

	private func tempFile(named name: String) -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent("pdguard-\(UUID().uuidString)-\(name)")
	}

	@Test("A missing store is not 'unreadable' — nothing to protect, recovery may proceed")
	func missingFileIsReadable() {
		let url = tempFile(named: "missing.store")
		#expect(PersistenceController.storeExistsButIsUnreadable(at: url) == false)
	}

	@Test("A readable (even corrupt) store is not 'unreadable' — corruption recovery may proceed")
	func readableGarbageIsReadable() throws {
		let url = tempFile(named: "garbage.store")
		// Not a valid SQLite file — the corruption case the recovery path exists for.
		try Data("definitely not sqlite".utf8).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(PersistenceController.storeExistsButIsUnreadable(at: url) == false)
	}

	@Test("An exists-but-unopenable store reads as locked — recovery must not touch it")
	func unopenableFileIsUnreadable() throws {
		let url = tempFile(named: "locked.store")
		try Data("locked".utf8).write(to: url)
		defer {
			try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
			try? FileManager.default.removeItem(at: url)
		}
		try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
		#expect(PersistenceController.storeExistsButIsUnreadable(at: url) == true)
	}
}
