import Foundation
import Testing

@testable import Meshtastic

@Suite("Persistence container generation")
@MainActor
struct PersistenceContainerGenerationTests {

	@Test("Recreating the container advances its generation")
	func recreatingContainerAdvancesGeneration() {
		let controller = PersistenceController(
			inMemory: true,
			storeName: "PersistenceContainerGenerationTests-\(UUID().uuidString)"
		)
		let originalContainer = controller.container
		let originalGeneration = controller.containerGeneration

		controller.recreateContainer()

		#expect(controller.containerGeneration == originalGeneration + 1)
		#expect(controller.container !== originalContainer)
	}
}
