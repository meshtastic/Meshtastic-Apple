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

// MARK: - Chirpy OTA runner

@Suite("Chirpy OTA runner")
struct ChirpyOTARunnerTests {

	@Test func firstTapStartsTheRunAndJumps() {
		var runner = ChirpyRunnerEngine(obstacleX: 0.8)

		runner.primaryAction()

		#expect(runner.phase == .running)
		#expect(runner.verticalVelocity > 0)
	}

	@Test func aTimelyJumpClearsTheFirstObstacle() {
		var runner = ChirpyRunnerEngine()
		runner.primaryAction()

		for _ in 0..<48 {
			runner.advance(by: 1.0 / 60.0)
		}

		#expect(runner.phase == .running)
		#expect(runner.score == 1)
	}

	@Test func stayingOnTheGroundHitsTheObstacle() {
		var runner = ChirpyRunnerEngine(obstacleX: 0.38)
		runner.startRunning()

		for _ in 0..<40 where runner.phase == .running {
			runner.advance(by: 1.0 / 60.0)
		}

		#expect(runner.phase == .gameOver)
	}

	@Test func collisionBoxesAreForgivingAtTheEdge() {
		var runner = ChirpyRunnerEngine(obstacleX: ChirpyRunnerEngine.playerX + 0.075)
		runner.startRunning()
		runner.advance(by: 1.0 / 60.0)

		#expect(runner.phase == .running)
	}

	@Test func restartReturnsToReadyWithoutJumping() {
		var runner = ChirpyRunnerEngine(obstacleX: ChirpyRunnerEngine.playerX)
		runner.startRunning()
		runner.advance(by: 1.0 / 60.0)
		#expect(runner.phase == .gameOver)

		runner.primaryAction()

		#expect(runner.phase == .ready)
		#expect(runner.score == 0)
		#expect(runner.verticalVelocity == 0)

		runner.primaryAction()

		#expect(runner.phase == .running)
		#expect(runner.verticalVelocity > 0)
	}

	@Test func difficultyIncreasesButRemainsCapped() {
		#expect(ChirpyRunnerEngine.speed(forScore: 0) == 0.5)
		#expect(ChirpyRunnerEngine.speed(forScore: 20) > ChirpyRunnerEngine.speed(forScore: 5))
		#expect(ChirpyRunnerEngine.speed(forScore: 10_000) == 0.88)
	}

	@Test func reactingToApproachingObstaclesClearsSeveralObstacles() {
		var runner = ChirpyRunnerEngine()
		runner.primaryAction()

		for _ in 0..<(60 * 14) {
			if runner.obstacleX < 0.43, runner.playerY <= 0.012 {
				runner.primaryAction()
			}
			runner.advance(by: 1.0 / 60.0)
		}

		#expect(runner.phase == .running)
		#expect(runner.score >= 5)
	}

	@Test func frameRateDoesNotChangeJumpPhysics() {
		var smooth = ChirpyRunnerEngine(obstacleX: 0.95)
		var delayed = ChirpyRunnerEngine(obstacleX: 0.95)
		smooth.primaryAction()
		delayed.primaryAction()

		for _ in 0..<6 {
			smooth.advance(by: 1.0 / 60.0)
		}
		delayed.advance(by: 0.1)

		#expect(abs(smooth.playerY - delayed.playerY) < 0.01)
		#expect(abs(smooth.obstacleX - delayed.obstacleX) < 0.01)
	}

	@Test func crouchingClearsALowFlyingObstacle() {
		var standing = ChirpyRunnerEngine(
			obstacleX: ChirpyRunnerEngine.playerX,
			obstacleKind: .flyingBird
		)
		standing.startRunning()
		standing.advance(by: 1.0 / 120.0)
		#expect(standing.phase == .gameOver)

		var crouching = ChirpyRunnerEngine(
			obstacleX: ChirpyRunnerEngine.playerX,
			obstacleKind: .flyingBird
		)
		crouching.startRunning()
		crouching.setCrouching(true)
		crouching.advance(by: 1.0 / 120.0)

		#expect(crouching.phase == .running)
		#expect(crouching.isCrouching)
	}

	@Test func obstacleSequenceHasGroundAndFlyingVariety() {
		let kinds = Set((0..<8).map(ChirpyRunnerEngine.obstacleKind(forScore:)))

		#expect(kinds.contains(.tallCactus))
		#expect(kinds.contains(.cactusCluster))
		#expect(kinds.contains(.flyingBird))
	}

	@Test func OTAStatusClampsProgressAndOnlyAllowsPlayDuringTransfer() {
		let uploading = FirmwareUpdateGameStatus(
			title: "ESP32 BLE OTA",
			message: "Uploading firmware",
			progress: 1.4,
			phase: .uploading
		)
		let complete = FirmwareUpdateGameStatus(
			title: "ESP32 BLE OTA",
			message: "Complete",
			progress: 1,
			phase: .complete
		)

		#expect(uploading.progress == 1)
		#expect(uploading.percentText == "100%")
		#expect(uploading.canPlay)
		#expect(!complete.canPlay)
	}

	@Test func mockUploadProgressesWhileTheGameIsPresented() {
		var upload = FirmwareUpdateDemoState(duration: 20)
		upload.advance(by: 8)

		#expect(upload.status.phase == .uploading)
		#expect(upload.status.progress == 0.4)

		upload.advance(by: 20)

		#expect(upload.status.phase == .complete)
		#expect(upload.status.progress == 1)
	}

	@Test func ESP32OTAStatesMapToGameAvailability() {
		#expect(LocalOTAStatusCode.waitingForConnection.gamePhase == .connecting)
		#expect(LocalOTAStatusCode.preparing.gamePhase == .preparing)
		#expect(LocalOTAStatusCode.transferring.gamePhase == .uploading)
		#expect(LocalOTAStatusCode.completed.gamePhase == .complete)
		#expect(LocalOTAStatusCode.error.gamePhase == .failed)
	}

	@Test func nRFDFUStatesMapToGameAvailability() {
		#expect(DFUUpdateState.starting.gamePhase == .preparing)
		#expect(DFUUpdateState.uploading.gamePhase == .uploading)
		#expect(DFUUpdateState.success.gamePhase == .complete)
		#expect(DFUUpdateState.error("No device").gamePhase == .failed)
	}
}
