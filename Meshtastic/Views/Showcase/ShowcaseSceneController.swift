//
//  ShowcaseSceneController.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import Metal
import OSLog
import RealityKit
import SwiftUI

/// Marks the connected radio's device, so a tap on any of its parts finds the node.
struct ShowcaseNodeComponent: Component {
	let nodeNum: Int64
}

/// Marks the wall rack's panel; a tap on it is turned into a cell from where it landed.
struct ShowcaseRackComponent: Component {}

/// Owns the showcase's entities: the room, the device models and the connected radio on the
/// display tables, and the wall rack, whose cells are one mesh colored by a small texture, one texel
/// per cell. Takes the reader's snapshots, places them with `ShowcaseLayout`, glows senders as
/// packets arrive, and keeps the state the control panel and cards show.
@MainActor @Observable
final class ShowcaseSceneController {
	/// Everything that moves with the seated/standing setting: the room and what is in it.
	@ObservationIgnored let world = Entity()
	@ObservationIgnored private(set) var room: ShowcaseRoom?
	/// Observed, so an open node card follows the rack's settled online state.
	private var layout: ShowcaseLayout?
	@ObservationIgnored private let rackHolder = Entity()
	@ObservationIgnored private var rackCells: ModelEntity?
	@ObservationIgnored private var rackTextureGeneration = 0
	@ObservationIgnored private var rackHalos: [ModelEntity] = []
	@ObservationIgnored private var rackHaloByNode: [Int64: ModelEntity] = [:]
	@ObservationIgnored private var boosts: [Int64: (start: TimeInterval, initial: Float)] = [:]
	@ObservationIgnored private var limiter = PulseRateLimiter(capacity: 12, refillPerSecond: 8, perSenderInterval: 0.3)
	@ObservationIgnored private var clock: TimeInterval = 0
	@ObservationIgnored var updateSubscription: EventSubscription?
	@ObservationIgnored var grabSubscription: EventSubscription?
	/// The device models on the display tables.
	let displays = ShowcaseDisplays()
	@ObservationIgnored private var displayHardware: [ShowcaseHardwareRecord]?

	/// The nodes from the last read, by number.
	private(set) var nodesByNum: [Int64: ShowcaseNodeSnapshot] = [:]
	/// Every node that isn't ignored, including those past the reader's limit.
	private(set) var totalCount = 0
	private(set) var rackPageCount = 1
	/// Nodes with no place: past the reader's limit, or past the rack's last page.
	private(set) var overflowCount = 0
	private(set) var page = 0
	/// The node whose card is open.
	var selected: Int64? {
		didSet {
			if selected != nil, selectedItem != nil { selectedItem = nil }
		}
	}
	/// The displayed model whose card is open.
	var selectedItem: String? {
		didSet {
			if selectedItem != nil, selected != nil { selected = nil }
		}
	}
	var isHighTraffic = false
	var reduceMotion = false
	var preset: ModemPresets = .longFast

	init() {
		ShowcaseNodeComponent.registerComponent()
		ShowcaseRackComponent.registerComponent()
		world.name = "ShowcaseWorld"
		rackHolder.name = "Rack"
	}

	/// Puts the loaded room in the world and builds the rack for its anchor.
	func install(room: ShowcaseRoom) {
		self.room = room
		world.addChild(room.root)
		let rackPose = room.pose(.wallRack)
		rackHolder.position = rackPose.position
		rackHolder.orientation = rackPose.orientation
		world.addChild(rackHolder)
		let grid = ShowcaseRackGrid.forRoom(rack: rackPose)
		layout = ShowcaseLayout(grid: grid)
		buildRack(grid: grid)
		world.addChild(displays.root)
		if !nodesByNum.isEmpty { relayout(now: Date(), force: true) }
	}

	/// Seated, the room is as authored; standing, it moves back a little so the front table isn't
	/// against the viewer.
	func setSeated(_ seated: Bool) {
		world.position = seated ? .zero : [0, 0, -Self.standingSetback]
	}

	static let standingSetback: Float = 0.25

	/// The radios on the rack page showing, in the order of their cells, for the panel's list.
	var nodesOnPage: [ShowcaseNodeSnapshot] {
		guard let layout else { return [] }
		return layout.rackPage(page).sorted { $0.key < $1.key }.compactMap { nodesByNum[$0.value] }
	}

	/// Online as the room shows it, after the layout's hysteresis.
	func isOnline(_ nodeNum: Int64) -> Bool {
		layout?.isOnline(nodeNum) ?? nodesByNum[nodeNum]?.isOnline ?? false
	}

	/// Lets a device or the rack pick up the room's warm environment light, as the room does.
	private func receiveRoomLight(_ entity: Entity) {
		guard let light = room?.root.findEntity(named: ShowcaseRoom.environmentLightName) else { return }
		var pending = [entity]
		while let next = pending.popLast() {
			if next.components.has(ModelComponent.self) {
				next.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
			}
			pending += next.children
		}
	}

	// MARK: Nodes

	func apply(_ result: ShowcaseSnapshotReader.Result, now: Date = Date()) {
		let nodes = Dictionary(result.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		let changed = nodes != nodesByNum
		if changed { nodesByNum = nodes }
		order = result.nodes.map(\.id)
		if totalCount != result.totalCount { totalCount = result.totalCount }
		relayout(now: now, force: changed)
	}

	@ObservationIgnored private var order: [Int64] = []

	/// Runs the layout; touches the entities only when a place or a node changed.
	private func relayout(now: Date, force: Bool) {
		guard var layout else { return }
		let before = layout.slots
		let onlineBefore = Set(before.keys.filter { layout.isOnline($0) })
		layout.update(order.compactMap { nodesByNum[$0] }, now: now)
		self.layout = layout
		let onlineAfter = Set(layout.slots.keys.filter { layout.isOnline($0) })
		let overflow = layout.overflow + max(0, totalCount - nodesByNum.count)
		if overflowCount != overflow { overflowCount = overflow }
		if rackPageCount != layout.rackPageCount { rackPageCount = layout.rackPageCount }
		if page >= rackPageCount { page = rackPageCount - 1 }
		if let selected, nodesByNum[selected] == nil { self.selected = nil }
		guard force || before != layout.slots || onlineBefore != onlineAfter else { return }
		refreshRackTexture()
	}

	func setPage(_ newPage: Int) {
		let clamped = min(max(newPage, 0), rackPageCount - 1)
		guard clamped != page else { return }
		page = clamped
		clearRackHalos()
		refreshRackTexture()
	}

	static func nodeColor(_ nodeNum: Int64) -> UIColor {
		UIColor(hex: UInt32(truncatingIfNeeded: nodeNum))
	}

	// MARK: Rack

	private func buildRack(grid: ShowcaseRackGrid) {
		guard let mesh = try? ShowcaseDeviceMeshes.resource(ShowcaseMeshGeometry.rackCells(grid: grid), name: "rack") else {
			Logger.services.error("📻 [Showcase] The rack mesh could not be built")
			return
		}
		let cells = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .darkGray, isMetallic: false)])
		cells.name = "RackCells"
		let size = SIMD3<Float>(Float(grid.columns) * grid.pitch, Float(grid.rows) * grid.pitch, 0.03)
		cells.components.set(CollisionComponent.inputTarget([ShapeResource.generateBox(size: size).offsetBy(translation: [0, 0, 0.015])]))
		cells.components.set(InputTargetComponent())
		cells.components.set(HoverEffectComponent(.spotlight(HoverEffectComponent.SpotlightHoverEffectStyle(color: .white, strength: 0.6))))
		cells.components.set(ShowcaseRackComponent())
		rackHolder.addChild(cells)
		rackCells = cells
		let haloMesh = MeshResource.generatePlane(width: grid.pitch, height: grid.pitch, cornerRadius: grid.pitch * 0.2)
		for _ in 0..<24 {
			let halo = ModelEntity(mesh: haloMesh, materials: [UnlitMaterial(color: .white)])
			halo.position = [0, 0, 0.001]
			halo.isEnabled = false
			rackHolder.addChild(halo)
			rackHalos.append(halo)
		}
	}

	/// Redraws the rack's texture for the page showing. Skipped if a newer one starts first.
	private func refreshRackTexture() {
		guard let layout, let cells = rackCells else { return }
		rackTextureGeneration += 1
		let generation = rackTextureGeneration
		let grid = layout.grid
		let pageNodes = layout.rackPage(page)
		var texels: [SIMD4<UInt8>] = Array(repeating: SIMD4(26, 28, 30, 255), count: grid.perPage)
		for (cell, num) in pageNodes where cell < texels.count {
			texels[cell] = ShowcaseDeviceMeshes.texel(Self.nodeColor(num), isOnline: layout.isOnline(num))
		}
		var ax = AccessibilityComponent()
		ax.isAccessibilityElement = true
		ax.label = LocalizedStringResource("Wall rack", comment: "Showcase: VoiceOver label for the rack of radios on the wall")
		ax.value = LocalizedStringResource("Page \(page + 1) of \(rackPageCount), \(pageNodes.count) radios", comment: "Showcase: VoiceOver value for the wall rack; the arguments are the page, the page count and the radios on the page")
		cells.components.set(ax)
		guard let image = ShowcaseDeviceMeshes.image(texels, width: grid.columns, height: grid.rows) else { return }
		Task {
			var options = TextureResource.CreateOptions(semantic: .color)
			options.mipmapsMode = .none
			guard let texture = try? await TextureResource(image: image, options: options),
				  generation == rackTextureGeneration else { return }
			let sampler = MTLSamplerDescriptor()
			sampler.minFilter = .nearest
			sampler.magFilter = .nearest
			sampler.sAddressMode = .clampToEdge
			sampler.tAddressMode = .clampToEdge
			let parameter = MaterialParameters.Texture(texture, sampler: .init(sampler))
			// Unlit, like a lit panel: lighting washed the colors out and turned empty cells gray.
			var material = UnlitMaterial()
			material.color = .init(tint: .white, texture: parameter)
			cells.model?.materials = [material]
		}
	}

	// MARK: Taps

	/// The node under a tap: the device's own node, or the rack cell under the point.
	func node(tappedOn entity: Entity, scenePoint: SIMD3<Float>) -> Int64? {
		var current: Entity? = entity
		while let candidate = current {
			if let component = candidate.components[ShowcaseNodeComponent.self] { return component.nodeNum }
			if candidate.components.has(ShowcaseRackComponent.self) {
				guard let layout else { return nil }
				let local = candidate.convert(position: scenePoint, from: nil)
				guard let cell = layout.grid.cell(at: SIMD2(local.x, local.y)) else { return nil }
				return layout.rackPage(page)[cell]
			}
			current = candidate.parent
		}
		return nil
	}

	/// Where the card goes for a node, in the world's space: above a device, or out from a rack
	/// cell. Nil when the node isn't placed or is on another rack page.
	func cardPosition(for nodeNum: Int64) -> SIMD3<Float>? {
		guard let layout, let room, let slot = layout.slots[nodeNum] else { return nil }
		let pose = ShowcasePlacement.pose(of: slot, grid: layout.grid, anchor: room.pose)
		switch slot {
		case .rack(let index):
			guard index / layout.grid.perPage == page else { return nil }
			// Well clear of the rack, toward the viewer, so the big card isn't lost against the wall.
			return pose.position + pose.forward * 0.6
		}
	}

	// MARK: Traffic

	func handle(_ event: MeshPacketEvent) {
		guard limiter.admit(sender: event.from, now: clock, highTraffic: isHighTraffic) else { return }
		boosts[event.from] = (clock, 1)
		if let radio = nodesByNum.values.first(where: \.isConnectedRadio)?.id, radio != event.from {
			boosts[radio] = (clock, 0.7)
		}
	}

	func step(deltaTime dt: TimeInterval) {
		clock += dt
		guard !boosts.isEmpty, let layout else { return }
		for (num, boost) in boosts {
			let value = NodeActivityGlow.boost(startedAt: boost.start, now: clock, initial: boost.initial)
			let spent = value < NodeActivityGlow.boostFloor
			let scale = reduceMotion ? 1 : NodeActivityGlow.scale(boost: value)
			if case .rack(let index) = layout.slots[num], index / layout.grid.perPage == page {
				stepRackHalo(num, cell: index % layout.grid.perPage, grid: layout.grid, value: spent ? 0 : value, scale: scale)
			}
			if spent {
				boosts[num] = nil
				releaseRackHalo(num)
			}
		}
	}

	private func stepRackHalo(_ num: Int64, cell: Int, grid: ShowcaseRackGrid, value: Float, scale: Float) {
		let halo: ModelEntity
		if let existing = rackHaloByNode[num] {
			halo = existing
		} else {
			guard value > 0, let free = rackHalos.popLast() else { return }
			halo = free
			halo.model?.materials = [UnlitMaterial(color: Self.nodeColor(num).lighter(componentDelta: 0.2))]
			let center = grid.center(ofCellOnPage: cell)
			halo.position = [center.x, center.y, 0.001]
			halo.isEnabled = true
			rackHaloByNode[num] = halo
		}
		halo.components.set(OpacityComponent(opacity: value))
		halo.scale = SIMD3(repeating: scale * 1.05)
	}

	private func releaseRackHalo(_ num: Int64) {
		guard let halo = rackHaloByNode.removeValue(forKey: num) else { return }
		halo.isEnabled = false
		rackHalos.append(halo)
	}

	private func clearRackHalos() {
		for num in Array(rackHaloByNode.keys) {
			releaseRackHalo(num)
			boosts[num] = nil
		}
	}
}

extension ShowcaseSceneController {
	// MARK: Displays

	/// The hardware catalog for the displays, read by the view; the room may not be in yet.
	func setDisplayHardware(_ hardware: [ShowcaseHardwareRecord]) async {
		displayHardware = hardware
		await loadDisplaysIfReady()
	}

	/// Once both the room and the catalog are in, stands the device models on the tables.
	func loadDisplaysIfReady() async {
		guard let room, let hardware = displayHardware else { return }
		displayHardware = nil
		await displays.load(room: room, hardware: hardware) { [weak self] in self?.receiveRoomLight($0) }
	}

	/// Where a model's card goes: above its place on the table.
	func cardPosition(forItem id: String) -> SIMD3<Float>? {
		displays.cardPosition(forItem: id)
	}
}

/// Meshes and cards drawn for the room: the rack's cells, and the cards on the display tables.
@MainActor
enum ShowcaseDeviceMeshes {
	/// One descriptor per material, in `ShowcaseMeshGeometry.Material` order.
	static func resource(_ geometry: ShowcaseMeshGeometry, name: String) throws -> MeshResource {
		let descriptors = ShowcaseMeshGeometry.Material.allCases.compactMap { material -> MeshDescriptor? in
			guard let part = geometry.parts[material] else { return nil }
			var descriptor = MeshDescriptor(name: "\(name)-\(material)")
			descriptor.positions = MeshBuffer(part.positions)
			descriptor.normals = MeshBuffer(part.normals)
			descriptor.textureCoordinates = MeshBuffer(part.uvs)
			descriptor.primitives = .triangles(part.indices)
			descriptor.materials = .allFaces(UInt32(material.rawValue))
			return descriptor
		}
		return try MeshResource.generate(from: descriptors)
	}

	/// The model cards' width in meters, the image pixels per meter they're drawn at, and how far in
	/// front of a stand's center they stand.
	static let placardSize = SIMD2<Float>(0.08, 0.04)
	private static let placardPixelsPerMeter: CGFloat = 4500
	static let placardDistance: Float = 0.07

	/// The tent card in front of a model on a display table: the maker, and the device's name
	/// under it. `width` in meters, up to `placardSize`'s.
	static func placard(for item: ShowcaseItem, width: Float, inFrontBy distance: Float) async -> ModelEntity? {
		let height = itemPlacardHeight
		let size = CGSize(width: CGFloat(width) * placardPixelsPerMeter, height: CGFloat(height) * placardPixelsPerMeter)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = false
		let name = item.nameWithoutMaker
		let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			UIColor.white.setFill()
			UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14).fill()
			let inset: CGFloat = 10
			let paragraph = NSMutableParagraphStyle()
			paragraph.alignment = .center
			paragraph.lineBreakMode = .byWordWrapping
			let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: UIColor(white: 0.45, alpha: 1), .paragraphStyle: paragraph]
			(item.vendor.name as NSString).draw(
				with: CGRect(x: inset, y: 4, width: size.width - inset * 2, height: 34),
				options: .usesLineFragmentOrigin, attributes: small, context: nil
			)
			// Up to two lines; long names shrink until they fit.
			let nameBox = CGRect(x: inset, y: 36, width: size.width - inset * 2, height: size.height - 38)
			var fontSize: CGFloat = 42
			var large: [NSAttributedString.Key: Any] = [:]
			repeat {
				large = [.font: UIFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: UIColor(white: 0.1, alpha: 1), .paragraphStyle: paragraph]
				fontSize -= 2
			} while (name as NSString).boundingRect(with: CGSize(width: nameBox.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: large, context: nil).height > nameBox.height && fontSize > 16
			(name as NSString).draw(with: nameBox, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: large, context: nil)
		}
		return await tentCard(image, size: [width, height], inFrontBy: distance)
	}

	/// The card at the start of a maker's run of models: its name in white on charcoal, larger than
	/// the models' cards, so it reads as a sign rather than a label.
	static let brandCardSize = SIMD2<Float>(0.1, 0.05)

	static func brandCard(for vendor: ShowcaseVendor) async -> ModelEntity? {
		let size = CGSize(width: CGFloat(brandCardSize.x) * placardPixelsPerMeter, height: CGFloat(brandCardSize.y) * placardPixelsPerMeter)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = false
		let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			UIColor(red: 0.17, green: 0.18, blue: 0.24, alpha: 1).setFill()
			UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18).fill()
			let name = vendor.name
			let inset: CGFloat = 24
			var fontSize: CGFloat = 76
			var attributes: [NSAttributedString.Key: Any] = [:]
			var measured = CGSize.zero
			repeat {
				attributes = [.font: UIFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: UIColor.white]
				measured = (name as NSString).size(withAttributes: attributes)
				fontSize -= 2
			} while measured.width > size.width - inset * 2 && fontSize > 24
			(name as NSString).draw(at: CGPoint(x: (size.width - measured.width) / 2, y: (size.height - measured.height) / 2), withAttributes: attributes)
		}
		return await tentCard(image, size: brandCardSize, inFrontBy: 0)
	}

	/// The model cards' height in meters.
	static let itemPlacardHeight: Float = 0.025

	/// A card drawn as `image`, standing on the table `distance` in front of a stand's center and
	/// leaning back a little.
	private static func tentCard(_ image: UIImage, size: SIMD2<Float>, inFrontBy distance: Float) async -> ModelEntity? {
		guard let cgImage = image.cgImage,
			  let texture = try? await TextureResource(image: cgImage, options: .init(semantic: .color)) else { return nil }
		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture))
		material.blending = .transparent(opacity: .init(floatLiteral: 1))
		let card = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y, cornerRadius: 0.004), materials: [material])
		card.name = "placard"
		let lean: Float = 0.35
		card.orientation = simd_quatf(angle: -lean, axis: [1, 0, 0])
		// Its bottom edge on the table.
		card.position = [0, size.y / 2 * cos(lean), distance]
		return card
	}

	static func texel(_ color: UIColor, isOnline: Bool) -> SIMD4<UInt8> {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		// Offline cells keep a hint of their color, mostly gray and dim.
		let mix: CGFloat = isOnline ? 1 : 0.3
		let level: CGFloat = isOnline ? 0.9 : 0.3
		func channel(_ value: CGFloat) -> UInt8 {
			UInt8(max(0, min(255, ((value * mix + 0.5 * (1 - mix)) * level * 255).rounded())))
		}
		return SIMD4(channel(red), channel(green), channel(blue), 255)
	}

	static func image(_ texels: [SIMD4<UInt8>], width: Int, height: Int) -> CGImage? {
		var bytes: [UInt8] = []
		bytes.reserveCapacity(texels.count * 4)
		for texel in texels { bytes += [texel.x, texel.y, texel.z, texel.w] }
		guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
		return CGImage(
			width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
			space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
		)
	}
}
#endif
