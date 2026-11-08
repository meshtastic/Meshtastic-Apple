//
//  DeviceModelScreenTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//

import Testing
import RealityKit
@testable import Meshtastic

@Suite("Live screen on the 3D model")
struct DeviceModelScreenTests {

	@available(iOS 18.0, macCatalyst 18.0, *)
	@Test("A wide picture on a wide display keeps its shape and fills the width")
	func fitsWidth() {
		let shape = DeviceModelScreen.shape(imageWidth: 128, imageHeight: 64, slotWidth: 0.0214, slotHeight: 0.0118)
		#expect(!shape.turned)
		#expect(abs(shape.width - 0.0214) < 1e-6)
		#expect(abs(shape.height - 0.0107) < 1e-6)
	}

	@available(iOS 18.0, macCatalyst 18.0, *)
	@Test("A wide picture on a taller display fills the height")
	func fitsHeight() {
		let shape = DeviceModelScreen.shape(imageWidth: 320, imageHeight: 240, slotWidth: 0.06, slotHeight: 0.03)
		#expect(!shape.turned)
		#expect(abs(shape.height - 0.03) < 1e-6)
		#expect(abs(shape.width - 0.04) < 1e-6)
	}

	@available(iOS 18.0, macCatalyst 18.0, *)
	@Test("A wide picture on a display mounted upright is turned a quarter")
	func turnsSideways() {
		let shape = DeviceModelScreen.shape(imageWidth: 240, imageHeight: 135, slotWidth: 0.0174, slotHeight: 0.0305)
		#expect(shape.turned)
		// Its width runs along the display's height.
		#expect(shape.width <= 0.0305 + 1e-6)
		#expect(shape.height <= 0.0174 + 1e-6)
	}

	@available(iOS 18.0, macCatalyst 18.0, *)
	@Test("A square picture is never turned")
	func squareStays() {
		let shape = DeviceModelScreen.shape(imageWidth: 200, imageHeight: 200, slotWidth: 0.02, slotHeight: 0.03)
		#expect(!shape.turned)
		#expect(abs(shape.width - 0.02) < 1e-6)
	}

	@available(iOS 18.0, macCatalyst 18.0, *)
	@MainActor
	@Test("In the room the model stands on its base at real size, wherever it was modeled")
	func standsOnItsBase() {
		let part = ModelEntity(mesh: .generateBox(size: [0.05, 0.02, 0.01]))
		part.position = [0.3, 0.1, -0.2]
		let model = Entity()
		model.addChild(part)
		let stage = DeviceModelStage(model: model)
		let scene = stage.makeStandingScene()
		let bounds = scene.visualBounds(relativeTo: nil)
		#expect(abs(bounds.min.y) < 1e-5)
		#expect(abs(bounds.center.x) < 1e-5)
		#expect(abs(bounds.center.z) < 1e-5)
		#expect(abs(bounds.extents.x - 0.05) < 1e-5)
		#expect(abs(bounds.extents.y - 0.02) < 1e-5)
	}
}

@MainActor
@Suite("Screen stream sharing")
struct DisplayMirrorOwnerTests {

	@Test("The stream stays wanted until every view lets go")
	func ownersShare() {
		let session = DisplayMirrorSession()
		session.claim(.deviceScreen)
		session.claim(.deviceModel)
		session.release(.deviceScreen)
		#expect(session.owners == [.deviceModel])
		session.release(.deviceModel)
		#expect(session.owners.isEmpty)
	}

	@Test("Claiming twice is the same as once")
	func claimIsIdempotent() {
		let session = DisplayMirrorSession()
		session.claim(.deviceModel)
		session.claim(.deviceModel)
		session.release(.deviceModel)
		#expect(session.owners.isEmpty)
	}

	@Test("A closed connection forgets who wanted the stream")
	func resetClearsOwners() {
		let session = DisplayMirrorSession()
		session.begin()
		session.claim(.deviceScreen)
		session.reset()
		#expect(session.owners.isEmpty)
		#expect(!session.isStreaming)
	}
}
