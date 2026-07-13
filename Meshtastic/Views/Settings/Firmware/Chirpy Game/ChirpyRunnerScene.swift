import SpriteKit
import UIKit

@MainActor
final class ChirpyRunnerScene: SKScene {
	private var runner = ChirpyRunnerEngine()
	private var previousUpdateTime = 0.0
	private var sceneTime = 0.0
	private var updateIsActive = true

	private let runTextures = [
		SKTexture(imageNamed: "ChirpyRun1"),
		SKTexture(imageNamed: "ChirpyRun2"),
		SKTexture(imageNamed: "ChirpyRun3"),
		SKTexture(imageNamed: "ChirpyRun4"),
		SKTexture(imageNamed: "ChirpyRun5"),
		SKTexture(imageNamed: "ChirpyRun6"),
		SKTexture(imageNamed: "ChirpyRun7"),
		SKTexture(imageNamed: "ChirpyRun8")
	]
	private let jumpTexture = SKTexture(imageNamed: "ChirpyJump")
	private let idleTexture = SKTexture(imageNamed: "ChirpyIdle")
	private let crouchTexture = SKTexture(imageNamed: "ChirpyCrouch")
	private let chirpy = SKSpriteNode()
	private let obstacle = SKNode()
	private let scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
	private let bestLabel = SKLabelNode(fontNamed: "Menlo-Regular")
	private let prompt = SKLabelNode(fontNamed: "Menlo-Bold")
	private var groundMarks: [SKShapeNode] = []
	private var clouds: [SKNode] = []
	private var gameOverMessage: SKNode?

	private var groundY: CGFloat { size.height * 0.18 }
	private var inkColor: UIColor { UIColor(white: 0.27, alpha: 1) }

	override init(size: CGSize) {
		super.init(size: size)
		scaleMode = .resizeFill
		backgroundColor = UIColor(white: 0.97, alpha: 1)
		runTextures.forEach { texture in
			texture.filteringMode = .linear
		}
		jumpTexture.filteringMode = .linear
		idleTexture.filteringMode = .linear
		crouchTexture.filteringMode = .linear
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func didMove(to view: SKView) {
		super.didMove(to: view)
		view.ignoresSiblingOrder = true
		buildScene()
	}

	override func didChangeSize(_ oldSize: CGSize) {
		super.didChangeSize(oldSize)
		guard view != nil, oldSize != .zero else {
			return
		}
		buildScene()
	}

	func primaryAction() {
		guard updateIsActive else {
			return
		}

		let wasGameOver = runner.phase == .gameOver
		runner.primaryAction()
		if wasGameOver {
			gameOverMessage?.removeFromParent()
			gameOverMessage = nil
			buildObstacle()
		}

		prompt.isHidden = runner.phase != .ready
		if runner.phase == .running {
			UIImpactFeedbackGenerator(style: .soft).impactOccurred()
		}
	}

	func setCrouching(_ crouching: Bool) {
		runner.setCrouching(crouching)
		updateCharacterPose()
	}

	func setUpdateActive(_ isActive: Bool) {
		updateIsActive = isActive
		previousUpdateTime = 0
	}

	override func update(_ currentTime: TimeInterval) {
		guard updateIsActive else {
			return
		}

		let delta = previousUpdateTime == 0 ? 1.0 / 60.0 : currentTime - previousUpdateTime
		previousUpdateTime = currentTime
		sceneTime += min(delta, 1.0 / 30.0)

		let previousScore = runner.score
		let previousPhase = runner.phase
		runner.advance(by: delta)

		updateWorldMotion(delta: delta)
		updateObstacleAnimation()
		updateCharacterPose()
		obstacle.position.x = size.width * runner.obstacleX

		if runner.score != previousScore {
			scoreLabel.text = String(format: "%05d", runner.score)
			storeBestScore()
			buildObstacle()
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
		}

		if previousPhase != .gameOver, runner.phase == .gameOver {
			showGameOver()
		}
	}

	private func buildScene() {
		removeAllChildren()
		groundMarks.removeAll()
		clouds.removeAll()
		gameOverMessage = nil

		addClouds()
		addGround()
		configureCharacter()
		configureHUD()
		buildObstacle()
		updateCharacterPose()
	}

	private func addClouds() {
		for index in 0..<2 {
			let cloud = makeCloud()
			cloud.position = CGPoint(
				x: size.width * CGFloat(index == 0 ? 0.3 : 0.78),
				y: size.height * CGFloat(index == 0 ? 0.72 : 0.58)
			)
			cloud.setScale(index == 0 ? 0.82 : 0.62)
			cloud.zPosition = -2
			clouds.append(cloud)
			addChild(cloud)
		}
	}

	private func makeCloud() -> SKNode {
		let path = CGMutablePath()
		path.move(to: CGPoint(x: -38, y: 0))
		path.addCurve(to: CGPoint(x: -14, y: 2), control1: CGPoint(x: -38, y: 17), control2: CGPoint(x: -23, y: 19))
		path.addCurve(to: CGPoint(x: 10, y: 8), control1: CGPoint(x: -8, y: 25), control2: CGPoint(x: 7, y: 25))
		path.addCurve(to: CGPoint(x: 38, y: 0), control1: CGPoint(x: 23, y: 17), control2: CGPoint(x: 38, y: 12))
		path.addLine(to: CGPoint(x: -38, y: 0))
		let cloud = SKShapeNode(path: path)
		cloud.fillColor = .clear
		cloud.strokeColor = UIColor(white: 0.66, alpha: 0.65)
		cloud.lineWidth = 3
		cloud.lineCap = .round
		return cloud
	}

	private func addGround() {
		let line = SKShapeNode(rectOf: CGSize(width: size.width, height: 3))
		line.fillColor = inkColor
		line.strokeColor = .clear
		line.position = CGPoint(x: size.width / 2, y: groundY)
		line.zPosition = 1
		addChild(line)

		let markCount = max(Int(size.width / 68) + 2, 6)
		for index in 0..<markCount {
			let width = CGFloat(8 + ((index * 7) % 19))
			let mark = SKShapeNode(rectOf: CGSize(width: width, height: 2))
			mark.fillColor = UIColor(white: 0.48, alpha: 0.7)
			mark.strokeColor = .clear
			mark.position = CGPoint(
				x: CGFloat(index) * 68,
				y: groundY - CGFloat(10 + ((index * 11) % 18))
			)
			mark.zPosition = 1
			groundMarks.append(mark)
			addChild(mark)
		}
	}

	private func configureCharacter() {
		chirpy.removeFromParent()
		chirpy.anchorPoint = CGPoint(x: 0.5, y: 0.08)
		chirpy.size = CGSize(width: 128, height: 168)
		chirpy.texture = idleTexture
		chirpy.zPosition = 12
		addChild(chirpy)
	}

	private func configureHUD() {
		scoreLabel.fontSize = 29
		scoreLabel.fontColor = inkColor
		scoreLabel.horizontalAlignmentMode = .right
		scoreLabel.position = CGPoint(x: size.width - 26, y: size.height - 49)
		scoreLabel.text = String(format: "%05d", runner.score)
		scoreLabel.zPosition = 20
		addChild(scoreLabel)

		bestLabel.fontSize = 13
		bestLabel.fontColor = UIColor(white: 0.48, alpha: 1)
		bestLabel.horizontalAlignmentMode = .right
		bestLabel.position = CGPoint(x: size.width - 26, y: size.height - 75)
		bestLabel.text = "HI \(String(format: "%05d", UserDefaults.standard.integer(forKey: "chirpyRunnerBestScore")))"
		bestLabel.zPosition = 20
		addChild(bestLabel)

		prompt.fontSize = 17
		prompt.fontColor = inkColor
		prompt.text = "TAP TO START"
		prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.51)
		prompt.zPosition = 20
		prompt.isHidden = runner.phase != .ready
		addChild(prompt)
	}
}

private extension ChirpyRunnerScene {
	func buildObstacle() {
		obstacle.removeAllChildren()
		obstacle.removeFromParent()
		obstacle.position = CGPoint(x: size.width * runner.obstacleX, y: groundY)
		obstacle.zPosition = 10

		switch runner.obstacleKind {
		case .tallCactus:
			addSaguaro(to: obstacle, x: 0, height: 98)
		case .cactusCluster:
			addSaguaro(to: obstacle, x: -25, height: 68)
			addSaguaro(to: obstacle, x: 18, height: 84)
		case .flyingBird:
			addFlyingBird(to: obstacle)
		}
		addChild(obstacle)
	}

	private func addSaguaro(to node: SKNode, x: CGFloat, height: CGFloat) {
		let cactus = SKNode()
		cactus.position.x = x

		let trunk = SKShapeNode(rectOf: CGSize(width: 22, height: height), cornerRadius: 8)
		trunk.fillColor = inkColor
		trunk.strokeColor = .clear
		trunk.position.y = height / 2
		cactus.addChild(trunk)

		addCactusArm(to: cactus, side: -1, baseY: height * 0.38, armHeight: height * 0.34)
		addCactusArm(to: cactus, side: 1, baseY: height * 0.57, armHeight: height * 0.27)

		node.addChild(cactus)
	}

	private func addCactusArm(to cactus: SKNode, side: CGFloat, baseY: CGFloat, armHeight: CGFloat) {
		let connector = SKShapeNode(rectOf: CGSize(width: 34, height: 14), cornerRadius: 7)
		connector.fillColor = inkColor
		connector.strokeColor = .clear
		connector.position = CGPoint(x: side * 15, y: baseY)
		cactus.addChild(connector)

		let arm = SKShapeNode(rectOf: CGSize(width: 16, height: armHeight), cornerRadius: 7)
		arm.fillColor = inkColor
		arm.strokeColor = .clear
		arm.position = CGPoint(x: side * 28, y: baseY + (armHeight / 2) - 3)
		cactus.addChild(arm)
	}

	private func addFlyingBird(to node: SKNode) {
		let bird = SKNode()
		bird.position.y = size.height * 0.145

		let body = SKShapeNode(ellipseOf: CGSize(width: 62, height: 32))
		body.fillColor = inkColor
		body.strokeColor = .clear
		bird.addChild(body)

		let head = SKShapeNode(circleOfRadius: 14)
		head.fillColor = inkColor
		head.strokeColor = .clear
		head.position = CGPoint(x: -29, y: 7)
		bird.addChild(head)

		let beakPath = CGMutablePath()
		beakPath.move(to: CGPoint(x: -40, y: 13))
		beakPath.addLine(to: CGPoint(x: -64, y: 5))
		beakPath.addLine(to: CGPoint(x: -40, y: 1))
		beakPath.closeSubpath()
		let beak = SKShapeNode(path: beakPath)
		beak.fillColor = inkColor
		beak.strokeColor = .clear
		bird.addChild(beak)

		let tailPath = CGMutablePath()
		tailPath.move(to: CGPoint(x: 27, y: 8))
		tailPath.addLine(to: CGPoint(x: 51, y: 21))
		tailPath.addLine(to: CGPoint(x: 42, y: 3))
		tailPath.addLine(to: CGPoint(x: 54, y: -10))
		tailPath.addLine(to: CGPoint(x: 26, y: -5))
		tailPath.closeSubpath()
		let tail = SKShapeNode(path: tailPath)
		tail.fillColor = inkColor
		tail.strokeColor = .clear
		bird.addChild(tail)

		let wing = makeBirdWing()
		wing.name = "birdWing"
		bird.addChild(wing)

		let eye = SKShapeNode(circleOfRadius: 3)
		eye.fillColor = UIColor(white: 0.97, alpha: 1)
		eye.strokeColor = .clear
		eye.position = CGPoint(x: -33, y: 11)
		bird.addChild(eye)
		node.addChild(bird)
	}

	private func makeBirdWing() -> SKShapeNode {
		let path = CGMutablePath()
		path.move(to: CGPoint(x: -10, y: 5))
		path.addCurve(
			to: CGPoint(x: 18, y: 8),
			control1: CGPoint(x: -3, y: 35),
			control2: CGPoint(x: 13, y: 42)
		)
		path.addLine(to: CGPoint(x: 9, y: -4))
		path.closeSubpath()
		let wing = SKShapeNode(path: path)
		wing.fillColor = inkColor
		wing.strokeColor = .clear
		wing.position = CGPoint(x: 2, y: 5)
		return wing
	}

	func updateWorldMotion(delta: TimeInterval) {
		guard runner.phase == .running else {
			return
		}
		let shift = CGFloat(ChirpyRunnerEngine.speed(forScore: runner.score) * delta) * size.width
		for mark in groundMarks {
			mark.position.x -= shift
			if mark.position.x < -24 {
				mark.position.x += size.width + 68
			}
		}
		for (index, cloud) in clouds.enumerated() {
			cloud.position.x -= shift * CGFloat(0.015 + (Double(index) * 0.005))
			if cloud.position.x < -60 {
				cloud.position.x = size.width + 60
			}
		}
	}

	func updateCharacterPose() {
		let jumpHeight = CGFloat(runner.playerY) * size.height * 0.72
		chirpy.position = CGPoint(x: size.width * ChirpyRunnerEngine.playerX, y: groundY + jumpHeight)

		switch runner.phase {
		case .ready, .gameOver:
			chirpy.texture = idleTexture
		case .running where runner.playerY > 0.012:
			chirpy.texture = jumpTexture
		case .running where runner.isCrouching:
			chirpy.texture = crouchTexture
		case .running:
			let cadence = 14 + (ChirpyRunnerEngine.speed(forScore: runner.score) * 8)
			let frame = Int(sceneTime * cadence) % runTextures.count
			chirpy.texture = runTextures[frame]
		}
	}

	func updateObstacleAnimation() {
		guard runner.obstacleKind == .flyingBird else {
			return
		}
		let flap = CGFloat(sin(sceneTime * 12))
		let wing = obstacle.childNode(withName: "//birdWing")
		wing?.zRotation = flap * 0.32
		wing?.yScale = 0.82 + (abs(flap) * 0.18)
	}

	func showGameOver() {
		UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
		chirpy.texture = idleTexture

		let message = SKNode()
		let title = SKLabelNode(fontNamed: "Menlo-Bold")
		title.text = "GAME OVER"
		title.fontSize = 27
		title.fontColor = inkColor
		title.position.y = 15
		message.addChild(title)

		let restartImage = UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 23, weight: .bold))
		if let restartImage {
			let restart = SKSpriteNode(texture: SKTexture(image: restartImage.withTintColor(inkColor, renderingMode: .alwaysOriginal)))
			restart.size = CGSize(width: 27, height: 27)
			restart.position.y = -30
			message.addChild(restart)
		}

		message.position = CGPoint(x: size.width / 2, y: size.height * 0.52)
		message.zPosition = 50
		gameOverMessage = message
		addChild(message)
	}

	func storeBestScore() {
		let defaults = UserDefaults.standard
		let currentBest = defaults.integer(forKey: "chirpyRunnerBestScore")
		if runner.score > currentBest {
			defaults.set(runner.score, forKey: "chirpyRunnerBestScore")
			bestLabel.text = "HI \(String(format: "%05d", runner.score))"
		}
	}
}
