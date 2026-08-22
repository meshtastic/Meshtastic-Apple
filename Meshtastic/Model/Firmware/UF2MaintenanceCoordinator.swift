import Foundation
import OSLog

struct UF2MaintenanceRecoveryRecord: Codable, Equatable {
	enum Phase: String, Codable {
		case prepared
		case writingMaintenance
		case awaitingApplicationWrite
		case writingApplication
		case awaitingReconnect
	}

	let id: UUID
	let createdAt: Date
	let request: UF2MaintenanceRequest
	let descriptor: UF2MaintenanceApplicationDescriptor
	let applicationArtifact: UF2FirmwareArtifactIdentity
	var phase: Phase
	var volume: UF2VolumeIdentity?
	var maintenanceArtifact: UF2MaintenanceArtifactIdentity?
	var maintenanceCopyError: String?
	var applicationCopyError: String?
	var maintenanceVerified: Bool?
}

protocol UF2MaintenanceRecoveryStoring {
	func load() -> UF2MaintenanceRecoveryRecord?
	func save(_ record: UF2MaintenanceRecoveryRecord) throws
	func clear()
}

extension Foundation.Notification.Name {
	static let uf2MaintenanceRecoveryChanged = Foundation.Notification.Name("UF2MaintenanceRecoveryChanged")
}

final class UF2MaintenanceRecoveryStore: UF2MaintenanceRecoveryStoring {
	static let shared = UF2MaintenanceRecoveryStore()
	static var pendingRecord: UF2MaintenanceRecoveryRecord? { shared.load() }

	private let defaults: UserDefaults
	private let key = "pendingUF2MaintenanceRecovery"

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	func load() -> UF2MaintenanceRecoveryRecord? {
		guard let data = defaults.data(forKey: key) else { return nil }
		do {
			return try JSONDecoder().decode(UF2MaintenanceRecoveryRecord.self, from: data)
		} catch {
			Logger.services.error("Discarding unreadable UF2 maintenance recovery record: \(error.localizedDescription, privacy: .public)")
			defaults.removeObject(forKey: key)
			return nil
		}
	}

	func save(_ record: UF2MaintenanceRecoveryRecord) throws {
		defaults.set(try JSONEncoder().encode(record), forKey: key)
		NotificationCenter.default.post(name: .uf2MaintenanceRecoveryChanged, object: nil)
	}

	func clear() {
		defaults.removeObject(forKey: key)
		NotificationCenter.default.post(name: .uf2MaintenanceRecoveryChanged, object: nil)
	}
}

@MainActor
final class UF2MaintenanceCoordinator: ObservableObject {
	typealias ArtifactLoad = (
		UF2MaintenanceArtifact,
		UF2MaintenanceRequest
	) async throws -> (Data, UF2MaintenanceArtifactIdentity)

	enum State: Equatable {
		case idle
		case preparing
		case ready
		case selectingVolume
		case loadingMaintenance
		case writing
		case awaitingApplicationWrite
		case awaitingReconnect
		case verifying
		case completed(warnings: [String])
		case failed(String)
	}

	@Published private(set) var state: State = .idle
	@Published private(set) var errorMessage: String?
	@Published private(set) var warningMessage: String?

	private let initialDescriptor: UF2MaintenanceApplicationDescriptor
	private let initialRequest: UF2MaintenanceRequest
	private let store: UF2MaintenanceRecoveryStoring
	private let artifactLoad: ArtifactLoad
	private var record: UF2MaintenanceRecoveryRecord?

	init(
		descriptor: UF2MaintenanceApplicationDescriptor,
		request: UF2MaintenanceRequest,
		store: UF2MaintenanceRecoveryStoring = UF2MaintenanceRecoveryStore.shared,
		artifactLoad: ArtifactLoad? = nil
	) {
		initialDescriptor = descriptor
		initialRequest = request
		self.store = store
		self.artifactLoad = artifactLoad ?? { artifact, request in
			try await UF2MaintenanceArtifactLoader.load(artifact, request: request)
		}
		resumeIfPresent()
	}

	var activeDescriptor: UF2MaintenanceApplicationDescriptor { record?.descriptor ?? initialDescriptor }
	var activeRequest: UF2MaintenanceRequest { record?.request ?? initialRequest }
	var applicationArtifact: UF2FirmwareArtifactIdentity? { record?.applicationArtifact }
	var maintenanceArtifact: UF2MaintenanceArtifactIdentity? { record?.maintenanceArtifact }
	var maintenanceCopyError: String? { record?.maintenanceCopyError }
	var applicationCopyError: String? { record?.applicationCopyError }
	var canSelectVolume: Bool { state == .ready || state == .awaitingApplicationWrite }
	var blocksDismissal: Bool {
		state == .loadingMaintenance || state == .writing || state == .awaitingApplicationWrite
	}
	var canStopTracking: Bool {
		recordMatchesInitialTarget && record?.phase == .awaitingReconnect && state != .writing
	}

	func prepare() async {
		guard record == nil else { return }
		state = .preparing
		errorMessage = nil
		warningMessage = nil
		do {
			let descriptor = initialDescriptor
			let (_, identity) = try await Task.detached(priority: .userInitiated) {
				try UF2MaintenanceApplicationInspector.inspect(
					fileURL: descriptor.localURL,
					descriptor: descriptor
				)
			}.value
			let record = UF2MaintenanceRecoveryRecord(
				id: UUID(),
				createdAt: .now,
				request: initialRequest,
				descriptor: descriptor,
				applicationArtifact: identity,
				phase: .prepared,
				volume: nil,
				maintenanceArtifact: nil,
				maintenanceCopyError: nil,
				applicationCopyError: nil,
				maintenanceVerified: nil
			)
			try store.save(record)
			self.record = record
			state = .ready
		} catch {
			errorMessage = error.localizedDescription
			state = .failed(error.localizedDescription)
		}
	}

	func selectVolume() {
		guard canSelectVolume else { return }
		state = .selectingVolume
		errorMessage = nil
	}

	func volumeSelectionCancelled() {
		guard state == .selectingVolume else { return }
		state = record?.phase == .awaitingApplicationWrite ? .awaitingApplicationWrite : .ready
	}

	func volumeSelectionFailed(_ error: Error) {
		guard state == .selectingVolume else { return }
		errorMessage = error.localizedDescription
		state = record?.phase == .awaitingApplicationWrite ? .awaitingApplicationWrite : .ready
	}

	func write(to folderURL: URL) async {
		guard let record, state == .selectingVolume else { return }
		errorMessage = nil
		warningMessage = nil
		if record.phase == .awaitingApplicationWrite {
			await writeApplication(to: folderURL, initialRecord: record)
		} else {
			await writeMaintenance(to: folderURL, initialRecord: record)
		}
	}

	func verify(reportedFirmwareVersion: String?) {
		guard let record, record.phase == .awaitingReconnect else { return }
		state = .verifying
		guard Self.versionsMatch(expected: record.descriptor.version, actual: reportedFirmwareVersion) else {
			let actual = reportedFirmwareVersion ?? String(localized: "Unknown")
			errorMessage = String(
				localized: "The radio reports firmware \(actual); expected \(record.descriptor.version)."
			)
			state = .awaitingReconnect
			return
		}
		var warnings: [String] = []
		if record.request == .bootloaderUpgrade, record.maintenanceVerified != true {
			warnings.append(
				String(localized: "Application firmware was verified, but the OTAFIX bootloader upgrade was not confirmed.")
			)
		}
		store.clear()
		self.record = nil
		errorMessage = nil
		warningMessage = nil
		state = .completed(warnings: warnings)
	}

	func stopTrackingRecovery() {
		guard canStopTracking else { return }
		store.clear()
		record = nil
		errorMessage = nil
		warningMessage = nil
		state = .idle
	}

	func cancelBeforeWrite() {
		guard recordMatchesInitialTarget, record?.phase == .prepared else { return }
		store.clear()
		record = nil
		state = .idle
	}

	private var recordMatchesInitialTarget: Bool {
		record?.descriptor.platformioTarget == initialDescriptor.platformioTarget
	}

	private func writeMaintenance(
		to folderURL: URL,
		initialRecord: UF2MaintenanceRecoveryRecord
	) async {
		var record = initialRecord
		state = .loadingMaintenance
		do {
			let volume = try await UF2MaintenanceVolumeIO.inspect(folderURL: folderURL)
			try UF2MaintenanceDestinationValidator.validate(
				volume: volume,
				artifact: record.applicationArtifact,
				descriptor: record.descriptor
			)
			let artifact = try UF2MaintenanceCatalog.artifact(for: record.request, volume: volume)
			let (data, identity) = try await artifactLoad(artifact, record.request)
			record.phase = .writingMaintenance
			record.volume = volume
			record.maintenanceArtifact = identity
			try store.save(record)
			self.record = record
			state = .writing

			let attempt: UF2WriteAttempt
			do {
				attempt = try await UF2MaintenanceVolumeIO.writeValidated(
					data,
					to: folderURL,
					expectedVolume: volume
				)
			} catch {
				record.phase = .prepared
				try store.save(record)
				self.record = record
				throw error
			}
			record.phase = .awaitingApplicationWrite
			record.maintenanceCopyError = attempt.copyError
			persistAfterWrite(record, fallback: .awaitingApplicationWrite)
			state = .awaitingApplicationWrite
		} catch {
			errorMessage = error.localizedDescription
			state = .ready
		}
	}

	private func writeApplication(
		to folderURL: URL,
		initialRecord: UF2MaintenanceRecoveryRecord
	) async {
		var record = initialRecord
		do {
			let descriptor = record.descriptor
			let (data, identity) = try await Task.detached(priority: .userInitiated) {
				try UF2MaintenanceApplicationInspector.inspect(
					fileURL: descriptor.localURL,
					descriptor: descriptor
				)
			}.value
			guard identity.sha256 == record.applicationArtifact.sha256 else {
				throw UF2FirmwareValidationError.firmwareChanged(
					expected: record.applicationArtifact.sha256,
					actual: identity.sha256
				)
			}
			let volume = try await UF2MaintenanceVolumeIO.inspect(folderURL: folderURL)
			try UF2MaintenanceDestinationValidator.validate(
				volume: volume,
				artifact: identity,
				descriptor: descriptor
			)
			guard volume.boardID == record.volume?.boardID,
				volume.softDevice == record.volume?.softDevice else {
				throw UF2FirmwareValidationError.volumeChanged
			}
			if record.request == .bootloaderUpgrade {
				record.maintenanceVerified = volume.bootloaderVersion?.contains(
					UF2MaintenanceCatalog.expectedOTAFIXVersion
				) == true
				if record.maintenanceVerified != true {
					warningMessage = String(
						localized: "The fresh volume does not confirm OTAFIX. The mandatory application reinstall will continue, and the maintenance image will not be retried."
					)
				}
			}
			record.phase = .writingApplication
			try store.save(record)
			self.record = record
			state = .writing

			let attempt: UF2WriteAttempt
			do {
				attempt = try await UF2MaintenanceVolumeIO.writeValidated(
					data,
					to: folderURL,
					expectedVolume: volume
				)
			} catch {
				record.phase = .awaitingApplicationWrite
				try store.save(record)
				self.record = record
				throw error
			}
			record.phase = .awaitingReconnect
			record.applicationCopyError = attempt.copyError
			persistAfterWrite(record, fallback: .awaitingReconnect)
			state = .awaitingReconnect
		} catch {
			errorMessage = error.localizedDescription
			state = .awaitingApplicationWrite
		}
	}

	private func persistAfterWrite(
		_ record: UF2MaintenanceRecoveryRecord,
		fallback: State
	) {
		self.record = record
		do {
			try store.save(record)
		} catch {
			errorMessage = String(
				localized: "The write may have completed, but recovery state could not be updated: \(error.localizedDescription)"
			)
			state = fallback
		}
	}

	private func resumeIfPresent() {
		guard var pending = store.load() else { return }
		if pending.descriptor.platformioTarget != initialDescriptor.platformioTarget {
			record = pending
			state = .failed(
				String(localized: "A firmware maintenance operation for \(pending.descriptor.platformioTarget) is still pending.")
			)
			return
		}

		let interruptedWrite = pending.phase == .writingMaintenance || pending.phase == .writingApplication
		if pending.phase == .writingMaintenance {
			pending.phase = .awaitingApplicationWrite
		} else if pending.phase == .writingApplication {
			pending.phase = .awaitingReconnect
		}
		if interruptedWrite {
			do {
				try store.save(pending)
			} catch {
				record = pending
				let message = String(
					localized: "The write may have completed, but recovery state could not be updated: \(error.localizedDescription)"
				)
				errorMessage = message
				state = .failed(message)
				return
			}
		}

		record = pending
		switch pending.phase {
		case .prepared: state = .ready
		case .writingMaintenance, .awaitingApplicationWrite: state = .awaitingApplicationWrite
		case .writingApplication, .awaitingReconnect: state = .awaitingReconnect
		}
	}

	private static func versionsMatch(expected: String, actual: String?) -> Bool {
		guard let actual else { return false }
		func releaseComponents(_ value: String) -> [Int]? {
			let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
			let withoutPrefix = trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
			let components = withoutPrefix.split(separator: ".").prefix(3).compactMap { Int($0) }
			return components.count == 3 ? components : nil
		}
		guard let expectedComponents = releaseComponents(expected),
			let actualComponents = releaseComponents(actual) else {
			return false
		}
		return expectedComponents == actualComponents
	}
}
