//
//  AccessoryManager+Connect.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/24/25.
//

import Foundation
import OSLog
import MeshtasticProtobufs

private let maxRetries = 10
private let retryDelay: Duration = .seconds(1)

extension AccessoryManager {
	func connect(to device: Device) async throws {
		
		// Prevent new connection if one is active
		if activeConnection != nil {
			throw AccessoryError.connectionFailed("Already connected to a device")
		}
		
		guard let transport = transports.first(where: { $0.type == device.transportType }) else {
			throw AccessoryError.connectionFailed("No transport for type")
		}
		
		// Clear any errors from last time
		lastConnectionError = nil
		packetsSent = 0
		packetsReceived = 0
		
		// Prepare to connect
		self.connectionStepper = SequentialSteps(maxRetries: maxRetries, retryDelay: retryDelay) {
			
			// Step 0
			Step { @MainActor retryAttempt in
				Logger.transport.info("🔗 [Connect] Starting connection to \(device.id)")
				if retryAttempt > 0 {
					try await self.closeConnection() // clean-up before retries.
					self.updateState(.retrying(attempt: retryAttempt + 1))
					self.allowDisconnect = true
				} else {
					self.updateState(.connecting)
				}
				self.updateDevice(deviceId: device.id, key: \.connectionState, value: .connecting)
			}
			
			// Step 1: Setup the connection
			Step(timeout: .seconds(2)) { @MainActor _ in
				Logger.transport.info("🔗 [Connect] Step 1: connection to \(device.id)")
				let connection = try await transport.connect(to: device)
				let eventStream = try await connection.connect()
				self.updateState(.communicating)
				self.connectionEventTask = Task {
					for await event in eventStream {
						self.didReceive(event)
					}
					Logger.transport.info("[Accessory] Event stream closed")
				}
				self.activeConnection = (device: device, connection: connection)
				
				if UserDefaults.preferredPeripheralId.count < 1 {
					UserDefaults.preferredPeripheralId = device.id.uuidString
				}
			}
			
			// Step 2: Send Heartbeat before wantConfig (config)
			Step { @MainActor _ in
				Logger.transport.info("💓 [Connect] Step 2: Send heartbeat")
				try await self.sendHeartbeat()
			}
			
			// Step 3: Send WantConfig (config)
			Step(timeout: .seconds(30)) { @MainActor _ in
				Logger.transport.info("🔗 [Connect] Step 3: Send wantConfig (config)")
				try await self.sendWantConfig()
			}
			
			// Step 4: Send Heartbeat before wantConfig (database)
			Step { @MainActor _ in
				Logger.transport.info("💓 [Connect] Step 4: Send heartbeat")
				try await self.sendHeartbeat()
			}
			
			// Step 5: Send WantConfig (database)
			Step(timeout: .seconds(3.0), onFailure: .retryStep(attempts: 3)) { @MainActor _ in
				Logger.transport.info("🔗 [Connect] Step 5: Send wantConfig (database)")
				self.updateState(.retrievingDatabase(nodeCount: 0))
				self.allowDisconnect = true
				try await self.sendWantDatabase()
			}
			
			// Step 5a: Wait for end of WantConfig (database)
			Step { @MainActor _ in
				Logger.transport.info("🔗[Connect] Step 5a: Wait for the final database")
				try await self.waitForWantDatabaseResponse()
			}
			
			// Step 6: Version check
			Step { @MainActor _ in
				Logger.transport.info("🔗 [Connect] Step 6: Version check")

				guard let firmwareVersion = self.activeConnection?.device.firmwareVersion else {
					Logger.transport.error("🔗 [Connect] Firmware version not available for device \(device.name, privacy: .public)")
					throw AccessoryError.connectionFailed("Firmware version not available")
				}
				
				let lastDotIndex = firmwareVersion.lastIndex(of: ".")
				if lastDotIndex == nil {
					throw AccessoryError.versionMismatch("🚨" + "Update Your Firmware".localized)
				}
				
				let version = firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: firmwareVersion))].dropLast()
				
				// TODO: do we really need to store the firmware version in the UserDefaults?
				UserDefaults.firmwareVersion = String(version)
				
				let supportedVersion = self.checkIsVersionSupported(forVersion: self.minimumVersion)
				if !supportedVersion {
					throw AccessoryError.connectionFailed("🚨" + "Update Your Firmware".localized)
				}
			}
			
			// Step 7: Update UI and status to connected
			Step { @MainActor _ in
				Logger.transport.info("🔗 [Connect] Step 7: Update UI and status")

				// We have an active connection
				self.updateDevice(deviceId: device.id, key: \.connectionState, value: .connected)
				self.updateState(.subscribed)
			}
			
			// Step 8: Update UI and status to connected
			Step { @MainActor _ in
				Logger.transport.debug("🔗 [Connect] Step 8: Initialize MQTT and Location Provider")
				self.stopDiscovery()
				await self.initializeMqtt()
				self.initializeLocationProvider()
				if transport.requiresPeriodicHeartbeat {
					await self.setupPeriodicHeartbeat()
				}
			}
		}
		
		// Run the connection process
		do {
			try await connectionStepper?.run()
		} catch {
			switch error {
			case  is CancellationError, AccessoryError.tooManyRetries:
				try await self.closeConnection()
				updateState(.discovering)
			default:
				Logger.transport.error("🔗 [Connect] Error returned by connectionStepper: \(error)")
			}
			self.lastConnectionError = error
		}
		
		// All done, one way or another, clean up
		self.connectionStepper = nil
	}
}

// Sequentially stepped tasks
typealias Step = SequentialSteps.Step
actor SequentialSteps {
	
	typealias StepClosure = @Sendable (_ retryAttempt: Int) async throws -> Void
	
	enum FailureBehavior {
		case fail
		case retryStep(attempts: Int)
		case retryAll
	}
	
	struct Step {
		let timeout: Duration?
		let failureBehavior: FailureBehavior
		let operation: StepClosure
		
		init(timeout: Duration? = nil, onFailure: FailureBehavior = .retryAll, operation: @escaping StepClosure) {
			self.timeout = timeout
			self.failureBehavior = onFailure
			self.operation = operation
		}
	}
	
	private enum SequentialStepError: Error, LocalizedError {
		case timeout(stepNumber: Int, afterWaiting: Duration)
		
		var errorDescription: String? {
			switch self {
			case .timeout(let stepNumber, let afterWaiting):
				return "Timeout after \(afterWaiting) waiting for step \(stepNumber)."
			}
		}
	}
	let steps: [Step]
	var currentlyExecutingStep: Task<Void, any Error>?
	var cancelled = false
	var maxRetries: Int
	var retryDelay: Duration
	var isRunning: Bool = false
	var externalError: Error?
	
	init(maxRetries: Int = 1, retryDelay: Duration = .seconds(3), @StepsBuilder _ builder: () -> [Step]) {
		self.maxRetries	= maxRetries
		self.retryDelay = retryDelay
		self.steps = builder()
	}
	
	func run() async throws {
		self.isRunning = true
		retryLoop: for attempt in 0..<maxRetries {
			for stepNumber in 0..<steps.count {
				if cancelled {
					throw CancellationError()
					break
				}
				let currentStep = steps[stepNumber]
				let isRetry = (attempt > 0)
				if isRetry {
					try await Task.sleep(for: retryDelay)
				}
				do {
					let stepRetries = if case let .retryStep(attempts) = currentStep.failureBehavior, attempts > 0 { attempts } else { 1 }
					stepRetryLoop: for stepRetryAttempt in 0..<stepRetries {
						if stepRetryAttempt > 0 {
							Logger.transport.info("[Retry Step Loop] Retrying step \(stepNumber + 1) for the \(stepRetryAttempt + 1) time.")
							try await Task.sleep(for: retryDelay)
						}
						do {
							// Starting a new attempt for this step.
							if let duration = currentStep.timeout {
								// Execute this task with a timeout
								self.currentlyExecutingStep = executeWithTimeout(stepNumber: stepNumber, timeout: duration) {
									try await currentStep.operation(attempt)
								}
								try await self.currentlyExecutingStep!.value
							} else {
								// Execute this task without a timeout
								self.currentlyExecutingStep = Task {
									try await currentStep.operation(attempt)
								}
								try await self.currentlyExecutingStep!.value
							}
							break stepRetryLoop // Exit retry loop if successful
						} catch {
							if stepRetryAttempt == stepRetries - 1 {
								// If this is the last retry attempt, we throw the error to the outer loop
								throw error
							} else {
								switch error {
								case let SequentialStepError.timeout(stepNumber, afterWaiting):
									Logger.transport.info("[Inner Retry Step Loop] Sequential process timed out on step \(stepNumber) of \(stepRetries) after waiting \(afterWaiting)")
								case is CancellationError:
									if let externalError {
										// Something from the outside had an error which caused the cancellation of this step
										let errorToThrow = externalError
										self.externalError = nil
										throw errorToThrow
									}
									break stepRetryLoop
								default:
									Logger.transport.error("[Inner Retry Step Loop] Sequential process failed on step \(stepNumber) with error: \(error.localizedDescription)")
								}
							}
						}
					}
				} catch {
					switch error {
					case let SequentialStepError.timeout(stepNumber, afterWaiting):
						Logger.transport.info("[Outer Step Retry Loop] Sequential process timed out on step \(stepNumber) after waiting \(afterWaiting)")
					default:
						Logger.transport.error("[Outer Step Retry Loop] Sequential process failed on step \(stepNumber) with error: \(error.localizedDescription)")
					}
					switch currentStep.failureBehavior {
					case .retryAll, .retryStep:
						// TODO: we could have a .retryStepAndFail and a .retryStepAndContinue instead of just .retryStep to clarify the behavior here
						continue retryLoop
					case .fail:
						isRunning = false
						throw error
					}
				}
			}
			// We have finished all steps
			isRunning = false
			return
		}
		isRunning = false
		throw AccessoryError.tooManyRetries
	}
	
	func cancel() {
		cancelled = true
		self.currentlyExecutingStep?.cancel()
	}
	
	func cancelCurrentlyExecutingStep(withError: Error?) {
		self.externalError = withError
		self.currentlyExecutingStep?.cancel()
	}
	
	func executeWithTimeout<ReturnType>(stepNumber: Int, timeout: Duration, operation: @escaping @Sendable () async throws -> ReturnType) -> Task<ReturnType, Error> {
		return Task {
			try await withThrowingTaskGroup(of: ReturnType.self) { group -> ReturnType in
				group.addTask(operation: operation)
				group.addTask {
					try await _Concurrency.Task.sleep(for: timeout)
					throw SequentialStepError.timeout(stepNumber: stepNumber, afterWaiting: timeout)
				}
				guard let success = try await group.next() else {
					throw SequentialStepError.timeout(stepNumber: stepNumber, afterWaiting: timeout)
				}
				group.cancelAll()
				return success
			}
		}
	}
	
	@resultBuilder
	struct StepsBuilder {
		static func buildBlock(_ components: Step...) -> [Step] {
			return components
		}
	}
}
