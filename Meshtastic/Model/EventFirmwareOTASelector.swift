import Foundation

struct EventFirmwareOTATarget: Equatable, Sendable {
	let pioEnv: String
	let hwModel: Int
	let architecture: String
	let firmwareVersion: String
	let supportsOTA: Bool
	let partitionScheme: String?
	let bootloaderVersion: String?
}

enum EventFirmwareOTAInstallPurpose: Equatable, Sendable {
	case event
	case standard
}

struct EventFirmwareOTASelection: Equatable, Sendable {
	let artifact: EventFirmwareOTAArtifact
	let purpose: EventFirmwareOTAInstallPurpose
}

enum EventFirmwareOTASelectionError: Error, Equatable {
	case noExactTarget
	case ambiguousTarget
	case sourceFirmwareTooOld(minimum: String)
	case bootloaderTooOld(minimum: String)
	case unsupportedOTAPath
	case unapprovedArtifactURL
	case incompatibleArtifact
}

struct EventFirmwareOTASelector {
	private let allowedHosts: Set<String>

	init(allowedHosts: Set<String> = ["raw.githubusercontent.com"]) {
		self.allowedHosts = allowedHosts
	}

	func select(
		from contract: EventFirmwareOTAContract,
		for target: EventFirmwareOTATarget,
		purpose: EventFirmwareOTAInstallPurpose
	) throws -> EventFirmwareOTASelection {
		let candidates = purpose == .event ? contract.artifacts : contract.standardArtifacts
		let matchingArtifacts = candidates.filter {
			$0.pioEnv == target.pioEnv &&
			$0.hwModel == target.hwModel &&
			$0.architecture == target.architecture
		}
		guard !matchingArtifacts.isEmpty else {
			throw EventFirmwareOTASelectionError.noExactTarget
		}
		guard matchingArtifacts.count == 1, let artifact = matchingArtifacts.first else {
			throw EventFirmwareOTASelectionError.ambiguousTarget
		}
		guard target.supportsOTA else {
			throw EventFirmwareOTASelectionError.unsupportedOTAPath
		}
		guard isVersion(target.firmwareVersion, atLeast: artifact.minimumSourceVersion) else {
			throw EventFirmwareOTASelectionError.sourceFirmwareTooOld(
				minimum: artifact.minimumSourceVersion
			)
		}
		guard isApprovedArtifactURL(artifact.url) else {
			throw EventFirmwareOTASelectionError.unapprovedArtifactURL
		}
		guard artifact.byteCount > 0,
			  numericVersion(artifact.version) != nil,
			  artifact.sha256.count == 64,
			  artifact.sha256.allSatisfy(\.isHexDigit) else {
			throw EventFirmwareOTASelectionError.incompatibleArtifact
		}

		switch Architecture(rawValue: target.architecture) {
		case .esp32, .esp32C3, .esp32S3, .esp32C6:
			guard artifact.format == .bin,
				  artifact.partitionRole == "app0",
				  artifact.byteCount <= 16 * 1_024 * 1_024,
				  let artifactPartitionScheme = artifact.partitionScheme,
				  !artifactPartitionScheme.isEmpty,
				  artifactPartitionScheme == target.partitionScheme else {
				throw EventFirmwareOTASelectionError.incompatibleArtifact
			}
		case .nrf52840:
			guard artifact.format == .otaZip,
				  artifact.dfuProtocol == "nordic-legacy",
				  artifact.partitionRole == nil,
				  artifact.partitionScheme == nil,
				  artifact.byteCount <= 4 * 1_024 * 1_024,
				  let minimumBootloaderVersion = artifact.minimumBootloaderVersion else {
				throw EventFirmwareOTASelectionError.incompatibleArtifact
			}
			guard let installedBootloaderVersion = target.bootloaderVersion else {
				throw EventFirmwareOTASelectionError.bootloaderTooOld(
					minimum: minimumBootloaderVersion
				)
			}
			guard isVersion(installedBootloaderVersion, atLeast: minimumBootloaderVersion) else {
				throw EventFirmwareOTASelectionError.bootloaderTooOld(
					minimum: minimumBootloaderVersion
				)
			}
		case .rp2040, .none:
			throw EventFirmwareOTASelectionError.unsupportedOTAPath
		}

		return EventFirmwareOTASelection(artifact: artifact, purpose: purpose)
	}

	private func isApprovedArtifactURL(_ url: URL) -> Bool {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			  components.scheme?.lowercased() == "https",
			  let host = components.host?.lowercased(),
			  allowedHosts.contains(host),
			  components.user == nil,
			  components.password == nil,
			  components.fragment == nil,
			  components.query == nil else {
			return false
		}

		if host == "raw.githubusercontent.com" {
			let path = components.path.split(separator: "/", omittingEmptySubsequences: true)
			guard path.count >= 4 else { return false }
			let revision = path[2]
			return revision.count == 40 && revision.allSatisfy(\.isHexDigit)
		}
		return true
	}

	private func isVersion(_ installed: String, atLeast minimum: String) -> Bool {
		guard let installedParts = numericVersion(installed),
			  let minimumParts = numericVersion(minimum) else {
			return false
		}
		let count = max(installedParts.count, minimumParts.count)
		for index in 0..<count {
			let installedPart = index < installedParts.count ? installedParts[index] : 0
			let minimumPart = index < minimumParts.count ? minimumParts[index] : 0
			if installedPart != minimumPart {
				return installedPart > minimumPart
			}
		}
		return true
	}

	private func numericVersion(_ version: String) -> [Int]? {
		let normalized = version
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingPrefix("v")
		let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
		guard components.count >= 3 else { return nil }
		let core = components.prefix(3)
		guard core.allSatisfy({
			!$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber }
		}) else {
			return nil
		}
		let suffix = components.dropFirst(3)
		guard suffix.allSatisfy({
			!$0.isEmpty && $0.allSatisfy {
				$0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
			}
		}) else {
			return nil
		}
		let numericCore = core.map { Int($0) }
		guard numericCore.count == 3,
			  numericCore.allSatisfy({ $0 != nil }) else {
			return nil
		}
		return numericCore.compactMap { $0 }
	}
}
