import Foundation

enum ChirpyRunnerPhase: Equatable {
	case ready
	case running
	case gameOver
}

enum ChirpyObstacleKind: Hashable {
	case tallCactus
	case cactusCluster
	case flyingBird
}

struct ChirpyRunnerEngine: Equatable {
	static let playerX = 0.2
	static let playerWidth = 0.09
	static let playerHeight = 0.17
	static let crouchingPlayerHeight = 0.095
	static let obstacleWidth = 0.075
	static let obstacleHeight = 0.18

	private static let gravity = 7.2
	private static let fastFallGravity = 11.2
	private static let jumpVelocity = 2.5
	private static let simulationStep = 1.0 / 120.0
	private static let maximumCatchUpDuration = 0.1
	private static let horizontalHitboxScale = 0.38

	private(set) var phase: ChirpyRunnerPhase = .ready
	private(set) var playerY = 0.0
	private(set) var verticalVelocity = 0.0
	private(set) var isCrouching = false
	private(set) var score = 0
	private(set) var obstacleX: Double
	private(set) var obstacleKind: ChirpyObstacleKind

	init(obstacleX: Double = 0.43, obstacleKind: ChirpyObstacleKind = .tallCactus) {
		self.obstacleX = obstacleX
		self.obstacleKind = obstacleKind
	}

	static func speed(forScore score: Int) -> Double {
		min(0.5 + (Double(max(score, 0)) * 0.019), 0.88)
	}

	static func obstacleKind(forScore score: Int) -> ChirpyObstacleKind {
		switch max(score, 0) % 5 {
		case 1, 4:
			return .cactusCluster
		case 3:
			return .flyingBird
		default:
			return .tallCactus
		}
	}

	mutating func primaryAction() {
		switch phase {
		case .ready:
			startRunning()
			jump()
		case .running:
			jump()
		case .gameOver:
			reset()
		}
	}

	mutating func startRunning() {
		guard phase != .running else {
			return
		}
		phase = .running
	}

	mutating func advance(by deltaTime: TimeInterval) {
		guard phase == .running else {
			return
		}

		var remaining = min(max(deltaTime, 0), Self.maximumCatchUpDuration)
		while remaining > 0, phase == .running {
			let step = min(remaining, Self.simulationStep)
			advanceStep(by: step)
			remaining -= step
		}
	}

	mutating func setCrouching(_ crouching: Bool) {
		guard phase == .running else {
			isCrouching = false
			return
		}
		isCrouching = crouching
	}

	private mutating func advanceStep(by delta: TimeInterval) {
		let activeGravity = isCrouching && playerY > 0 ? Self.fastFallGravity : Self.gravity
		verticalVelocity -= activeGravity * delta
		playerY += verticalVelocity * delta
		if playerY <= 0 {
			playerY = 0
			verticalVelocity = 0
		}

		obstacleX -= Self.speed(forScore: score) * delta
		if collidesWithObstacle {
			phase = .gameOver
			return
		}

		let obstacleRight = obstacleX + (Self.obstacleWidth / 2)
		let playerLeft = Self.playerX - (Self.playerWidth / 2)
		if obstacleRight < playerLeft {
			score += 1
			obstacleX = nextObstacleX
			obstacleKind = Self.obstacleKind(forScore: score)
		}
	}

	mutating func reset() {
		phase = .ready
		playerY = 0
		verticalVelocity = 0
		isCrouching = false
		score = 0
		obstacleX = 0.43
		obstacleKind = .tallCactus
	}

	private mutating func jump() {
		guard playerY <= 0.012, !isCrouching else {
			return
		}
		verticalVelocity = Self.jumpVelocity
	}

	private var collidesWithObstacle: Bool {
		let obstacleWidth = switch obstacleKind {
		case .tallCactus:
			Self.obstacleWidth
		case .cactusCluster:
			0.115
		case .flyingBird:
			0.1
		}
		let horizontalRange = (Self.playerWidth + obstacleWidth) * Self.horizontalHitboxScale
		let overlapsHorizontally = abs(obstacleX - Self.playerX) < horizontalRange
		guard overlapsHorizontally else {
			return false
		}

		let playerHeight = isCrouching && playerY == 0 ? Self.crouchingPlayerHeight : Self.playerHeight
		let playerBottom = playerY + 0.01
		let playerTop = playerY + (playerHeight * 0.88)
		let obstacleRange = switch obstacleKind {
		case .tallCactus:
			0.0...(Self.obstacleHeight * 0.88)
		case .cactusCluster:
			0.0...0.132
		case .flyingBird:
			0.115...0.195
		}
		return playerTop > obstacleRange.lowerBound && playerBottom < obstacleRange.upperBound
	}

	private var nextObstacleX: Double {
		let cadence = Double(score % 4) * 0.055
		return 1.04 + cadence
	}
}

enum FirmwareUpdateGamePhase: Equatable {
	case connecting
	case preparing
	case uploading
	case verifying
	case complete
	case failed

	var isActive: Bool {
		switch self {
		case .connecting, .preparing, .uploading, .verifying:
			return true
		case .complete, .failed:
			return false
		}
	}
}

struct FirmwareUpdateGameStatus: Equatable {
	let title: String
	let message: String
	let progress: Double
	let phase: FirmwareUpdateGamePhase

	init(title: String, message: String, progress: Double, phase: FirmwareUpdateGamePhase) {
		self.title = title
		self.message = message
		self.progress = min(max(progress, 0), 1)
		self.phase = phase
	}

	var percentText: String {
		"\(Int((progress * 100).rounded()))%"
	}

	var canPlay: Bool {
		phase.isActive
	}
}

struct FirmwareUpdateDemoState: Equatable {
	private(set) var elapsed = 0.0
	let duration: TimeInterval

	init(duration: TimeInterval = 75) {
		self.duration = max(duration, 1)
	}

	var status: FirmwareUpdateGameStatus {
		let progress = min(elapsed / duration, 1)
		let phase: FirmwareUpdateGamePhase
		let message: String

		switch progress {
		case ..<0.08:
			phase = .preparing
			message = "Preparing the mock firmware image"
		case ..<0.94:
			phase = .uploading
			message = "Uploading firmware over Bluetooth"
		case ..<1:
			phase = .verifying
			message = "Verifying firmware on the node"
		default:
			phase = .complete
			message = "Mock firmware update complete"
		}

		return FirmwareUpdateGameStatus(
			title: "Mock BLE OTA",
			message: message,
			progress: progress,
			phase: phase
		)
	}

	mutating func advance(by deltaTime: TimeInterval) {
		elapsed = min(elapsed + max(deltaTime, 0), duration)
	}

	mutating func reset() {
		elapsed = 0
	}
}

extension LocalOTAStatusCode {
	var gamePhase: FirmwareUpdateGamePhase {
		switch self {
		case .waitingForConnection, .connected:
			return .connecting
		case .preparing:
			return .preparing
		case .transferring:
			return .uploading
		case .completed:
			return .complete
		case .idle, .error:
			return .failed
		}
	}
}

extension DFUUpdateState {
	var gamePhase: FirmwareUpdateGamePhase {
		switch self {
		case .starting:
			return .preparing
		case .uploading:
			return .uploading
		case .success:
			return .complete
		case .idle, .error:
			return .failed
		}
	}
}
