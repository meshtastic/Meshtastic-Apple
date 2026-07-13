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
		SKTexture(imageNamed: "ChirpyRun2")
	]
	private let jumpTexture = SKTexture(imageNamed: "ChirpyJump")
	private let idleTexture = SKTexture(imageNamed: "ChirpyIdle")
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

		prompt.isHidden = true
		UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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

		switch runner.score % 3 {
		case 0:
			addCactus(to: obstacle, x: 0, height: 92, armSide: 1)
		case 1:
			addCactus(to: obstacle, x: -18, height: 68, armSide: -1)
			addCactus(to: obstacle, x: 18, height: 86, armSide: 1)
		default:
			addCactus(to: obstacle, x: -22, height: 80, armSide: 1)
			addCactus(to: obstacle, x: 8, height: 62, armSide: -1)
			addCactus(to: obstacle, x: 32, height: 72, armSide: 1)
		}
		addChild(obstacle)
	}

	private func addCactus(to node: SKNode, x: CGFloat, height: CGFloat, armSide: CGFloat) {
		let cactus = SKNode()
		cactus.position.x = x

		let trunk = SKShapeNode(rectOf: CGSize(width: 24, height: height), cornerRadius: 7)
		trunk.fillColor = inkColor
		trunk.strokeColor = .clear
		trunk.position.y = height / 2
		cactus.addChild(trunk)

		let armHeight = height * 0.43
		let verticalArm = SKShapeNode(rectOf: CGSize(width: 16, height: armHeight), cornerRadius: 6)
		verticalArm.fillColor = inkColor
		verticalArm.strokeColor = .clear
		verticalArm.position = CGPoint(x: armSide * 19, y: height * 0.51)
		cactus.addChild(verticalArm)

		let connector = SKShapeNode(rectOf: CGSize(width: 26, height: 15), cornerRadius: 6)
		connector.fillColor = inkColor
		connector.strokeColor = .clear
		connector.position = CGPoint(x: armSide * 12, y: height * 0.38)
		cactus.addChild(connector)

		node.addChild(cactus)
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
		case .running:
			let frame = Int(sceneTime * 9) % runTextures.count
			chirpy.texture = runTextures[frame]
		}
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
