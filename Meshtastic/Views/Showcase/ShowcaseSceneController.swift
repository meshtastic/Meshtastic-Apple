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
	@ObservationIgnored private var layout: ShowcaseLayout?
	@ObservationIgnored private var heroes: [Int64: Hero] = [:]
	@ObservationIgnored private let heroContainer = Entity()
	@ObservationIgnored private let rackHolder = Entity()
	@ObservationIgnored private var rackCells: ModelEntity?
	@ObservationIgnored private var rackTextureGeneration = 0
	@ObservationIgnored private var rackHalos: [ModelEntity] = []
	@ObservationIgnored private var rackHaloByNode: [Int64: ModelEntity] = [:]
	@ObservationIgnored private var boosts: [Int64: (start: TimeInterval, initial: Float)] = [:]
	@ObservationIgnored private var limiter = PulseRateLimiter(capacity: 12, refillPerSecond: 8, perSenderInterval: 0.3)
	@ObservationIgnored private var clock: TimeInterval = 0
	@ObservationIgnored var updateSubscription: EventSubscription?
	@ObservationIgnored private var labelMaterials: [Style: UnlitMaterial] = [:]
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
	private(set) var hasConnectedRadio = false
	/// The node whose card is open.
	var selected: Int64? {
		didSet {
			if selected != nil, selectedItem != nil { selectedItem = nil }
			updateInspection()
		}
	}
	/// The displayed model whose card is open.
	var selectedItem: String? {
		didSet {
			if selectedItem != nil, selected != nil { selected = nil }
			updateInspection()
		}
	}
	/// Holds the selected model, or the connected radio, up in front of the viewer.
	@ObservationIgnored let inspector = ShowcaseInspector()
	var isHighTraffic = false
	var reduceMotion = false {
		didSet { inspector.reduceMotion = reduceMotion }
	}
	var preset: ModemPresets = .longFast

	/// The stand-in box for a connected radio with no model is drawn a little larger so it reads
	/// from the chair; a real model stays real size.
	static let standInScale: Float = 1.2

	private struct Hero {
		let holder: Entity
		let device: Entity
		/// The short name on a stand-in box's screen; a real model has its own face.
		let label: ModelEntity?
		let halo: ModelEntity
		/// The model shown, or nil for the stand-in box.
		let modelName: String?
		var archetype: ShowcaseDeviceArchetype
		var slot: ShowcaseSlot
		var baseGlow: Float
		var style: Style
		/// Top of the device above the table, in meters.
		var height: Float
	}

	private struct Style: Hashable {
		let shortName: String
		let isOnline: Bool
	}

	init() {
		ShowcaseNodeComponent.registerComponent()
		ShowcaseRackComponent.registerComponent()
		world.name = "ShowcaseWorld"
		heroContainer.name = "Devices"
		rackHolder.name = "Rack"
	}

	/// Puts the loaded room in the world and builds the rack for its anchor.
	func install(room: ShowcaseRoom) {
		self.room = room
		world.addChild(room.root)
		world.addChild(heroContainer)
		let rackPose = room.pose(.wallRack)
		rackHolder.position = rackPose.position
		rackHolder.orientation = rackPose.orientation
		world.addChild(rackHolder)
		let grid = ShowcaseRackGrid.forRoom(rack: rackPose)
		layout = ShowcaseLayout(grid: grid)
		buildRack(grid: grid)
		world.addChild(displays.root)
		world.addChild(inspector.stage)
		if !nodesByNum.isEmpty { relayout(now: Date(), force: true) }
	}

	/// Seated, the room is as authored; standing, it moves back a little so the front table isn't
	/// against the viewer.
	func setSeated(_ seated: Bool) {
		world.position = seated ? .zero : [0, 0, -Self.standingSetback]
		inspector.setSeated(seated)
	}

	static let standingSetback: Float = 0.25

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
		let connected = nodesByNum.values.contains { $0.isConnectedRadio }
		if hasConnectedRadio != connected { hasConnectedRadio = connected }
		if let selected, nodesByNum[selected] == nil { self.selected = nil }
		guard force || before != layout.slots || onlineBefore != onlineAfter else { return }
		syncHeroes(layout: layout, now: now)
		refreshRackTexture()
	}

	func setPage(_ newPage: Int) {
		let clamped = min(max(newPage, 0), rackPageCount - 1)
		guard clamped != page else { return }
		page = clamped
		clearRackHalos()
		refreshRackTexture()
	}

	private func syncHeroes(layout: ShowcaseLayout, now: Date) {
		guard let room else { return }
		var wanted: [Int64: ShowcaseSlot] = [:]
		for (num, slot) in layout.slots where slot.tier != .rack {
			wanted[num] = slot
		}
		for (num, hero) in heroes where wanted[num] == nil {
			if inspector.model === hero.device { selected = nil }
			hero.holder.removeFromParent()
			heroes[num] = nil
			if boosts[num] != nil, rackHaloByNode[num] == nil { boosts[num] = nil }
		}
		for (num, slot) in wanted {
			guard let node = nodesByNum[num] else { continue }
			let archetype = ShowcaseDeviceArchetype(hwModel: node.hwModel, role: node.role)
			let modelName = radioModelName(for: node)
			var hero = heroes[num] ?? makeHero(node, archetype: archetype, modelName: modelName, slot: slot)
			if hero.archetype != archetype || hero.modelName != modelName {
				if inspector.model === hero.device { inspector.release() }
				hero.holder.removeFromParent()
				hero = makeHero(node, archetype: archetype, modelName: modelName, slot: slot)
			}
			let pose = ShowcasePlacement.pose(of: slot, grid: layout.grid, anchor: room.pose)
			hero.holder.position = pose.position
			hero.holder.orientation = pose.orientation
			hero.slot = slot
			let style = Style(shortName: node.shortName, isOnline: layout.isOnline(num))
			if style != hero.style { styleHero(&hero, node: node, style: style) }
			hero.baseGlow = NodeActivityGlow.baseOpacity(NodeActivityGlow.tier(lastHeard: node.lastHeard, now: now))
			if boosts[num] == nil {
				hero.halo.components.set(OpacityComponent(opacity: hero.baseGlow))
			}
			hero.device.components.set(ShowcaseDeviceMeshes.accessibility(for: node, isOnline: style.isOnline))
			heroes[num] = hero
		}
		// A rebuilt radio that was held up goes back up as its new model.
		updateInspection()
	}

	/// The model for the connected radio's hardware, once it has loaded.
	private func radioModelName(for node: ShowcaseNodeSnapshot) -> String? {
		displays.modelName(forHardwareSlug: node.hwModel)
	}

	private func makeHero(_ node: ShowcaseNodeSnapshot, archetype: ShowcaseDeviceArchetype, modelName: String?, slot: ShowcaseSlot) -> Hero {
		let holder = Entity()
		holder.name = "node-\(node.id)"
		let halo = ModelEntity(mesh: ShowcaseDeviceMeshes.haloMesh, materials: [UnlitMaterial(color: Self.nodeColor(node.id))])
		halo.position = [0, 0.002, 0]
		halo.components.set(OpacityComponent(opacity: 0))
		holder.addChild(halo)
		heroContainer.addChild(holder)
		refreshPlacard(in: holder, nodeNum: node.id, shortName: node.shortName)
		if let modelName, let template = displays.template(named: modelName) {
			// The radio's own model at real size, on a stand like the others; it can be picked up too.
			let device = template.clone(recursive: true)
			// The clone is the radio, not the table's example: its taps open the node's card, and it
			// keeps none of the example's inspection state.
			device.components.remove(ShowcaseItemComponent.self)
			device.components.remove(ShowcaseInspectedComponent.self)
			device.components.remove(ShowcaseHomeComponent.self)
			let height = ShowcaseDisplays.stand(device, in: holder)
			device.components.set(ShowcaseNodeComponent(nodeNum: node.id))
			device.components.set(ShowcaseDeviceMeshes.accessibility(for: node, isOnline: false))
			receiveRoomLight(device)
			return Hero(holder: holder, device: device, label: nil, halo: halo, modelName: modelName, archetype: archetype, slot: slot, baseGlow: 0, style: Style(shortName: node.shortName, isOnline: false), height: height)
		}
		let device = ModelEntity(mesh: ShowcaseDeviceMeshes.mesh(for: archetype), materials: [])
		device.components.set(InputTargetComponent())
		device.components.set(HoverEffectComponent())
		device.components.set(CollisionComponent.inputTarget([ShowcaseDeviceMeshes.shape(for: archetype)]))
		device.components.set(ShowcaseNodeComponent(nodeNum: node.id))
		device.scale = SIMD3(repeating: Self.standInScale)
		let label = ModelEntity()
		label.name = "label"
		device.addChild(label)
		receiveRoomLight(device)
		holder.addChild(device)
		var hero = Hero(holder: holder, device: device, label: label, halo: halo, modelName: nil, archetype: archetype, slot: slot, baseGlow: 0, style: Style(shortName: "", isOnline: false), height: archetype.height * Self.standInScale)
		styleHero(&hero, node: node, style: Style(shortName: node.shortName, isOnline: false))
		return hero
	}

	private func styleHero(_ hero: inout Hero, node: ShowcaseNodeSnapshot, style: Style) {
		if hero.style.shortName != style.shortName {
			refreshPlacard(in: hero.holder, nodeNum: node.id, shortName: style.shortName)
		}
		hero.style = style
		guard let label = hero.label, let device = hero.device as? ModelEntity else { return }
		device.model?.materials = ShowcaseDeviceMeshes.materials(color: Self.nodeColor(node.id), isOnline: style.isOnline)
		if label.model == nil {
			let screen = hero.archetype.screen
			label.model = ModelComponent(mesh: ShowcaseDeviceMeshes.labelMesh(for: hero.archetype), materials: [UnlitMaterial(color: .clear)])
			label.position = screen.center + [0, 0, 0.0008]
		}
		Task {
			guard let material = await labelMaterial(style) else { return }
			// A newer style may have been applied while this one was drawn.
			guard heroes[node.id]?.style == style || heroes[node.id] == nil else { return }
			label.model?.materials = [material]
		}
	}

	/// The short name drawn on the device's screen. Drawn into a texture rather than built as a
	/// Draws the "Your radio" card for `shortName`, replacing any older one. Skipped if the name
	/// changed again while it was drawn.
	private func refreshPlacard(in holder: Entity, nodeNum: Int64, shortName: String) {
		Task {
			guard let placard = await ShowcaseDeviceMeshes.placard(shortName: shortName),
				  heroes[nodeNum].map({ $0.style.shortName == shortName || $0.style.shortName.isEmpty }) ?? true else { return }
			for old in Array(holder.children) where old.name == "placard" { old.removeFromParent() }
			holder.addChild(placard)
		}
	}

	/// text mesh, because text meshes leave out emoji, which many short names are.
	private func labelMaterial(_ style: Style) async -> UnlitMaterial? {
		if let material = labelMaterials[style] { return material }
		guard let image = ShowcaseDeviceMeshes.labelImage(style.shortName.isEmpty ? "?" : style.shortName, isOnline: style.isOnline),
			  let texture = try? await TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture))
		material.blending = .transparent(opacity: .init(floatLiteral: 1))
		labelMaterials[style] = material
		return material
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
		if let device = heroes[nodeNum]?.device, inspector.model === device { return inspector.cardPosition }
		guard let layout, let room, let slot = layout.slots[nodeNum] else { return nil }
		let pose = ShowcasePlacement.pose(of: slot, grid: layout.grid, anchor: room.pose)
		switch slot {
		case .rack(let index):
			guard index / layout.grid.perPage == page else { return nil }
			return pose.position + pose.forward * 0.3
		case .connectedRadio:
			let top = heroes[nodeNum]?.height ?? ShowcaseDeviceArchetype.generic.height
			return pose.position + [0, top + 0.13, 0] + pose.forward * 0.12
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
		inspector.step(deltaTime: dt)
		clock += dt
		guard !boosts.isEmpty, let layout else { return }
		for (num, boost) in boosts {
			let value = NodeActivityGlow.boost(startedAt: boost.start, now: clock, initial: boost.initial)
			let spent = value < NodeActivityGlow.boostFloor
			let scale = reduceMotion ? 1 : NodeActivityGlow.scale(boost: value)
			if let hero = heroes[num] {
				hero.halo.components.set(OpacityComponent(opacity: NodeActivityGlow.opacity(base: hero.baseGlow, boost: spent ? 0 : value)))
				hero.halo.scale = SIMD3(scale, 1, scale)
			} else if case .rack(let index) = layout.slots[num], index / layout.grid.perPage == page {
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
			if heroes[num] == nil { boosts[num] = nil }
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

	/// Once both the room and the catalog are in, stands the device models on the tables, then
	/// swaps the connected radio's stand-in for its model.
	func loadDisplaysIfReady() async {
		guard let room, let hardware = displayHardware else { return }
		displayHardware = nil
		await displays.load(room: room, hardware: hardware) { [weak self] in self?.receiveRoomLight($0) }
		if let layout { syncHeroes(layout: layout, now: Date()) }
		// A selection made while the models were loading.
		updateInspection()
	}

	// MARK: Inspection

	/// Holds up whatever is selected: a table's model, or the connected radio when it is a real
	/// model; puts the last one back otherwise.
	private func updateInspection() {
		if let id = selectedItem, let model = displays.model(for: id) {
			inspector.inspect(model)
		} else if let num = selected, let hero = heroes[num], hero.modelName != nil {
			inspector.inspect(hero.device)
		} else {
			inspector.release()
		}
	}

	/// Where a model's card goes: beside it when held up, else above it on its table.
	func cardPosition(forItem id: String) -> SIMD3<Float>? {
		if let model = displays.model(for: id), inspector.model === model { return inspector.cardPosition }
		return displays.cardPosition(forItem: id)
	}
}

/// The device meshes, built once per shape, and their materials.
@MainActor
enum ShowcaseDeviceMeshes {
	private static var meshes: [ShowcaseDeviceArchetype: MeshResource] = [:]
	private static var shapes: [ShowcaseDeviceArchetype: ShapeResource] = [:]
	static let haloMesh = MeshResource.generatePlane(width: 0.17, depth: 0.17, cornerRadius: 0.085)
	private static var labelMeshes: [ShowcaseDeviceArchetype: MeshResource] = [:]

	/// A quad covering most of the screen, for the short name.
	static func labelMesh(for archetype: ShowcaseDeviceArchetype) -> MeshResource {
		if let mesh = labelMeshes[archetype] { return mesh }
		let size = archetype.screen.size
		// The label texture is 2:1; keep its shape inside the screen.
		let width = min(size.x * 0.92, size.y * 0.9 * 2)
		let mesh = MeshResource.generatePlane(width: width, height: width / 2)
		labelMeshes[archetype] = mesh
		return mesh
	}

	static func mesh(for archetype: ShowcaseDeviceArchetype) -> MeshResource {
		if let mesh = meshes[archetype] { return mesh }
		let mesh = (try? resource(archetype.geometry, name: "device")) ?? MeshResource.generateBox(size: 0.08)
		meshes[archetype] = mesh
		return mesh
	}

	/// The device's hit box, a little bigger than the device so it is easy to look at.
	static func shape(for archetype: ShowcaseDeviceArchetype) -> ShapeResource {
		if let shape = shapes[archetype] { return shape }
		let bounds = mesh(for: archetype).bounds
		let shape = ShapeResource.generateBox(size: bounds.extents + [0.02, 0.01, 0.02]).offsetBy(translation: bounds.center)
		shapes[archetype] = shape
		return shape
	}

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

	/// Body in the node's color, a screen that is lit when the node is online, and dark plastic.
	static func materials(color: UIColor, isOnline: Bool) -> [any RealityKit.Material] {
		var body = PhysicallyBasedMaterial()
		body.baseColor = .init(tint: isOnline ? color : color.darker(componentDelta: 0.25))
		body.roughness = 0.42
		body.clearcoat = 0.4
		let screen = UnlitMaterial(color: isOnline ? UIColor(red: 0.05, green: 0.16, blue: 0.12, alpha: 1) : UIColor(white: 0.04, alpha: 1))
		var dark = PhysicallyBasedMaterial()
		dark.baseColor = .init(tint: UIColor(white: 0.08, alpha: 1))
		dark.roughness = 0.75
		return [body, screen, dark]
	}

	/// The short name drawn for a stand-in box's screen, 2:1, fitted to the width.
	static func labelImage(_ text: String, isOnline: Bool) -> CGImage? {
		let size = CGSize(width: 256, height: 128)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = false
		let color = isOnline ? UIColor(red: 0.62, green: 1, blue: 0.78, alpha: 1) : UIColor(white: 0.5, alpha: 1)
		let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			var fontSize: CGFloat = 96
			var attributes: [NSAttributedString.Key: Any] = [:]
			var measured = CGSize.zero
			// Shrink until the name fits the screen.
			repeat {
				attributes = [.font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold), .foregroundColor: color]
				measured = (text as NSString).size(withAttributes: attributes)
				fontSize -= 4
			} while (measured.width > size.width * 0.92 || measured.height > size.height * 0.9) && fontSize > 12
			let origin = CGPoint(x: (size.width - measured.width) / 2, y: (size.height - measured.height) / 2)
			(text as NSString).draw(at: origin, withAttributes: attributes)
		}
		return image.cgImage
	}

	/// The tent card in front of the connected radio: "Your radio" and its short name.
	static func placard(shortName: String) async -> ModelEntity? {
		let size = CGSize(width: 360, height: 180)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = false
		let title = String(localized: "Your radio", comment: "Showcase: card in front of the connected radio on the display table")
		let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
			UIColor.white.setFill()
			UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18).fill()
			let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: UIColor(white: 0.45, alpha: 1)]
			let large: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 64, weight: .semibold), .foregroundColor: UIColor(white: 0.1, alpha: 1)]
			let titleSize = (title as NSString).size(withAttributes: small)
			(title as NSString).draw(at: CGPoint(x: (size.width - titleSize.width) / 2, y: 22), withAttributes: small)
			let name = shortName.isEmpty ? "?" : shortName
			let nameSize = (name as NSString).size(withAttributes: large)
			(name as NSString).draw(at: CGPoint(x: (size.width - nameSize.width) / 2, y: 74), withAttributes: large)
		}
		return await tentCard(image, size: placardSize, inFrontBy: placardDistance)
	}

	/// The tent cards' size in meters, the image pixels per meter they're drawn at, and how far in
	/// front of a stand's center they stand.
	static let placardSize = SIMD2<Float>(0.08, 0.04)
	private static let placardPixelsPerMeter: CGFloat = 4500
	static let placardDistance: Float = 0.07

	/// The tent card in front of a model on a display table: the maker, and the device's name
	/// under it. Shorter than the "Your radio" card; `width` in meters, up to that card's.
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

	static func accessibility(for node: ShowcaseNodeSnapshot, isOnline: Bool) -> AccessibilityComponent {
		var component = AccessibilityComponent()
		component.isAccessibilityElement = true
		component.traits = [.button]
		component.label = LocalizedStringResource(stringLiteral: node.longName)
		let heard = node.lastHeard?.lastHeard ?? String(localized: "Never", comment: "Spatial map: node has never been heard")
		component.value = isOnline
			? LocalizedStringResource("Online, last heard \(heard)", comment: "Showcase: VoiceOver value for a radio that is online; the argument is when it was last heard")
			: LocalizedStringResource("Offline, last heard \(heard)", comment: "Showcase: VoiceOver value for a radio that is offline; the argument is when it was last heard")
		return component
	}
}
#endif
