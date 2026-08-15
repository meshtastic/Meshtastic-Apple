//
//  DeviceProfileImportCancellationTests.swift
//  Meshtastic
//
//  Tests for in-flight cancellation of the import engine, covering the cancellation → commit
//  handoff, shielding of the commit from inherited cancellation, and keyed-continuation
//  bookkeeping in WriteContinuationStore.
//

import Foundation
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

@Suite("DeviceProfile import cancellation")
struct DeviceProfileImportCancellationTests {

	// MARK: - Helpers

	private func makeThreeItemPlan() throws -> DeviceProfileImportPlan {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.display = Config.DisplayConfig()
		config.position = Config.PositionConfig()
		profile.config = config
		return try DeviceProfileImportPlan(profile: profile, currentUser: nil)
	}

	@MainActor
	private final class MockGateway: ProfileApplyGateway {
		var isConnected = true
		var attempted: [ImportItemKind] = []
		var calls: [String] = []
		/// Throws CancellationError when this item is applied.
		var cancelOn: ImportItemKind?
		/// If set, the surrounding Task is cancelled when this item is applied (simulates
		/// a user tapping Cancel mid-send).
		var cancelTaskOn: ImportItemKind?
		private var cancelTask: (() -> Void)?
		/// Set true to make commitEditSettings throw.
		var failOnCommit = false
		/// Fired as the commit is sent.
		var onCommit: (() -> Void)?
		/// Records whether Task.isCancelled was true when commitEditSettings ran.
		var commitSawCancellation: Bool?

		func setTaskToCancel<T>(_ task: Task<T, Never>) {
			cancelTask = { task.cancel() }
		}

		private func cancelStoredTask() {
			cancelTask?()
		}

		func beginEditSettings() async throws {
			calls.append("begin")
		}

		func commitEditSettings() async throws {
			calls.append("commit")
			commitSawCancellation = Task.isCancelled
			onCommit?()
			if failOnCommit {
				throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "commit failed"])
			}
		}

		func apply(_ item: ImportItem) async throws {
			attempted.append(item.kind)
			calls.append(item.kind.rawValue)
			if item.kind == cancelTaskOn {
				cancelStoredTask()
				// Yield so the cancellation flag propagates before the next send.
				await Task.yield()
			}
			if item.kind == cancelOn {
				throw CancellationError()
			}
		}
	}

	// MARK: - (a) Cancel mid-run still attempts the commit

	@MainActor
	@Test("A gateway that throws CancellationError on an item still runs the commit")
	func cancelMidRunStillCommits() async throws {
		let plan = try makeThreeItemPlan()
		let gateway = MockGateway()
		gateway.cancelOn = .displayConfig

		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway,
			sleep: { _ in }
		)

		#expect(result.wasCancelled)
		#expect(result.applied == [.deviceConfig])
		#expect(result.skipped.contains(.displayConfig))
		#expect(result.skipped.contains(.positionConfig))
		// The commit must always run, even after cancellation.
		#expect(gateway.calls.contains("commit"))
		#expect(result.transactionCommitted)
	}

	// MARK: - (b) CancellationError from gateway marks wasCancelled, skips rest, commit still runs

	@MainActor
	@Test("CancellationError on an item sets wasCancelled, skips remaining, and the commit succeeds")
	func cancellationErrorMarksWasCancelledAndCommits() async throws {
		let plan = try makeThreeItemPlan()
		let gateway = MockGateway()
		gateway.cancelOn = .deviceConfig  // first item

		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway,
			sleep: { _ in }
		)

		#expect(result.wasCancelled)
		#expect(result.failed == nil)  // cancellation is not a failure
		#expect(result.applied.isEmpty)
		#expect(Set(result.skipped) == Set([.deviceConfig, .displayConfig, .positionConfig]))
		#expect(result.transactionCommitted)
		#expect(gateway.calls.contains("commit"))
	}

	// MARK: - (c) Commit succeeds even when Task.isCancelled is true (shielding works)

	@MainActor
	@Test("The commit runs in an un-cancelled context even when the import Task is cancelled")
	func commitIsShieldedFromInheritedCancellation() async throws {
		let plan = try makeThreeItemPlan()
		let gateway = MockGateway()

		// We'll run the import in a Task, cancel it after the first item, and verify
		// the commit did not see the cancellation flag.
		let task = Task { @MainActor in
			await DeviceProfileImporter.apply(
				plan: plan,
				selection: Set(plan.presentSections),
				gateway: gateway,
				sleep: { _ in }
			)
		}
		gateway.setTaskToCancel(task)
		gateway.cancelTaskOn = .deviceConfig  // cancel the task during the first item

		let result = await task.value

		// The commit must have run, and it must not have seen isCancelled == true
		// (because withoutCancellation creates a fresh Task).
		#expect(gateway.calls.contains("commit"))
		#expect(result.transactionCommitted)
		#expect(gateway.commitSawCancellation == false)
	}

	// MARK: - (d) WriteContinuationStore keyed-continuation bookkeeping

	@Suite("WriteContinuationStore")
	struct WriteContinuationStoreTests {

		@Test("insert + removeFirst returns the oldest entry")
		func removeFirstIsOrdered() async {
			var store = WriteContinuationStore()
			let id1 = UUID()
			let id2 = UUID()
			// We can't create real CheckedContinuations outside of withCheckedThrowingContinuation,
			// so test the structural behavior via insert/remove/isEmpty.
			#expect(store.isEmpty)
			#expect(store.removeFirst() == nil)

			// Simulate two writes by using withCheckedThrowingContinuation to get real continuations.
			var retrieved1: UUID?
			var retrieved2: UUID?

			// Use a Task to run the continuations through the store.
			await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
				// We need to test the store without real CoreBluetooth, so we create continuations
				// and immediately exercise the store's bookkeeping.
				Task {
					// First continuation
					try? await withCheckedThrowingContinuation { (cont1: CheckedContinuation<Void, Error>) in
						store.insert(id: id1, continuation: cont1)

						// Second continuation (nested for test purposes)
						Task {
							try? await withCheckedThrowingContinuation { (cont2: CheckedContinuation<Void, Error>) in
								store.insert(id: id2, continuation: cont2)

								// Now test removeFirst returns oldest
								if let first = store.removeFirst() {
									retrieved1 = first.id
									first.continuation?.resume()
								}
								if let second = store.removeFirst() {
									retrieved2 = second.id
									second.continuation?.resume()
								}
								#expect(store.isEmpty)
								outerCont.resume()
							}
						}
					}
				}
			}

			#expect(retrieved1 == id1)
			#expect(retrieved2 == id2)
		}

		@Test("remove(id:) targets the right entry and leaves others intact")
		func removeByIdIsTargeted() async {
			var store = WriteContinuationStore()
			let id1 = UUID()
			let id2 = UUID()

			await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
				Task {
					try? await withCheckedThrowingContinuation { (cont1: CheckedContinuation<Void, Error>) in
						store.insert(id: id1, continuation: cont1)

						Task {
							try? await withCheckedThrowingContinuation { (cont2: CheckedContinuation<Void, Error>) in
								store.insert(id: id2, continuation: cont2)

								// Remove the second by ID; the first should remain.
								let removed = store.remove(id: id2)
								#expect(removed != nil)
								removed?.resume()

								// The first is still there.
								#expect(!store.isEmpty)

								// Removing the same ID again returns nil (already consumed).
								#expect(store.remove(id: id2) == nil)

								// Clean up the first.
								if let first = store.removeFirst() {
									#expect(first.id == id1)
									first.continuation?.resume()
								}
								#expect(store.isEmpty)
								outerCont.resume()
							}
						}
					}
				}
			}
		}

		@Test("drainAll resumes every pending continuation with the given error")
		func drainAllResumesWithError() async {
			var store = WriteContinuationStore()
			let id1 = UUID()
			let id2 = UUID()
			var errors: [Error] = []

			await withCheckedContinuation { (outerCont: CheckedContinuation<Void, Never>) in
				Task {
					// Create two continuations, insert them, then drain.
					let task1 = Task<Void, Error> {
						try await withCheckedThrowingContinuation { (cont1: CheckedContinuation<Void, Error>) in
							store.insert(id: id1, continuation: cont1)

							Task {
								try? await withCheckedThrowingContinuation { (cont2: CheckedContinuation<Void, Error>) in
									store.insert(id: id2, continuation: cont2)

									store.drainAll(throwing: CancellationError())
									#expect(store.isEmpty)
								}
							}
						}
					}
					do {
						try await task1.value
					} catch {
						errors.append(error)
					}
					// Resume only after task1's result is recorded, so the assertion below
					// cannot race the catch. (The drain closure resuming us was a race: the
					// outer await completed before the error was appended.)
					outerCont.resume()
				}
			}

			#expect(errors.first is CancellationError)
		}
	}
}
