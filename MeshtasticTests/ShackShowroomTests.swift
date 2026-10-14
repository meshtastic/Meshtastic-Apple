//
//  ShackShowroomTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Ham shack showroom")
struct ShackShowroomTests {

	private func record(_ slug: String, _ target: String, _ name: String, tag: String, images: [String], number: Int? = nil) -> ShackHardwareRecord {
		ShackHardwareRecord(hwModel: number, hwModelSlug: slug, platformioTarget: target, displayName: name, tags: [tag], images: images)
	}

	private var hardware: [ShackHardwareRecord] {
		[
			record("RAK4631", "rak4631", "RAK WisBlock 4631", tag: "RAK", images: ["rak4631.svg", "rak4631_case.svg"]),
			record("RAK4631", "rak_wismesh_pocket", "RAK WisMesh Pocket V3", tag: "RAK", images: ["rak4631.svg"]),
			record("THINKNODE_M1", "thinknode_m1", "ThinkNode M1", tag: "Elecrow", images: ["thinknode_m1.svg"]),
			record("THINKNODE_M5", "thinknode_m5", "ThinkNode M5", tag: "Elecrow", images: ["thinknode_m1.svg"]),
			record("TRACKER_T1000_E", "tracker-t1000-e", "Seeed Card Tracker T1000-E", tag: "Seeed", images: ["tracker-t1000-e.svg"]),
			record("TBEAM", "tbeam", "LILYGO T-Beam", tag: "LilyGo", images: ["tbeam.svg"]),
			record("WISMESH_HUB", "rak2560", "RAK WisMesh Repeater", tag: "RAK", images: ["rak2560.svg"], number: 22),
			record("SEEED_WIO_TRACKER_L1", "seeed_wio_tracker_L1_Pro_1W", "Seeed Wio Tracker L1 Pro 1W", tag: "Seeed", images: ["wio_tracker_l1_case.svg"]),
			record("CROWPANEL", "elecrow-adv-24-28-tft", "Crowpanel Adv 2.4/2.8 TFT", tag: "Elecrow", images: ["crowpanel_2_4.svg", "crowpanel_2_8.svg"])
		]
	}

	@Test("A model lists every device drawn with it, and goes on its vendor's shelf")
	func items() {
		let models: Set<String> = ["rak4631", "rak4631_case", "rak_wismesh_pocket", "thinknode_m1", "tracker-t1000-e", "tbeam", "orphan"]
		let items = ShackShowroomCatalog.items(models: models, hardware: hardware)
		// T-Beam is another maker's and "orphan" has no device, so both are left out.
		#expect(items.map(\.id) == ["thinknode_m1", "rak4631", "rak4631_case", "rak_wismesh_pocket", "tracker-t1000-e"])
		// The board's case is the board's own variant, so the board is listed under it.
		#expect(items.first { $0.id == "rak4631_case" }?.title == "RAK WisBlock 4631 (case)")
		let board = items.first { $0.id == "rak4631" }
		// The pocket has its own model, so it isn't listed under the board it shares an image with.
		#expect(board?.deviceNames == ["RAK WisBlock 4631"])
		#expect(board?.targets == ["rak4631"])
		// It finds that model by firmware target, before the catalog points at it.
		let pocket = items.first { $0.id == "rak_wismesh_pocket" }
		#expect(pocket?.deviceNames == ["RAK WisMesh Pocket V3"])
		#expect(items.first { $0.id == "thinknode_m1" }?.deviceNames == ["ThinkNode M1", "ThinkNode M5"])
		#expect(items.map(\.vendor.shelf) == [0, 1, 1, 1, 2])
	}

	@Test("Firmware targets match whatever their case, and models drawn for one device are told apart")
	func variantsAndCase() {
		let models: Set<String> = ["seeed_wio_tracker_l1_pro_1w", "crowpanel_2_4", "crowpanel_2_8"]
		let items = ShackShowroomCatalog.items(models: models, hardware: hardware)
		#expect(items.first { $0.id == "seeed_wio_tracker_l1_pro_1w" }?.title == "Seeed Wio Tracker L1 Pro 1W")
		#expect(items.first { $0.id == "crowpanel_2_4" }?.title == "Crowpanel Adv 2.4/2.8 TFT (2.4)")
		#expect(items.first { $0.id == "crowpanel_2_8" }?.title == "Crowpanel Adv 2.4/2.8 TFT (2.8)")
		#expect(ShackShowroomCatalog.variants(of: ["rak4631", "rak4631_case"]) == [nil, "case"])
		#expect(ShackShowroomCatalog.variants(of: ["crowpanel_5_0", "crowpanel_7_0"]) == ["5.0", "7.0"])
	}

	@Test("A node's hardware finds its model from the catalog's images")
	func modelForNode() {
		let models: Set<String> = ["rak4631", "thinknode_m1"]
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: "RAK4631", models: models, hardware: hardware) == "rak4631")
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: "THINKNODE_M5", models: models, hardware: hardware) == "thinknode_m1")
		// As nodes store it, without underscores.
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: "THINKNODEM1", models: models, hardware: hardware) == "thinknode_m1")
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: "TBEAM", models: models, hardware: hardware) == nil)
		// The stored name and the catalog's can differ; the number still finds it.
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: "RAK2560", number: 22, models: ["rak2560"], hardware: hardware) == "rak2560")
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: "RAK2560", models: ["rak2560"], hardware: hardware) == nil)
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: "UNSET", models: models, hardware: hardware) == nil)
		#expect(ShackShowroomCatalog.modelName(forHardwareSlug: nil, models: models, hardware: hardware) == nil)
	}

	@Test("The bundled catalog decodes")
	func bundledCatalog() {
		let hardware = ShackShowroomCatalog.bundledHardware()
		#expect(!hardware.isEmpty)
		#expect(hardware.contains { $0.platformioTarget == "thinknode_m1" })
	}

	@Test("Models share a shelf's spare room evenly, between them and at the ends")
	func packing() {
		let centers = ShackShelfPacking.centers(widths: [0.1, 0.2, 0.1], length: 1.0)
		// 0.6 m spare over four gaps: 0.15 m each.
		#expect(centers.count == 3)
		#expect(abs(centers[0] - (-0.5 + 0.15 + 0.05)) < 1e-5)
		#expect(abs(centers[1]) < 1e-5)
		#expect(abs(centers[2] - (0.5 - 0.15 - 0.05)) < 1e-5)
		// Too wide for the shelf: they touch, centered.
		let crowded = ShackShelfPacking.centers(widths: [0.6, 0.6], length: 1.0)
		#expect(abs(crowded[0] + 0.3) < 1e-5)
		#expect(abs(crowded[1] - 0.3) < 1e-5)
		#expect(ShackShelfPacking.centers(widths: [], length: 1).isEmpty)
	}
}
