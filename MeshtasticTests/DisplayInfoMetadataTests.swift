//
//  DisplayInfoMetadataTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/29/26.
//

import Testing
import MeshtasticProtobufs
@testable import Meshtastic

/// `DeviceMetadata.display` (field 16) is saved on `DeviceMetadataEntity` so the app knows
/// whether the connected radio can stream its screen (design#142).
@Suite("Display info metadata")
struct DisplayInfoMetadataTests {

	private func metadata(display: DisplayInfo?) -> DeviceMetadata {
		var metadata = DeviceMetadata()
		metadata.firmwareVersion = "2.8.1.abcdef"
		if let display {
			metadata.display = display
		}
		return metadata
	}

	@Test("A reported display is saved")
	func displayIsSaved() {
		var display = DisplayInfo()
		display.width = 320
		display.height = 240
		display.format = .monoVlsb
		display.panelClass = .tft
		display.hasTouch_p = true

		let entity = DeviceMetadataEntity()
		entity.update(from: metadata(display: display))

		#expect(entity.hasDisplay)
		#expect(entity.displayWidth == 320)
		#expect(entity.displayHeight == 240)
		#expect(entity.displayFormat == Int32(DisplayFrame.Format.monoVlsb.rawValue))
		#expect(entity.displayPanelClass == Int32(DisplayInfo.PanelClass.tft.rawValue))
		#expect(entity.displayHasTouch)
	}

	@Test("No display reported means no display")
	func missingDisplay() {
		let entity = DeviceMetadataEntity()
		entity.update(from: metadata(display: nil))
		#expect(!entity.hasDisplay)
	}

	@Test("Metadata without a display clears one saved earlier")
	func displayIsClearedOnDowngrade() {
		var display = DisplayInfo()
		display.width = 128
		display.height = 64
		display.hasTouch_p = true

		let entity = DeviceMetadataEntity()
		entity.update(from: metadata(display: display))
		entity.update(from: metadata(display: nil))

		#expect(!entity.hasDisplay)
		#expect(entity.displayWidth == 0)
		#expect(!entity.displayHasTouch)
	}
}
