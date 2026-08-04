// ContainerLeaseTests.swift
// MeshtasticTests

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Container leases", .serialized)
struct ContainerLeaseTests {

	@Test("container replacement invalidates the previous lease")
	@MainActor
	func containerReplacementInvalidatesPreviousLease() async throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-Replacement")
		let oldLease = controller.currentContainerLease

		try controller.requireCurrent(oldLease)
		let didRecreate = await controller.recreateContainer()
		#expect(didRecreate)

		#expect(throws: ContainerLeaseError.self) {
			try controller.requireCurrent(oldLease)
		}
		try controller.requireCurrent(controller.currentContainerLease)
	}

	@Test("delayed callback cannot mutate through a stale lease")
	@MainActor
	func delayedCallbackCannotMutateThroughStaleLease() async throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-Delayed")
		let oldContext = controller.context
		let oldLease = controller.currentContainerLease
		let (stream, continuation) = AsyncStream.makeStream(of: Void.self)

		let delayedCallback = Task { @MainActor in
			for await _ in stream { break }
			try controller.requireCurrent(oldLease)
			let node = NodeInfoEntity()
			node.num = 42
			oldContext.insert(node)
			try oldContext.save()
		}

		await Task.yield()
		let didRecreate = await controller.recreateContainer()
		#expect(didRecreate)
		continuation.yield(())
		continuation.finish()

		do {
			try await delayedCallback.value
			Issue.record("A delayed callback accepted a stale container lease")
		} catch {
			#expect(error is ContainerLeaseError)
		}

		let nodes = try controller.context.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(nodes.isEmpty)
	}

	@Test("lease is checked again before save")
	@MainActor
	func leaseIsCheckedAgainBeforeSave() async throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-Save")
		let oldContext = controller.context
		let oldLease = controller.currentContainerLease

		try controller.requireCurrent(oldLease)
		let node = NodeInfoEntity()
		node.num = 77
		oldContext.insert(node)

		let didRecreate = await controller.recreateContainer()
		#expect(didRecreate)

		#expect(throws: ContainerLeaseError.self) {
			try controller.requireCurrent(oldLease)
		}
		let nodes = try controller.context.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(nodes.isEmpty)
	}

	@Test("transition drains an active writer without blocking the main actor")
	@MainActor
	func transitionDrainsActiveWriterWithoutBlockingMainActor() async throws {
		let firstContainer = NSObject()
		let secondContainer = NSObject()
		let firstContainerID = ObjectIdentifier(firstContainer)
		let coordinator = ContainerAccessCoordinator(containerID: firstContainerID)
		let oldLease = coordinator.currentLease
		let writer = try coordinator.beginWrite(using: oldLease, containerID: firstContainerID)

		let transitionTask = Task {
			try await coordinator.beginTransition(timeout: .seconds(1))
		}
		var rejectedDuringTransition = false
		for _ in 0..<100 where !rejectedDuringTransition {
			await Task.yield()
			do {
				let extraWriter = try coordinator.beginWrite(
					using: oldLease,
					containerID: firstContainerID
				)
				extraWriter.finish()
			} catch ContainerLeaseError.transitioning {
				rejectedDuringTransition = true
			}
		}
		#expect(rejectedDuringTransition)

		writer.finish()
		let transition = try await transitionTask.value
		try coordinator.commitTransition(
			transition,
			newContainerID: ObjectIdentifier(secondContainer)
		)

		#expect(throws: ContainerLeaseError.self) {
			_ = try coordinator.beginWrite(using: oldLease, containerID: firstContainerID)
		}
	}

	@Test("write permit rejects a context from another container")
	func writePermitRejectsContextFromAnotherContainer() throws {
		let currentContainer = NSObject()
		let otherContainer = NSObject()
		let coordinator = ContainerAccessCoordinator(containerID: ObjectIdentifier(currentContainer))

		#expect(throws: ContainerLeaseError.self) {
			_ = try coordinator.beginWrite(
				using: coordinator.currentLease,
				containerID: ObjectIdentifier(otherContainer)
			)
		}
	}

	@Test("transition timeout preserves the current lease")
	func transitionTimeoutPreservesCurrentLease() async throws {
		let container = NSObject()
		let containerID = ObjectIdentifier(container)
		let coordinator = ContainerAccessCoordinator(containerID: containerID)
		let lease = coordinator.currentLease
		let writer = try coordinator.beginWrite(using: lease, containerID: containerID)

		do {
			_ = try await coordinator.beginTransition(timeout: .milliseconds(20))
			Issue.record("A transition with a leaked writer did not time out")
		} catch {
			#expect(error as? ContainerLeaseError == .drainTimedOut)
		}

		let nextWriter = try coordinator.beginWrite(using: lease, containerID: containerID)
		nextWriter.finish()
		writer.finish()
	}

	@Test("cancelled transition preserves the current lease")
	func cancelledTransitionPreservesCurrentLease() async throws {
		let container = NSObject()
		let containerID = ObjectIdentifier(container)
		let coordinator = ContainerAccessCoordinator(containerID: containerID)
		let lease = coordinator.currentLease
		let transition = try await coordinator.beginTransition(timeout: .seconds(1))

		try coordinator.cancelTransition(transition)

		let writer = try coordinator.beginWrite(using: lease, containerID: containerID)
		writer.finish()
	}

	@Test("retired MeshPackets actor drops its pending write")
	@MainActor
	func retiredMeshPacketsActorDropsPendingWrite() async throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-MeshPackets")
		let retiredContainer = controller.container
		let packets = MeshPackets(
			modelContainer: retiredContainer,
			writeAccess: controller.currentWriteAccess
		)

		let didRecreate = await controller.recreateContainer()
		#expect(didRecreate)
		let didSave = await packets.insertNodeAndSaveForLeaseTest(num: 8080)
		#expect(!didSave)

		let retiredContext = ModelContext(retiredContainer)
		let retiredNodes = try retiredContext.fetch(FetchDescriptor<NodeInfoEntity>())
		let currentNodes = try controller.context.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(retiredNodes.isEmpty)
		#expect(currentNodes.isEmpty)
	}

	@Test("retired AccessoryManager context rejects save")
	@MainActor
	func retiredAccessoryManagerContextRejectsSave() async throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-Accessory")
		let retiredContainer = controller.container
		let manager = AccessoryManager(transports: [])
		manager.context = controller.context
		manager.writeAccess = controller.currentWriteAccess

		let didRecreate = await controller.recreateContainer()
		#expect(didRecreate)

		let node = NodeInfoEntity()
		node.num = 9090
		manager.context.insert(node)
		#expect(throws: ContainerLeaseError.self) {
			try manager.commitContextChanges()
		}

		let retiredContext = ModelContext(retiredContainer)
		let retiredNodes = try retiredContext.fetch(FetchDescriptor<NodeInfoEntity>())
		let currentNodes = try controller.context.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(retiredNodes.isEmpty)
		#expect(currentNodes.isEmpty)
	}

	@Test("retired discovery engine context rejects save")
	@MainActor
	func retiredDiscoveryEngineContextRejectsSave() async throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-Discovery")
		let retiredContainer = controller.container
		let retiredContext = controller.context
		let session = DiscoverySessionEntity()
		session.completionStatus = "inProgress"
		retiredContext.insert(session)
		try retiredContext.save()

		let manager = AccessoryManager(transports: [])
		let engine = DiscoveryScanEngine()
		engine.configure(
			accessoryManager: manager,
			modelContext: retiredContext,
			writeAccess: controller.currentWriteAccess
		)

		let didRecreate = await controller.recreateContainer()
		#expect(didRecreate)
		engine.checkForInterruptedSessions(context: retiredContext)

		let verificationContext = ModelContext(retiredContainer)
		let sessions = try verificationContext.fetch(FetchDescriptor<DiscoverySessionEntity>())
		#expect(sessions.first?.completionStatus == "inProgress")
		#expect(try controller.context.fetch(FetchDescriptor<DiscoverySessionEntity>()).isEmpty)
	}

	@Test("managed ModelContext save acquires a write permit")
	@MainActor
	func managedModelContextSaveAcquiresWritePermit() throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-Coordinated")
		let node = NodeInfoEntity()
		node.num = 10_101
		controller.context.insert(node)

		try controller.context.coordinatedSave()

		#expect(try controller.context.fetch(FetchDescriptor<NodeInfoEntity>()).count == 1)
	}

	@Test("retired ModelContext coordinated save is rejected")
	@MainActor
	func retiredModelContextCoordinatedSaveIsRejected() async throws {
		let controller = PersistenceController(inMemory: true, storeName: "ContainerLeaseTests-RetiredContext")
		let retiredContainer = controller.container
		let retiredContext = controller.context

		let didRecreate = await controller.recreateContainer()
		#expect(didRecreate)

		let node = NodeInfoEntity()
		node.num = 10_202
		retiredContext.insert(node)
		#expect(throws: ContainerLeaseError.self) {
			try retiredContext.coordinatedSave()
		}

		let verificationContext = ModelContext(retiredContainer)
		#expect(try verificationContext.fetch(FetchDescriptor<NodeInfoEntity>()).isEmpty)
	}

	@Test("unmanaged test ModelContext saves normally")
	@MainActor
	func unmanagedTestModelContextSavesNormally() throws {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let configuration = ModelConfiguration(
			"ContainerLeaseTests-Unmanaged",
			schema: schema,
			isStoredInMemoryOnly: true
		)
		let container = try ModelContainer(for: schema, configurations: configuration)
		let context = container.mainContext
		let node = NodeInfoEntity()
		node.num = 10_303
		context.insert(node)

		try context.coordinatedSave()

		#expect(try context.fetch(FetchDescriptor<NodeInfoEntity>()).count == 1)
	}
}
