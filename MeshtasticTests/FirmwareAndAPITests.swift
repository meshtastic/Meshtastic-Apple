import Foundation
import Testing

@testable import Meshtastic

// MARK: - FirmwareFileError

@Suite("FirmwareFileError")
struct FirmwareFileErrorTests {

	@Test func invalidFilenamePrefix_description() {
		let error = FirmwareFile.FirmwareFileError.invalidFilenamePrefix
		#expect(error.errorDescription?.contains("firmware-") == true)
	}

	@Test func parseError_description() {
		let error = FirmwareFile.FirmwareFileError.parseError
		#expect(error.errorDescription?.contains("parse") == true)
	}

	@Test func unknownFileType_description() {
		let error = FirmwareFile.FirmwareFileError.unknownFileType
		#expect(error.errorDescription?.contains("file type") == true)
	}

	@Test func unknownTarget_description() {
		let error = FirmwareFile.FirmwareFileError.unknownTarget
		#expect(error.errorDescription?.contains("target") == true)
	}

	@Test func unknownArchitecture_description() {
		let error = FirmwareFile.FirmwareFileError.unknownArchitecture
		#expect(error.errorDescription?.contains("architecture") == true)
	}

	@Test func unknownVersion_description() {
		let error = FirmwareFile.FirmwareFileError.unknownVersion
		#expect(error.errorDescription?.contains("version") == true)
	}

	@Test func unknownReleaseType_description() {
		let error = FirmwareFile.FirmwareFileError.unknownReleaseType
		#expect(error.errorDescription?.contains("release type") == true)
	}

	@Test func unknownRemoteURL_description() {
		let error = FirmwareFile.FirmwareFileError.unknownRemoteURL
		#expect(error.errorDescription?.contains("URL") == true)
	}
}

// MARK: - DownloadStatus

@Suite("DownloadStatus")
struct DownloadStatusTests {

	@Test func notDownloaded_equatable() {
		#expect(FirmwareFile.DownloadStatus.notDownloaded == .notDownloaded)
	}

	@Test func downloading_equatable() {
		#expect(FirmwareFile.DownloadStatus.downloading == .downloading)
	}

	@Test func downloaded_equatable() {
		#expect(FirmwareFile.DownloadStatus.downloaded == .downloaded)
	}

	@Test func error_equatable() {
		#expect(FirmwareFile.DownloadStatus.error("test") == .error("test"))
	}

	@Test func different_notEqual() {
		#expect(FirmwareFile.DownloadStatus.notDownloaded != .downloaded)
	}

	@Test func differentErrors_notEqual() {
		#expect(FirmwareFile.DownloadStatus.error("a") != .error("b"))
	}
}

// MARK: - FirmwareType

@Suite("FirmwareType")
struct FirmwareTypeTests {

	@Test func uf2_rawValue() {
		#expect(FirmwareFile.FirmwareType.uf2.rawValue == ".uf2")
	}

	@Test func bin_rawValue() {
		#expect(FirmwareFile.FirmwareType.bin.rawValue == ".bin")
	}

	@Test func otaZip_rawValue() {
		#expect(FirmwareFile.FirmwareType.otaZip.rawValue == "-ota.zip")
	}

	@Test func description_matchesRawValue() {
		for ft in [FirmwareFile.FirmwareType.uf2, .bin, .otaZip] {
			#expect(ft.description == ft.rawValue)
		}
	}

	@Test func id_matchesRawValue() {
		#expect(FirmwareFile.FirmwareType.uf2.id == ".uf2")
	}
}

// MARK: - Architecture

@Suite("Architecture")
struct ArchitectureTests {

	@Test func esp32_rawValue() {
		#expect(Architecture.esp32.rawValue == "esp32")
	}

	@Test func esp32C3_rawValue() {
		#expect(Architecture.esp32C3.rawValue == "esp32-c3")
	}

	@Test func esp32S3_rawValue() {
		#expect(Architecture.esp32S3.rawValue == "esp32-s3")
	}

	@Test func esp32C6_rawValue() {
		#expect(Architecture.esp32C6.rawValue == "esp32-c6")
	}

	@Test func nrf52840_rawValue() {
		#expect(Architecture.nrf52840.rawValue == "nrf52840")
	}

	@Test func rp2040_rawValue() {
		#expect(Architecture.rp2040.rawValue == "rp2040")
	}

	@Test func id_matchesRawValue() {
		#expect(Architecture.esp32.id == "esp32")
	}

	@Test func initFromRawValue() {
		#expect(Architecture(rawValue: "esp32") == .esp32)
		#expect(Architecture(rawValue: "invalid") == nil)
	}
}

// MARK: - ReleaseType

@Suite("ReleaseType")
struct ReleaseTypeTests {

	@Test func stable_rawValue() {
		#expect(ReleaseType.stable.rawValue == "Stable")
	}

	@Test func alpha_rawValue() {
		#expect(ReleaseType.alpha.rawValue == "Alpha")
	}

	@Test func unlisted_rawValue() {
		#expect(ReleaseType.unlisted.rawValue == "Unlisted")
	}

	@Test func initFromRawValue() {
		#expect(ReleaseType(rawValue: "Stable") == .stable)
		#expect(ReleaseType(rawValue: "Alpha") == .alpha)
		#expect(ReleaseType(rawValue: "invalid") == nil)
	}
}

// MARK: - MeshtasticAPIError

@Suite("MeshtasticAPIError")
struct MeshtasticAPIErrorTests {

	@Test func timedOut_description() {
		let error = MeshtasticAPI.MeshtasticAPIError.timedOut(5.0)
		#expect(error.errorDescription?.contains("5.0") == true)
	}

	@Test func unableToRetreiveJSON_description() {
		let error = MeshtasticAPI.MeshtasticAPIError.unableToRetreviveJSON
		#expect(error.errorDescription != nil)
	}

	@Test func unableToFindOrCreateEntity_description() {
		let error = MeshtasticAPI.MeshtasticAPIError.unableToFindOrCreateEntity
		#expect(error.errorDescription != nil)
	}

	@Test func unknownArchitecture_description() {
		let error = MeshtasticAPI.MeshtasticAPIError.unknownArchitecture
		#expect(error.errorDescription?.contains("architecture") == true)
	}

	@Test func unknownPlatformIOTarget_description() {
		let error = MeshtasticAPI.MeshtasticAPIError.unknownPlatformIOTarget
		#expect(error.errorDescription?.contains("target") == true)
	}
}

// MARK: - URL TimeoutError

@Suite("URL TimeoutError")
struct URLTimeoutErrorTests {

	@Test func timedOut_description() {
		let error = URL.TimeoutError.timedOut(3.0)
		#expect(error.errorDescription?.contains("3.0") == true)
	}
}

// MARK: - FirmwareFile validFilenameSuffixes

@Suite("FirmwareFile validFilenameSuffixes")
struct ValidFilenameSuffixesTests {

	@Test func esp32_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32)
		#expect(suffixes == [.bin])
	}

	@Test func esp32C3_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32C3)
		#expect(suffixes == [.bin])
	}

	@Test func esp32S3_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32S3)
		#expect(suffixes == [.bin])
	}

	@Test func esp32C6_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32C6)
		#expect(suffixes == [.bin])
	}

	@Test func nrf52840_returnsUf2AndOta() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .nrf52840)
		#expect(suffixes == [.uf2, .otaZip])
	}

	@Test func rp2040_returnsUf2() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .rp2040)
		#expect(suffixes == [.uf2])
	}
}

// MARK: - FirmwareFile Static URLs

@Suite("FirmwareFile Static URLs")
struct FirmwareFileStaticURLTests {

	@Test func localStorageURL_isDocuments() {
		let url = FirmwareFile.localFirmwareStorageURL
		#expect(url.path.contains("Documents"))
	}

	@Test func remoteFirmwareURLPrefix_isGithub() {
		let url = FirmwareFile.remoteFirmwareURLPrefix
		#expect(url.absoluteString.contains("github"))
	}
}

// MARK: - MeshtasticAPI Static URLs

@Suite("MeshtasticAPI URLs")
struct MeshtasticAPIURLTests {

	@Test func deviceURLEndpoint() {
		#expect(MeshtasticAPI.deviceURLEndpoint.absoluteString.contains("deviceHardware"))
	}

	@Test func firmwareURLEndpoint() {
		#expect(MeshtasticAPI.firmwareURLEndpoint.absoluteString.contains("firmware"))
	}

	@Test func imageURLPrefix() {
		#expect(MeshtasticAPI.imageURLPrefix.absoluteString.contains("devices"))
	}
}
