import SpriteKit
import UIKit

@MainActor
final class ChirpyRunnerScene: SKScene {
	private var runner = ChirpyRunnerEngine()
	private var previousUpdateTime = 0.0
	private var sceneTime = 0.0
	private var updateIsActive = true

	private let chirpy = SKSpriteNode(texture: SKTexture(imageNamed: "Chirpy"))
	private let shadow = SKShapeNode(ellipseOf: CGSize(width: 76, height: 16))
	private let obstacle = SKNode()
	private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
	private let bestLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
	private let prompt = SKLabelNode(fontNamed: "AvenirNext-Bold")
	private var groundDashes: [SKShapeNode] = []
	private var clouds: [SKNode] = []
	private var gameOverPanel: SKNode?

	private var groundY: CGFloat { size.height * 0.2 }

	override init(size: CGSize) {
		super.init(size: size)
		scaleMode = .resizeFill
		backgroundColor = UIColor(red: 0.9, green: 0.97, blue: 1, alpha: 1)
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
			gameOverPanel?.removeFromParent()
			gameOverPanel = nil
			chirpy.zRotation = 0
			buildObstacle()
		}

		prompt.isHidden = true
		animateJump()
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
			scoreLabel.text = String(format: "%04d", runner.score)
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
		groundDashes.removeAll()
		clouds.removeAll()
		gameOverPanel = nil

		addSky()
		addMountains()
		addClouds()
		addSignalMotif()
		addGround()
		configureCharacter()
		configureHUD()
		buildObstacle()
		updateCharacterPose()
	}

	private func addSky() {
		let sky = SKSpriteNode(texture: gradientTexture(size: size))
		sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
		sky.size = size
		sky.zPosition = -20
		addChild(sky)

		let sun = SKShapeNode(circleOfRadius: min(size.width, size.height) * 0.075)
		sun.fillColor = UIColor(red: 1, green: 0.82, blue: 0.42, alpha: 0.9)
		sun.strokeColor = .clear
		sun.position = CGPoint(x: size.width * 0.79, y: size.height * 0.76)
		sun.glowWidth = 8
		sun.zPosition = -18
		addChild(sun)
	}

	private func addMountains() {
		let distantPath = CGMutablePath()
		distantPath.move(to: CGPoint(x: 0, y: groundY))
		distantPath.addLine(to: CGPoint(x: 0, y: size.height * 0.43))
		distantPath.addLine(to: CGPoint(x: size.width * 0.18, y: size.height * 0.62))
		distantPath.addLine(to: CGPoint(x: size.width * 0.38, y: size.height * 0.39))
		distantPath.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.57))
		distantPath.addLine(to: CGPoint(x: size.width * 0.8, y: size.height * 0.38))
		distantPath.addLine(to: CGPoint(x: size.width, y: size.height * 0.54))
		distantPath.addLine(to: CGPoint(x: size.width, y: groundY))
		distantPath.closeSubpath()

		let distant = SKShapeNode(path: distantPath)
		distant.fillColor = UIColor(red: 0.43, green: 0.57, blue: 0.64, alpha: 0.72)
		distant.strokeColor = .clear
		distant.zPosition = -15
		addChild(distant)

		let nearPath = CGMutablePath()
		nearPath.move(to: CGPoint(x: 0, y: groundY))
		nearPath.addCurve(
			to: CGPoint(x: size.width * 0.5, y: groundY),
			control1: CGPoint(x: size.width * 0.17, y: size.height * 0.47),
			control2: CGPoint(x: size.width * 0.34, y: size.height * 0.31)
		)
		nearPath.addCurve(
			to: CGPoint(x: size.width, y: groundY),
			control1: CGPoint(x: size.width * 0.68, y: size.height * 0.4),
			control2: CGPoint(x: size.width * 0.82, y: size.height * 0.34)
		)
		nearPath.closeSubpath()

		let near = SKShapeNode(path: nearPath)
		near.fillColor = UIColor(red: 0.18, green: 0.36, blue: 0.32, alpha: 1)
		near.strokeColor = .clear
		near.zPosition = -11
		addChild(near)
	}

	private func addClouds() {
		for index in 0..<4 {
			let cloud = SKNode()
			for part in 0..<3 {
				let circle = SKShapeNode(circleOfRadius: CGFloat(18 + (part * 4)))
				circle.fillColor = UIColor.white.withAlphaComponent(0.72)
				circle.strokeColor = .clear
				circle.position.x = CGFloat(part * 24)
				cloud.addChild(circle)
			}
			cloud.position = CGPoint(
				x: size.width * CGFloat(0.08 + (Double(index) * 0.29)),
				y: size.height * CGFloat(0.62 + (Double(index % 2) * 0.12))
			)
			cloud.setScale(0.72 + CGFloat(index % 3) * 0.12)
			cloud.zPosition = -16
			clouds.append(cloud)
			addChild(cloud)
		}
	}

	private func addSignalMotif() {
		let origin = CGPoint(x: size.width * 0.68, y: groundY + size.height * 0.16)
		for radius in [34.0, 58.0, 82.0] {
			let path = CGMutablePath()
			path.addArc(
				center: origin,
				radius: radius,
				startAngle: .pi * 0.2,
				endAngle: .pi * 0.8,
				clockwise: false
			)
			let arc = SKShapeNode(path: path)
			arc.strokeColor = UIColor(red: 0.4, green: 0.92, blue: 0.58, alpha: 0.35)
			arc.lineWidth = 4
			arc.zPosition = -8
			addChild(arc)
		}
	}

	private func addGround() {
		let ground = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: groundY))
		ground.fillColor = UIColor(red: 0.17, green: 0.18, blue: 0.24, alpha: 1)
		ground.strokeColor = .clear
		ground.zPosition = 0
		addChild(ground)

		let turf = SKShapeNode(rect: CGRect(x: 0, y: groundY - 8, width: size.width, height: 10))
		turf.fillColor = UIColor(red: 0.4, green: 0.92, blue: 0.58, alpha: 1)
		turf.strokeColor = .clear
		turf.zPosition = 1
		addChild(turf)

		let dashCount = max(Int(size.width / 76) + 2, 4)
		for index in 0..<dashCount {
			let dash = SKShapeNode(rectOf: CGSize(width: 38, height: 5), cornerRadius: 2.5)
			dash.fillColor = UIColor.white.withAlphaComponent(0.2)
			dash.strokeColor = .clear
			dash.position = CGPoint(x: CGFloat(index) * 76, y: groundY * 0.48)
			dash.zPosition = 2
			groundDashes.append(dash)
			addChild(dash)
		}
	}

	private func configureCharacter() {
		chirpy.removeFromParent()
		chirpy.anchorPoint = CGPoint(x: 0.5, y: 0)
		chirpy.size = CGSize(width: 98, height: 138)
		chirpy.zPosition = 12
		addChild(chirpy)

		shadow.removeFromParent()
		shadow.fillColor = UIColor.black.withAlphaComponent(0.24)
		shadow.strokeColor = .clear
		shadow.zPosition = 4
		addChild(shadow)
	}

	private func configureHUD() {
		scoreLabel.fontSize = 34
		scoreLabel.fontColor = UIColor(red: 0.17, green: 0.18, blue: 0.24, alpha: 1)
		scoreLabel.horizontalAlignmentMode = .right
		scoreLabel.position = CGPoint(x: size.width - 28, y: size.height - 54)
		scoreLabel.text = String(format: "%04d", runner.score)
		scoreLabel.zPosition = 20
		addChild(scoreLabel)

		bestLabel.fontSize = 15
		bestLabel.fontColor = UIColor(red: 0.24, green: 0.32, blue: 0.37, alpha: 0.72)
		bestLabel.horizontalAlignmentMode = .right
		bestLabel.position = CGPoint(x: size.width - 28, y: size.height - 80)
		bestLabel.text = "BEST \(UserDefaults.standard.integer(forKey: "chirpyRunnerBestScore"))"
		bestLabel.zPosition = 20
		addChild(bestLabel)

		prompt.fontSize = 18
		prompt.fontColor = UIColor(red: 0.17, green: 0.18, blue: 0.24, alpha: 0.76)
		prompt.text = "TAP TO HOP"
		prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.47)
		prompt.zPosition = 20
		prompt.isHidden = runner.phase != .ready
		prompt.run(.repeatForever(.sequence([
			.fadeAlpha(to: 0.45, duration: 0.7),
			.fadeAlpha(to: 1, duration: 0.7)
		])))
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
			addRelayTower(to: obstacle)
		case 1:
			addRockBeacon(to: obstacle)
		default:
			addSolarRepeater(to: obstacle)
		}
		addChild(obstacle)
	}

	private func addRelayTower(to node: SKNode) {
		let mast = SKShapeNode(rectOf: CGSize(width: 12, height: 82), cornerRadius: 6)
		mast.fillColor = UIColor(red: 0.25, green: 0.31, blue: 0.35, alpha: 1)
		mast.strokeColor = .clear
		mast.position.y = 41
		node.addChild(mast)

		for y in [30.0, 52.0, 74.0] {
			let arm = SKShapeNode(rectOf: CGSize(width: 54, height: 7), cornerRadius: 3.5)
			arm.fillColor = UIColor(red: 0.4, green: 0.92, blue: 0.58, alpha: 1)
			arm.strokeColor = .clear
			arm.position.y = y
			node.addChild(arm)
		}
		addBeaconLight(to: node, y: 94)
	}

	private func addRockBeacon(to node: SKNode) {
		let rockPath = CGMutablePath()
		rockPath.move(to: CGPoint(x: -35, y: 0))
		rockPath.addLine(to: CGPoint(x: -24, y: 55))
		rockPath.addLine(to: CGPoint(x: 4, y: 77))
		rockPath.addLine(to: CGPoint(x: 34, y: 34))
		rockPath.addLine(to: CGPoint(x: 30, y: 0))
		rockPath.closeSubpath()
		let rock = SKShapeNode(path: rockPath)
		rock.fillColor = UIColor(red: 0.31, green: 0.38, blue: 0.43, alpha: 1)
		rock.strokeColor = UIColor.white.withAlphaComponent(0.18)
		rock.lineWidth = 3
		node.addChild(rock)
		addBeaconLight(to: node, y: 84)
	}

	private func addSolarRepeater(to node: SKNode) {
		let post = SKShapeNode(rectOf: CGSize(width: 10, height: 78), cornerRadius: 5)
		post.fillColor = UIColor(red: 0.25, green: 0.31, blue: 0.35, alpha: 1)
		post.strokeColor = .clear
		post.position.y = 39
		node.addChild(post)

		let panel = SKShapeNode(rectOf: CGSize(width: 64, height: 38), cornerRadius: 5)
		panel.fillColor = UIColor(red: 0.12, green: 0.36, blue: 0.56, alpha: 1)
		panel.strokeColor = UIColor(red: 0.4, green: 0.92, blue: 0.58, alpha: 1)
		panel.lineWidth = 4
		panel.position = CGPoint(x: -12, y: 64)
		panel.zRotation = -0.16
		node.addChild(panel)
		addBeaconLight(to: node, y: 94)
	}

	private func addBeaconLight(to node: SKNode, y: CGFloat) {
		let beacon = SKShapeNode(circleOfRadius: 8)
		beacon.fillColor = UIColor(red: 1, green: 0.47, blue: 0.24, alpha: 1)
		beacon.strokeColor = UIColor.white.withAlphaComponent(0.8)
		beacon.lineWidth = 2
		beacon.position.y = y
		beacon.run(.repeatForever(.sequence([
			.fadeAlpha(to: 0.35, duration: 0.45),
			.fadeAlpha(to: 1, duration: 0.45)
		])))
		node.addChild(beacon)
	}

	private func updateWorldMotion(delta: TimeInterval) {
		guard runner.phase == .running else {
			return
		}
		let shift = CGFloat(ChirpyRunnerEngine.speed(forScore: runner.score) * delta) * size.width
		for dash in groundDashes {
			dash.position.x -= shift
			if dash.position.x < -30 {
				dash.position.x += size.width + 76
			}
		}
		for (index, cloud) in clouds.enumerated() {
			cloud.position.x -= shift * CGFloat(0.025 + (Double(index) * 0.008))
			if cloud.position.x < -80 {
				cloud.position.x = size.width + 80
			}
		}
	}

	private func updateCharacterPose() {
		let jumpHeight = CGFloat(runner.playerY) * size.height * 0.72
		chirpy.position = CGPoint(x: size.width * ChirpyRunnerEngine.playerX, y: groundY + jumpHeight)
		shadow.position = CGPoint(x: chirpy.position.x, y: groundY + 2)
		let heightRatio = min(jumpHeight / max(size.height * 0.3, 1), 1)
		shadow.xScale = 1 - (heightRatio * 0.48)
		shadow.alpha = 0.25 - (heightRatio * 0.14)

		guard runner.phase == .running else {
			return
		}
		chirpy.zRotation = CGFloat(max(min(runner.verticalVelocity * -0.08, 0.14), -0.14))
		if runner.playerY == 0 {
			chirpy.position.y += sin(sceneTime * 12) * 2
		}
	}

	private func animateJump() {
		chirpy.removeAction(forKey: "jumpSquash")
		let squash = SKAction.group([
			.scaleX(to: 1.12, duration: 0.07),
			.scaleY(to: 0.88, duration: 0.07)
		])
		let stretch = SKAction.group([
			.scaleX(to: 0.94, duration: 0.1),
			.scaleY(to: 1.08, duration: 0.1)
		])
		let settle = SKAction.scale(to: 1, duration: 0.13)
		chirpy.run(.sequence([squash, stretch, settle]), withKey: "jumpSquash")
		addDustBurst()
		UIImpactFeedbackGenerator(style: .soft).impactOccurred()
	}

	private func addDustBurst() {
		for index in 0..<5 {
			let dust = SKShapeNode(circleOfRadius: CGFloat(3 + (index % 2)))
			dust.fillColor = UIColor.white.withAlphaComponent(0.55)
			dust.strokeColor = .clear
			dust.position = CGPoint(x: chirpy.position.x, y: groundY + 5)
			dust.zPosition = 8
			addChild(dust)
			let direction = CGFloat(index - 2) * 14
			dust.run(.sequence([
				.group([
					.moveBy(x: direction, y: CGFloat(14 + (index * 3)), duration: 0.28),
					.fadeOut(withDuration: 0.28),
					.scale(to: 0.35, duration: 0.28)
				]),
				.removeFromParent()
			]))
		}
	}

	private func showGameOver() {
		UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
		chirpy.run(.rotate(toAngle: -0.2, duration: 0.16, shortestUnitArc: true))

		let panel = SKNode()
		let background = SKShapeNode(rectOf: CGSize(width: 260, height: 112), cornerRadius: 18)
		background.fillColor = UIColor(red: 0.17, green: 0.18, blue: 0.24, alpha: 0.92)
		background.strokeColor = UIColor(red: 0.4, green: 0.92, blue: 0.58, alpha: 1)
		background.lineWidth = 3
		panel.addChild(background)

		let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
		title.text = "SIGNAL LOST"
		title.fontSize = 24
		title.fontColor = .white
		title.position.y = 15
		panel.addChild(title)

		let retry = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
		retry.text = "TAP TO RETRY"
		retry.fontSize = 14
		retry.fontColor = UIColor(red: 0.4, green: 0.92, blue: 0.58, alpha: 1)
		retry.position.y = -24
		panel.addChild(retry)

		panel.position = CGPoint(x: size.width / 2, y: size.height * 0.52)
		panel.zPosition = 50
		panel.setScale(0.82)
		panel.alpha = 0
		panel.run(.group([
			.scale(to: 1, duration: 0.2),
			.fadeIn(withDuration: 0.18)
		]))
		gameOverPanel = panel
		addChild(panel)
	}

	private func storeBestScore() {
		let defaults = UserDefaults.standard
		let currentBest = defaults.integer(forKey: "chirpyRunnerBestScore")
		if runner.score > currentBest {
			defaults.set(runner.score, forKey: "chirpyRunnerBestScore")
			bestLabel.text = "BEST \(runner.score)"
		}
	}

	private func gradientTexture(size: CGSize) -> SKTexture {
		let renderer = UIGraphicsImageRenderer(size: size)
		let image = renderer.image { context in
			let colors = [
				UIColor(red: 0.88, green: 0.96, blue: 1, alpha: 1).cgColor,
				UIColor(red: 0.71, green: 0.91, blue: 0.79, alpha: 1).cgColor
			] as CFArray
			guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else {
				return
			}
			context.cgContext.drawLinearGradient(
				gradient,
				start: CGPoint(x: 0, y: 0),
				end: CGPoint(x: 0, y: size.height),
				options: []
			)
		}
		return SKTexture(image: image)
	}
}
